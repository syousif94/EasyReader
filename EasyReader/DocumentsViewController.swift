//
//  DocumentsViewController.swift
//  EasyReader
//
//  Created by Sammy Yousif on 11/10/25.
//

import UIKit
import Combine
import PinLayout
import CoreData
import UniformTypeIdentifiers
import PDFKit

class DocumentsViewController: UIViewController {
    
    let navigationDelegate = RootNavigationDelegate()
    
    let viewModel: AppViewModel = .init()
    
    var cancellables: Set<AnyCancellable> = []
    
    let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 16
        layout.minimumInteritemSpacing = 0
        layout.scrollDirection = .vertical
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.alwaysBounceVertical = true
        return collectionView
    }()
    
    let emptyStateView: UIView = {
        let container = UIView()
        container.isHidden = true
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 16
        
        let iconImageView = UIImageView()
        iconImageView.image = UIImage(systemName: "doc.text.fill")
        iconImageView.tintColor = .tertiaryLabel
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.widthAnchor.constraint(equalToConstant: 80).isActive = true
        iconImageView.heightAnchor.constraint(equalToConstant: 80).isActive = true
        
        let titleLabel = UILabel()
        titleLabel.text = "No Documents"
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        
        let subtitleLabel = UILabel()
        subtitleLabel.text = "Import PDFs or EPUBs to get started.\nTap + or drag and drop files here."
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        
        stackView.addArrangedSubview(iconImageView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        
        container.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 32),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -32)
        ])
        
        return container
    }()
    
    let importMenuViewController = ImportMenuViewController()
    
    var readableDocController: ReadableDocController<DocCell, ReadableDoc>!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        addChild(importMenuViewController)
        
        collectionView.delegate = self
        collectionView.dragDelegate = self
        navigationController?.delegate = navigationDelegate
        title = "My Documents"
        
        
        readableDocController = .init(for: collectionView, in: AppDelegate.getManagedContext()) { cell, indexPath, doc in
            cell.document = doc
        }
        
        setupViews()
        setupDropInteraction()
        setupDragInteraction()
        
        // Observe when document viewers close to refresh cell metadata
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentViewerClosed(_:)),
            name: .documentViewerDidClose,
            object: nil
        )
    }
    
    private func setupDropInteraction() {
        let dropInteraction = UIDropInteraction(delegate: self)
        collectionView.addInteraction(dropInteraction)
    }
    
    private func setupDragInteraction() {
        collectionView.dragInteractionEnabled = true
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func documentViewerClosed(_ notification: Notification) {
        guard let closedURL = notification.userInfo?["documentURL"] as? URL else { return }
        
        // Find and refresh the cell for this document
        // Small delay to ensure Core Data has saved the latest state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            // Find the visible cell for this document and refresh it
            for cell in self.collectionView.visibleCells {
                if let docCell = cell as? DocCell,
                   let doc = docCell.document,
                   doc.url == closedURL {
                    // Re-assign the document to trigger updatePageInfo
                    docCell.document = doc
                    break
                }
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Enable iCloud updates after the document list has appeared
        // This prevents iCloud sync from slowing down the initial UI load
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            // Delay slightly to ensure the UI is fully rendered
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                appDelegate.enableICloudUpdates()
            }
        }
    }
    
    private func setupViews() {
        view.addSubview(collectionView)
        view.addSubview(emptyStateView)
        view.addSubview(importMenuViewController.view)
    }
    
    override func updateProperties() {
        super.updateProperties()
        
        readableDocController.update(with: viewModel.documents)
        
        let isEmpty = viewModel.documents.isEmpty
        let showEmptyState = isEmpty && viewModel.hasCompletedInitialLoad
        emptyStateView.isHidden = !showEmptyState
        collectionView.isHidden = showEmptyState
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        collectionView.pin.all()
        
        emptyStateView.pin.all()
        
        importMenuViewController.view.pin.all()
        
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 16
        layout.minimumInteritemSpacing = 0
        layout.scrollDirection = .vertical
        
        collectionView.setCollectionViewLayout(layout, animated: false)
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension DocumentsViewController: UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let columns = floor(collectionView.bounds.width / 180)
        let width = (collectionView.bounds.width - (16 * (columns + 1)) - view.safeAreaInsets.left - view.safeAreaInsets.right) / columns
        let height = width * 1.5
        return .init(width: width, height: height)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        let bottomInset: CGFloat = 68 // Space for import button
        return .init(top: 0, left: 16 + view.safeAreaInsets.left, bottom: bottomInset, right: 16 + view.safeAreaInsets.right)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // Deselect the cell for visual feedback
        collectionView.deselectItem(at: indexPath, animated: true)
        
        if let cell = collectionView.cellForItem(at: indexPath) as? DocCell,
           let doc = cell.document {
            let status = doc.getDownloadStatus()
            
            if !status.isDownloaded {
                if status.isDownloading {
                    cell.cancelDownload()
                }
                else {
                    cell.startDownload()
                }
                return
            }
            
            switch doc.docType {
            case .pdf:
                let readerVC = PDFViewController(document: doc, viewModel: viewModel)
                navigationController?.pushViewController(readerVC, animated: true)
            case .epub:
                let readerVC = EPUBViewController(document: doc, viewModel: viewModel)
                navigationController?.pushViewController(readerVC, animated: true)
            default:
                return
            }
            
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let cell = collectionView.cellForItem(at: indexPath) as? DocCell,
              let doc = cell.document else {
            return nil
        }
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] suggestedActions in
            // Delete action
            let deleteAction = UIAction(
                title: "Delete",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                self?.deleteDocument(doc)
            }
            
            // Share action
            let shareAction = UIAction(
                title: "Share",
                image: UIImage(systemName: "square.and.arrow.up")
            ) { _ in
                self?.shareDocument(doc)
            }
            
            return UIMenu(title: "", children: [shareAction, deleteAction])
        }
    }
    
    private func deleteDocument(_ document: ReadableDoc) {
        let alert = UIAlertController(
            title: "Delete Document",
            message: "Are you sure you want to delete \"\(document.title ?? "this document")\"?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.performDelete(document)
        })
        
        present(alert, animated: true)
    }
    
    private func performDelete(_ document: ReadableDoc) {
        do {
            try FileManager.default.removeItem(at: document.url)
            
            // The DirectoryMonitor will automatically trigger a rescan
            // and update the UI through the viewModel
            
        } catch {
            let errorAlert = UIAlertController(
                title: "Error",
                message: "Failed to delete document: \(error.localizedDescription)",
                preferredStyle: .alert
            )
            errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
            present(errorAlert, animated: true)
        }
    }
    
    private func shareDocument(_ document: ReadableDoc) {
        let activityVC = UIActivityViewController(
            activityItems: [document.url],
            applicationActivities: nil
        )
        
        // For iPad, set the popover presentation controller
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        present(activityVC, animated: true)
    }
}

