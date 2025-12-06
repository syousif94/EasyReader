//
//  LatexImageRenderer.swift
//  EasyReader
//
//  Created by Sammy Yousif on 12/1/25.
//

import UIKit
import SwiftMath
import CryptoKit

/// Renders LaTeX strings to UIImages using SwiftMath
/// Supports both light and dark mode with disk-based caching in tmp directory
class LatexImageRenderer {
    
    static let shared = LatexImageRenderer()
    
    /// Directory for caching rendered LaTeX images
    private let cacheDirectory: URL
    
    /// Font size for LaTeX rendering
    var fontSize: CGFloat = 16
    
    private init() {
        // Create cache directory in tmp
        let tmpDir = FileManager.default.temporaryDirectory
        cacheDirectory = tmpDir.appendingPathComponent("LatexImageCache", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// Clears the image cache
    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// Generates a cache file URL for given parameters
    private func cacheFileURL(for latex: String, isDarkMode: Bool, fontSize: CGFloat) -> URL {
        let key = "\(latex)_\(isDarkMode)_\(fontSize)"
        let hash = SHA256.hash(data: Data(key.utf8))
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent("\(hashString).png")
    }
    
    /// Loads a cached image from disk if it exists
    private func loadCachedImage(from url: URL) -> UIImage? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        
        // Recreate with proper scale (images are saved at 3x)
        return UIImage(cgImage: image.cgImage!, scale: 3.0, orientation: .up)
    }
    
    /// Saves an image to disk cache
    private func saveToCache(_ image: UIImage, at url: URL) {
        guard let data = image.pngData() else { return }
        try? data.write(to: url)
    }
    
    /// Preprocesses LaTeX to replace unsupported commands with SwiftMath-compatible alternatives
    private func preprocessLatex(_ latex: String) -> String {
        var result = latex
        
        // Replace \underset{sub}{main} with {main}_{sub} - handle nested braces (do this first)
        result = replaceUnderset(in: result)
        
        // Replace \boldsymbol{...} - just extract the content, SwiftMath doesn't support bold Greek
        result = replaceCommand(in: result, command: "\\boldsymbol", replacement: nil)
        
        // Replace \operatorname{name} - just output the operator name plainly
        result = replaceCommand(in: result, command: "\\operatorname", replacement: nil)
        
        // Replace \text{...} - just output the text
        result = replaceCommand(in: result, command: "\\text", replacement: nil)
        
        // Replace \textbf{...} - just extract content
        result = replaceCommand(in: result, command: "\\textbf", replacement: nil)
        
        // Replace \textit{...} - just extract content
        result = replaceCommand(in: result, command: "\\textit", replacement: nil)
        
        // Replace \mathbf{} containing Greek letters - just extract the content
        // SwiftMath doesn't support \mathbf with Greek letters
        result = result.replacingOccurrences(
            of: #"\\mathbf\{(\\[a-zA-Z]+)\}"#,
            with: "$1",
            options: .regularExpression
        )
        
        // Remove matrix environments entirely - SwiftMath doesn't support them well
        // Just strip out the matrix markup and leave content as-is
        result = result.replacingOccurrences(of: "\\begin{pmatrix}", with: "")
        result = result.replacingOccurrences(of: "\\end{pmatrix}", with: "")
        result = result.replacingOccurrences(of: "\\begin{bmatrix}", with: "")
        result = result.replacingOccurrences(of: "\\end{bmatrix}", with: "")
        result = result.replacingOccurrences(of: "\\begin{vmatrix}", with: "")
        result = result.replacingOccurrences(of: "\\end{vmatrix}", with: "")
        result = result.replacingOccurrences(of: "\\begin{matrix}", with: "")
        result = result.replacingOccurrences(of: "\\end{matrix}", with: "")
        
        // Remove array environments - SwiftMath doesn't support them
        // Handle \begin{array}{...} with column specifiers
        result = result.replacingOccurrences(
            of: #"\\begin\{array\}\{[^}]*\}"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: "\\end{array}", with: "")
        
        // Remove align/aligned environments
        result = result.replacingOccurrences(of: "\\begin{align}", with: "")
        result = result.replacingOccurrences(of: "\\end{align}", with: "")
        result = result.replacingOccurrences(of: "\\begin{align*}", with: "")
        result = result.replacingOccurrences(of: "\\end{align*}", with: "")
        result = result.replacingOccurrences(of: "\\begin{aligned}", with: "")
        result = result.replacingOccurrences(of: "\\end{aligned}", with: "")
        
        // Remove cases environment
        result = result.replacingOccurrences(of: "\\begin{cases}", with: "")
        result = result.replacingOccurrences(of: "\\end{cases}", with: "")
        
        // Remove | used as column separators in matrices
        // Be careful not to remove | used for absolute value - only remove when surrounded by spaces or &
        result = result.replacingOccurrences(
            of: #"\s*\|\s*&"#,
            with: " ",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"&\s*\|\s*"#,
            with: " ",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\|\s*\|"#,
            with: "",
            options: .regularExpression
        )
        
        // Replace \\ (newline in matrix) with space
        result = result.replacingOccurrences(of: " \\\\ ", with: " ")
        result = result.replacingOccurrences(of: "\\\\", with: " ")
        
        // Replace \ followed by space (alternative row separator sometimes used in matrices)
        // This handles cases like "3 \ 1" which should be treated as a row break
        result = result.replacingOccurrences(
            of: #"\\\s+(?=[a-zA-Z0-9\-])"#,
            with: " ",
            options: .regularExpression
        )
        
        // Replace & (column separator) with space
        result = result.replacingOccurrences(of: " & ", with: " ")
        result = result.replacingOccurrences(of: "&", with: " ")
        
        // Replace various dots commands with \cdots (which SwiftMath supports)
        result = result.replacingOccurrences(of: "\\vdots", with: "\\cdots")
        result = result.replacingOccurrences(of: "\\hdots", with: "\\cdots")
        result = result.replacingOccurrences(of: "\\dots", with: "\\cdots")
        result = result.replacingOccurrences(of: "\\ldots", with: "\\cdots")
        
        // Replace arrow commands that SwiftMath may not support
        result = result.replacingOccurrences(of: "\\implies", with: "\\Rightarrow")
        result = result.replacingOccurrences(of: "\\iff", with: "\\Leftrightarrow")
        result = result.replacingOccurrences(of: "\\impliedby", with: "\\Leftarrow")
        
        // Clean up multiple spaces
        result = result.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        
        return result
    }
    
    /// Replaces a LaTeX command with optional replacement, handling nested braces
    /// If replacement is nil, just extracts the content without the command
    private func replaceCommand(in latex: String, command: String, replacement: String?) -> String {
        var result = latex
        let searchString = command + "{"
        
        while let range = result.range(of: searchString) {
            let startIndex = range.lowerBound
            let braceStart = result.index(before: range.upperBound)
            
            guard let (content, afterBrace) = extractBraceGroup(from: result, startingAt: braceStart) else {
                break
            }
            
            let replacementString: String
            if let repl = replacement {
                replacementString = "\(repl){\(content)}"
            } else {
                replacementString = content
            }
            
            result.replaceSubrange(startIndex..<afterBrace, with: replacementString)
        }
        
        return result
    }
    
    /// Replaces \underset{sub}{main} with {main}_{sub}, handling nested braces
    private func replaceUnderset(in latex: String) -> String {
        var result = latex
        
        // Find \underset and manually parse the two brace groups
        while let range = result.range(of: "\\underset{") {
            let startIndex = range.lowerBound
            let afterUnderset = range.upperBound
            
            // Parse first brace group (subscript)
            guard let (sub, afterSub) = extractBraceGroup(from: result, startingAt: result.index(before: afterUnderset)) else {
                break
            }
            
            // Parse second brace group (main content)
            guard let (main, afterMain) = extractBraceGroup(from: result, startingAt: afterSub) else {
                break
            }
            
            // Replace \underset{sub}{main} with {main}_{sub}
            let replacement = "{\(main)}_{\(sub)}"
            result.replaceSubrange(startIndex..<afterMain, with: replacement)
        }
        
        return result
    }
    
    /// Extracts content within balanced braces starting at given index
    /// - Returns: Tuple of (content inside braces, index after closing brace) or nil if invalid
    private func extractBraceGroup(from string: String, startingAt start: String.Index) -> (String, String.Index)? {
        guard start < string.endIndex, string[start] == "{" else {
            return nil
        }
        
        var depth = 0
        var current = start
        var contentStart: String.Index?
        
        while current < string.endIndex {
            let char = string[current]
            if char == "{" {
                if depth == 0 {
                    contentStart = string.index(after: current)
                }
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    guard let start = contentStart else { return nil }
                    let content = String(string[start..<current])
                    return (content, string.index(after: current))
                }
            }
            current = string.index(after: current)
        }
        
        return nil
    }
    
    /// Renders a LaTeX string to a UIImage
    /// - Parameters:
    ///   - latex: The LaTeX string to render (without $ delimiters)
    ///   - isDarkMode: Whether to render for dark mode
    ///   - maxWidth: Maximum width for the rendered image
    /// - Returns: A UIImage of the rendered LaTeX, or nil if rendering fails
    func renderLatex(_ latex: String, isDarkMode: Bool, maxWidth: CGFloat? = nil) -> UIImage? {
        // Preprocess to handle unsupported commands
        let processedLatex = preprocessLatex(latex)
        
        let cacheURL = cacheFileURL(for: latex, isDarkMode: isDarkMode, fontSize: fontSize)
        
        // Check disk cache first
        if let cachedImage = loadCachedImage(from: cacheURL) {
            return cachedImage
        }
        
        // Render at 3x resolution for crisp display
        let renderScale: CGFloat = 3.0
        
        // Create MTMathUILabel for rendering
        let mathLabel = MTMathUILabel()
        mathLabel.latex = processedLatex
        mathLabel.fontSize = fontSize  // Scale up font for 3x rendering
        mathLabel.textAlignment = .center
        mathLabel.labelMode = .display
        
        // Set colors based on appearance
        if isDarkMode {
            mathLabel.textColor = .white
            mathLabel.backgroundColor = .clear
        } else {
            mathLabel.textColor = .black
            mathLabel.backgroundColor = .clear
        }
        
        // Calculate intrinsic size at 3x scale
        let intrinsicSize = mathLabel.intrinsicContentSize
        
        guard intrinsicSize.width > 0 && intrinsicSize.height > 0 else {
            print("[LatexImageRenderer] Failed to render LaTeX: \(latex)")
            print("[LatexImageRenderer] Processed LaTeX was: \(processedLatex)")
            return nil
        }
        
        // Set frame for rendering at 3x
        mathLabel.frame = CGRect(origin: .zero, size: intrinsicSize)
        
        // Render to image at 3x resolution with vertical flip
        let renderer = UIGraphicsImageRenderer(size: intrinsicSize)
        let image = renderer.image { context in
            let cgContext = context.cgContext
            
            // Flip vertically: translate to bottom, then scale Y by -1
            cgContext.translateBy(x: 0, y: intrinsicSize.height)
            cgContext.scaleBy(x: 1, y: -1)
            
            mathLabel.layer.render(in: cgContext)
        }
        
        // Calculate the final display size (1/3 of render size)
        let displaySize = CGSize(
            width: intrinsicSize.width / renderScale,
            height: intrinsicSize.height / renderScale
        )
        
        // Apply max width constraint if needed
        var finalSize = displaySize
        if let maxWidth = maxWidth, displaySize.width > maxWidth {
            let scale = maxWidth / displaySize.width
            finalSize = CGSize(width: maxWidth, height: displaySize.height * scale)
        }
        
        // Create final image with proper scale factor for display
        // The image has 3x pixels but will display at 1x size
        let finalImage = UIImage(cgImage: image.cgImage!, scale: renderScale, orientation: .up)
        
        // Save to disk cache
        saveToCache(finalImage, at: cacheURL)
        
        return finalImage
    }
    
    /// Renders LaTeX and returns images for both light and dark mode
    /// - Parameters:
    ///   - latex: The LaTeX string to render
    ///   - maxWidth: Maximum width for the rendered image
    /// - Returns: A tuple with light and dark mode images
    func renderLatexForBothModes(_ latex: String, maxWidth: CGFloat? = nil) -> (light: UIImage?, dark: UIImage?) {
        let lightImage = renderLatex(latex, isDarkMode: false, maxWidth: maxWidth)
        let darkImage = renderLatex(latex, isDarkMode: true, maxWidth: maxWidth)
        return (lightImage, darkImage)
    }
}

/// A UIImage subclass that automatically switches between light and dark variants
class DynamicLatexImage: UIImage {
    var lightImage: UIImage?
    var darkImage: UIImage?
    
