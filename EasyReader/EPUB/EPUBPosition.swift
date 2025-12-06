//
//  EPUBPosition.swift
//  EasyReader
//
//  Created by Sammy Yousif on 12/2/25.
//

import Foundation

/// Represents a stable reading position in an EPUB that can be restored regardless of screen size.
/// Uses a combination of chapter index, paragraph index, and character offset for precise positioning.
struct EPUBPosition: Codable, Equatable {
    /// The index of the chapter (spine item) in the EPUB
    let chapterIndex: Int
    
    /// The paragraph index within the chapter (0-based)
    /// This provides coarse positioning that's stable across font/screen changes
    let paragraphIndex: Int
    
    /// The character offset from the start of the paragraph
    /// This provides fine-grained positioning within a paragraph
    let characterOffset: Int
    
    /// A short snippet of text around the position for validation/recovery
    /// Used to find the position if paragraph structure changes slightly
    let contextSnippet: String
    
    /// Percentage through the chapter (for fallback/display purposes)
    let chapterProgress: Double
    
    /// Percentage through the entire book (for display)
    let bookProgress: Double
    
    /// Creates a position at the start of a chapter
    static func chapterStart(chapterIndex: Int, totalChapters: Int) -> EPUBPosition {
        return EPUBPosition(
            chapterIndex: chapterIndex,
            paragraphIndex: 0,
            characterOffset: 0,
            contextSnippet: "",
            chapterProgress: 0.0,
            bookProgress: Double(chapterIndex) / Double(max(totalChapters, 1))
        )
    }
    
    /// Creates a position at the start of the book
    static var bookStart: EPUBPosition {
        return EPUBPosition(
            chapterIndex: 0,
            paragraphIndex: 0,
            characterOffset: 0,
            contextSnippet: "",
            chapterProgress: 0.0,
            bookProgress: 0.0
        )
    }
    
    /// Encodes to a JSON string for storage
    func encode() -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// Decodes from a JSON string
    static func decode(from string: String) -> EPUBPosition? {
        guard let data = string.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(EPUBPosition.self, from: data)
    }
}

/// Represents paragraph information for stable position tracking
struct EPUBParagraph {
    /// The range of this paragraph in the attributed string
    let range: NSRange
    
    /// The paragraph index (0-based within the chapter)
    let index: Int
    
    /// The starting character offset from the beginning of the chapter
    var startOffset: Int { range.location }
    
    /// The ending character offset
    var endOffset: Int { range.location + range.length }
    
    /// Check if a character offset falls within this paragraph
    func contains(characterOffset: Int) -> Bool {
        return characterOffset >= startOffset && characterOffset < endOffset
    }
}

/// Helper to extract paragraphs from attributed string
class EPUBParagraphExtractor {
    
    /// Extract paragraph ranges from an attributed string
    static func extractParagraphs(from attributedString: NSAttributedString) -> [EPUBParagraph] {
        let string = attributedString.string
        var paragraphs: [EPUBParagraph] = []
        var paragraphIndex = 0
        
        string.enumerateSubstrings(
            in: string.startIndex..<string.endIndex,
            options: .byParagraphs
        ) { _, substringRange, _, _ in
            let nsRange = NSRange(substringRange, in: string)
            let paragraph = EPUBParagraph(range: nsRange, index: paragraphIndex)
            paragraphs.append(paragraph)
            paragraphIndex += 1
        }
        
        return paragraphs
    }
    
    /// Find the paragraph containing a given character offset
    static func findParagraph(containing offset: Int, in paragraphs: [EPUBParagraph]) -> EPUBParagraph? {
        return paragraphs.first { $0.contains(characterOffset: offset) }
    }
    
    /// Extract a context snippet around a character offset
    static func extractContextSnippet(
        from string: String,
        at offset: Int,
        length: Int = 50
    ) -> String {
        let startIndex = string.index(string.startIndex, offsetBy: max(0, offset - length/2), limitedBy: string.endIndex) ?? string.startIndex
        let endIndex = string.index(startIndex, offsetBy: length, limitedBy: string.endIndex) ?? string.endIndex
        
        return String(string[startIndex..<endIndex])
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
    
    /// Find a character offset by searching for a context snippet
    /// Returns the best matching offset, or nil if not found
    static func findOffset(byContext snippet: String, in string: String, nearOffset hint: Int) -> Int? {
        guard !snippet.isEmpty else { return nil }
        
        // Clean the snippet for searching
        let cleanSnippet = snippet.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        let cleanString = string.replacingOccurrences(of: "\n", with: " ")
        
        // Try exact match first
        if let range = cleanString.range(of: cleanSnippet) {
            return cleanString.distance(from: cleanString.startIndex, to: range.lowerBound)
        }
        
        // Try finding with first few words
        let words = cleanSnippet.split(separator: " ").prefix(5).joined(separator: " ")
        if words.count >= 10, let range = cleanString.range(of: words) {
            return cleanString.distance(from: cleanString.startIndex, to: range.lowerBound)
        }
        
        return nil
    }
}
