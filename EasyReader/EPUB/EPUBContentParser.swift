//
//  EPUBContentParser.swift
//  EasyReader
//
//  Created by Sammy Yousif on 12/2/25.
//

import Foundation
import UIKit
import EPUBKit
import CoreText

/// Represents content from a single EPUB page (a segment of a chapter)
struct EPUBPage {
    let attributedString: NSAttributedString
    let chapterIndex: Int
    let chapterTitle: String
    let segmentIndex: Int  // Which segment within the chapter (0, 1, 2...)
    let isFirstSegment: Bool  // Is this the first segment of a chapter?
    let isLastSegment: Bool   // Is this the last segment of a chapter?
    
    /// Character range within the original chapter
    let chapterCharacterRange: NSRange
    
    /// Paragraph information for stable position tracking
    let paragraphs: [EPUBParagraph]
    
    /// Total character count in this segment
    var characterCount: Int {
        return attributedString.length
    }
    
    /// Find the paragraph at a given character offset (relative to this segment)
    func paragraph(at characterOffset: Int) -> EPUBParagraph? {
        return paragraphs.first { $0.contains(characterOffset: characterOffset) }
    }
    
    /// Find the character offset for a paragraph index
    func characterOffset(forParagraph paragraphIndex: Int) -> Int? {
        guard paragraphIndex >= 0 && paragraphIndex < paragraphs.count else { return nil }
        return paragraphs[paragraphIndex].startOffset
    }
    
    /// Get a context snippet at a character offset
    func contextSnippet(at characterOffset: Int, length: Int = 50) -> String {
        return EPUBParagraphExtractor.extractContextSnippet(
            from: attributedString.string,
            at: characterOffset,
            length: length
        )
    }
}

/// Parses EPUB documents and paginates content into attributed string pages
class EPUBContentParser {
    
    let document: EPUBDocument
    private(set) var pages: [EPUBPage] = []
    private(set) var chapterTitles: [String] = []
    
    /// Original chapter content (before segmentation)
    private var chapterContents: [(attributedString: NSAttributedString, title: String, paragraphs: [EPUBParagraph])] = []
    
    /// Maximum characters per segment (roughly 2-3 screens worth of text)
    private static let maxCharactersPerSegment: Int = 3000
    
    /// Total character count across all chapters
    private(set) var totalCharacterCount: Int = 0
    
    /// Cumulative character offsets for each chapter (for book progress calculation)
    private(set) var chapterStartOffsets: [Int] = []
    
    /// Base URL for resolving relative image paths
    var contentDirectory: URL {
        return document.contentDirectory
    }
    
    init(document: EPUBDocument) {
        self.document = document
    }
    
    /// Parse the EPUB and load all chapter content
    /// - Parameter pageSize: The size for content layout (used for segmentation hints)
    func parse(pageSize: CGSize) async throws {
        pages = []
        chapterTitles = []
        chapterContents = []
        chapterStartOffsets = []
        totalCharacterCount = 0
        
        // Get reading order from spine
        let spineItems = document.spine.items
        
        for (chapterIndex, spineItem) in spineItems.enumerated() {
            // Track cumulative offset before adding this chapter
            chapterStartOffsets.append(totalCharacterCount)
            
            // Get the manifest item for this spine entry
            guard let manifestItem = document.manifest.items[spineItem.idref] else {
                continue
            }
            let itemPath = manifestItem.path
            
            // Only process XHTML content
            guard manifestItem.mediaType == .xHTML else {
                continue
            }
            
            // Load the XHTML content
            let contentURL = contentDirectory.appendingPathComponent(itemPath)
            
            guard let htmlData = try? Data(contentsOf: contentURL),
                  let htmlString = String(data: htmlData, encoding: .utf8) else {
                continue
            }
            
            // Extract chapter title from TOC or filename
            let chapterTitle = extractChapterTitle(for: itemPath) ?? "Chapter \(chapterIndex + 1)"
            chapterTitles.append(chapterTitle)
            
            // Convert HTML to attributed string
            let attributedString = try await convertHTMLToAttributedString(
                html: htmlString,
                baseURL: contentURL.deletingLastPathComponent()
            )
            
            // Skip empty chapters
            guard attributedString.length > 0 else {
                continue
            }
            
            // Extract paragraphs for stable position tracking
            let paragraphs = EPUBParagraphExtractor.extractParagraphs(from: attributedString)
            
            // Store the full chapter content
            chapterContents.append((attributedString, chapterTitle, paragraphs))
            
            // Split chapter into segments
            let segments = splitChapterIntoSegments(
                attributedString: attributedString,
                paragraphs: paragraphs,
                chapterIndex: chapterIndex,
                chapterTitle: chapterTitle
            )
            
            pages.append(contentsOf: segments)
            
            // Update total character count
            totalCharacterCount += attributedString.length
        }
    }
    
