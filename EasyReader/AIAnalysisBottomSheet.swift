//
//  AIAnalysisBottomSheet.swift
//  EasyReader
//
//  Created by Sammy Yousif on 11/30/25.
//

import UIKit
import Down
import PinLayout

// MARK: - Chat Message Bubble View

class ChatMessageBubbleView: UIView {
    
    private let role: String
    private var dynamicAttachments: [DynamicImageTextAttachment] = []
    
    private let bubbleContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    #if targetEnvironment(macCatalyst)
    private let contentLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.textColor = .label
        label.backgroundColor = .clear
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    #else
    private let textView: UITextView = {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 16, weight: .regular)
        tv.textColor = .label
        tv.backgroundColor = .clear
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()
    #endif
    
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    
    init(role: String) {
        self.role = role
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(bubbleContainer)
        #if targetEnvironment(macCatalyst)
        bubbleContainer.addSubview(contentLabel)
        #else
        bubbleContainer.addSubview(textView)
        #endif
        
        // Style based on role
        if role == "user" {
            // User messages: blue bubble, right-aligned
            bubbleContainer.backgroundColor = .systemBlue
            bubbleContainer.layer.cornerRadius = 16
            bubbleContainer.layer.cornerCurve = .continuous
            #if targetEnvironment(macCatalyst)
            contentLabel.textColor = .white
            #else
            textView.textColor = .white
            #endif
            
            // Bubble constraints for user messages
            leadingConstraint = bubbleContainer.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 60)
            trailingConstraint = bubbleContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
            
            NSLayoutConstraint.activate([
                bubbleContainer.topAnchor.constraint(equalTo: topAnchor),
                bubbleContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
                leadingConstraint!,
                trailingConstraint!,
            ])
            
            #if targetEnvironment(macCatalyst)
            NSLayoutConstraint.activate([
                contentLabel.topAnchor.constraint(equalTo: bubbleContainer.topAnchor, constant: 10),
                contentLabel.leadingAnchor.constraint(equalTo: bubbleContainer.leadingAnchor, constant: 14),
                contentLabel.trailingAnchor.constraint(equalTo: bubbleContainer.trailingAnchor, constant: -14),
                contentLabel.bottomAnchor.constraint(equalTo: bubbleContainer.bottomAnchor, constant: -10),
            ])
            #else
            NSLayoutConstraint.activate([
                textView.topAnchor.constraint(equalTo: bubbleContainer.topAnchor, constant: 10),
                textView.leadingAnchor.constraint(equalTo: bubbleContainer.leadingAnchor, constant: 14),
                textView.trailingAnchor.constraint(equalTo: bubbleContainer.trailingAnchor, constant: -14),
                textView.bottomAnchor.constraint(equalTo: bubbleContainer.bottomAnchor, constant: -10),
            ])
            #endif
        } else {
            // Model messages: no background, full width
            bubbleContainer.backgroundColor = .clear
            #if targetEnvironment(macCatalyst)
            contentLabel.textColor = .label
            #else
            textView.textColor = .label
            #endif
            
            // Full width constraints for model messages
            NSLayoutConstraint.activate([
                bubbleContainer.topAnchor.constraint(equalTo: topAnchor),
                bubbleContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
                bubbleContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
                bubbleContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            ])
            
            #if targetEnvironment(macCatalyst)
            NSLayoutConstraint.activate([
                contentLabel.topAnchor.constraint(equalTo: bubbleContainer.topAnchor),
                contentLabel.leadingAnchor.constraint(equalTo: bubbleContainer.leadingAnchor),
                contentLabel.trailingAnchor.constraint(equalTo: bubbleContainer.trailingAnchor),
                contentLabel.bottomAnchor.constraint(equalTo: bubbleContainer.bottomAnchor),
            ])
            #else
            NSLayoutConstraint.activate([
                textView.topAnchor.constraint(equalTo: bubbleContainer.topAnchor),
                textView.leadingAnchor.constraint(equalTo: bubbleContainer.leadingAnchor),
                textView.trailingAnchor.constraint(equalTo: bubbleContainer.trailingAnchor),
                textView.bottomAnchor.constraint(equalTo: bubbleContainer.bottomAnchor),
            ])
            #endif
        }
    }
    
    func setContent(_ content: String, width: CGFloat) {
        if role == "user" {
            // Simple text for user messages
            #if targetEnvironment(macCatalyst)
            contentLabel.text = content
            #else
            textView.text = content
            textView.textColor = .white
            #endif
        } else {
            // Render markdown for model messages (full width minus padding)
            let renderer = MarkdownLatexRenderer.shared
            let (attributedString, attachments) = renderer.renderWithDynamicImages(content, width: width - 32)
            self.dynamicAttachments = attachments
            
            #if targetEnvironment(macCatalyst)
            contentLabel.attributedText = attributedString
            #else
            textView.attributedText = attributedString
            #endif
        }
    }
    
    func appendContent(_ text: String, fullContent: String, width: CGFloat) {
        // Re-render the full content for streaming
        setContent(fullContent, width: width)
    }
    
    func updateForTraitChange() {
        for attachment in dynamicAttachments {
            attachment.updateImageForCurrentMode()
        }
    }
}

// MARK: - Chat Image Message View

