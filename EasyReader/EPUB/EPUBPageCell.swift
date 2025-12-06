//
//  EPUBPageCell.swift
//  EasyReader
//
//  Created by Sammy Yousif on 12/2/25.
//

import UIKit
import PinLayout

/// Collection view cell for displaying EPUB chapter content with self-sizing
class EPUBPageCell: UICollectionViewCell {
    
    static let reuseIdentifier = "EPUBPageCell"
    
    /// Text view for rendering attributed string content
    let textView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.showsVerticalScrollIndicator = false
        tv.showsHorizontalScrollIndicator = false
        tv.isScrollEnabled = false
        tv.textContainerInset = UIEdgeInsets(top: 24, left: 20, bottom: 24, right: 20)
        tv.backgroundColor = .systemBackground
        return tv
    }()
    
    /// Transparent overlay for drawing annotations
    let drawingOverlay: EPUBDrawingOverlay = {
        let overlay = EPUBDrawingOverlay()
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = true
        return overlay
    }()
    
    /// Current page/chapter index
    var pageIndex: Int = 0
    
    /// Container width for sizing calculations
    private var containerWidth: CGFloat = 0
    
    /// Maximum text width for readability
    private static let maxTextWidth: CGFloat = 850
    /// Threshold for increased padding
    private static let widePaddingThreshold: CGFloat = 700
    /// Padding for narrow screens
    private static let narrowPadding: CGFloat = 20
    /// Padding for wide screens
    private static let widePadding: CGFloat = 80
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        contentView.backgroundColor = .systemBackground
        contentView.addSubview(textView)
        contentView.addSubview(drawingOverlay)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = contentView.bounds
        drawingOverlay.frame = contentView.bounds
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        // Update text color when appearance changes (light/dark mode)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateTextColorForCurrentAppearance()
        }
    }
    
    /// Update text color to match current appearance mode
    private func updateTextColorForCurrentAppearance() {
        guard let attributedText = textView.attributedText else { return }
        
        let mutableText = NSMutableAttributedString(attributedString: attributedText)
        let fullRange = NSRange(location: 0, length: mutableText.length)
        mutableText.addAttribute(.foregroundColor, value: UIColor.label, range: fullRange)
        textView.attributedText = mutableText
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        textView.attributedText = nil
        drawingOverlay.clearAnnotations()
        pageIndex = 0
        containerWidth = 0
    }
    
    /// Configure the cell with chapter content
    func configure(with page: EPUBPage, at index: Int, containerWidth: CGFloat) {
        textView.attributedText = page.attributedString
        pageIndex = index
        self.containerWidth = containerWidth
        
        // Calculate horizontal padding based on container width
        let horizontalPadding = Self.calculateHorizontalPadding(for: containerWidth)
        textView.textContainerInset = UIEdgeInsets(top: 24, left: horizontalPadding, bottom: 24, right: horizontalPadding)
    }
    
    /// Update container width and recalculate padding (for resize without reconfiguring content)
    func updateContainerWidth(_ newWidth: CGFloat) {
        guard newWidth != containerWidth else { return }
        containerWidth = newWidth
        
        let horizontalPadding = Self.calculateHorizontalPadding(for: newWidth)
        textView.textContainerInset = UIEdgeInsets(top: 24, left: horizontalPadding, bottom: 24, right: horizontalPadding)
    }
    
    /// Calculate horizontal padding for a given container width
    private static func calculateHorizontalPadding(for containerWidth: CGFloat) -> CGFloat {
        if containerWidth > widePaddingThreshold {
            // For wide screens, use larger padding and ensure max text width
            let textWidth = containerWidth - (widePadding * 2)
            if textWidth > maxTextWidth {
                // Center the text by using extra padding
                return (containerWidth - maxTextWidth) / 2
            }
            return widePadding
        }
        return narrowPadding
    }
    
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        
        // Calculate the required height based on text content
        let targetWidth = containerWidth > 0 ? containerWidth : layoutAttributes.frame.width
        
        // Use textView's sizeThatFits to calculate content height
        let insets = textView.textContainerInset
        let textWidth = targetWidth - insets.left - insets.right - textView.textContainer.lineFragmentPadding * 2
        
        if let attributedText = textView.attributedText {
            let boundingRect = attributedText.boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            let contentHeight = ceil(boundingRect.height) + insets.top + insets.bottom + 20 // Add extra padding
            attributes.frame.size = CGSize(width: targetWidth, height: max(contentHeight, 100))
        } else {
            attributes.frame.size = CGSize(width: targetWidth, height: 100)
        }
        
        return attributes
    }
    
    /// Enable or disable drawing mode
    func setDrawingEnabled(_ enabled: Bool) {
        drawingOverlay.isDrawingEnabled = enabled
        textView.isSelectable = !enabled
    }
    
    /// Capture a snapshot of the current page content (for AI analysis)
    func captureSnapshot() -> UIImage? {
        let renderer = UIGraphicsImageRenderer(bounds: contentView.bounds)
        return renderer.image { context in
            contentView.drawHierarchy(in: contentView.bounds, afterScreenUpdates: true)
        }
    }
    
    /// Capture a snapshot of a specific region (including drawing annotations)
    func captureSnapshot(in rect: CGRect) -> UIImage? {
        // Clamp rect to contentView bounds
        let clampedRect = rect.intersection(contentView.bounds)
        guard !clampedRect.isEmpty else { return nil }
        
        // Create renderer for the clamped region
        let renderer = UIGraphicsImageRenderer(size: clampedRect.size)
        let image = renderer.image { context in
            // Translate to capture only the specified region
            context.cgContext.translateBy(x: -clampedRect.origin.x, y: -clampedRect.origin.y)
            contentView.drawHierarchy(in: contentView.bounds, afterScreenUpdates: true)
        }
        
        return image
    }
    
    // MARK: - Position Calculation
    
    /// Get the character offset at a given y-position within this cell
    /// Returns the index of the first character visible at that y-coordinate
    func characterOffset(at yPosition: CGFloat) -> Int {
        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        
        // Convert to text view coordinates
        let insets = textView.textContainerInset
        let point = CGPoint(x: insets.left + 10, y: yPosition + insets.top)
        
        // Get the glyph index at this point
        var fraction: CGFloat = 0
        let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        
        // Convert glyph index to character index
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        
        return charIndex
    }
    
    /// Get the y-position for a given character offset
    /// Returns the y-coordinate in cell coordinates where this character is rendered
    func yPosition(forCharacterOffset offset: Int) -> CGFloat {
        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        
        guard offset >= 0 && offset < textView.attributedText?.length ?? 0 else {
            return 0
        }
        
        // Get the glyph index for this character
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: offset)
        
        // Get the line fragment rect
        var lineFragmentRect = CGRect.zero
        layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil, withoutAdditionalLayout: false)
        lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        
        // Return the top of the line fragment
        return lineFragmentRect.origin.y
    }
    
    /// Get the total content height
    var contentHeight: CGFloat {
        return textView.contentSize.height
    }
}

