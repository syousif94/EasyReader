//
//  DocCell.swift
//  EasyReader
//
//  Created by Sammy Yousif on 11/10/25.
//

import UIKit
import PinLayout

class DocCell: UICollectionViewCell {
    
    private var thumbnailTask: Task<Void, Never>?
    private var cachedPageCount: Int?
    private var lastLocalUpdateTime: Date?
    private static let localUpdateGracePeriod: TimeInterval = 5.0 // Ignore iCloud updates within 5 seconds of local change
    
    // Track which documents are currently being viewed (shared across all cells)
    private static var documentsBeingViewed: Set<URL> = []
    private static let viewedDocumentsLock = NSLock()
    
    // Debounce iCloud updates per document
    private var updateDebounceTimer: Timer?
    private static var pendingUpdates: Set<URL> = []
    private static let pendingUpdatesLock = NSLock()
    
    var document: ReadableDoc? {
        didSet {
            // Cancel any existing thumbnail generation task
            thumbnailTask?.cancel()
            
            if let document = document {
                titleTextField.text = document.title
                
                // Cache page count when document is set
                if oldValue?.url != document.url {
                    cachedPageCount = document.getPageCount()
                }
                
                updatePageInfo()
                loadThumbnail(for: document)
                updateCloudStatus()
            } else {
                imageView.image = nil
                cloudStatusView.isHidden = true
                pageInfoLabel.text = nil
                cachedPageCount = nil
            }
        }
    }
    