    convenience init?(lightImage: UIImage?, darkImage: UIImage?) {
        guard let light = lightImage, let dark = darkImage else {
            return nil
        }
        
        // Initialize with the light image as base
        guard let cgImage = light.cgImage else {
            return nil
        }
        
        self.init(cgImage: cgImage, scale: light.scale, orientation: light.imageOrientation)
        self.lightImage = light
        self.darkImage = dark
    }
    
    func imageForCurrentMode() -> UIImage {
        let isDarkMode = UITraitCollection.current.userInterfaceStyle == .dark
        return (isDarkMode ? darkImage : lightImage) ?? self
    }
}

/// NSTextAttachment that supports dynamic light/dark mode images
class DynamicImageTextAttachment: NSTextAttachment {
    var lightImage: UIImage?
    var darkImage: UIImage?
    
    init(lightImage: UIImage?, darkImage: UIImage?) {
        super.init(data: nil, ofType: nil)
        self.lightImage = lightImage
        self.darkImage = darkImage
        updateImageForCurrentMode()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    func updateImageForCurrentMode() {
        let isDarkMode = UITraitCollection.current.userInterfaceStyle == .dark
        self.image = isDarkMode ? darkImage : lightImage
    }
    
    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect, glyphPosition position: CGPoint, characterIndex charIndex: Int) -> CGRect {
        guard let image = self.image else {
            return .zero
        }
        
        // Center the image and maintain aspect ratio
        let maxWidth = lineFrag.width
        var size = image.size
        
        if size.width > maxWidth {
            let scale = maxWidth / size.width
            size = CGSize(width: maxWidth, height: size.height * scale)
        }
        
        // Adjust Y position to vertically center with text baseline
        let yOffset = -(size.height - 12) / 2 // Adjust based on font metrics
        
        return CGRect(x: 0, y: yOffset, width: size.width, height: size.height)
    }
}