/// View for displaying images in the chat (for follow-up image attachments)
class ChatImageMessageView: UIView {
    
    private let imageContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 4
        view.layer.shadowOpacity = 0.15
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 12
        iv.layer.cornerCurve = .continuous
        iv.backgroundColor = .secondarySystemBackground
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    
    private var imageWidthConstraint: NSLayoutConstraint?
    private var imageHeightConstraint: NSLayoutConstraint?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(imageContainerView)
        imageContainerView.addSubview(imageView)
        
        // Container is right-aligned (user messages)
        NSLayoutConstraint.activate([
            imageContainerView.topAnchor.constraint(equalTo: topAnchor),
            imageContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageContainerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            imageContainerView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 60),
        ])
        
        // Image view fills container
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: imageContainerView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor),
        ])
        
        // Default size constraints (will be updated based on image)
        imageWidthConstraint = imageView.widthAnchor.constraint(equalToConstant: 200)
        imageHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: 150)
        imageWidthConstraint?.isActive = true
        imageHeightConstraint?.isActive = true
    }
    
    func setImage(_ image: UIImage, maxWidth: CGFloat = 250, maxHeight: CGFloat = 300) {
        imageView.image = image
        
        // Calculate size maintaining aspect ratio
        let aspectRatio = image.size.width / image.size.height
        var width: CGFloat
        var height: CGFloat
        
        if aspectRatio > 1 {
            // Landscape: constrain by width
            width = min(image.size.width, maxWidth)
            height = width / aspectRatio
            if height > maxHeight {
                height = maxHeight
                width = height * aspectRatio
            }
        } else {
            // Portrait: constrain by height
            height = min(image.size.height, maxHeight)
            width = height * aspectRatio
            if width > maxWidth {
                width = maxWidth
                height = width / aspectRatio
            }
        }
        
        imageWidthConstraint?.constant = width
        imageHeightConstraint?.constant = height
        
        // Update shadow path
        imageContainerView.layer.shadowPath = UIBezierPath(
            roundedRect: CGRect(origin: .zero, size: CGSize(width: width, height: height)),
            cornerRadius: 12
        ).cgPath
    }
}

// MARK: - AIAnalysisDrawingOverlay

/// Transparent overlay view for drawing annotations on AI analysis images
class AIAnalysisDrawingOverlay: UIView {
    
    // MARK: - Properties
    
    /// Whether drawing is currently enabled
    var isDrawingEnabled: Bool = false {
        didSet {
            gestureRecognizer?.isEnabled = isDrawingEnabled
        }
    }
    
    // MARK: - Hit Testing (Passthrough when not drawing)
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // When drawing is disabled, pass through all touches
        guard isDrawingEnabled else {
            return nil
        }
        return super.hitTest(point, with: event)
    }
    
    /// Delegate for drawing events
    weak var drawingDelegate: AIAnalysisDrawingDelegate?
    
    /// Current drawing path
    private var currentPath: UIBezierPath?
    
    /// All completed annotation paths
    private var annotations: [(path: UIBezierPath, color: UIColor, bounds: CGRect)] = []
    
    /// Drawing gesture recognizer
    private var gestureRecognizer: DrawingGestureRecognizer?
    
    /// Drawing color
    static let drawingColor = UIColor.systemBlue
    
    /// Line width
    private let lineWidth: CGFloat = 3.0
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = .clear
        isUserInteractionEnabled = true
        setupGestureRecognizer()
    }
    
    private func setupGestureRecognizer() {
        let recognizer = DrawingGestureRecognizer()
        recognizer.drawingDelegate = self
        recognizer.isEnabled = false
        addGestureRecognizer(recognizer)
        gestureRecognizer = recognizer
    }
    
    // MARK: - Drawing
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        // Draw completed annotations
        for annotation in annotations {
            annotation.color.withAlphaComponent(0.6).setStroke()
            let path = annotation.path
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
        
        // Draw current path being drawn
        if let path = currentPath {
            Self.drawingColor.withAlphaComponent(0.6).setStroke()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
    }
    
    // MARK: - Public Methods
    
    /// Clear all annotations
    func clearAnnotations() {
        annotations.removeAll()
        currentPath = nil
        setNeedsDisplay()
        drawingDelegate?.drawingOverlayDidChange(hasAnnotations: false)
    }
    
    /// Undo the last annotation
    @discardableResult
    func undoLastAnnotation() -> Bool {
        guard !annotations.isEmpty else { return false }
        annotations.removeLast()
        setNeedsDisplay()
        drawingDelegate?.drawingOverlayDidChange(hasAnnotations: !annotations.isEmpty)
        return true
    }
    
    /// Check if there are annotations that can be undone
    var canUndo: Bool {
        return !annotations.isEmpty
    }
    
    /// Check if there are any annotations
    var hasAnnotations: Bool {
        return !annotations.isEmpty
    }
    
    /// Number of annotations
    var annotationCount: Int {
        return annotations.count
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
    
    /// Get all annotation paths (for capturing)
    var annotationPaths: [UIBezierPath] {
        return annotations.map { $0.path }
    }
    
    /// Capture a snapshot of a specific region (including drawing annotations)
    /// This should be called on the parent view that contains both content and this overlay
    func captureSnapshot(in rect: CGRect, from parentView: UIView) -> UIImage? {
        // Clamp rect to parent bounds
        let clampedRect = rect.intersection(parentView.bounds)
        guard !clampedRect.isEmpty else { return nil }
        
        // Create renderer for the clamped region
        let renderer = UIGraphicsImageRenderer(size: clampedRect.size)
        let image = renderer.image { context in
            // Translate to capture only the specified region
            context.cgContext.translateBy(x: -clampedRect.origin.x, y: -clampedRect.origin.y)
            parentView.drawHierarchy(in: parentView.bounds, afterScreenUpdates: true)
        }
        
        return image
    }
    
    /// Capture the annotated area with padding (like EPUB does)
    func captureAnnotatedArea(from parentView: UIView, padding: CGFloat = 20) -> UIImage? {
        guard let bounds = annotationsBounds else { return nil }
        
        // Expand bounds with padding
        let expandedBounds = bounds.insetBy(dx: -padding, dy: -padding)
        
        return captureSnapshot(in: expandedBounds, from: parentView)
    }
    
    /// Clear all paths (alias for clearAnnotations)
    func clearAllPaths() {
        clearAnnotations()
    }
    
    /// Undo the last path (alias for undoLastAnnotation)
    func undoLastPath() {
        undoLastAnnotation()
    }
    
    /// Whether there are drawings
    var hasDrawings: Bool {
        return hasAnnotations
    }
}

// MARK: - DrawingGestureRecognizerDelegate

extension AIAnalysisDrawingOverlay: DrawingGestureRecognizerDelegate {
    
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
            color: Self.drawingColor,
            bounds: bounds
        ))
        
        currentPath = nil
        setNeedsDisplay()
        
        // Notify delegate
        drawingDelegate?.drawingOverlayDidChange(hasAnnotations: true)
        drawingDelegate?.drawingOverlayDidCompleteStroke()
    }
}

