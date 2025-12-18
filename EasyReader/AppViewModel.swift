//
//  AppViewModel.swift
//  EasyReader
//
//  Created by Sammy Yousif on 10/18/25.
//

import Combine
import Foundation
import Observation
import UIKit
import FirebaseAI

@Observable
class AppViewModel: NSObject, DirectoryMonitorDelegate {
    var documents: [ReadableDoc] = []
    var hasCompletedInitialLoad: Bool = false
    let monitor: DirectoryMonitor?
    
    // MARK: - Documents Cache
    private let documentsCacheFileName = "documents_cache.json"
    private var documentsCacheURL: URL? {
        let fm = FileManager.default
        if let cacheDir = try? fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            return cacheDir.appendingPathComponent(documentsCacheFileName)
        }
        return nil
    }
    
    private struct CachedDoc: Codable {
        let url: URL
        let docType: String
    }
    
    private func loadCachedDocumentsIfAvailable() {
        guard let cacheURL = documentsCacheURL,
              let data = try? Data(contentsOf: cacheURL) else { return }
        
        do {
            let cached = try JSONDecoder().decode([CachedDoc].self, from: data)
            let mapped: [ReadableDoc] = cached.compactMap { item in
                guard let type = DocType(rawValue: item.docType.lowercased()) else { return nil }
                return ReadableDoc(id: UUID(), url: item.url, docType: type)
            }
            if !mapped.isEmpty {
                // Show cached list immediately
                self.documents = mapped
            }
        } catch {
            print("Failed to decode documents cache: \(error)")
        }
    }
    
    private func saveDocumentsToCache(_ docs: [ReadableDoc]) {
        guard let cacheURL = documentsCacheURL else { return }
        let cached: [CachedDoc] = docs.map { CachedDoc(url: $0.url, docType: $0.docType.rawValue) }
        do {
            let data = try JSONEncoder().encode(cached)
            try data.write(to: cacheURL, options: [.atomic])
        } catch {
            print("Failed to write documents cache: \(error)")
        }
    }
    
    // AI Analysis properties
    var aiAnalysisText: String = ""
    var isAnalyzingWithAI: Bool = false
    
    nonisolated static var documentDirectory: URL? {
        let documentsUrl: URL?
        
        if let url = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            documentsUrl = url
        } else if let url = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)  {
            documentsUrl = url
        } else {
            documentsUrl = nil
        }
        
        return documentsUrl
    }
    
    override init() {
        if let url = Self.documentDirectory {
            monitor = DirectoryMonitor(url: url)
        } else {
            monitor = nil
        }
        super.init()
        
        // Load cached documents synchronously for fast offline startup
        // This ensures documents are available immediately before async scan
        loadCachedDocumentsIfAvailable()
        
        monitor?.delegate = self
        monitor?.startMonitoring()
        scanDirectoryAsync()
    }
    
    func directoryMonitor(directoryMonitor: DirectoryMonitor, didDetectChangeIn directoryURL: URL) {
        scanDirectoryAsync()
    }
    
    private func scanDirectoryAsync() {
        guard let directoryURL = Self.documentDirectory else {
            // No directory available - mark as loaded so cached documents can be shown
            DispatchQueue.main.async { [weak self] in
                self?.hasCompletedInitialLoad = true
            }
            return
        }
        
        // Perform file enumeration off the main thread to avoid blocking startup
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var newDocuments: [ReadableDoc] = []
            
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
                )
                
                for url in fileURLs {
                    // Check if it's a regular file
                    let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
                    guard resourceValues.isRegularFile == true else { continue }
                    
                    // Determine document type based on file extension
                    let pathExtension = url.pathExtension.lowercased()
                    
                    if let docType = DocType(rawValue: pathExtension) {
                        let document = ReadableDoc(
                            id: UUID(),
                            url: url,
                            docType: docType
                        )
                        newDocuments.append(document)
                    }
                }
                
                // Sort documents by filename for consistent ordering
                newDocuments.sort { $0.url.lastPathComponent < $1.url.lastPathComponent }
                
                // Publish results on the main actor
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.documents = newDocuments
                    self.hasCompletedInitialLoad = true
                    // Persist cache for next launch
                    self.saveDocumentsToCache(newDocuments)
                }
            } catch {
                print("Error scanning directory: \(error)")
                // Mark as loaded even on error so cached documents remain visible
                // The app can work offline with previously cached document list
                DispatchQueue.main.async { [weak self] in
                    self?.hasCompletedInitialLoad = true
                }
            }
        }
    }
    
    deinit {
        monitor?.stopMonitoring()
    }
    
    // MARK: - Cache Management
    
    func clearThumbnailCache() async {
        await ThumbnailCache.shared.clearCache()
    }
    
    func getThumbnailCacheSize() async -> Int64 {
        return await ThumbnailCache.shared.getCacheSize()
    }

}
