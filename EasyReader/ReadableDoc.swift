//
//  ReadableDoc.swift
//  EasyReader
//
//  Created by Sammy Yousif on 10/18/25.
//

import Foundation
import UIKit
import CoreData
import CryptoKit
import PDFKit
import EPUBKit

// Helper class to avoid circular dependencies
class EPUBKitHelper {
    static func parseDocument(at url: URL) throws -> EPUBDocument? {
        return EPUBDocument(url: url)
    }
}

// Notification name for when document reading state changes
extension Notification.Name {
    static let documentReadingStateDidChange = Notification.Name("documentReadingStateDidChange")
    static let documentMetadataDidUpdateFromCloud = Notification.Name("documentMetadataDidUpdateFromCloud")
    static let documentViewerDidOpen = Notification.Name("documentViewerDidOpen")
    static let documentViewerDidClose = Notification.Name("documentViewerDidClose")
    static let documentsCacheLoaded = Notification.Name("documentsCacheLoaded")
    static let navigateToAIAnalysis = Notification.Name("navigateToAIAnalysis")
}

struct ReadableDoc: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let docType: DocType
    
    var metadata: ReaderDocMetadata? {
        get {
            let metadata = getMetadata()
            return metadata
        }
    }
    
    func saveMetadata() throws {
        let context = AppDelegate.getManagedContext()
        try context.save()
    }
    
    var currentPage: Int? {
        get {
            guard let metadata = getMetadata() else {
                return nil
            }
            
            return Int(metadata.currentPage)
        }
        set {
            guard let newValue, let metadata = metadata else {
                return
            }
            metadata.currentPage = Int16(newValue)
            do {
                try saveMetadata()
                print("Saved current page: \(newValue)")
                
                // Post notification that reading state changed with device identifier
                NotificationCenter.default.post(
                    name: .documentReadingStateDidChange,
                    object: nil,
                    userInfo: [
                        "documentURL": url,
                        "sourceDeviceID": UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
                    ]
                )
            }
            catch {
                print("Error saving current page: \(error)")
            }
        }
    }
    
    var pageProgress: CGFloat? {
        get {
            guard let metadata = metadata else {
                return nil
            }
            
            return CGFloat(metadata.currentPageProgress)
        }
        set {
            guard let newValue, let metadata = metadata else {
                return
            }
            
            metadata.currentPageProgress = Double(newValue)
            do {
                try saveMetadata()
            }
            catch {
                print("Error saving page progress: \(error)")
            }
        }
    }
    
    var scaleFactor: CGFloat? {
        get {
            guard let metadata = metadata else {
                return nil
            }
            
            return CGFloat(metadata.scaleFactor)
        }
        set {
            guard let newValue, let metadata = metadata else {
                return
            }
            
            metadata.scaleFactor = Double(newValue)
            do {
                try saveMetadata()
                print("Saved scale factor: \(newValue)")
            }
            catch {
                print("Error saving scale factor: \(error)")
            }
        }
    }
    
    /// Stable EPUB reading position (JSON encoded EPUBPosition)
    var epubPosition: String? {
        get {
            guard let metadata = metadata else {
                return nil
            }
            return metadata.epubPosition
        }
        set {
            guard let metadata = metadata else {
                return
            }
            metadata.epubPosition = newValue
            do {
                try saveMetadata()
                print("Saved EPUB position")
                
                // Post notification that reading state changed
                NotificationCenter.default.post(
                    name: .documentReadingStateDidChange,
                    object: nil,
                    userInfo: [
                        "documentURL": url,
                        "sourceDeviceID": UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
                    ]
                )
            }
            catch {
                print("Error saving EPUB position: \(error)")
            }
        }
    }
    
    /// Total page count (used for EPUB after parsing)
    var totalPages: Int? {
        get {
            guard let metadata = metadata else {
                return nil
            }
            let value = Int(metadata.totalPages)
            return value > 0 ? value : nil
        }
        set {
            guard let newValue, let metadata = metadata else {
                return
            }
            metadata.totalPages = Int16(newValue)
            do {
                try saveMetadata()
                print("Saved total pages: \(newValue)")
                
                // Post notification that reading state changed
                NotificationCenter.default.post(
                    name: .documentReadingStateDidChange,
                    object: nil,
                    userInfo: [
                        "documentURL": url,
                        "sourceDeviceID": UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
                    ]
                )
            }
            catch {
                print("Error saving total pages: \(error)")
            }
        }
    }

    var fileHash: String? {
        let status = getDownloadStatus()
        if status.isDownloaded {
            let hash = url.sha256HashStreaming()
            return hash
        }
        return nil
    }
    
    var title: String? {
        return url.lastPathComponent.split(separator: ".").dropLast().joined()
    }
    
    /// Get the total page count for PDF and EPUB documents
    func getPageCount() -> Int? {
        switch docType {
        case .pdf:
            guard let pdfDocument = PDFKit.PDFDocument(url: url) else { return nil }
            return pdfDocument.pageCount
        case .epub:
            // For EPUB, return spine item count as a rough chapter count
            // Actual page count depends on pagination which requires screen size
            return getEPUBSpineCount()
        default:
            return nil
        }
    }
    
    /// Get spine item count for EPUB (used as rough page/chapter count)
    private func getEPUBSpineCount() -> Int? {
        // Lazy import to avoid requiring EPUBKit for non-EPUB documents
        guard let epubDocument = try? EPUBKitHelper.parseDocument(at: url) else {
            return nil
        }
        return epubDocument.spine.items.count
    }
    
    func getPreviewImage() async -> UIImage? {
        switch docType {
        case .pdf:
            return await ThumbnailCache.shared.getThumbnail(for: url)
        case .epub:
            return await ThumbnailCache.shared.getEPUBThumbnail(for: url)
        default:
            return nil
        }
    }
    
    func isGeneratingThumbnail() async -> Bool {
        switch docType {
        case .pdf:
            return await ThumbnailCache.shared.isGenerating(for: url)
        case .epub:
            return await ThumbnailCache.shared.isGenerating(for: url)
        default:
            return false
        }
    }
    
    func getMetadata() -> ReaderDocMetadata? {
        guard let fileHash else { return nil }
        let context = AppDelegate.getManagedContext()
        let fetchRequest: NSFetchRequest<ReaderDocMetadata> = ReaderDocMetadata.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "fileHash == %@", fileHash)
        fetchRequest.fetchLimit = 1
        
        do {
            let results = try context.fetch(fetchRequest)
            if results.isEmpty {
                let newMetadata = ReaderDocMetadata(context: context)
                newMetadata.fileHash = fileHash
                try context.save()
                return newMetadata
            }
            return results.first
        } catch {
            print("Error fetching metadata: \(error)")
            return nil
        }
    }
    
    /// Get reading progress for this document (0.0 to 1.0)
    func getReadingProgress() -> Double {
        let metadata = getMetadata()
        if let progress = metadata?.currentPage {
            return Double(progress)
        }
        return 0
    }
    
    // MARK: - iCloud Status
    
    /// Check if the file is stored in iCloud
    var isICloudFile: Bool {
        guard let ubiquityURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return false
        }
        return url.path.hasPrefix(ubiquityURL.path)
    }
    
    /// Get the download status of the file
    func getDownloadStatus() -> (isDownloading: Bool, downloadProgress: Double, isDownloaded: Bool) {
        guard isICloudFile else {
            return (false, 1.0, true) // Local files are always "downloaded"
        }
        
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsDownloadingKey,
                .ubiquitousItemDownloadingErrorKey
            ])
            
            let isDownloading = resourceValues.ubiquitousItemIsDownloading ?? false
            let downloadStatus = resourceValues.ubiquitousItemDownloadingStatus
            
            // Determine download progress based on status
            // Note: ubiquitousItemPercentDownloadedKey is not available on Mac Catalyst
            let progress: Double
            if let status = downloadStatus {
                switch status {
                case .current:
                    progress = 1.0
                case .notDownloaded:
                    progress = 0.0
                case .downloaded:
                    progress = 1.0
                default:
                    progress = isDownloading ? 0.5 : 0.0
                }
            } else {
                progress = isDownloading ? 0.5 : 1.0
            }
            
            let isDownloaded: Bool
            if let status = downloadStatus {
                isDownloaded = (status == .current)
            } else {
                isDownloaded = !isDownloading && progress >= 1.0
            }
            
            return (isDownloading, progress, isDownloaded)
        } catch {
            print("Error getting download status: \(error)")
            return (false, 0.0, false)
        }
    }
    
    /// Request download of the file from iCloud
    func requestDownload() {
        guard isICloudFile else { return }
        
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            print("Error requesting download: \(error)")
        }
    }
}

