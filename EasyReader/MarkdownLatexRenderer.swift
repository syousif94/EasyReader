//
//  MarkdownLatexRenderer.swift
//  EasyReader
//
//  Created by Sammy Yousif on 12/1/25.
//

import UIKit
import Down

/// Configuration for markdown styling
struct MarkdownStyleConfiguration {
    /// Font size for body/paragraph text
    var paragraphFontSize: CGFloat = 17
    
    /// Font size for H1 headings
    var h1FontSize: CGFloat = 28
    
    /// Font size for H2 headings
    var h2FontSize: CGFloat = 24
    
    /// Font size for H3 headings
    var h3FontSize: CGFloat = 20
    
    /// Font size for H4 headings
    var h4FontSize: CGFloat = 18
    
    /// Font size for H5 headings
    var h5FontSize: CGFloat = 16
    
    /// Font size for H6 headings
    var h6FontSize: CGFloat = 14
    
    /// Font size for code blocks
    var codeFontSize: CGFloat = 15
    
    /// Line height multiplier
    var lineHeightMultiple: CGFloat = 1.4
    
    /// Paragraph spacing
    var paragraphSpacing: CGFloat = 12
    
    /// Text color for light mode
    var textColor: UIColor = .label
    
    /// Code background color
    var codeBackgroundColor: UIColor = .secondarySystemBackground
    
    /// Blockquote color
    var blockquoteColor: UIColor = .secondaryLabel
}

/// Renders mixed markdown and LaTeX content to NSAttributedString
class MarkdownLatexRenderer {
    
    static let shared = MarkdownLatexRenderer()
    
    /// Style configuration for markdown rendering
    var styleConfig = MarkdownStyleConfiguration()
    
    /// Font size for body text (convenience accessor)
    var bodyFontSize: CGFloat {
        get { styleConfig.paragraphFontSize }
        set { styleConfig.paragraphFontSize = newValue }
    }
    
    /// Font size for inline LaTeX equations
    #if targetEnvironment(macCatalyst)
    var latexFontSize: CGFloat = 28
    #else
    var latexFontSize: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 28 : 18
    #endif
    
    /// Font size for display (block) LaTeX equations
    #if targetEnvironment(macCatalyst)
    var displayLatexFontSize: CGFloat = 32
    #else
    var displayLatexFontSize: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 32 : 28
    #endif
    
    /// Paragraph spacing (convenience accessor)
    var paragraphSpacing: CGFloat {
        get { styleConfig.paragraphSpacing }
        set { styleConfig.paragraphSpacing = newValue }
    }
    
    /// Line height multiplier (convenience accessor)
    var lineHeightMultiple: CGFloat {
        get { styleConfig.lineHeightMultiple }
        set { styleConfig.lineHeightMultiple = newValue }
    }
    
    /// Scale factor for LaTeX images (0.0-1.0)
    var latexImageScale: CGFloat = 1
    
    private let latexRenderer = LatexImageRenderer.shared
    
    private init() {}
    
    /// Renders markdown with LaTeX to an NSAttributedString
    /// - Parameters:
    ///   - input: The input string containing markdown and LaTeX
    ///   - width: The width available for rendering (used for image sizing)
    ///   - isDarkMode: Whether to render for dark mode
    /// - Returns: An NSAttributedString with rendered content
    func render(_ input: String, width: CGFloat, isDarkMode: Bool) -> NSAttributedString {
        // Extract LaTeX blocks and get markdown with placeholders
        let (markdownWithPlaceholders, latexBlocks) = MarkdownLatexParser.extractLatex(input)
        
        // Pre-render all LaTeX images with appropriate font sizes
        var latexImages: [String: (light: UIImage?, dark: UIImage?, isDisplay: Bool)] = [:]
        for block in latexBlocks {
            // Use display font size for display blocks, inline font size for inline
            latexRenderer.fontSize = block.isDisplay ? displayLatexFontSize : latexFontSize
            let images = latexRenderer.renderLatexForBothModes(block.latex, maxWidth: width - 40)
            latexImages[block.placeholder] = (images.light, images.dark, block.isDisplay)
        }
        
        // Parse markdown with Down
        let attributedString = parseMarkdown(markdownWithPlaceholders, isDarkMode: isDarkMode)
        
        // Replace placeholders with LaTeX images
        let finalString = replaceLatexPlaceholders(
            in: attributedString,
            latexImages: latexImages,
            isDarkMode: isDarkMode,
            maxWidth: width - 40
        )
        
        return finalString
    }
    
