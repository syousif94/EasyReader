//
//  MarkdownLatexParser.swift
//  EasyReader
//
//  Created by Sammy Yousif on 12/1/25.
//

import Foundation

/// Represents a parsed segment of text that may be markdown or LaTeX
enum ParsedSegment {
    case markdown(String)
    case inlineLatex(String)   // $...$
    case displayLatex(String)  // $$...$$
    
    var isLatex: Bool {
        switch self {
        case .markdown:
            return false
        case .inlineLatex, .displayLatex:
            return true
        }
    }
    
    var content: String {
        switch self {
        case .markdown(let content),
             .inlineLatex(let content),
             .displayLatex(let content):
            return content
        }
    }
}

/// Parses mixed markdown and LaTeX content
class MarkdownLatexParser {
    
    /// Placeholder format for LaTeX blocks during markdown processing
    static let placeholderPrefix = "<<<LATEX_"
    static let placeholderSuffix = ">>>"
    
    /// Parses a string containing mixed markdown and LaTeX
    /// - Parameter input: The input string with markdown and LaTeX
    /// - Returns: An array of parsed segments in order
    static func parse(_ input: String) -> [ParsedSegment] {
        var segments: [ParsedSegment] = []
        var currentIndex = input.startIndex
        
        // Pattern to match both $$ and $ delimited LaTeX
        // We need to match $$ first (greedy), then $
        // Using a simple state machine approach for reliability
        
        while currentIndex < input.endIndex {
            // Look for the next $ sign
            guard let dollarIndex = input[currentIndex...].firstIndex(of: "$") else {
                // No more LaTeX, rest is markdown
                let remaining = String(input[currentIndex...])
                if !remaining.isEmpty {
                    segments.append(.markdown(remaining))
                }
                break
            }
            
            // Add markdown content before this LaTeX block
            if dollarIndex > currentIndex {
                let markdownContent = String(input[currentIndex..<dollarIndex])
                if !markdownContent.isEmpty {
                    segments.append(.markdown(markdownContent))
                }
            }
            
            // Check if this is $$ (display math) or $ (inline math)
            let nextIndex = input.index(after: dollarIndex)
            let isDisplayMath = nextIndex < input.endIndex && input[nextIndex] == "$"
            
            if isDisplayMath {
                // Find closing $$
                let contentStart = input.index(dollarIndex, offsetBy: 2)
                if contentStart < input.endIndex,
                   let closingRange = input.range(of: "$$", range: contentStart..<input.endIndex) {
                    let latexContent = String(input[contentStart..<closingRange.lowerBound])
                    segments.append(.displayLatex(latexContent.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentIndex = closingRange.upperBound
                } else {
                    // No closing $$, treat rest as markdown
                    segments.append(.markdown(String(input[dollarIndex...])))
                    break
                }
            } else {
                // Find closing $ (but not $$)
                let contentStart = input.index(after: dollarIndex)
                if contentStart < input.endIndex {
                    var searchStart = contentStart
                    var foundClosing = false
                    
                    while searchStart < input.endIndex {
                        guard let closingIndex = input[searchStart...].firstIndex(of: "$") else {
                            break
                        }
                        
                        // Make sure it's not $$ (which would be display math delimiter)
                        let afterClosing = input.index(after: closingIndex)
                        if afterClosing < input.endIndex && input[afterClosing] == "$" {
                            // This is $$, skip past it
                            searchStart = input.index(after: afterClosing)
                            continue
                        }
                        
                        // Found a valid closing $
                        let latexContent = String(input[contentStart..<closingIndex])
                        let trimmedContent = latexContent.trimmingCharacters(in: .whitespaces)
                        
                        // Make sure content is not empty after trimming
                        // Allow content that contains LaTeX commands (starting with \) even if there are spaces
                        if !trimmedContent.isEmpty && (trimmedContent.contains("\\") || (!latexContent.hasPrefix(" ") && !latexContent.hasSuffix(" "))) {
                            segments.append(.inlineLatex(trimmedContent))
                            currentIndex = input.index(after: closingIndex)
                            foundClosing = true
                        } else if trimmedContent.isEmpty {
                            // Empty content, treat $ as literal
                            segments.append(.markdown("$"))
                            currentIndex = contentStart
                            foundClosing = true
                        } else {
                            // Likely not a LaTeX delimiter (has spaces but no commands), treat $ as literal
                            segments.append(.markdown("$"))
                            currentIndex = contentStart
                            foundClosing = true
                        }
                        break
                    }
                    
                    if !foundClosing {
                        // No closing $, treat as literal $
                        segments.append(.markdown("$"))
                        currentIndex = contentStart
                    }
                } else {
                    // $ at end of string
                    segments.append(.markdown("$"))
                    break
                }
            }
        }
        
        return segments
    }
    
    /// Extracts LaTeX blocks and returns markdown with placeholders
    /// - Parameter input: The input string with markdown and LaTeX
    /// - Returns: A tuple containing the modified markdown string and a dictionary mapping placeholders to LaTeX content
    static func extractLatex(_ input: String) -> (markdown: String, latexBlocks: [(placeholder: String, latex: String, isDisplay: Bool)]) {
        let segments = parse(input)
        var markdown = ""
        var latexBlocks: [(placeholder: String, latex: String, isDisplay: Bool)] = []
        var latexIndex = 0
        
        for segment in segments {
            switch segment {
            case .markdown(let content):
                markdown += content
                
            case .inlineLatex(let content):
                let placeholder = "\(placeholderPrefix)\(latexIndex)\(placeholderSuffix)"
                latexBlocks.append((placeholder: placeholder, latex: content, isDisplay: false))
                markdown += placeholder
                latexIndex += 1
                
            case .displayLatex(let content):
                let placeholder = "\(placeholderPrefix)\(latexIndex)\(placeholderSuffix)"
                latexBlocks.append((placeholder: placeholder, latex: content, isDisplay: true))
                // For display math, add newlines to ensure it's on its own line
                markdown += "\n\n\(placeholder)\n\n"
                latexIndex += 1
            }
        }
        
        return (markdown, latexBlocks)
    }
}