    /// Split a chapter into smaller segments at paragraph boundaries
    private func splitChapterIntoSegments(
        attributedString: NSAttributedString,
        paragraphs: [EPUBParagraph],
        chapterIndex: Int,
        chapterTitle: String
    ) -> [EPUBPage] {
        let totalLength = attributedString.length
        
        // If the chapter is small enough, return as a single page
        if totalLength <= Self.maxCharactersPerSegment {
            return [EPUBPage(
                attributedString: attributedString,
                chapterIndex: chapterIndex,
                chapterTitle: chapterTitle,
                segmentIndex: 0,
                isFirstSegment: true,
                isLastSegment: true,
                chapterCharacterRange: NSRange(location: 0, length: totalLength),
                paragraphs: paragraphs
            )]
        }
        
        var segments: [EPUBPage] = []
        var currentStart = 0
        var segmentIndex = 0
        
        while currentStart < totalLength {
            // Find a good break point around maxCharactersPerSegment
            let targetEnd = min(currentStart + Self.maxCharactersPerSegment, totalLength)
            var breakPoint = targetEnd
            
            // Try to break at a paragraph boundary
            if targetEnd < totalLength {
                // Find the paragraph that contains targetEnd
                for paragraph in paragraphs.reversed() {
                    // Look for paragraph that ends before or at our target
                    if paragraph.endOffset <= targetEnd && paragraph.endOffset > currentStart {
                        breakPoint = paragraph.endOffset
                        break
                    }
                }
                
                // If we couldn't find a good break, try to break at newline
                if breakPoint == targetEnd {
                    let searchRange = NSRange(location: max(currentStart, targetEnd - 500), length: min(500, targetEnd - currentStart))
                    let string = attributedString.string as NSString
                    let newlineRange = string.range(of: "\n", options: .backwards, range: searchRange)
                    if newlineRange.location != NSNotFound {
                        breakPoint = newlineRange.location + 1
                    }
                }
            }
            
            // Extract the segment
            let segmentRange = NSRange(location: currentStart, length: breakPoint - currentStart)
            let segmentString = attributedString.attributedSubstring(from: segmentRange)
            
            // Extract paragraphs for this segment (adjusted to local offsets)
            let segmentParagraphs = paragraphs.compactMap { paragraph -> EPUBParagraph? in
                // Check if paragraph overlaps with segment
                if paragraph.endOffset <= currentStart || paragraph.startOffset >= breakPoint {
                    return nil
                }
                // Adjust to local offset
                let localStart = max(0, paragraph.startOffset - currentStart)
                let localEnd = min(segmentString.length, paragraph.endOffset - currentStart)
                return EPUBParagraph(
                    range: NSRange(location: localStart, length: localEnd - localStart),
                    index: paragraph.index
                )
            }
            
            let isFirst = currentStart == 0
            let isLast = breakPoint >= totalLength
            
            segments.append(EPUBPage(
                attributedString: segmentString,
                chapterIndex: chapterIndex,
                chapterTitle: chapterTitle,
                segmentIndex: segmentIndex,
                isFirstSegment: isFirst,
                isLastSegment: isLast,
                chapterCharacterRange: segmentRange,
                paragraphs: segmentParagraphs
            ))
            
            currentStart = breakPoint
            segmentIndex += 1
        }
        
        return segments
    }
    
