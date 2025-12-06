//
//  AIAnalysisBottomSheet.swift
//  EasyReader
//
//  Created by Sammy Yousif on 11/30/25.
//

import UIKit
import Down

class AIAnalysisViewController: UIViewController {
    
    // Callback for delete action
    var onDelete: (() -> Void)?
    
    // Screenshot image to display in nav bar
    private var screenshotImage: UIImage?
    
    // Current markdown content for re-rendering on trait changes
    private var currentMarkdownContent: String = ""
    
    // Dynamic attachments that need updating on trait changes
    private var dynamicAttachments: [DynamicImageTextAttachment] = []
    
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
    
    #if targetEnvironment(macCatalyst)
    // Using UILabel on Mac Catalyst to avoid UITextView bugs
    private let contentLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 24, weight: .regular)
        label.textColor = .label
        label.backgroundColor = .clear
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    #else
    // Using UITextView on iOS for better text selection and rendering
    private let textView: UITextView = {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 24, weight: .regular)
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
    
    // Timestamp label
    private let timestampLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
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
        
        let closeButton = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )
        navigationItem.rightBarButtonItems = [closeButton]
        
        // Setup views
        view.addSubview(scrollView)
        #if targetEnvironment(macCatalyst)
        scrollView.addSubview(contentLabel)
        #else
        scrollView.addSubview(textView)
        #endif
        scrollView.addSubview(timestampLabel)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            // Timestamp label (at top)
            timestampLabel.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 12),
            timestampLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            timestampLabel.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            timestampLabel.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -20),
        ])
        
        // Content view constraints (platform-specific)
        #if targetEnvironment(macCatalyst)
        NSLayoutConstraint.activate([
            contentLabel.topAnchor.constraint(equalTo: timestampLabel.bottomAnchor, constant: 8),
            contentLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            contentLabel.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            contentLabel.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            contentLabel.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40),
        ])
        #else
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: timestampLabel.bottomAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            textView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            textView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            textView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40),
        ])
        #endif
    }
    
    // MARK: - Public Methods
    
    /// Set the full text content (replaces existing text)
    /// Renders markdown and LaTeX to attributed string
    func setText(_ text: String) {
        currentMarkdownContent = text
        renderMarkdownContent()
    }
    
    /// Append text to existing content (for streaming)
    func appendText(_ text: String) {
        // Append new text chunk
        if currentMarkdownContent.isEmpty || currentMarkdownContent == "Explaining" {
            currentMarkdownContent = text
        } else {
            currentMarkdownContent += text
        }
        renderMarkdownContent()
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
    
    func setLoading(_ isLoading: Bool) {
        if isLoading {
            // Show activity indicator on title image
            titleActivityOverlay.alpha = 1
            titleActivityIndicator.startAnimating()
            
            // Show centered, smaller, gray "Explaining" text if no content yet
            if currentMarkdownContent.isEmpty {
                currentMarkdownContent = "Explaining"
                let analyzingAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                    .foregroundColor: UIColor.secondaryLabel
                ]
                let centeredParagraph = NSMutableParagraphStyle()
                centeredParagraph.alignment = .center
                let attributedText = NSAttributedString(
                    string: "Explaining",
                    attributes: analyzingAttributes.merging([.paragraphStyle: centeredParagraph]) { _, new in new }
                )
                #if targetEnvironment(macCatalyst)
                contentLabel.attributedText = attributedText
                #else
                textView.attributedText = attributedText
                #endif
            }
        } else {
            // Hide activity indicator on title image
            titleActivityIndicator.stopAnimating()
            UIView.animate(withDuration: 0.25) {
                self.titleActivityOverlay.alpha = 0
            }
        }
    }
    
    func reset() {
        currentMarkdownContent = ""
        dynamicAttachments = []
        #if targetEnvironment(macCatalyst)
        contentLabel.text = ""
        contentLabel.attributedText = nil
        #else
        textView.text = ""
        textView.attributedText = nil
        #endif
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
            // Update dynamic attachments for new appearance
            for attachment in dynamicAttachments {
                attachment.updateImageForCurrentMode()
            }
            
            // Re-render the entire content to update markdown colors
            if !currentMarkdownContent.isEmpty && currentMarkdownContent != "Explaining" {
                renderMarkdownContent()
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Renders the current markdown content with LaTeX to attributed string
    private func renderMarkdownContent() {
        guard !currentMarkdownContent.isEmpty && currentMarkdownContent != "Explaining" else {
            #if targetEnvironment(macCatalyst)
            contentLabel.text = currentMarkdownContent
            #else
            textView.text = currentMarkdownContent
            #endif
            return
        }
        
        let width = view.bounds.width - 40 // Account for padding
        let renderer = MarkdownLatexRenderer.shared
        let isDarkMode = traitCollection.userInterfaceStyle == .dark
        
        // Use the dynamic rendering method
        let (attributedString, attachments) = renderer.renderWithDynamicImages(currentMarkdownContent, width: width)
        self.dynamicAttachments = attachments
        
        #if targetEnvironment(macCatalyst)
        contentLabel.attributedText = attributedString
        #else
        textView.attributedText = attributedString
        #endif
    }
    
    private func confirmDelete() {
        let alert = UIAlertController(
            title: "Delete Analysis",
            message: "This will delete the annotation and its analysis. This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.dismiss(animated: true) {
                self?.onDelete?()
            }
        })
        
        present(alert, animated: true)
    }
    
    private func copyTextToClipboard() {
        guard !currentMarkdownContent.isEmpty, currentMarkdownContent != "Explaining" else { return }
        
        // Copy the raw markdown content (not the rendered version)
        UIPasteboard.general.string = currentMarkdownContent
        
        // Show feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Temporarily change button to checkmark
        if let copyButton = navigationItem.rightBarButtonItems?.last {
            copyButton.image = UIImage(systemName: "checkmark")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                copyButton.image = UIImage(systemName: "doc.on.doc")
            }
        }
    }
}