// MARK: - RootNavigationDelegate

class RootNavigationDelegate: NSObject, UINavigationControllerDelegate {
    
}

// MARK: - UIDropInteractionDelegate

extension DocumentsViewController: UIDropInteractionDelegate {
    
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        let isValid = session.hasItemsConforming(toTypeIdentifiers: [UTType.pdf.identifier, UTType.epub.identifier])
        
        return isValid
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        return UIDropProposal(operation: .copy)
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        for item in session.items {
            // Handle PDF files
            if item.itemProvider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                item.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, error in
                    guard let url = url else { return }
                    self.importDroppedFile(from: url)
                }
            }
            // Handle EPUB files
            else if item.itemProvider.hasItemConformingToTypeIdentifier(UTType.epub.identifier) {
                item.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.epub.identifier) { url, error in
                    guard let url = url else { return }
                    self.importDroppedFile(from: url)
                }
            }
        }
    }
    
    private func importDroppedFile(from url: URL) {
        let result = DocumentImporter.shared.importDocument(from: url)
        
        DispatchQueue.main.async {
            switch result {
            case .imported(let destinationUrl):
                print("✅ [Drop] Imported: \(destinationUrl.lastPathComponent)")
            case .duplicate(let existingUrl):
                print("📄 [Drop] Duplicate skipped: \(existingUrl.lastPathComponent)")
                // Optionally show a toast/alert that file already exists
            case .failed(let error):
                print("❌ [Drop] Failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - UICollectionViewDragDelegate

extension DocumentsViewController: UICollectionViewDragDelegate {
    
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard let cell = collectionView.cellForItem(at: indexPath) as? DocCell,
              let doc = cell.document else {
            return []
        }
        
        // Check if the document is downloaded
        let status = doc.getDownloadStatus()
        guard status.isDownloaded else {
            return []
        }
        
        let url = doc.url
        let itemProvider = NSItemProvider(contentsOf: url)
        
        guard let provider = itemProvider else {
            return []
        }
        
        let dragItem = UIDragItem(itemProvider: provider)
        dragItem.localObject = doc
        
        return [dragItem]
    }
    
    func collectionView(_ collectionView: UICollectionView, dragPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
        guard let cell = collectionView.cellForItem(at: indexPath) as? DocCell else {
            return nil
        }
        
        let parameters = UIDragPreviewParameters()
        parameters.visiblePath = UIBezierPath(roundedRect: cell.bounds, cornerRadius: 8)
        return parameters
    }
}