    let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 15
        return imageView
    }()
    
    let imageContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 15
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.1
        view.layer.shadowOffset = .zero
        view.layer.shadowRadius = 8
        return view
    }()
    
    let titleTextField: UITextField = {
        let textField = UITextField()
        textField.font = .preferredFont(forTextStyle: .caption1)
        textField.textColor = .secondaryLabel
        textField.textAlignment = .center
        textField.returnKeyType = .done
        textField.enablesReturnKeyAutomatically = true
        return textField
    }()
    
    let pageInfoLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .caption2)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        return label
    }()
    
    let cloudStatusView: CloudDownloadStatusView = {
        let view = CloudDownloadStatusView()
        view.isHidden = true
        view.backgroundColor = .clear
        return view
    }()
    
    let downloadProgressView: DownloadProgressView = {
        let view = DownloadProgressView()
        view.isHidden = true
        return view
    }()
    
    private let downloadManager = DocumentDownloadManager.shared
    var onCloudStatusTapped: ((ReadableDoc) -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(titleTextField)
        contentView.addSubview(pageInfoLabel)
        contentView.addSubview(imageContainerView)
        imageContainerView.addSubview(imageView)
        contentView.addSubview(cloudStatusView)
        imageContainerView.addSubview(downloadProgressView)
        
        titleTextField.delegate = self
        
        // Add tap gesture to cloud status view
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(cloudStatusTapped))
        cloudStatusView.addGestureRecognizer(tapGesture)
        cloudStatusView.isUserInteractionEnabled = true
        
        // Set up download progress view cancel handler
        downloadProgressView.onCancelTapped = { [weak self] in
            self?.cancelDownload()
        }
        
        // Observe document reading state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentReadingStateChanged(_:)),
            name: .documentReadingStateDidChange,
            object: nil
        )
        
        // Observe iCloud metadata updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataUpdatedFromCloud(_:)),
            name: .documentMetadataDidUpdateFromCloud,
            object: nil
        )
        
        // Observe when documents are opened/closed in viewers
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentViewerOpened(_:)),
            name: .documentViewerDidOpen,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentViewerClosed(_:)),
            name: .documentViewerDidClose,
            object: nil
        )
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        updateDebounceTimer?.invalidate()
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailTask?.cancel()
        updateDebounceTimer?.invalidate()
        imageView.image = nil
        titleTextField.text = nil
        pageInfoLabel.text = nil
        cloudStatusView.isHidden = true
        downloadProgressView.isHidden = true
        lastLocalUpdateTime = nil
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Layout from bottom to top
        pageInfoLabel.pin.bottom().horizontally(8).sizeToFit(.width)
        titleTextField.pin.bottom(to: pageInfoLabel.edge.top).horizontally(8).sizeToFit(.width)
        imageContainerView.pin.top().horizontally().bottom(to: titleTextField.edge.top).marginBottom(8)
        imageView.pin.all()
        
        // Position cloud status view in the top-right corner of the image
        let cloudSize: CGFloat = 24
        cloudStatusView.pin.size(CGSize(width: cloudSize, height: cloudSize))
            .top(8).right(8)
        
        // Position download progress view in the center of the image
        let progressSize: CGFloat = 80
        downloadProgressView.pin
            .size(CGSize(width: progressSize, height: progressSize))
            .center()
    }
    
    private func loadThumbnail(for document: ReadableDoc) {
        thumbnailTask = Task { @MainActor in
            if let thumbnail = await document.getPreviewImage() {
                // Check if this cell still represents the same document
                guard self.document?.id == document.id else { return }
                
                self.imageView.image = thumbnail
            }
        }
    }
    
    private func updatePageInfo() {
        guard let document = document else {
            pageInfoLabel.text = nil
            return
        }
        
        switch document.docType {
        case .epub:
            // For EPUB, use the saved totalPages from the parser (if available)
            // This matches the paging used by EPUBViewController
            if let totalPages = document.totalPages, totalPages > 0 {
                // Use actual page index saved by EPUBViewController
                let currentPage = (document.currentPage ?? 0) + 1
                pageInfoLabel.text = "Page \(currentPage) of \(totalPages)"
                print("[DocCell] EPUB '\(document.title ?? "Unknown")' updated: Page \(currentPage) of \(totalPages)")
            } else if let totalChapters = cachedPageCount {
                // Fall back to chapter count if EPUB hasn't been opened yet
                let currentChapter = (document.currentPage ?? 0) + 1
                pageInfoLabel.text = "Chapter \(currentChapter) of \(totalChapters)"
                print("[DocCell] EPUB '\(document.title ?? "Unknown")' updated: Chapter \(currentChapter) of \(totalChapters) (fallback)")
            } else {
                pageInfoLabel.text = nil
                print("[DocCell] EPUB '\(document.title ?? "Unknown")' updated: no page info available")
            }
            
        default:
            // For PDF and others, show actual page numbers
            let currentPage = (document.currentPage ?? 0) + 1
            if let totalPages = cachedPageCount {
                pageInfoLabel.text = "Page \(currentPage) of \(totalPages)"
            } else {
                pageInfoLabel.text = nil
            }
        }
    }
    
    @objc private func documentReadingStateChanged(_ notification: Notification) {
        // Check if the notification is for the current document
        guard let document = document,
              let changedURL = notification.userInfo?["documentURL"] as? URL,
              changedURL == document.url else {
            return
        }
        
        // Track that this device made a local change
        lastLocalUpdateTime = Date()
        
        let currentPage = (document.currentPage ?? 0) + 1
        print("📄 [Local] Page changed for '\(document.title ?? "Unknown")' - Page \(currentPage)")
        
        // Update the page info on the main thread
        DispatchQueue.main.async { [weak self] in
            self?.updatePageInfo()
        }
    }
    
    @objc private func metadataUpdatedFromCloud(_ notification: Notification) {
        // Check if this is a remote change from iCloud
        guard notification.userInfo?["isRemoteChange"] as? Bool == true else {
            return
        }
        
        guard let document = document else { return }
        
        // Don't update if this document is currently being viewed
        Self.viewedDocumentsLock.lock()
        let isBeingViewed = Self.documentsBeingViewed.contains(document.url)
        Self.viewedDocumentsLock.unlock()
        
        if isBeingViewed {
            print("🚫 [iCloud] Ignoring update - document is currently being viewed")
            return
        }
        
        // Ignore iCloud updates that arrive shortly after a local update
        // This prevents the device that made the change from processing its own update
        if let lastUpdate = lastLocalUpdateTime,
           Date().timeIntervalSince(lastUpdate) < Self.localUpdateGracePeriod {
            print("🚫 [iCloud] Ignoring iCloud update - recent local change detected")
            return
        }
        
        // Check if this document already has a pending update
        Self.pendingUpdatesLock.lock()
        let alreadyPending = Self.pendingUpdates.contains(document.url)
        if !alreadyPending {
            Self.pendingUpdates.insert(document.url)
        }
        Self.pendingUpdatesLock.unlock()
        
        if alreadyPending {
            print("⏭️ [iCloud] Skipping duplicate update for '\(document.title ?? "Unknown")' - already pending")
            return
        }
        
        // Debounce updates: wait for a brief period to coalesce multiple rapid changes
        updateDebounceTimer?.invalidate()
        updateDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self = self, let document = self.document else { return }
            
            // Remove from pending set
            Self.pendingUpdatesLock.lock()
            Self.pendingUpdates.remove(document.url)
            Self.pendingUpdatesLock.unlock()
            
            // Perform the actual update
            let currentPage = (document.currentPage ?? 0) + 1
            print("📱 [iCloud] Updating page info for '\(document.title ?? "Unknown")' - Page \(currentPage)")
            
            DispatchQueue.main.async {
                self.updatePageInfo()
            }
        }
    }
    
    @objc private func documentViewerOpened(_ notification: Notification) {
        guard let openedURL = notification.userInfo?["documentURL"] as? URL else { return }
        
        Self.viewedDocumentsLock.lock()
        Self.documentsBeingViewed.insert(openedURL)
        Self.viewedDocumentsLock.unlock()
        
        print("👁️ [DocCell] Document marked as being viewed: \(openedURL.lastPathComponent)")
    }
    
    @objc private func documentViewerClosed(_ notification: Notification) {
        guard let closedURL = notification.userInfo?["documentURL"] as? URL else { return }
        
        Self.viewedDocumentsLock.lock()
        Self.documentsBeingViewed.remove(closedURL)
        Self.viewedDocumentsLock.unlock()
        
        print("👁️ [DocCell] Document marked as no longer viewed: \(closedURL.lastPathComponent)")
        
        // Update page info now that viewer is closed (in case there were pending changes)
        // The document metadata (including totalPages) may have been updated while viewing
        if let document = document, document.url == closedURL {
            // Small delay to ensure Core Data has saved the latest state
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.updatePageInfo()
            }
        }
    }
    
    private func updateCloudStatus() {
        guard let document = document else { return }
        
        // Show cloud icon only if it's an iCloud file and not downloading
        if document.isICloudFile {
            let status = document.getDownloadStatus()
            let isDownloading = downloadManager.isDownloading(document)
            
            // Hide cloud icon if downloaded or currently downloading
            cloudStatusView.isHidden = status.isDownloaded || isDownloading
            
            // Show progress view if downloading
            if isDownloading {
                downloadProgressView.show()
                if let progress = downloadManager.getProgress(for: document) {
                    downloadProgressView.downloadProgress = progress
                }
            } else {
                downloadProgressView.hide()
            }
        } else {
            cloudStatusView.isHidden = true
            downloadProgressView.hide()
        }
    }
    
    @objc private func cloudStatusTapped() {
        guard let document = document else { return }
        
        // Start downloading
        startDownload()
        
        // Also notify the delegate if set
        onCloudStatusTapped?(document)
    }
    
    func startDownload() {
        guard let document = document else { return }
        
        // Hide cloud icon and show progress view
        cloudStatusView.isHidden = true
        downloadProgressView.show()
        
        // Subscribe to download progress
        let publisher = downloadManager.startDownload(for: document)
        
        publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                guard let self = self else { return }
                
                print("Download progress: \(progress.progress)")
                
                self.downloadProgressView.downloadProgress = progress.progress
                
                if progress.isComplete {
                    // Hide progress view and cloud icon on completion
                    self.downloadProgressView.hide()
                    self.cloudStatusView.isHidden = true
                }
                
                if let error = progress.error {
                    print("Download error: \(error.localizedDescription)")
                    // Show cloud icon again on error
                    self.cloudStatusView.isHidden = false
                    self.downloadProgressView.hide()
                }
            }
            .store(in: &cancellables)
    }
    
    func cancelDownload() {
        guard let document = document else { return }
        
        downloadManager.cancelDownload(for: document)
        
        // Hide progress view and show cloud icon again
        downloadProgressView.hide()
        cloudStatusView.isHidden = false
    }
}

