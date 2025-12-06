//
//  ThumbnailCache.swift
//  EasyReader
//
//  Created by Sammy Yousif on 10/18/25.
//

import Foundation
import UIKit
import PDFKit
import CryptoKit
import EPUBKit

actor ThumbnailCache {
    static let shared = ThumbnailCache()
    
    private let thumbnailSize = CGSize(width: 200, height: 300)
    private let cacheDirectoryName = "thumbnails"
    private let imageQuality: CGFloat = 0.7
    
    // Track which thumbnails are currently being generated
    private var generatingThumbnails: Set<String> = []
    
    private var cacheDirectory: URL? {
        guard let documentsDirectory = AppViewModel.documentDirectory else { return nil }
        let cacheDir = documentsDirectory.appendingPathComponent(cacheDirectoryName, isDirectory: true)
        
        // Create cache directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: cacheDir.path) {
            do {
                try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            } catch {
                print("Failed to create cache directory: \(error)")
                return nil
            }
        }
        
        return cacheDir
    }
    
    private init() {}
    
    /// Check if a thumbnail is currently being generated for the given URL
    func isGenerating(for url: URL) -> Bool {
        let hash = hashForURL(url)
        return generatingThumbnails.contains(hash)
    }
    
    func getThumbnail(for url: URL) async -> UIImage? {
        // First check if cached version exists
        if let cachedImage = await getCachedThumbnail(for: url) {
            return cachedImage
        }
        
        // Generate new thumbnail
        return await generateAndCacheThumbnail(for: url)
    }
    
    // MARK: - EPUB Thumbnail
    
    func getEPUBThumbnail(for url: URL) async -> UIImage? {
        // First check if cached version exists
        if let cachedImage = await getCachedThumbnail(for: url) {
            return cachedImage
        }
        
        // Generate new thumbnail
        return await generateAndCacheEPUBThumbnail(for: url)
    }
    
    private func generateAndCacheEPUBThumbnail(for url: URL) async -> UIImage? {
        let hash = hashForURL(url)
        
        // Mark as generating
        generatingThumbnails.insert(hash)
        
        let thumbnail = await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                let thumbnail = await self.generateEPUBThumbnail(for: url)
                
                if let thumbnail = thumbnail {
                    await self.cacheThumbnail(thumbnail, for: url)
                }
                
                continuation.resume(returning: thumbnail)
            }
        }
        
        // Mark as done generating
        generatingThumbnails.remove(hash)
        
        return thumbnail
    }
    
    private func generateEPUBThumbnail(for url: URL) async -> UIImage? {
        guard let document = EPUBDocument(url: url) else {
            return nil
        }
        
        // Try to get cover image first
        if let coverURL = document.cover,
           let coverData = try? Data(contentsOf: coverURL),
           let coverImage = UIImage(data: coverData) {
            // Resize cover to thumbnail size
            return resizeImage(coverImage, to: thumbnailSize)
        }
        
        // Fallback: Create a placeholder with the title
        return createEPUBPlaceholderThumbnail(title: document.title ?? "EPUB")
    }
    
    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            // Fill with white background
            UIColor.white.set()
            context.fill(CGRect(origin: .zero, size: size))
            
            // Calculate aspect-fit rect
            let imageAspect = image.size.width / image.size.height
            let targetAspect = size.width / size.height
            
            var drawRect: CGRect
            if imageAspect > targetAspect {
                // Image is wider
                let height = size.width / imageAspect
                drawRect = CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
            } else {
                // Image is taller
                let width = size.height * imageAspect
                drawRect = CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
            }
            
            image.draw(in: drawRect)
        }
    }
    
    private func createEPUBPlaceholderThumbnail(title: String) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
        return renderer.image { context in
            // Fill with a nice gradient background
            let colors = [UIColor.systemIndigo.cgColor, UIColor.systemPurple.cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: thumbnailSize.height), options: [])
            
            // Draw EPUB icon
            let iconRect = CGRect(x: (thumbnailSize.width - 60) / 2, y: 40, width: 60, height: 60)
            let iconConfig = UIImage.SymbolConfiguration(pointSize: 50, weight: .regular)
            if let bookIcon = UIImage(systemName: "book.fill", withConfiguration: iconConfig) {
                UIColor.white.withAlphaComponent(0.8).setFill()
                bookIcon.draw(in: iconRect)
            }
            
            // Draw title
            let titleStyle = NSMutableParagraphStyle()
            titleStyle.alignment = .center
            titleStyle.lineBreakMode = .byTruncatingTail
            
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: titleStyle
            ]
            
            let titleRect = CGRect(x: 10, y: 120, width: thumbnailSize.width - 20, height: 80)
            (title as NSString).draw(in: titleRect, withAttributes: titleAttributes)
        }
    }
    
    private func getCachedThumbnail(for url: URL) async -> UIImage? {
        guard let cacheDirectory = cacheDirectory else { return nil }
        
        let cacheFileName = hashForURL(url) + ".jpg"
        let cacheFileURL = cacheDirectory.appendingPathComponent(cacheFileName)
        
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else { return nil }
        
        // Check if the cached file is newer than the original file
        do {
            let cacheAttributes = try FileManager.default.attributesOfItem(atPath: cacheFileURL.path)
            let originalAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            
            if let cacheDate = cacheAttributes[.modificationDate] as? Date,
               let originalDate = originalAttributes[.modificationDate] as? Date,
               cacheDate < originalDate {
                // Cache is older than original file, remove it
                try FileManager.default.removeItem(at: cacheFileURL)
                return nil
            }
        } catch {
            // If we can't get attributes, proceed with loading cached image
        }
        
        return UIImage(contentsOfFile: cacheFileURL.path)
    }
    
    private func generateAndCacheThumbnail(for url: URL) async -> UIImage? {
        let hash = hashForURL(url)
        
        // Mark as generating
        generatingThumbnails.insert(hash)
        
        let thumbnail = await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                let thumbnail = await self.generatePDFThumbnail(for: url)
                
                if let thumbnail = thumbnail {
                    await self.cacheThumbnail(thumbnail, for: url)
                }
                
                continuation.resume(returning: thumbnail)
            }
        }
        
        // Mark as done generating
        generatingThumbnails.remove(hash)
        
        return thumbnail
    }
    
    private func generatePDFThumbnail(for url: URL) async -> UIImage? {
        guard let pdfDocument = PDFDocument(url: url),
              let firstPage = pdfDocument.page(at: 0) else {
            return nil
        }
        
        let pageRect = firstPage.bounds(for: .trimBox)
        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
        
        let thumbnail = renderer.image { context in
            // Fill with white background
            UIColor.white.set()
            context.fill(CGRect(origin: .zero, size: thumbnailSize))
            
            // Calculate scale to fit the page in thumbnail size while maintaining aspect ratio
            let scaleX = thumbnailSize.width / pageRect.width
            let scaleY = thumbnailSize.height / pageRect.height
            let scale = min(scaleX, scaleY)
            
            let scaledSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
            let drawRect = CGRect(
                x: (thumbnailSize.width - scaledSize.width) / 2,
                y: (thumbnailSize.height - scaledSize.height) / 2,
                width: scaledSize.width,
                height: scaledSize.height
            )
            
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: drawRect.minX, y: drawRect.maxY)
            context.cgContext.scaleBy(x: scale, y: -scale)
            context.cgContext.translateBy(x: -pageRect.minX, y: -pageRect.minY)
            
            firstPage.draw(with: .mediaBox, to: context.cgContext)
            
            context.cgContext.restoreGState()
        }
        
        return thumbnail
    }
    
    private func cacheThumbnail(_ image: UIImage, for url: URL) async {
        guard let cacheDirectory = cacheDirectory,
              let imageData = image.jpegData(compressionQuality: imageQuality) else {
            return
        }
        
        let cacheFileName = hashForURL(url) + ".jpg"
        let cacheFileURL = cacheDirectory.appendingPathComponent(cacheFileName)
        
        do {
            try imageData.write(to: cacheFileURL)
        } catch {
            print("Failed to cache thumbnail: \(error)")
        }
    }
    
    private func hashForURL(_ url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    func clearCache() async {
        guard let cacheDirectory = cacheDirectory else { return }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            print("Failed to clear cache: \(error)")
        }
    }
    
    func getCacheSize() async -> Int64 {
        guard let cacheDirectory = cacheDirectory else { return 0 }
        
        var totalSize: Int64 = 0
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            for file in files {
                let resourceValues = try file.resourceValues(forKeys: [.fileSizeKey])
                totalSize += Int64(resourceValues.fileSize ?? 0)
            }
        } catch {
            print("Failed to calculate cache size: \(error)")
        }
        
        return totalSize
    }
}
