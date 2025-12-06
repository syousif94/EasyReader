//
//  DocumentImporter.swift
//  EasyReader
//
//  Created by Sammy Yousif on 12/5/25.
//

import Foundation
import CoreData
import UIKit

/// Result of a document import attempt
enum DocumentImportResult {
    case imported(URL)      // New document was imported
    case duplicate(URL)     // Document already exists, returns existing URL
    case failed(Error)      // Import failed
}

/// Centralized document import logic with duplicate detection
class DocumentImporter {
    
    static let shared = DocumentImporter()
    
    private init() {}
    
    /// Import a document, checking for duplicates based on file hash
    /// - Parameters:
    ///   - sourceURL: The URL of the file to import
    ///   - accessSecurityScoped: Whether to access security-scoped resource
    /// - Returns: The result of the import operation
    func importDocument(from sourceURL: URL, accessSecurityScoped: Bool = false) -> DocumentImportResult {
        // Validate file type
        let fileExtension = sourceURL.pathExtension.lowercased()
        guard fileExtension == "pdf" || fileExtension == "epub" else {
            return .failed(ImportError.unsupportedFileType(fileExtension))
        }
        
        // Access security-scoped resource if needed
        let shouldStopAccessing = accessSecurityScoped ? sourceURL.startAccessingSecurityScopedResource() : false
        
        defer {
            if shouldStopAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // Compute hash of incoming file
        guard let incomingHash = sourceURL.sha256HashStreaming() else {
            return .failed(ImportError.hashComputationFailed)
        }
        
        print("🔍 [DocumentImporter] Incoming file hash: \(incomingHash)")
        
        // Check for existing document with same hash
        if let existingURL = findExistingDocument(withHash: incomingHash) {
            print("📄 [DocumentImporter] Duplicate found: \(existingURL.lastPathComponent)")
            return .duplicate(existingURL)
        }
        
        // No duplicate, proceed with import
        guard let documentsUrl = AppViewModel.documentDirectory else {
            return .failed(ImportError.noDocumentsDirectory)
        }
        
        // Generate unique filename if needed
        let destinationUrl = generateUniqueDestinationURL(for: sourceURL, in: documentsUrl)
        
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationUrl)
            print("✅ [DocumentImporter] Imported: \(destinationUrl.lastPathComponent)")
            return .imported(destinationUrl)
        } catch {
            return .failed(error)
        }
    }
    
    /// Find an existing document with the same hash
    private func findExistingDocument(withHash hash: String) -> URL? {
        // Check if we have metadata for this hash in Core Data
        let context = AppDelegate.getManagedContext()
        let fetchRequest: NSFetchRequest<ReaderDocMetadata> = ReaderDocMetadata.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "fileHash == %@", hash)
        fetchRequest.fetchLimit = 1
        
        do {
            let results = try context.fetch(fetchRequest)
            if results.isEmpty {
                // No existing document with this hash
                return nil
            }
            
            // We have metadata for this hash, now find the actual file
            guard let documentsUrl = AppViewModel.documentDirectory else { return nil }
            
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: documentsUrl,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
            
            for fileURL in fileURLs {
                let pathExtension = fileURL.pathExtension.lowercased()
                guard pathExtension == "pdf" || pathExtension == "epub" else { continue }
                
                // Compute hash of existing file to find the matching one
                if let existingHash = fileURL.sha256HashStreaming(), existingHash == hash {
                    return fileURL
                }
            }
        } catch {
            print("❌ [DocumentImporter] Error checking for duplicate: \(error)")
        }
        
        return nil
    }
    
    /// Generate a unique destination URL, appending a number if file already exists
    private func generateUniqueDestinationURL(for sourceURL: URL, in directory: URL) -> URL {
        let filename = sourceURL.deletingPathExtension().lastPathComponent
        let fileExtension = sourceURL.pathExtension
        var destinationUrl = directory.appendingPathComponent(sourceURL.lastPathComponent)
        var counter = 1
        
        while FileManager.default.fileExists(atPath: destinationUrl.path) {
            let newFilename = "\(filename) (\(counter)).\(fileExtension)"
            destinationUrl = directory.appendingPathComponent(newFilename)
            counter += 1
        }
        
        return destinationUrl
    }
    
    // MARK: - Errors
    
    enum ImportError: LocalizedError {
        case unsupportedFileType(String)
        case hashComputationFailed
        case noDocumentsDirectory
        
        var errorDescription: String? {
            switch self {
            case .unsupportedFileType(let ext):
                return "Unsupported file type: \(ext)"
            case .hashComputationFailed:
                return "Failed to compute file hash"
            case .noDocumentsDirectory:
                return "Could not access documents directory"
            }
        }
    }
}