// MARK: - Combine Support

import Combine

extension DocCell {
    private var cancellables: Set<AnyCancellable> {
        get {
            objc_getAssociatedObject(self, &cancellablesKey) as? Set<AnyCancellable> ?? []
        }
        set {
            objc_setAssociatedObject(self, &cancellablesKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}

private var cancellablesKey: UInt8 = 0

// MARK: - UITextFieldDelegate

extension DocCell: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        guard let document = document,
              let newTitle = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !newTitle.isEmpty,
              newTitle != document.title else {
            // Revert to original title if empty or unchanged
            textField.text = document?.title
            return
        }
        
        // Rename the file
        renameDocument(document, to: newTitle)
    }
    
    private func renameDocument(_ document: ReadableDoc, to newTitle: String) {
        let oldURL = document.url
        let directory = oldURL.deletingLastPathComponent()
        let fileExtension = oldURL.pathExtension
        
        // Create new URL with new title and same extension
        let newFileName = newTitle + "." + fileExtension
        let newURL = directory.appendingPathComponent(newFileName)
        
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            // The DirectoryMonitor will automatically detect the change and update the UI
        } catch {
            // Show error and revert to original title
            print("Failed to rename document: \(error.localizedDescription)")
            titleTextField.text = document.title
            
            // Optionally show an alert
            if let viewController = self.findViewController() {
                let alert = UIAlertController(
                    title: "Rename Failed",
                    message: "Could not rename the document: \(error.localizedDescription)",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                viewController.present(alert, animated: true)
            }
        }
    }
    
    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let nextResponder = responder?.next {
            if let viewController = nextResponder as? UIViewController {
                return viewController
            }
            responder = nextResponder
        }
        return nil
    }
}