// MARK: - EPUBDrawingOverlay

/// Transparent overlay view for drawing annotations on EPUB pages
class EPUBDrawingOverlay: UIView {
    
    /// Whether drawing is currently enabled
    var isDrawingEnabled: Bool = false {
        didSet {
            gestureRecognizer?.isEnabled = isDrawingEnabled
        }
    }
    
    /// Delegate for drawing events
    weak var drawingDelegate: EPUBDrawerDelegate?
    
    /// Current drawing path
    private var currentPath: UIBezierPath?
    
    /// All completed annotation paths
    private var annotations: [(path: UIBezierPath, color: UIColor, bounds: CGRect)] = []
    
    /// Annotations that have been saved (with AI analysis)
    private var savedAnnotations: [(path: UIBezierPath, color: UIColor, bounds: CGRect, analysisID: UUID)] = []
    
    /// Drawing gesture recognizer
    private var gestureRecognizer: DrawingGestureRecognizer?
    
    /// Drawing color
    static let freshColor = UIColor.systemBlue
    static let generatedColor = UIColor.systemGreen
    
    /// Line width
    private let lineWidth: CGFloat = 2.0
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGestureRecognizer()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGestureRecognizer()
    }
    
    private func setupGestureRecognizer() {
        let recognizer = DrawingGestureRecognizer()
        recognizer.drawingDelegate = self
        recognizer.isEnabled = false
        addGestureRecognizer(recognizer)
        gestureRecognizer = recognizer
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        // Draw saved annotations (green)
        for annotation in savedAnnotations {
            annotation.color.withAlphaComponent(0.6).setStroke()
            annotation.path.lineWidth = lineWidth
            annotation.path.lineCapStyle = .round
            annotation.path.lineJoinStyle = .round
            annotation.path.stroke()
        }
        
        // Draw completed annotations (blue)
        for annotation in annotations {
            annotation.color.withAlphaComponent(0.6).setStroke()
            annotation.path.lineWidth = lineWidth
            annotation.path.lineCapStyle = .round
            annotation.path.lineJoinStyle = .round
            annotation.path.stroke()
        }
        
        // Draw current path
        if let path = currentPath {
            Self.freshColor.withAlphaComponent(0.6).setStroke()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
    }
    
    /// Clear all annotations
    func clearAnnotations() {
        annotations.removeAll()
        savedAnnotations.removeAll()
        currentPath = nil
        setNeedsDisplay()
    }
    
    /// Clear only fresh (unsaved) annotations
    func clearFreshAnnotations() {
        annotations.removeAll()
        currentPath = nil
        setNeedsDisplay()
    }
    
    /// Undo the last annotation
    @discardableResult
    func undoLastAnnotation() -> Bool {
        guard !annotations.isEmpty else { return false }
        annotations.removeLast()
        setNeedsDisplay()
        return true
    }
    
    /// Check if there are annotations that can be undone
    var canUndo: Bool {
        return !annotations.isEmpty
    }
    
    /// Get the bounds of all current annotations
    var annotationsBounds: CGRect? {
        guard !annotations.isEmpty else { return nil }
        
        var combinedBounds = annotations[0].bounds
        for annotation in annotations.dropFirst() {
            combinedBounds = combinedBounds.union(annotation.bounds)
        }
        return combinedBounds
    }
    
    /// Get all current annotations for saving
    var currentAnnotations: [(path: UIBezierPath, color: UIColor, bounds: CGRect)] {
        return annotations
    }
    
    /// Get all current annotation paths
    var annotationPaths: [UIBezierPath] {
        return annotations.map { $0.path }
    }
    
    /// Mark all current annotations as saved (changes color to green)
    func markAnnotationsAsSaved(analysisID: UUID) {
        for annotation in annotations {
            savedAnnotations.append((
                path: annotation.path,
                color: Self.generatedColor,
                bounds: annotation.bounds,
                analysisID: analysisID
            ))
        }
        annotations.removeAll()
        setNeedsDisplay()
    }
    
    /// Load a saved annotation
    func loadSavedAnnotation(path: UIBezierPath, bounds: CGRect, analysisID: UUID) {
        savedAnnotations.append((
            path: path,
            color: Self.generatedColor,
            bounds: bounds,
            analysisID: analysisID
        ))
        setNeedsDisplay()
    }
    
    /// Remove a saved annotation by analysis ID
    func removeSavedAnnotation(for analysisID: UUID) {
        savedAnnotations.removeAll { $0.analysisID == analysisID }
        setNeedsDisplay()
    }
    
    /// Find analysis ID for an annotation at a point
    func findAnalysisID(at point: CGPoint) -> UUID? {
        for annotation in savedAnnotations {
            if annotation.bounds.contains(point) {
                return annotation.analysisID
            }
        }
        return nil
    }
    
    /// Check if there are any annotations (fresh or saved)
    var hasAnnotations: Bool {
        return !annotations.isEmpty || !savedAnnotations.isEmpty
    }
    
    /// Number of fresh annotations
    var freshAnnotationCount: Int {
        return annotations.count
    }
}

// MARK: - DrawingGestureRecognizerDelegate

extension EPUBDrawingOverlay: DrawingGestureRecognizerDelegate {
    func gestureRecognizerBegan(_ location: CGPoint) {
        currentPath = UIBezierPath()
        currentPath?.move(to: location)
        setNeedsDisplay()
    }
    
    func gestureRecognizerMoved(_ location: CGPoint) {
        currentPath?.addLine(to: location)
        currentPath?.move(to: location)
        setNeedsDisplay()
    }
    
    func gestureRecognizerEnded(_ location: CGPoint) {
        guard let path = currentPath else { return }
        
        path.addLine(to: location)
        
        // Calculate bounds with some padding
        let bounds = path.bounds.insetBy(dx: -5, dy: -5)
        
        annotations.append((
            path: path,
            color: Self.freshColor,
            bounds: bounds
        ))
        
        currentPath = nil
        setNeedsDisplay()
        
        // Notify delegate
        drawingDelegate?.epubDrawerDidCompleteDrawing()
    }
}

// MARK: - EPUBDrawerDelegate

protocol EPUBDrawerDelegate: AnyObject {
    func epubDrawerDidCompleteDrawing()
}