    // MARK: - Position Calculation
    
    /// Create a position from page index and character offset within that page
    func createPosition(
        pageIndex: Int,
        characterOffset: Int
    ) -> EPUBPosition {
        guard pageIndex >= 0 && pageIndex < pages.count else {
            return .bookStart
        }
        
        let page = pages[pageIndex]
        let clampedOffset = min(max(0, characterOffset), page.characterCount)
        
        // Calculate the absolute character offset within the chapter
        let chapterCharOffset = page.chapterCharacterRange.location + clampedOffset
        
        // Find paragraph index (using the page's local paragraphs)
        let paragraph = page.paragraph(at: clampedOffset)
        let paragraphIndex = paragraph?.index ?? 0
        let paragraphOffset = clampedOffset - (paragraph?.startOffset ?? 0)
        
        // Extract context snippet
        let snippet = page.contextSnippet(at: clampedOffset)
        
        // Calculate chapter progress using the absolute offset
        let chapterIndex = page.chapterIndex
        let chapterLength = chapterContents.indices.contains(chapterIndex) 
            ? chapterContents[chapterIndex].attributedString.length 
            : page.characterCount
        
        let chapterProgress = chapterLength > 0 
            ? Double(chapterCharOffset) / Double(chapterLength) 
            : 0.0
        
        let globalOffset = (chapterIndex < chapterStartOffsets.count ? chapterStartOffsets[chapterIndex] : 0) + chapterCharOffset
        let bookProgress = totalCharacterCount > 0 
            ? Double(globalOffset) / Double(totalCharacterCount) 
            : 0.0
        
        return EPUBPosition(
            chapterIndex: chapterIndex,
            paragraphIndex: paragraphIndex,
            characterOffset: paragraphOffset,
            contextSnippet: snippet,
            chapterProgress: chapterProgress,
            bookProgress: bookProgress
        )
    }
    
    /// Legacy method for compatibility - creates position from chapter index
    func createPosition(
        chapterIndex: Int,
        characterOffset: Int
    ) -> EPUBPosition {
        // Find the first page for this chapter
        guard let pageIndex = firstPageIndex(for: chapterIndex) else {
            return .bookStart
        }
        
        // Find which page contains this character offset
        var targetPageIndex = pageIndex
        var remainingOffset = characterOffset
        
        for i in pageIndex..<pages.count {
            let page = pages[i]
            guard page.chapterIndex == chapterIndex else { break }
            
            if remainingOffset < page.characterCount {
                targetPageIndex = i
                break
            }
            remainingOffset -= page.characterCount
            targetPageIndex = i
        }
        
        return createPosition(pageIndex: targetPageIndex, characterOffset: min(remainingOffset, pages[targetPageIndex].characterCount))
    }
    
    /// Resolve a position to a page index and character offset within that page
    func resolvePosition(_ position: EPUBPosition) -> (pageIndex: Int, characterOffset: Int) {
        // Find pages for this chapter
        let chapterPages = pages.enumerated().filter { $0.element.chapterIndex == position.chapterIndex }
        
        guard !chapterPages.isEmpty else {
            return (0, 0)
        }
        
        // Try to find by context snippet first (most reliable)
        if !position.contextSnippet.isEmpty {
            for (pageIndex, page) in chapterPages {
                if let foundOffset = EPUBParagraphExtractor.findOffset(
                    byContext: position.contextSnippet,
                    in: page.attributedString.string,
                    nearOffset: 0
                ) {
                    return (pageIndex, foundOffset)
                }
            }
        }
        
        // Fall back to chapter progress to find the right page
        let targetChapterOffset = Int(position.chapterProgress * Double(
            chapterContents.indices.contains(position.chapterIndex) 
                ? chapterContents[position.chapterIndex].attributedString.length 
                : chapterPages.last?.element.chapterCharacterRange.upperBound ?? 0
        ))
        
        for (pageIndex, page) in chapterPages {
            let pageStart = page.chapterCharacterRange.location
            let pageEnd = pageStart + page.characterCount
            
            if targetChapterOffset >= pageStart && targetChapterOffset < pageEnd {
                let localOffset = targetChapterOffset - pageStart
                return (pageIndex, min(localOffset, page.characterCount))
            }
        }
        
        // Default to first page of chapter
        return (chapterPages.first?.offset ?? 0, 0)
    }
    
