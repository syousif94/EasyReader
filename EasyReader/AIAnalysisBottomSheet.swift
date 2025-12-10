//
//  AIAnalysisBottomSheet.swift
//  EasyReader
//
//  Created by Sammy Yousif on 11/30/25.
//

import UIKit
import Down

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

// MARK: - AIAnalysisViewController

class AIAnalysisViewController: UIViewController {
    
    // Callback for delete action
    var onDelete: (() -> Void)?
    
    // Screenshot image to display in nav bar
    private var screenshotImage: UIImage?
    
    // Reference to the current analysis for follow-up questions
    var currentAnalysis: AIAnalysisResult?
    
    // Track message views
    private var messageBubbles: [ChatMessageBubbleView] = []
    
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
    
    // Track if currently generating
    private var isGenerating: Bool = false
    
    // Height constraint for input text view
    private var inputTextViewHeightConstraint: NSLayoutConstraint?
    
    // Scroll view bottom constraint for keyboard
    private var scrollViewBottomConstraint: NSLayoutConstraint?
    
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
        
        // Add delete button on the left
        let deleteButton = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            primaryAction: UIAction { [weak self] _ in
                self?.confirmDelete()
            }
        )
        deleteButton.tintColor = .systemRed
        navigationItem.leftBarButtonItem = deleteButton
        
        // Only show close button on iOS (Catalyst has window close button)
        #if !targetEnvironment(macCatalyst)
        let closeButton = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )
        navigationItem.rightBarButtonItems = [closeButton]
        #endif
        
        // Setup scroll view
        view.addSubview(scrollView)
        scrollView.addSubview(timestampLabel)
        scrollView.addSubview(messagesStackView)
        
        // Setup input area inside scroll view (added to stack view later)
        inputContainerView.addSubview(inputTextView)
        inputContainerView.addSubview(inputPlaceholder)
        inputContainerView.addSubview(sendButton)
        
        // Configure input text view
        inputTextView.delegate = self
        sendButton.addTarget(self, action: #selector(sendButtonTapped), for: .touchUpInside)
        
        // Set up keyboard observers
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        
        // Layout constraints
        scrollViewBottomConstraint = scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        
        NSLayoutConstraint.activate([
            // Scroll view takes full height
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
            messagesStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            messagesStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
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
            
            let bubble = ChatMessageBubbleView(role: message.role)
            bubble.setContent(message.content, width: width)
            messagesStackView.addArrangedSubview(bubble)
            messageBubbles.append(bubble)
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
    
    private func confirmDelete() {
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
        
        // Add user message bubble
        let userBubble = ChatMessageBubbleView(role: "user")
        userBubble.setContent(question, width: view.bounds.width)
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
        
        // Send follow-up to API
        Task {
            await AIAnalysisManager.shared.sendFollowUp(question: question, analysis: analysis) { [weak self] chunk in
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