    /// Renders markdown with LaTeX, returning attributed string with dynamic image attachments
    /// that automatically update for light/dark mode
    /// - Parameters:
    ///   - input: The input string containing markdown and LaTeX
    ///   - width: The width available for rendering
    /// - Returns: A tuple with the attributed string and a list of dynamic attachments that need updating on trait change
    func renderWithDynamicImages(_ input: String, width: CGFloat) -> (attributedString: NSMutableAttributedString, attachments: [DynamicImageTextAttachment]) {
        // Extract LaTeX blocks and get markdown with placeholders
        let (markdownWithPlaceholders, latexBlocks) = MarkdownLatexParser.extractLatex(input)
        
        // Pre-render all LaTeX images for both modes with appropriate font sizes
        var latexImages: [String: (light: UIImage?, dark: UIImage?, isDisplay: Bool)] = [:]
        for block in latexBlocks {
            // Use display font size for display blocks, inline font size for inline
            latexRenderer.fontSize = block.isDisplay ? displayLatexFontSize : latexFontSize
            let images = latexRenderer.renderLatexForBothModes(block.latex, maxWidth: width - 40)
            latexImages[block.placeholder] = (images.light, images.dark, block.isDisplay)
        }
        
        // Determine current mode
        let isDarkMode = UITraitCollection.current.userInterfaceStyle == .dark
        
        // Parse markdown with Down
        let attributedString = parseMarkdown(markdownWithPlaceholders, isDarkMode: isDarkMode)
        
        // Replace placeholders with dynamic LaTeX images
        let (finalString, attachments) = replaceLatexPlaceholdersWithDynamic(
            in: attributedString,
            latexImages: latexImages,
            maxWidth: width - 40
        )
        
        return (finalString, attachments)
    }
    
    // MARK: - Private Methods
    
    private func createDownStyler() -> DownStyler {
        let config = styleConfig
        
        // Create fonts for different heading levels
        let fonts = StaticFontCollection(
            heading1: .boldSystemFont(ofSize: config.h1FontSize),
            heading2: .boldSystemFont(ofSize: config.h2FontSize),
            heading3: .boldSystemFont(ofSize: config.h3FontSize),
            heading4: .boldSystemFont(ofSize: config.h4FontSize),
            heading5: .boldSystemFont(ofSize: config.h5FontSize),
            heading6: .boldSystemFont(ofSize: config.h6FontSize),
            body: .systemFont(ofSize: config.paragraphFontSize),
            code: .monospacedSystemFont(ofSize: config.codeFontSize, weight: .regular),
            listItemPrefix: .monospacedDigitSystemFont(ofSize: config.paragraphFontSize, weight: .regular)
        )
        
        // Create colors
        let colors = StaticColorCollection(
            heading1: config.textColor,
            heading2: config.textColor,
            heading3: config.textColor,
            heading4: config.textColor,
            heading5: config.textColor,
            heading6: config.textColor,
            body: config.textColor,
            code: config.textColor,
            link: .systemBlue,
            quote: config.blockquoteColor,
            quoteStripe: config.blockquoteColor,
            thematicBreak: .separator,
            listItemPrefix: .secondaryLabel,
            codeBlockBackground: config.codeBackgroundColor
        )
        
        
        
        // Create paragraph styles
        let paragraphStyles = StaticParagraphStyleCollection()
        
        // Create styler configuration
        let stylerConfig = DownStylerConfiguration(
            fonts: fonts,
            colors: colors,
            paragraphStyles: paragraphStyles
        )
        
        return DownStyler(configuration: stylerConfig)
    }
    
    private func createBodyParagraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = styleConfig.lineHeightMultiple
        style.paragraphSpacing = styleConfig.paragraphSpacing
        return style
    }
    
    private func createHeadingParagraphStyle(spacing: CGFloat) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.2
        style.paragraphSpacingBefore = spacing
        style.paragraphSpacing = spacing * 0.5
        return style
    }
    
    private func createCodeParagraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.3
        style.paragraphSpacing = styleConfig.paragraphSpacing * 0.5
        return style
    }
    
    private func parseMarkdown(_ markdown: String, isDarkMode: Bool) -> NSMutableAttributedString {
        let down = Down(markdownString: markdown)
        
        // Create custom styler with our configuration
        let styler = createDownStyler()
        
        // Try to get attributed string from Down with custom styling
        do {
            let attributedString = try down.toAttributedString(styler: styler)
            let mutableString = NSMutableAttributedString(attributedString: attributedString)
            return mutableString
        } catch {
            // Fallback to plain text
            let paragraphStyle = createBodyParagraphStyle()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: styleConfig.paragraphFontSize),
                .foregroundColor: isDarkMode ? UIColor.white : UIColor.black,
                .paragraphStyle: paragraphStyle
            ]
            return NSMutableAttributedString(string: markdown, attributes: attributes)
        }
    }
    
    private func replaceLatexPlaceholders(
        in attributedString: NSMutableAttributedString,
        latexImages: [String: (light: UIImage?, dark: UIImage?, isDisplay: Bool)],
        isDarkMode: Bool,
        maxWidth: CGFloat
    ) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        