    /// Extract chapter title from table of contents
    private func extractChapterTitle(for path: String) -> String? {
        // Derive a human-friendly title from the file name as a safe fallback
        let lastComponent = (path as NSString).lastPathComponent
        let baseName = (lastComponent as NSString).deletingPathExtension
        if baseName.isEmpty { return nil }
        let cleaned = baseName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        // Capitalize words for readability
        return cleaned.capitalized
    }
    
    /// Convert HTML string to NSAttributedString with embedded images
    private func convertHTMLToAttributedString(html: String, baseURL: URL) async throws -> NSAttributedString {
        // Pre-process HTML to handle images
        let processedHTML = await preprocessHTML(html, baseURL: baseURL)
        
        // Create attributed string from HTML
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        
        // Must be called on main thread
        return try await MainActor.run {
            guard let data = processedHTML.data(using: .utf8),
                  let attributedString = try? NSMutableAttributedString(
                    data: data,
                    options: options,
                    documentAttributes: nil
                  ) else {
                return NSAttributedString(string: "")
            }
            
            // Apply custom styling
            applyCustomStyling(to: attributedString)
            
            return attributedString
        }
    }
    
    /// Extract and inline CSS from stylesheet links in HTML
    private func extractAndInlineCSS(from html: String, baseURL: URL) -> String {
        var inlinedCSS = ""
        
        // Find all <link rel="stylesheet"> tags
        let linkPattern = #"<link[^>]*rel\s*=\s*[\"']stylesheet[\"'][^>]*href\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#
        let linkPatternAlt = #"<link[^>]*href\s*=\s*[\"']([^\"']+)[\"'][^>]*rel\s*=\s*[\"']stylesheet[\"'][^>]*>"#
        
        for pattern in [linkPattern, linkPatternAlt] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
            
            for match in matches {
                guard let hrefRange = Range(match.range(at: 1), in: html) else { continue }
                let href = String(html[hrefRange])
                
                // Resolve CSS path
                let cssURL: URL
                if href.hasPrefix("http://") || href.hasPrefix("https://") {
                    continue // Skip remote stylesheets
                } else if href.hasPrefix("/") {
                    cssURL = contentDirectory.appendingPathComponent(String(href.dropFirst()))
                } else {
                    cssURL = baseURL.appendingPathComponent(href)
                }
                
                // Load CSS content
                if let cssData = try? Data(contentsOf: cssURL),
                   let cssContent = String(data: cssData, encoding: .utf8) {
                    inlinedCSS += "\n/* From: \(href) */\n"
                    inlinedCSS += cssContent
                    inlinedCSS += "\n"
                }
            }
        }
        
        // Also check for embedded <style> tags
        let stylePattern = #"<style[^>]*>([\s\S]*?)</style>"#
        if let regex = try? NSRegularExpression(pattern: stylePattern, options: .caseInsensitive) {
            let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
            for match in matches {
                guard let contentRange = Range(match.range(at: 1), in: html) else { continue }
                let styleContent = String(html[contentRange])
                inlinedCSS += "\n/* Embedded style */\n"
                inlinedCSS += styleContent
                inlinedCSS += "\n"
            }
        }
        