// MARK: - AIAnalysisDrawingDelegate

protocol AIAnalysisDrawingDelegate: AnyObject {
    /// Called when annotations change (added, undone, or cleared)
    func drawingOverlayDidChange(hasAnnotations: Bool)
    
    /// Called when a stroke is completed
    func drawingOverlayDidCompleteStroke()
}

// MARK: - AIAnalysisViewController

class AIAnalysisViewController: UIViewController {
    
    // Callback for delete action
    var onDelete: (() -> Void)?
    
    // Screenshot image to display in nav bar
    private(set) var screenshotImage: UIImage?
    
    // Reference to the current analysis for follow-up questions
    var currentAnalysis: AIAnalysisResult?
    
    // Track message views
    private var messageBubbles: [ChatMessageBubbleView] = []
    private var imageMessageViews: [ChatImageMessageView] = []
    
    // Currently streaming bubble
    private var streamingBubble: ChatMessageBubbleView?
    private var streamingContent: String = ""
    
    // Container view for shadow (doesn't clip)
    private let titleContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 4
        view.layer.shadowOpacity = 0.15
        return view
    }()
    
    // Title image view for nav bar (clips to bounds for corner radius)
    private let titleImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 6
        iv.layer.cornerCurve = .continuous
        iv.backgroundColor = .secondarySystemBackground
        return iv
    }()
    
    // Activity indicator overlay for title image
    private let titleActivityOverlay: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        view.layer.cornerRadius = 6
        view.layer.cornerCurve = .continuous
        return view
    }()
    
    // Activity indicator centered on title image
    private let titleActivityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = .white
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    // Scroll view for text content
    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.showsVerticalScrollIndicator = true
        scroll.alwaysBounceVertical = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()
    
    // Stack view for chat messages
    private let messagesStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    // Timestamp label
    private let timestampLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Input Area Components
    
    // Container for the input area (inside scroll view)
    private let inputContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Text input field
    private let inputTextView: UITextView = {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 16)
        tv.textColor = .label
        tv.backgroundColor = .tertiarySystemBackground
        tv.layer.cornerRadius = 20
        tv.layer.cornerCurve = .continuous
        tv.layer.borderWidth = 1
        tv.layer.borderColor = UIColor.separator.cgColor
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 40)
        tv.isScrollEnabled = false
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()
    
    // Placeholder label for text input
    private let inputPlaceholder: UILabel = {
        let label = UILabel()
        label.text = "Ask a follow-up question..."
        label.font = .systemFont(ofSize: 16)
        label.textColor = .placeholderText
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Send button
    private let sendButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        button.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: config), for: .normal)
        button.tintColor = .systemBlue
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isEnabled = false
        return button
    }()
    
    // Bottom toolbar with drawing controls + action buttons (like PDFViewController)
    private let bottomToolbar: UIToolbar = {
        let toolbar = UIToolbar()
        // Don't set translatesAutoresizingMaskIntoConstraints - using PinLayout
        return toolbar
    }()
    
    // Bar button items for drawing (like PDFViewController)
    private lazy var drawingToggleBarButton: UIBarButtonItem = {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "scribble"),
            style: .plain,
            target: self,
            action: #selector(toggleDrawingMode)
        )
        return button
    }()
    
    private lazy var undoBarButton: UIBarButtonItem = {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.backward"),
            style: .plain,
            target: self,
            action: #selector(undoLastDrawing)
        )
        return button
    }()
    
    private lazy var clearAllBarButton: UIBarButtonItem = {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "delete.left"),
            style: .plain,
            target: self,
            action: #selector(clearAllDrawing)
        )
        return button
    }()
    
    // Action bar button items
    private lazy var deleteBarButton: UIBarButtonItem = {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: self,
            action: #selector(confirmDelete)
        )
        button.tintColor = .systemRed
        return button
    }()
    
    private lazy var retryBarButton: UIBarButtonItem = {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(retryAnalysis)
        )
        return button
    }()
    
    private lazy var closeBarButton: UIBarButtonItem = {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(closeTapped)
        )
        return button
    }()
    
    // AI Analysis button (like PDFViewController's Explain button)
    private let aiAnalysisButton: UIButton = {
        let button = UIButton()
        button.configuration = .prominentGlass()
        button.configuration?.imagePadding = 10
        button.setTitle("Explain", for: .normal)
        button.backgroundColor = .systemBlue
        button.setImage(UIImage(systemName: "brain"), for: .normal)
        button.alpha = 0 // Initially hidden
        return button
    }()
    
    // Drawing overlay for annotating the scroll view content
    private let drawingOverlay: AIAnalysisDrawingOverlay = {
        let overlay = AIAnalysisDrawingOverlay()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        return overlay
    }()
    
    // Track drawing state
    private var isDrawingEnabled = false {
        didSet {
            drawingOverlay.isDrawingEnabled = isDrawingEnabled
            scrollView.isScrollEnabled = !isDrawingEnabled // Disable scrolling while drawing
            updateBottomToolbarItems()
            view.setNeedsLayout()
        }
    }
    
    // Track if currently generating
    private var isGenerating: Bool = false
    
    // Height constraint for input text view
    private var inputTextViewHeightConstraint: NSLayoutConstraint?
    
    // Scroll view bottom constraint for keyboard
    private var scrollViewBottomConstraint: NSLayoutConstraint?
    
    // Drawing overlay height constraint (matches scroll view content size)
    private var drawingOverlayHeightConstraint: NSLayoutConstraint?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        
        // Configure transparent navigation bar
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        
        // Set up title image view with shadow container
        setupTitleImageView()
        
        // Add tap gesture to title image for expanding
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(titleImageTapped))
        titleContainerView.addGestureRecognizer(tapGesture)
        titleContainerView.isUserInteractionEnabled = true
        
        // Setup scroll view with drawing overlay on top
        view.addSubview(scrollView)
        view.addSubview(bottomToolbar)
        view.addSubview(aiAnalysisButton)
        scrollView.addSubview(timestampLabel)
        scrollView.addSubview(messagesStackView)
        scrollView.addSubview(drawingOverlay) // Drawing overlay on top of content
        
        // Setup drawing overlay delegate
        drawingOverlay.drawingDelegate = self
        
        // Setup input area inside scroll view (added to stack view later)
        inputContainerView.addSubview(inputTextView)
        inputContainerView.addSubview(inputPlaceholder)
        inputContainerView.addSubview(sendButton)
        
        // Configure input text view
        inputTextView.delegate = self
        sendButton.addTarget(self, action: #selector(sendButtonTapped), for: .touchUpInside)
        
        // Configure AI analysis button
        aiAnalysisButton.addTarget(self, action: #selector(addDrawingToChat), for: .touchUpInside)
        
        // Set up keyboard observers
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        
        // Layout constraints - scroll view extends to bottom of screen, toolbar floats over it (like PDFViewController)
        scrollViewBottomConstraint = scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        
        NSLayoutConstraint.activate([
            // Scroll view takes full height to bottom of screen (toolbar floats over it like PDFViewController)
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollViewBottomConstraint!,
            
            // Timestamp label (at top, centered)
            timestampLabel.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 12),
            timestampLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            timestampLabel.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            timestampLabel.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40),
            
            // Messages stack view
            messagesStackView.topAnchor.constraint(equalTo: timestampLabel.bottomAnchor, constant: 16),
            messagesStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            messagesStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            messagesStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -70), // Extra padding for floating toolbar
            messagesStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Drawing overlay covers the entire scroll view content
            drawingOverlay.topAnchor.constraint(equalTo: scrollView.topAnchor),
            drawingOverlay.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            drawingOverlay.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            drawingOverlay.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Input container constraints
            inputContainerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            
            // Input text view
            inputTextView.topAnchor.constraint(equalTo: inputContainerView.topAnchor, constant: 8),
            inputTextView.leadingAnchor.constraint(equalTo: inputContainerView.leadingAnchor, constant: 16),
            inputTextView.trailingAnchor.constraint(equalTo: inputContainerView.trailingAnchor, constant: -16),
            inputTextView.bottomAnchor.constraint(equalTo: inputContainerView.bottomAnchor, constant: -8),
            
            // Send button (inside text view, right side)
            sendButton.trailingAnchor.constraint(equalTo: inputTextView.trailingAnchor, constant: -8),
            sendButton.bottomAnchor.constraint(equalTo: inputTextView.bottomAnchor, constant: -6),
            sendButton.widthAnchor.constraint(equalToConstant: 28),
            sendButton.heightAnchor.constraint(equalToConstant: 28),
            
            // Placeholder
            inputPlaceholder.leadingAnchor.constraint(equalTo: inputTextView.leadingAnchor, constant: 16),
            inputPlaceholder.centerYAnchor.constraint(equalTo: inputTextView.centerYAnchor),
        ])
        
        // Set up input text view height constraint
        inputTextViewHeightConstraint = inputTextView.heightAnchor.constraint(equalToConstant: 40)
        inputTextViewHeightConstraint?.isActive = true
        
        // Set up drawing overlay height constraint (will be updated in viewDidLayoutSubviews)
        drawingOverlayHeightConstraint = drawingOverlay.heightAnchor.constraint(equalToConstant: 1000)
        drawingOverlayHeightConstraint?.isActive = true
        
        // Setup bottom toolbar items
        updateBottomToolbarItems()
    }
    
    // MARK: - Layout (PinLayout like PDFViewController)
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Update drawing overlay height to match scroll view content
        let contentHeight = max(scrollView.contentSize.height, scrollView.bounds.height)
        drawingOverlayHeightConstraint?.constant = contentHeight
        
        let insets = view.safeAreaInsets
        let bottomInset = insets.bottom > 0 ? insets.bottom : 20
        
        // Layout the bottom toolbar using PinLayout (like PDFViewController)
        layoutBottomToolbar(bottomInset: bottomInset)
        
        // Position AI analysis button above the toolbar when there are drawings
        aiAnalysisButton.pin
            .height(54)
            .width(180)
            .bottom(to: bottomToolbar.edge.top).marginBottom(16)
            .right(20)
    }
    
    private func layoutBottomToolbar(bottomInset: CGFloat) {
        let toolbarHeight: CGFloat = 44
        
        // Resize toolbar to fit its content
        bottomToolbar.sizeToFit()
        
        // Position toolbar on the right side, at bottom (like PDFViewController)
        bottomToolbar.pin
            .height(toolbarHeight)
            .right(16)
            .left(16)
            .bottom(bottomInset)
    }
    
    // MARK: - Bottom Toolbar
    
    private func updateBottomToolbarItems() {
        var items: [UIBarButtonItem] = []
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        if isDrawingEnabled {
            // Drawing mode: show undo, clear, and drawing toggle (like PDFViewController)
            let hasDrawings = drawingOverlay.hasDrawings
            undoBarButton.isEnabled = hasDrawings
            undoBarButton.tintColor = hasDrawings ? .label : .secondaryLabel
            clearAllBarButton.isEnabled = hasDrawings
            clearAllBarButton.tintColor = hasDrawings ? .secondaryLabel : .tertiaryLabel
            drawingToggleBarButton.tintColor = .systemBlue // Blue when active
            
            items = [
                flexibleSpace,
                undoBarButton,
                clearAllBarButton,
                drawingToggleBarButton,
            ]
        } else {
            // Normal mode: show action buttons + drawing toggle
            retryBarButton.isEnabled = currentAnalysis?.isCompleted == true || currentAnalysis?.isFailed == true
            drawingToggleBarButton.tintColor = .label // Normal color when inactive
            
            #if targetEnvironment(macCatalyst)
            // Catalyst: delete, retry, drawing toggle (no close - window has close button)
            items = [
                deleteBarButton,
                flexibleSpace,
                retryBarButton,
                flexibleSpace,
                drawingToggleBarButton,
            ]
            #else
            // iOS: delete, retry, drawing toggle, close
            items = [
                deleteBarButton,
                flexibleSpace,
                retryBarButton,
                flexibleSpace,
                drawingToggleBarButton,
                flexibleSpace,
                closeBarButton,
            ]
            #endif
        }
        
        bottomToolbar.setItems(items, animated: true)
    }
    
    private func updateDrawingControls() {
        let hasDrawings = drawingOverlay.hasDrawings
        undoBarButton.isEnabled = hasDrawings
        undoBarButton.tintColor = hasDrawings ? .label : .secondaryLabel
        clearAllBarButton.isEnabled = hasDrawings
        clearAllBarButton.tintColor = hasDrawings ? .secondaryLabel : .tertiaryLabel
        
        // Show/hide AI analysis button based on whether there are drawings
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            self.aiAnalysisButton.alpha = hasDrawings ? 1 : 0
        }
    }
    
    // MARK: - Drawing Actions
    
    @objc private func toggleDrawingMode() {
        isDrawingEnabled.toggle()
    }
    
    @objc private func undoLastDrawing() {
        drawingOverlay.undoLastPath()
        updateDrawingControls()
    }
    
    @objc private func clearAllDrawing() {
        drawingOverlay.clearAllPaths()
        updateDrawingControls()
    }
    
    @objc private func addDrawingToChat() {
        guard drawingOverlay.hasDrawings else { return }
        
        // Capture the annotated area from the scroll view (like EPUB does)
        guard let drawnImage = drawingOverlay.captureAnnotatedArea(from: scrollView) else { return }
        
        // Exit drawing mode
        isDrawingEnabled = false
        
        // Clear the drawings
        drawingOverlay.clearAllPaths()
        updateDrawingControls()
        
        // Add the image to chat and send for analysis
        guard let analysis = currentAnalysis else { return }
        
        // The prompt to send with the circled image
        let imagePrompt = "Please explain what I've circled in this screenshot."
        
        // Add image message to chat history BEFORE sending (this also saves the image to Core Data)
        analysis.appendToChatHistory(role: "user", content: imagePrompt, image: drawnImage)
        
        // Get the last message to retrieve the stored image (reconstructed from PNG data)
        let chatHistory = analysis.getChatHistory()
        let storedImage: UIImage?
        if let lastMessage = chatHistory.last {
            storedImage = analysis.getFollowUpImage(for: lastMessage)
        } else {
            storedImage = drawnImage
        }
        
        // Add image to chat UI (use stored image for consistency)
        let imageMessageView = ChatImageMessageView()
        imageMessageView.setImage(storedImage ?? drawnImage, maxWidth: view.bounds.width - 76)
        messagesStackView.addArrangedSubview(imageMessageView)
        imageMessageViews.append(imageMessageView)
        
        // Scroll to bottom to show the new image
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let bottomOffset = CGPoint(
                x: 0,
                y: max(0, self.scrollView.contentSize.height - self.scrollView.bounds.height + self.scrollView.contentInset.bottom)
            )
            self.scrollView.setContentOffset(bottomOffset, animated: true)
        }
        
        // Show loading state
        setLoading(true)
        
        // Create a streaming bubble for the response
        let responseBubble = ChatMessageBubbleView(role: "model")
        messagesStackView.addArrangedSubview(responseBubble)
        messageBubbles.append(responseBubble)
        streamingBubble = responseBubble
        streamingContent = ""
        
        // Send for analysis using the stored/reconstructed image (from PNG data)
        Task {
            await AIAnalysisManager.shared.sendFollowUp(
                question: imagePrompt,
                image: storedImage ?? drawnImage,
                analysis: analysis
            ) { [weak self] chunk in
                DispatchQueue.main.async {
                    self?.appendFollowUpText(chunk)
                }
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.setLoading(false)
                self?.updateBottomToolbarItems()
                self?.showInputField()
            }
        }
    }
    
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    @objc private func retryAnalysis() {
        let alert = UIAlertController(
            title: "Retry Analysis",
            message: "This will regenerate the analysis. Continue?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
            self?.performRetryAnalysis()
        })
        
        present(alert, animated: true)
    }
    
    private func performRetryAnalysis() {
        guard let analysis = currentAnalysis else { return }
        
        // Clear current messages
        clearMessages()
        
        // Show loading state
        setLoading(true, isInitialAnalysis: true)
        
        // Retry the analysis
        Task {
            await AIAnalysisManager.shared.retryAnalysis(analysis) { [weak self] chunk in
                DispatchQueue.main.async {
                    self?.appendText(chunk)
                }
            }
            
            DispatchQueue.main.async {
                self.setLoading(false)
                if let timestamp = self.currentAnalysis?.formattedCompletedDate {
                    self.setTimestamp("Analyzed \(timestamp)")
                }
                self.updateBottomToolbarItems()
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Load chat history from an analysis and display as bubbles
    func loadChatHistory(from analysis: AIAnalysisResult) {
        currentAnalysis = analysis
        let messages = analysis.getChatHistory()
        
        // Clear existing bubbles
        clearMessages()
        
        let width = view.bounds.width
        
        // Filter out the first user message (the system prompt from "Explain" button)
        // Only show model responses and subsequent user follow-up questions
        var isFirstUserMessage = true
        for message in messages {
            if message.role == "user" && isFirstUserMessage {
                // Skip the first user message (system prompt)
                isFirstUserMessage = false
                continue
            }
            isFirstUserMessage = false
            
            // Check if this message has an image attachment
            if let image = analysis.getFollowUpImage(for: message) {
                // Create image message view (don't show the prompt text with the image)
                let imageMessageView = ChatImageMessageView()
                imageMessageView.setImage(image, maxWidth: width - 76)
                messagesStackView.addArrangedSubview(imageMessageView)
                imageMessageViews.append(imageMessageView)
            } else {
                // Regular text-only message
                let bubble = ChatMessageBubbleView(role: message.role)
                bubble.setContent(message.content, width: width)
                messagesStackView.addArrangedSubview(bubble)
                messageBubbles.append(bubble)
            }
        }
        
        // Show input field when not generating
        showInputField()
    }
    
    /// Set text content for initial streaming (creates model bubble)
    func setText(_ text: String) {
        // Hide input while streaming
        hideInputField()
        
        // If there's no streaming bubble, create one
        if streamingBubble == nil {
            let bubble = ChatMessageBubbleView(role: "model")
            messagesStackView.addArrangedSubview(bubble)
            messageBubbles.append(bubble)
            streamingBubble = bubble
            streamingContent = ""
        }
        
        streamingContent = text
        streamingBubble?.setContent(text, width: view.bounds.width)
    }
    
    /// Append text to existing content (for streaming)
    func appendText(_ text: String) {
        // If there's no streaming bubble, create one
        if streamingBubble == nil {
            hideInputField()
            let bubble = ChatMessageBubbleView(role: "model")
            messagesStackView.addArrangedSubview(bubble)
            messageBubbles.append(bubble)
            streamingBubble = bubble
            streamingContent = ""
        }
        
        if streamingContent == "Explaining" {
            streamingContent = text
        } else {
            streamingContent += text
        }
        streamingBubble?.setContent(streamingContent, width: view.bounds.width)
    }
    
    /// Set the timestamp label
    func setTimestamp(_ timestamp: String) {
        timestampLabel.text = timestamp
    }
    
    /// Set the screenshot image to display in the nav bar
    func setImage(_ image: UIImage?) {
        screenshotImage = image
        titleImageView.image = image
        setupTitleImageView()
    }
    
    /// Show the input field at the bottom of the messages
    private func showInputField() {
        guard inputContainerView.superview == nil else { return }
        isGenerating = false
        messagesStackView.addArrangedSubview(inputContainerView)
    }
    
    /// Hide the input field while generating
    private func hideInputField() {
        isGenerating = true
        inputContainerView.removeFromSuperview()
    }
    
    /// Clear all message bubbles
    private func clearMessages() {
        // Remove input container first
        inputContainerView.removeFromSuperview()
        
        for bubble in messageBubbles {
            bubble.removeFromSuperview()
        }
        messageBubbles.removeAll()
        
        // Clear image message views
        for imageView in imageMessageViews {
            imageView.removeFromSuperview()
        }
        imageMessageViews.removeAll()
        
        streamingBubble = nil
        streamingContent = ""
    }
    
    private func setupTitleImageView() {
        let height: CGFloat = 44
        var width: CGFloat = 44
        
        // Calculate width based on image aspect ratio
        if let image = screenshotImage {
            let aspectRatio = image.size.width / image.size.height
            width = height * aspectRatio
            // Clamp width to reasonable bounds
            width = min(max(width, 44), 120)
        }
        
        // Set up the container with shadow
        titleContainerView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        titleContainerView.layer.shadowPath = UIBezierPath(roundedRect: titleContainerView.bounds, cornerRadius: 6).cgPath
        
        // Set up the image view inside the container
        titleImageView.frame = titleContainerView.bounds
        titleImageView.image = screenshotImage
        
        // Set up activity overlay and indicator
        titleActivityOverlay.frame = titleContainerView.bounds
        titleActivityIndicator.center = CGPoint(x: width / 2, y: height / 2)
        
        // Add subviews to container if not already added
        if titleImageView.superview != titleContainerView {
            titleContainerView.addSubview(titleImageView)
        }
        if titleActivityOverlay.superview != titleContainerView {
            titleContainerView.addSubview(titleActivityOverlay)
        }
        if titleActivityIndicator.superview != titleContainerView {
            titleContainerView.addSubview(titleActivityIndicator)
        }
        
        navigationItem.titleView = titleContainerView
    }
    
    func setLoading(_ isLoading: Bool, isInitialAnalysis: Bool = true) {
        if isLoading {
            // Hide input field while loading
            hideInputField()
            
            // Show activity indicator on title image
            titleActivityOverlay.alpha = 1
            titleActivityIndicator.startAnimating()
            
            // Only show "Explaining" for initial analysis, not follow-ups
            if isInitialAnalysis && streamingContent.isEmpty && streamingBubble == nil {
                streamingContent = "Explaining"
                let bubble = ChatMessageBubbleView(role: "model")
                bubble.setContent("Explaining", width: view.bounds.width)
                messagesStackView.addArrangedSubview(bubble)
                messageBubbles.append(bubble)
                streamingBubble = bubble
            }
        } else {
            // Hide activity indicator on title image
            titleActivityIndicator.stopAnimating()
            UIView.animate(withDuration: 0.25) {
                self.titleActivityOverlay.alpha = 0
            }
            
            // Finalize streaming bubble
            streamingBubble = nil
            
            // Show input field when loading completes
            showInputField()
        }
    }
    
    func reset() {
        clearMessages()
        timestampLabel.text = ""
        scrollView.contentOffset = .zero
        
        // Reset title activity indicator
        titleActivityOverlay.alpha = 0
        titleActivityIndicator.stopAnimating()
    }
    
    // MARK: - Trait Collection Changes
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        // Re-render content when appearance changes
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            // Update all message bubbles for new appearance
            for bubble in messageBubbles {
                bubble.updateForTraitChange()
            }
        }
    }
    
    // MARK: - Private Methods
    
    @objc private func confirmDelete() {
        let alert = UIAlertController(
            title: "Delete Analysis",
            message: "This will delete the annotation and its analysis. This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.performDelete()
        })
        
        present(alert, animated: true)
    }
    
    private func performDelete() {
        // Post notification so the original view controller can clean up annotations
        if let analysis = currentAnalysis, let analysisID = analysis.id {
            NotificationCenter.default.post(
                name: .didDeleteAIAnalysis,
                object: nil,
                userInfo: ["analysisID": analysisID]
            )
        }
        
        #if targetEnvironment(macCatalyst)
        // On Catalyst, close the scene
        if let windowScene = view.window?.windowScene {
            UIApplication.shared.requestSceneSessionDestruction(
                windowScene.session,
                options: nil,
                errorHandler: { error in
                    print("❌ [AIAnalysis] Failed to close scene: \(error)")
                }
            )
        }
        #else
        // On iOS, dismiss and call the callback
        dismiss(animated: true) {
            self.onDelete?()
        }
        #endif
    }
    
    // MARK: - Keyboard Handling
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }
        
        let keyboardHeight = keyboardFrame.height
        
        UIView.animate(withDuration: duration) {
            self.scrollView.contentInset.bottom = keyboardHeight
            self.scrollView.verticalScrollIndicatorInsets.bottom = keyboardHeight
        }
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }
        
        UIView.animate(withDuration: duration) {
            self.scrollView.contentInset.bottom = 0
            self.scrollView.verticalScrollIndicatorInsets.bottom = 0
        }
    }
    
    // MARK: - Send Follow-up Question
    
    @objc private func sendButtonTapped() {
        guard let question = inputTextView.text, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        guard let analysis = currentAnalysis else {
            print("❌ [AIAnalysis] No current analysis for follow-up")
            return
        }
        
        // Clear input
        inputTextView.text = ""
        inputPlaceholder.isHidden = false
        sendButton.isEnabled = false
        updateInputTextViewHeight()
        
        // Dismiss keyboard
        inputTextView.resignFirstResponder()
        
        // Hide input field while generating
        hideInputField()
        
        // Add user message to chat history BEFORE sending (so it's included in the API call)
        analysis.appendToChatHistory(role: "user", content: question)
        
        // Add text bubble to UI
        let width = view.bounds.width
        let userBubble = ChatMessageBubbleView(role: "user")
        userBubble.setContent(question, width: width)
        messagesStackView.addArrangedSubview(userBubble)
        messageBubbles.append(userBubble)
        
        // Show loading state (not initial analysis, so no "Explaining" text)
        setLoading(true, isInitialAnalysis: false)
        
        // Create a new streaming bubble for the response
        let responseBubble = ChatMessageBubbleView(role: "model")
        messagesStackView.addArrangedSubview(responseBubble)
        messageBubbles.append(responseBubble)
        streamingBubble = responseBubble
        streamingContent = ""
        
        // Send follow-up to API (user message already in history)
        Task {
            await AIAnalysisManager.shared.sendFollowUp(
                question: question,
                image: nil,
                analysis: analysis
            ) { [weak self] chunk in
                DispatchQueue.main.async {
                    self?.appendFollowUpText(chunk)
                }
            }
            
            DispatchQueue.main.async {
                self.setLoading(false)
                // Show input field again after generation completes
                self.showInputField()
            }
        }
    }
    
    /// Append text to the current follow-up response (for streaming)
    private func appendFollowUpText(_ text: String) {
        streamingContent += text
        streamingBubble?.setContent(streamingContent, width: view.bounds.width)
    }
    
    private func updateInputTextViewHeight() {
        let maxHeight: CGFloat = 120
        let minHeight: CGFloat = 40
        
        let sizeThatFits = inputTextView.sizeThatFits(CGSize(width: inputTextView.bounds.width, height: .greatestFiniteMagnitude))
        let newHeight = min(max(sizeThatFits.height, minHeight), maxHeight)
        
        inputTextViewHeightConstraint?.constant = newHeight
        inputTextView.isScrollEnabled = sizeThatFits.height > maxHeight
    }
    
    // MARK: - Title Image Tap (for viewing, not drawing)
    
    @objc private func titleImageTapped() {
        // Just show the image in a quick look or preview - no drawing here
        // Drawing is done on the scroll view content instead
        guard let image = screenshotImage else { return }
        
        // Create simple full-screen preview
        let containerView = UIView()
        containerView.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        containerView.alpha = 0
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        // Create image view
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.layer.cornerCurve = .continuous
        imageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(imageView)
        
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            imageView.widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, constant: -40),
            imageView.heightAnchor.constraint(lessThanOrEqualTo: containerView.heightAnchor, constant: -80),
        ])
        
        // Animate in
        UIView.animate(withDuration: 0.25) {
            containerView.alpha = 1
        }
        
        // Add tap to dismiss
        let tapToDismiss = UITapGestureRecognizer(target: self, action: #selector(dismissImagePreview(_:)))
        containerView.addGestureRecognizer(tapToDismiss)
        containerView.tag = 999 // Tag for finding later
    }
    
    @objc private func dismissImagePreview(_ gesture: UITapGestureRecognizer) {
        guard let containerView = gesture.view else { return }
        
        UIView.animate(withDuration: 0.25, animations: {
            containerView.alpha = 0
        }) { _ in
            containerView.removeFromSuperview()
        }
    }
}

// MARK: - UITextViewDelegate

extension AIAnalysisViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        // Update placeholder visibility
        inputPlaceholder.isHidden = !textView.text.isEmpty
        
        // Update send button state
        sendButton.isEnabled = !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        // Update height
        updateInputTextViewHeight()
    }
}

// MARK: - AIAnalysisDrawingDelegate

extension AIAnalysisViewController: AIAnalysisDrawingDelegate {
    func drawingOverlayDidChange(hasAnnotations: Bool) {
        updateDrawingControls()
    }
    
    func drawingOverlayDidCompleteStroke() {
        updateDrawingControls()
    }
}

// MARK: - UIGestureRecognizerDelegate

extension AIAnalysisViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Don't trigger tap on toolbar buttons
        if touch.view is UIControl {
            return false
        }
        return true
    }
}