//        // Sort placeholders by index (descending) to avoid offset issues when replacing
//        let sortedPlaceholders = latexImages.keys.sorted { placeholder1, placeholder2 in
//            guard let range1 = mutableString.string.range(of: placeholder1),
//                  let range2 = mutableString.string.range(of: placeholder2) else {
//                return false
//            }
//            return range1.lowerBound > range2.lowerBound
//        }
//        
//        for placeholder in sortedPlaceholders {
//            guard let imageData = latexImages[placeholder],
//                  let range = mutableString.string.range(of: placeholder) else {
//                continue
//            }
//            
//            let nsRange = NSRange(range, in: mutableString.string)
//            let image = isDarkMode ? imageData.dark : imageData.light
//            
//            guard let img = image else {
//                continue
//            }
//            
//            // Create text attachment with image
//            let attachment = NSTextAttachment()
//            attachment.image = img
//            
//            // Calculate bounds - scale down and fit within maxWidth
//            let size = CGSize(width: img.size.width * latexImageScale, height: img.size.height * latexImageScale)
//            
//            // For display math, center the image using baseline offset
//            if imageData.isDisplay {
//                attachment.bounds = CGRect(x: 0, y: -size.height * 0.1, width: size.width, height: size.height)
//            } else {
//                // For inline math, vertically center with text
//                let yOffset = -(size.height - bodyFontSize) / 2
//                attachment.bounds = CGRect(x: 0, y: yOffset, width: size.width, height: size.height)
//            }
//            
//            let attachmentString = NSMutableAttributedString(attachment: attachment)
//            
//            // For display math, wrap with paragraph style for centering
//            if imageData.isDisplay {
//                let paragraphStyle = NSMutableParagraphStyle()
//                paragraphStyle.alignment = .center
//                paragraphStyle.paragraphSpacingBefore = 12
//                paragraphStyle.paragraphSpacing = 12
//                
//                // Add newlines and center alignment
//                let centeredAttachment = NSMutableAttributedString(string: "\n")
//                centeredAttachment.append(attachmentString)
//                centeredAttachment.append(NSAttributedString(string: "\n"))
//                centeredAttachment.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: centeredAttachment.length))
//                
//                mutableString.replaceCharacters(in: nsRange, with: centeredAttachment)
//            } else {
//                mutableString.replaceCharacters(in: nsRange, with: attachmentString)
//            }
//        }
        
        return mutableString
    }
    
    private func replaceLatexPlaceholdersWithDynamic(
        in attributedString: NSMutableAttributedString,
        latexImages: [String: (light: UIImage?, dark: UIImage?, isDisplay: Bool)],
        maxWidth: CGFloat
    ) -> (NSMutableAttributedString, [DynamicImageTextAttachment]) {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        var attachments: [DynamicImageTextAttachment] = []
        
        // Sort placeholders by index (descending) to avoid offset issues when replacing
        let sortedPlaceholders = latexImages.keys.sorted { placeholder1, placeholder2 in
            guard let range1 = mutableString.string.range(of: placeholder1),
                  let range2 = mutableString.string.range(of: placeholder2) else {
                return false
            }
            return range1.lowerBound > range2.lowerBound
        }
        
        for placeholder in sortedPlaceholders {
            guard let imageData = latexImages[placeholder],
                  let range = mutableString.string.range(of: placeholder) else {
                continue
            }
            
            let nsRange = NSRange(range, in: mutableString.string)
            
            // Create dynamic text attachment
            let attachment = DynamicImageTextAttachment(lightImage: imageData.light, darkImage: imageData.dark)
            attachments.append(attachment)
            
            // Get current image for size calculation - if no image, highlight the placeholder
            guard let currentImage = attachment.image else {
                // No image available - highlight the placeholder text with yellow background
                mutableString.addAttribute(.backgroundColor, value: UIColor.systemYellow, range: nsRange)
                continue
            }
            
            // Calculate bounds - scale down and fit within maxWidth
            var size = CGSize(width: currentImage.size.width * latexImageScale, height: currentImage.size.height * latexImageScale)
//            if size.width > maxWidth {
//                let scale = maxWidth / size.width
//                size = CGSize(width: maxWidth, height: size.height * scale)
//            }
            
            // Set bounds based on display mode
            if imageData.isDisplay {
                attachment.bounds = CGRect(x: 0, y: -size.height * 0.1, width: size.width, height: size.height)
            } else {
                let yOffset = -(size.height - bodyFontSize) / 2
                attachment.bounds = CGRect(x: 0, y: yOffset, width: size.width, height: size.height)
            }
            
            let attachmentString = NSMutableAttributedString(attachment: attachment)
            
            // For display math, wrap with paragraph style for centering
            if imageData.isDisplay {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center
                paragraphStyle.paragraphSpacingBefore = 12
                paragraphStyle.paragraphSpacing = 12
                
                let centeredAttachment = NSMutableAttributedString(string: "\n")
                centeredAttachment.append(attachmentString)
                centeredAttachment.append(NSAttributedString(string: "\n"))
                centeredAttachment.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: centeredAttachment.length))
                
                mutableString.replaceCharacters(in: nsRange, with: centeredAttachment)
            } else {
                mutableString.replaceCharacters(in: nsRange, with: attachmentString)
            }
        }
        
        return (mutableString, attachments)
    }
}