        return inlinedCSS
    }
    
    /// Extract the body content from HTML
    private func extractBodyContent(from html: String) -> String {
        // Try to extract just the body content
        let bodyPattern = #"<body[^>]*>([\s\S]*)</body>"#
        if let regex = try? NSRegularExpression(pattern: bodyPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let contentRange = Range(match.range(at: 1), in: html) {
            return String(html[contentRange])
        }
        return html
    }
    
    /// Preprocess HTML to embed images and inline CSS from the EPUB
    private func preprocessHTML(_ html: String, baseURL: URL) async -> String {
        var processedHTML = html
        
        // Extract CSS from the EPUB's stylesheets
        let epubCSS = extractAndInlineCSS(from: html, baseURL: baseURL)
        
        // Extract body content
        let bodyContent = extractBodyContent(from: processedHTML)
        
        // Find all img tags and replace src with base64 data URLs
        var processedBody = bodyContent
        let imgPattern = #"<img[^>]*src\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#
        
        guard let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) else {
            return html
        }
        
        let matches = regex.matches(in: bodyContent, options: [], range: NSRange(bodyContent.startIndex..., in: bodyContent))
        
        // Process matches in reverse order to maintain string indices
        for match in matches.reversed() {
            guard let srcRange = Range(match.range(at: 1), in: bodyContent) else { continue }
            let src = String(bodyContent[srcRange])
            
            // Resolve the image path
            let imageURL: URL
            if src.hasPrefix("http://") || src.hasPrefix("https://") {
                // Skip remote images for now
                continue
            } else if src.hasPrefix("/") {
                imageURL = contentDirectory.appendingPathComponent(String(src.dropFirst()))
            } else {
                imageURL = baseURL.appendingPathComponent(src)
            }
            
            // Load and encode image as base64
            if let imageData = try? Data(contentsOf: imageURL),
               let mimeType = mimeTypeForImage(at: imageURL) {
                let base64String = imageData.base64EncodedString()
                let dataURL = "data:\(mimeType);base64,\(base64String)"
                
                // Replace the src in the HTML
                if let fullRange = Range(match.range, in: processedBody) {
                    let originalTag = String(processedBody[fullRange])
                    let newTag = originalTag.replacingOccurrences(of: src, with: dataURL)
                    processedBody.replaceSubrange(fullRange, with: newTag)
                }
            }
        }
        
        // Build final HTML with EPUB's CSS + our enhancements
        let styledHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                /* EPUB's original styles */
                \(epubCSS)
                
                /* Our enhancements - applied on top */
                body {
                    font-family: Georgia, "Times New Roman", serif;
                    font-size: 21px;
                    line-height: 1.9;
                    color: #1a1a1a;
                    margin: 0;
                    padding: 24px;
                }
                p {
                    margin-bottom: 1.2em;
                }
                h1, h2, h3, h4, h5, h6 {
                    font-family: Georgia, "Times New Roman", serif;
                    text-align: center;
                    font-weight: normal;
                    margin-top: 1.5em;
                    margin-bottom: 1em;
                }
                h1 {
                    font-size: 2em;
                    margin-top: 0.5em;
                }
                img {
                    max-width: 100%;
                    height: auto;
                }
            </style>
        </head>
        <body>
        \(processedBody)
        </body>
        </html>
        """
        
        return styledHTML
    }
    
    /// Get MIME type for image file
    private func mimeTypeForImage(at url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "svg":
            return "image/svg+xml"
        case "webp":
            return "image/webp"
        default:
            return nil
        }
    }
    
    /// Apply custom styling to the attributed string
    /// This respects the EPUB's original styling while ensuring readability
    private func applyCustomStyling(to attributedString: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attributedString.length)
        
        // Set text color to adapt to dark/light mode
        attributedString.addAttribute(.foregroundColor, value: UIColor.label, range: fullRange)
        
        // Track if we've found headings for drop cap placement
        var hasFoundHeading = false
        var headingEndLocation = 0
        
        // Create base paragraph style with good line spacing
        let baseParagraphStyle = NSMutableParagraphStyle()
        baseParagraphStyle.lineSpacing = 8
        baseParagraphStyle.paragraphSpacing = 18
        
        // First pass: identify headings and ensure minimum font sizes
        attributedString.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            guard let font = value as? UIFont else { return }
            
            let fontDescriptor = font.fontDescriptor
            let traits = fontDescriptor.symbolicTraits
            let isBold = traits.contains(.traitBold)
            
            // Detect headings (larger text or bold text that's reasonably sized)
            let isHeading = font.pointSize >= 22 || (isBold && font.pointSize >= 18)
            
            if isHeading {
                hasFoundHeading = true
                headingEndLocation = max(headingEndLocation, range.location + range.length)
                
                // Center headings with extra spacing
                let headingStyle = NSMutableParagraphStyle()
                headingStyle.alignment = .center
                headingStyle.paragraphSpacingBefore = 24
                headingStyle.paragraphSpacing = 20
                headingStyle.lineSpacing = 6
                attributedString.addAttribute(.paragraphStyle, value: headingStyle, range: range)
            } else {
                // Body text - ensure minimum size and apply line spacing
                let minFontSize: CGFloat = 20
                if font.pointSize < minFontSize {
                    let scaledFont = font.withSize(minFontSize)
                    attributedString.addAttribute(.font, value: scaledFont, range: range)
                }
                
                // Apply paragraph style with line spacing
                attributedString.addAttribute(.paragraphStyle, value: baseParagraphStyle, range: range)
            }
        }
        
        // Apply drop cap to the first letter after headings
        applyDropCap(to: attributedString, startingAfter: headingEndLocation)
    }
    
    /// Apply drop cap styling to the first letter of content
    private func applyDropCap(to attributedString: NSMutableAttributedString, startingAfter: Int) {
        let string = attributedString.string
        guard string.count > startingAfter else { return }
        
        // Find the first letter character after the heading
        let searchStartIndex = string.index(string.startIndex, offsetBy: startingAfter)
        let substring = string[searchStartIndex...]
        
        // Skip whitespace and find the first letter
        guard let firstLetterIndex = substring.firstIndex(where: { $0.isLetter }) else {
            return
        }
        
        let letterPosition = string.distance(from: string.startIndex, to: firstLetterIndex)
        guard letterPosition < attributedString.length else { return }
        
        let letterRange = NSRange(location: letterPosition, length: 1)
        
        // Check if this letter is already styled as a drop cap (large font)
        if let currentFont = attributedString.attribute(.font, at: letterPosition, effectiveRange: nil) as? UIFont {
            // If already large (drop cap from EPUB), don't modify
            if currentFont.pointSize >= 28 {
                return
            }
        }
        
        // Create a large drop cap font matching the EPUB's font family if possible
        let dropCapSize: CGFloat = 48
        let dropCapFont: UIFont
        
        if let currentFont = attributedString.attribute(.font, at: letterPosition, effectiveRange: nil) as? UIFont {
            // Try to use the same font family, just larger
            dropCapFont = currentFont.withSize(dropCapSize)
        } else if let georgiaFont = UIFont(name: "Georgia", size: dropCapSize) {
            dropCapFont = georgiaFont
        } else {
            dropCapFont = UIFont.systemFont(ofSize: dropCapSize, weight: .regular)
        }
        
        attributedString.addAttribute(.font, value: dropCapFont, range: letterRange)
    }
    
    /// Get the total chapter count
    var pageCount: Int {
        return pages.count
    }
    
    /// Get chapter index for a given page
    func chapterIndex(for pageIndex: Int) -> Int {
        guard pageIndex >= 0 && pageIndex < pages.count else {
            return 0
        }
        return pages[pageIndex].chapterIndex
    }
    
    /// Get the first page index for a chapter
    func firstPageIndex(for chapterIndex: Int) -> Int? {
        return pages.firstIndex { $0.chapterIndex == chapterIndex }
    }
}

