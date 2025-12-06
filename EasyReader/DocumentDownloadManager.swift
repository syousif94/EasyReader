//
//  DocumentDownloadManager.swift
//  EasyReader
//
//  Created by Sammy Yousif on 11/10/25.
//

import Foundation
import Combine

/// Manages downloading of iCloud documents and provides progress updates
@Observable
class DocumentDownloadManager {
    
    /// Shared singleton instance
    static let shared = DocumentDownloadManager()
    
    /// Active download operations
    private var activeDownloads: [URL: DownloadOperation] = [:]
    
    /// Publishers for download progress
    private var progressPublishers: [URL: CurrentValueSubject<DownloadProgress, Never>] = [:]
    
    private init() {
        setupMetadataQueryObserver()
    }
    
    // MARK: - Download Management
    
    /// Start downloading a document
    /// - Parameter document: The document to download
    /// - Returns: A publisher that emits progress updates
    func startDownload(for document: ReadableDoc) -> AnyPublisher<DownloadProgress, Never> {
        print("starting download")
        let url = document.url
        
        // If already downloading, return existing publisher
        if let existingPublisher = progressPublishers[url] {
            return existingPublisher.eraseToAnyPublisher()
        }
        
        // Create new progress publisher
        let progressSubject = CurrentValueSubject<DownloadProgress, Never>(
            DownloadProgress(url: url, progress: 0, isComplete: false, error: nil)
        )
        progressPublishers[url] = progressSubject
        
        // Create download operation
        let operation = DownloadOperation(url: url, progressSubject: progressSubject)
        activeDownloads[url] = operation
        
        // Start the download
        operation.start()
        
        return progressSubject.eraseToAnyPublisher()
    }
    
    /// Cancel an active download
    /// - Parameter document: The document to cancel downloading
    func cancelDownload(for document: ReadableDoc) {
        let url = document.url
        
        guard let operation = activeDownloads[url] else { return }
        
        operation.cancel()
        activeDownloads.removeValue(forKey: url)
        progressPublishers.removeValue(forKey: url)
    }
    
    /// Check if a document is currently downloading
    func isDownloading(_ document: ReadableDoc) -> Bool {
        return activeDownloads[document.url] != nil
    }
    
    /// Get progress for a document
    func getProgress(for document: ReadableDoc) -> Double? {
        return progressPublishers[document.url]?.value.progress
    }
    
    // MARK: - Metadata Query Observer
    
    private var metadataQuery: NSMetadataQuery?
    private var metadataQueryCancellable: AnyCancellable?
    
    private func setupMetadataQueryObserver() {
        // Create metadata query to monitor iCloud file downloads
        let query = NSMetadataQuery()
        query.notificationBatchingInterval = 1
        query.searchScopes = [
            NSMetadataQueryUbiquitousDataScope,
            NSMetadataQueryUbiquitousDocumentsScope
        ]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        
        // Use Combine to observe notifications
        let notificationNames: [NSNotification.Name] = [
            .NSMetadataQueryDidFinishGathering,
            .NSMetadataQueryDidUpdate
        ]
        
        let publishers = notificationNames.map { name in
            NotificationCenter.default.publisher(for: name, object: query)
        }
        
        metadataQueryCancellable = Publishers.MergeMany(publishers)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleMetadataUpdate(notification: notification)
            }
        
        query.start()
        metadataQuery = query
    }
    
    private func handleMetadataUpdate(notification: Notification) {
        print("progress query updated: \(notification.name)")
        
        guard let query = notification.object as? NSMetadataQuery,
              query == metadataQuery else { return }
        
        query.disableUpdates()
        defer { query.enableUpdates() }
        
        // Update progress for all active downloads
        for (url, progressSubject) in progressPublishers {
            updateProgress(for: url, query: query, progressSubject: progressSubject)
        }
    }
    
    private func updateProgress(
        for url: URL,
        query: NSMetadataQuery,
        progressSubject: CurrentValueSubject<DownloadProgress, Never>
    ) {
        // Find the item in the metadata query
        let fileName = url.lastPathComponent
        
        guard let item = (query.results as? [NSMetadataItem])?.first(where: { item in
            guard let itemName = item.value(forAttribute: NSMetadataItemFSNameKey) as? String else {
                return false
            }
            return itemName == fileName
        }) else {
            print("Item not found in metadata query: \(fileName)")
            return
        }
        
        // Get download status
        let downloadStatus = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
        let isDownloading = item.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey) as? Bool ?? false
        let percentDownloaded = item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double ?? 0
        
        print("Download status for \(fileName): status=\(downloadStatus ?? "nil"), downloading=\(isDownloading), percent=\(percentDownloaded)")
        
        // Update progress
        let progress = percentDownloaded / 100.0
        let isComplete = (downloadStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent) || progress >= 1.0
        
        let newProgress = DownloadProgress(
            url: url,
            progress: progress,
            isComplete: isComplete,
            error: nil
        )
        
        progressSubject.send(newProgress)
        
        // Clean up if complete
        if isComplete {
            activeDownloads.removeValue(forKey: url)
            // Keep the publisher for a bit so subscribers get the completion
            Task {
                try? await Task.sleep(for: .seconds(2))
                progressPublishers.removeValue(forKey: url)
            }
        }
    }
    
    deinit {
        metadataQuery?.stop()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Download Operation

private class DownloadOperation {
    let url: URL
    let progressSubject: CurrentValueSubject<DownloadProgress, Never>
    private var isCancelled = false
    
    init(url: URL, progressSubject: CurrentValueSubject<DownloadProgress, Never>) {
        self.url = url
        self.progressSubject = progressSubject
    }
    
    func start() {
        guard !isCancelled else { return }
        
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            let progress = DownloadProgress(
                url: url,
                progress: 0,
                isComplete: false,
                error: error
            )
            progressSubject.send(progress)
        }
    }
    
    func cancel() {
        isCancelled = true
        
        do {
            // Stop downloading by evicting the item
            try FileManager.default.evictUbiquitousItem(at: url)
            
            let progress = DownloadProgress(
                url: url,
                progress: 0,
                isComplete: false,
                error: NSError(domain: "DocumentDownload", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Download cancelled"
                ])
            )
            progressSubject.send(progress)
        } catch {
            print("Error cancelling download: \(error)")
        }
    }
}

// MARK: - Download Progress

struct DownloadProgress {
    let url: URL
    let progress: Double // 0.0 to 1.0
    let isComplete: Bool
    let error: Error?
}
