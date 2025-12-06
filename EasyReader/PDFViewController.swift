//
//  PDFViewController.swift
//  EasyReader
//
//  Created by Sammy Yousif on 11/10/25.
//

import UIKit
import Combine
import PinLayout
import PDFKit

class PDFViewController: UIViewController {
    var document: ReadableDoc
    weak var viewModel: AppViewModel?
    
    private var cancellables: Set<AnyCancellable> = []
    
    let pdfView: PDFView = {
        let view = PDFView()
        view.autoScales = true
        view.displayDirection = .vertical
        view.displayMode = .singlePageContinuous
        return view
    }()
    
    // Drawing controls toolbar with glass effect
    let drawingControlsToolbar: UIToolbar = {
        let toolbar = UIToolbar()
        toolbar.isTranslucent = true
        toolbar.layer.cornerRadius = 22
        toolbar.layer.cornerCurve = .continuous
        return toolbar
    }()
    
    // Bar button items
    lazy var drawingToggleBarButton: UIBarButtonItem = {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "scribble"),
            style: .plain,
            target: self,
            action: #selector(toggleDrawing)
        )
        return button
    }()
    
    lazy var undoBarButton: UIBarButtonItem = {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.backward"),
            style: .plain,
            target: self,
            action: #selector(undoLastDrawing)
        )
        return button
    }()
    
    lazy var clearAllBarButton: UIBarButtonItem = {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "xmark.circle.fill"),
            style: .plain,
            target: self,
            action: #selector(clearAllAnnotations)
        )
        return button
    }()
    
    // AI Analysis button
    let aiAnalysisButton: UIButton = {
        let button = UIButton()
        button.configuration = .prominentGlass()
        button.configuration?.imagePadding = 10
        button.setTitle("Explain", for: .normal)
        button.backgroundColor = .systemBlue
        button.setImage(UIImage(systemName: "brain"), for: .normal)
        button.alpha = 0 // Initially transparent
        return button
    }()
    
    // Page preview bar
    let pagePreviewView: PDFPagePreviewView = {
        let preview = PDFPagePreviewView()
        preview.alpha = 0 // Initially hidden
        return preview
    }()
    
    // Page indicator pill with liquid glass effect
    let pageIndicatorContainer: UIVisualEffectView = {
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        let view = UIVisualEffectView(effect: blurEffect)
        view.layer.cornerRadius = 20
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        view.alpha = 0 // Initially hidden
        return view
    }()
    
    let pageIndicatorLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .label
        label.textAlignment = .center
        return label
    }()
    
    // Custom title view with pill blur effect
    let titlePillContainer: UIVisualEffectView = {
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        let view = UIVisualEffectView(effect: blurEffect)
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }()
    
    let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        return label
    }()
    
    private var isPagePreviewVisible = false {
        didSet {
            updatePagePreviewVisibility()
        }
    }
    
    private var pageIndicatorHideTimer: Timer?
    
    // Track drawing state
    private var isDrawingEnabled = false {
        didSet {
            updateDrawingToggleButton()
            updateDrawingControls()
            pdfDrawingGestureRecognizer?.isEnabled = isDrawingEnabled
        }
    }
    
    private let pdfDrawer = PDFDrawer()
    private var pdfDrawingGestureRecognizer: DrawingGestureRecognizer?
    
    // AI Analysis bottom sheet
    private var aiAnalysisViewController: AIAnalysisViewController?
    private var lastProcessedTextLength = 0
    private var currentAnalysis: AIAnalysisResult? // Track current/displayed analysis
    
    // AI generating indicator
    private var generatingIndicator: AIGeneratingIndicatorView?
    private var generatingAnalysisID: UUID?
    
    // Flag to prevent saving state during programmatic navigation
    private var isProgrammaticNavigation = false
    
    // Navigation bar auto-hide tracking
    private var lastContentOffset: CGPoint = .zero
    private var scrollObservation: NSKeyValueObservation?
    private var isTogglingUI = false
    private var hasCompletedInitialSetup = false
    
    init(document: ReadableDoc, viewModel: AppViewModel? = nil) {
        self.document = document
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        
        // Early setup of PDF document to restore state as soon as possible
        if let pdfDocument = PDFDocument(url: document.url) {
            pdfView.document = pdfDocument
        }
        
        setupViews()
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupObservations()
        setupNotificationObservers()
        setupScrollObserver()
        setupAIAnalysisObservers()
    }
    
    private func setupNotificationObservers() {
        // MARK: iCloud Sync Protection Strategy
        // When a document viewer is open, we need to prevent iCloud metadata updates
        // from interfering with local user actions. This is handled in multiple layers:
        //
        // 1. PDFViewController (this class):
        //    - Posts .documentViewerDidOpen when viewDidAppear is called
        //    - Posts .documentViewerDidClose when viewWillDisappear is called
        //    - Observes .documentMetadataDidUpdateFromCloud and ignores updates
        //    - Only saves state when actual changes occur (see saveReadingState())
        //
        // 2. DocCell:
        //    - Maintains a static set of documents currently being viewed
        //    - Ignores iCloud updates for documents in the "being viewed" set
        //    - Also ignores updates within 5 seconds of local changes
        //
        // 3. ReadableDoc:
        //    - Posts .documentReadingStateDidChange when local changes occur
        //    - Includes device identifier to help track change sources
        
        // Observe iCloud metadata updates to prevent conflicts
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataUpdatedFromCloud(_:)),
            name: .documentMetadataDidUpdateFromCloud,
            object: nil
        )
    }
    
    @objc private func metadataUpdatedFromCloud(_ notification: Notification) {
        // Check if this is a remote change from iCloud
        guard notification.userInfo?["isRemoteChange"] as? Bool == true else {
            return
        }
        
        // Since this document is being actively viewed, ignore any iCloud updates
        // to prevent conflicts with local user actions
        print("🚫 [PDFViewController] Ignoring iCloud metadata update - document is being actively viewed")
    }
    
    private func setupObservations() {
        // No longer needed - using NotificationCenter for AI analysis updates
    }
    
    private func setupScrollObserver() {
        // Find the scroll view inside PDFView
        guard let scrollView = findScrollView(in: pdfView) else { return }
        
        // Observe content offset changes
        scrollObservation = scrollView.observe(\.contentOffset, options: [.new, .old]) { [weak self] scrollView, change in
            guard let self = self else { return }
            
            // Don't activate scroll observer until initial setup is complete
            guard self.hasCompletedInitialSetup else { return }
            
            // Don't hide/show navigation bar during programmatic navigation or UI toggling
            guard !self.isProgrammaticNavigation && !self.isTogglingUI else { return }
            
            guard let newOffset = change.newValue,
                  let oldOffset = change.oldValue else { return }
            
            // Calculate scroll delta
            let delta = newOffset.y - oldOffset.y
            
            // Threshold to prevent minor scrolls from toggling
            let threshold: CGFloat = 5
            
            // Ignore very small movements
            guard abs(delta) > threshold else { return }
            
            // Scrolling up (delta positive) - hide navigation bar
            // Scrolling down (delta negative) - show navigation bar
            if delta > 0 {
                self.hideNavigationBar()
            } else if delta < 0 {
                self.showNavigationBar()
            }
        }
    }
    
    private func setupAIAnalysisObservers() {
        // Observe AI analysis completion notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(aiAnalysisDidComplete(_:)),
            name: .aiAnalysisDidComplete,
            object: nil
        )
    }
    
    @objc private func aiAnalysisDidComplete(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let analysisID = userInfo["analysisID"] as? UUID else { return }
        
        let isStreaming = userInfo["isStreaming"] as? Bool ?? false
        let text = userInfo["text"] as? String ?? ""
        
        // Show completion state when this analysis completes
        if !isStreaming && generatingAnalysisID == analysisID {
            showGeneratingComplete()
        }
        
        // Check if this notification is for our current analysis (if sheet is open)
        guard currentAnalysis?.id == analysisID else { return }
        
        if isStreaming {
            // Stream new text to sheet
            if text.count > lastProcessedTextLength {
                let newTextRange = text.index(text.startIndex, offsetBy: lastProcessedTextLength)..<text.endIndex
                let newChunk = String(text[newTextRange])
                aiAnalysisViewController?.appendText(newChunk)
                lastProcessedTextLength = text.count
            }
        } else {
            // Analysis complete
            aiAnalysisViewController?.setLoading(false)
            
            if let error = userInfo["error"] as? String {
                aiAnalysisViewController?.appendText("\n\nError: \(error)")
            }
        }
    }
    
    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView {
            return scrollView
        }
        
        for subview in view.subviews {
            if let scrollView = findScrollView(in: subview) {
                return scrollView
            }
        }
        
        return nil
    }
    
    private func hideNavigationBar() {
        guard let navigationController = navigationController,
              !navigationController.isNavigationBarHidden else { return }
        
        UIView.animate(withDuration: 0.3) {
            navigationController.setNavigationBarHidden(true, animated: false)
        }
    }
    
    private func showNavigationBar() {
        guard let navigationController = navigationController,
              navigationController.isNavigationBarHidden else { return }
        
        UIView.animate(withDuration: 0.3) {
            navigationController.setNavigationBarHidden(false, animated: false)
        }
    }
    
    private func setupViews() {
        
        view.backgroundColor = .systemBackground
        view.addSubview(pdfView)
        view.addSubview(pagePreviewView)
        view.addSubview(pageIndicatorContainer)
        pageIndicatorContainer.contentView.addSubview(pageIndicatorLabel)
        view.addSubview(drawingControlsToolbar)
        view.addSubview(aiAnalysisButton)
        
        // Add target to AI analysis button
        aiAnalysisButton.addTarget(self, action: #selector(analyzeSelectedArea), for: .touchUpInside)
        
        pdfView.backgroundColor = .systemBackground
        // PDF document is already set in init() for early page restoration
        
        // Setup custom title view
        setupCustomTitleView()
        
        // Setup toolbar items
        updateToolbarItems()
        
        // Add tap gesture to toggle page preview
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handlePDFViewTap))
        tapGesture.delegate = self
        pdfView.addGestureRecognizer(tapGesture)
        
        // Configure page preview (will be updated with correct page in restoreReadingState)
        pagePreviewView.configure(with: pdfView.document, currentPage: 0)
        pagePreviewView.delegate = self
        
        let gestureRecognizer = DrawingGestureRecognizer()
        pdfDrawingGestureRecognizer = gestureRecognizer
        pdfView.addGestureRecognizer(gestureRecognizer)
        gestureRecognizer.drawingDelegate = pdfDrawer
        gestureRecognizer.isEnabled = isDrawingEnabled // Initially disabled
        pdfDrawer.pdfView = pdfView
        pdfDrawer.delegate = self
        
        updateDrawingToggleButton()
        updateDrawingControls()
        updateAIAnalysisButton()

        // Restore reading state after a brief delay to ensure PDFView is ready
        DispatchQueue.main.async {
            print("🔧 [Setup] Restoring reading state...")
            self.restoreReadingState()
            
            // Show initial page indicator after restoration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showInitialPageIndicator()
            }
            
            // Set up page change observer to update preview UI only
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.setupPageChangeObserver()
            }
            
            // Load saved AI analysis annotations
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.loadSavedAnnotations()
            }
        }
    }
    
    // MARK: - Load Saved Annotations
    
    private func loadSavedAnnotations() {
        guard let documentHash = document.fileHash,
              let pdfDocument = pdfView.document else {
            print("⚠️ [AIAnalysis] Cannot load annotations - missing hash or document")
            return
        }
        
        let savedAnalyses = AIAnalysisManager.shared.getAnalyses(forDocumentHash: documentHash)
        print("📝 [AIAnalysis] Loading \(savedAnalyses.count) saved annotations")
        
        for analysis in savedAnalyses {
            let pageIndex = Int(analysis.pageIndex)
            guard pageIndex < pdfDocument.pageCount,
                  let page = pdfDocument.page(at: pageIndex),
                  let annotation = AIAnalysisManager.shared.createAnnotation(from: analysis),
                  let analysisID = analysis.id else {
                continue
            }
            
            // Load the annotation via PDFDrawer
            pdfDrawer.loadSavedAnnotation(
                annotation: annotation,
                page: page,
                analysisID: analysisID
            )
        }
        
        updateDrawingControls()
        updateAIAnalysisButton()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Ensure navigation bar is visible when first appearing
        if let navigationController = navigationController {
            navigationController.setNavigationBarHidden(false, animated: false)
        }
        
        // Notify that this document is now being viewed
        // This will pause iCloud updates for cells showing this document
        NotificationCenter.default.post(
            name: .documentViewerDidOpen,
            object: nil,
            userInfo: ["documentURL": document.url]
        )
        print("👁️ [PDFViewController] Document viewer opened for '\(document.title ?? "Unknown")'")
        
        // Enable scroll observer after initial setup is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.hasCompletedInitialSetup = true
            print("✅ [PDFViewController] Initial setup complete - scroll observer activated")
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Save reading state when leaving the view
        saveReadingState()
        
        // Notify that this document is no longer being viewed
        // This will resume iCloud updates for cells
        NotificationCenter.default.post(
            name: .documentViewerDidClose,
            object: nil,
            userInfo: ["documentURL": document.url]
        )
        print("👁️ [PDFViewController] Document viewer closed for '\(document.title ?? "Unknown")'")
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // PDF view always fills the entire view
        pdfView.pin.all()
        
        // Position page preview as a vertical sidebar overlay on the left
        let pagePreviewWidth: CGFloat = 140
        pagePreviewView.pin
            .left()
            .top()
            .bottom()
            .width(pagePreviewWidth)
        
        // Layout page indicator pill
        layoutPageIndicator()
        
        // Position the buttons
        let insets = view.safeAreaInsets
        let bottomInsets = insets.bottom
        
        // Layout the drawing controls toolbar (center horizontally)
        layoutDrawingControlsToolbar(bottomInset: bottomInsets)
        
        // Position AI analysis button above the drawing controls when there's an annotation
        aiAnalysisButton.pin
            .height(54)
            .width(160)
            .bottom(to: drawingControlsToolbar.edge.top).marginBottom(16)
            .right(20)
    }
    
    private func layoutDrawingControlsToolbar(bottomInset: CGFloat) {
        let toolbarHeight: CGFloat = 60
        
        // Resize toolbar to fit its content
        drawingControlsToolbar.sizeToFit()
        
        // Position toolbar on the right side, at bottom
        drawingControlsToolbar.pin
            .height(toolbarHeight)
            .right()
            .bottom(bottomInset)
            .width(drawingControlsToolbar.frame.width)
    }
    
    private func updateToolbarItems() {
        var items: [UIBarButtonItem] = []
        
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        if isDrawingEnabled {
            // Show all three buttons with spacing
            items = [
                flexibleSpace,
                undoBarButton,
                clearAllBarButton,
                drawingToggleBarButton,
            ]
        } else {
            // Show only pencil button
            items = [
                flexibleSpace,
                drawingToggleBarButton,
            ]
        }
        
        drawingControlsToolbar.setItems(items, animated: true)
        
        // Trigger layout update
//        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
//            self.drawingControlsToolbar.sizeToFit()
//            self.view.setNeedsLayout()
//            self.view.layoutIfNeeded()
//        }
    }
    
    private func layoutPageIndicator() {
        
        // Add padding for the container
        let horizontalPadding: CGFloat = 16
        let verticalPadding: CGFloat = 8
        
        // Size and position the label inside the container
        pageIndicatorLabel.pin
            .sizeToFit()
        
        let labelSize = pageIndicatorLabel.frame
        
        // Size the container around the label with padding
        let containerWidth = labelSize.width + (horizontalPadding * 2)
        let containerHeight: CGFloat = 32 + (verticalPadding * 2)
        
        // Position the container at the bottom center of the view
        let insets = view.safeAreaInsets
        let bottomOffset: CGFloat = (insets.bottom > 0 ? insets.bottom : 24) + 8
        
        pageIndicatorContainer.pin
            .width(containerWidth)
            .height(containerHeight)
            .hCenter()
            .bottom(bottomOffset)
        
        pageIndicatorLabel.pin.hCenter().vCenter()
    }
    
    deinit {
        // Clean up observers
        scrollObservation?.invalidate()
        pageIndicatorHideTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Button Actions
    
    @objc private func toggleDrawing() {
        isDrawingEnabled.toggle()
    }
    
    @objc private func handlePDFViewTap(_ gesture: UITapGestureRecognizer) {
        let tapLocation = gesture.location(in: pdfView)
        
        // Check if tap is on a saved annotation with AI analysis
        if let page = pdfView.page(for: tapLocation, nearest: true),
           let pdfDocument = pdfView.document {
            let pageIndex = pdfDocument.index(for: page)
            let convertedPoint = pdfView.convert(tapLocation, to: page)
            
            // First check PDFDrawer's saved annotations
            if let analysisID = pdfDrawer.findAnalysisID(atPoint: convertedPoint, page: page),
               let analysis = AIAnalysisManager.shared.getAnalysis(byID: analysisID) {
                // Show the analysis result
                showAnalysisResult(analysis)
                return
            }
            
            // Also check via AIAnalysisManager (for bounds-based hit testing)
            if let documentHash = document.fileHash,
               let analysis = AIAnalysisManager.shared.findAnalysis(
                   atPoint: convertedPoint,
                   pageIndex: pageIndex,
                   documentFileHash: documentHash
               ) {
                showAnalysisResult(analysis)
                return
            }
        }
        
        // Set flag to prevent scroll observer from interfering
        isTogglingUI = true
        defer {
            // Reset flag after UI update completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.isTogglingUI = false
            }
        }
        
        // Toggle the page preview when tapping on the PDF view
        isPagePreviewVisible.toggle()
        
        // Show navigation bar when preview is shown, hide when preview is hidden
        if let navigationController = navigationController {
            if isPagePreviewVisible {
                // Show navigation bar when showing preview
                if navigationController.isNavigationBarHidden {
                    toggleNavigationBarWithoutJump(show: true)
                }
            } else {
                // Hide navigation bar when hiding preview
                if !navigationController.isNavigationBarHidden {
                    toggleNavigationBarWithoutJump(show: false)
                }
            }
        }
    }
    
    /// Show an existing AI analysis result
    private func showAnalysisResult(_ analysis: AIAnalysisResult) {
        currentAnalysis = analysis
        lastProcessedTextLength = 0  // Reset for new analysis
        
        let analysisVC = AIAnalysisViewController()
        
        // Set the screenshot image in the nav bar
        if let imageData = analysis.imageData, let image = UIImage(data: imageData) {
            analysisVC.setImage(image)
        }
        
        // Set up delete handler
        analysisVC.onDelete = { [weak self] in
            self?.deleteAnalysis(analysis)
        }
        
        if analysis.isCompleted {
            analysisVC.setLoading(false)
            if let response = analysis.response {
                analysisVC.setText(response)
            }
            if let timestamp = analysis.formattedCompletedDate {
                analysisVC.setTimestamp("Analyzed \(timestamp)")
            }
        } else if analysis.isPending {
            analysisVC.setLoading(true)
            if let response = analysis.response, !response.isEmpty {
                analysisVC.setText(response)
                lastProcessedTextLength = response.count
            }
        } else if analysis.isFailed {
            analysisVC.setLoading(false)
            analysisVC.setText("Analysis failed: \(analysis.errorMessage ?? "Unknown error")")
        }
        
        let nav = UINavigationController(rootViewController: analysisVC)
        nav.modalPresentationStyle = .pageSheet
        
        present(nav, animated: true)
        aiAnalysisViewController = analysisVC
    }
    
    /// Delete an analysis and its associated annotation
    private func deleteAnalysis(_ analysis: AIAnalysisResult) {
        guard let analysisID = analysis.id else { return }
        
        // Remove the annotation from the PDF
        if let page = pdfView.document?.page(at: Int(analysis.pageIndex)) {
            // Find and remove annotations matching this analysis
            for annotation in page.annotations {
                // Check if this annotation belongs to this analysis by comparing bounds
                if let boundsData = analysis.annotationBoundsData,
                   let bounds = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSValue.self, from: boundsData)?.cgRectValue,
                   annotation.bounds == bounds {
                    page.removeAnnotation(annotation)
                }
            }
        }
        
        // Remove from PDFDrawer's saved annotations
        pdfDrawer.removeSavedAnnotation(for: analysisID)
        
        // Delete from Core Data
        AIAnalysisManager.shared.deleteAnalysis(analysis)
        
        // Clear current analysis reference
        if currentAnalysis?.id == analysisID {
            currentAnalysis = nil
        }
        
        print("✅ [AIAnalysis] Deleted analysis \(analysisID)")
    }
    
    private func toggleNavigationBarWithoutJump(show: Bool) {
        guard let navigationController = navigationController,
              let scrollView = findScrollView(in: pdfView) else {
            if show {
                showNavigationBar()
            } else {
                hideNavigationBar()
            }
            return
        }
        
        // Capture current scroll position
        let currentOffset = scrollView.contentOffset
        let navBarHeight = navigationController.navigationBar.frame.height
        
        // Calculate new offset immediately (without animation)
        let newOffset: CGPoint
        if show {
            // When showing, increase offset to keep content in same visual position
            newOffset = CGPoint(x: currentOffset.x, y: currentOffset.y + navBarHeight)
        } else {
            // When hiding, decrease offset to keep content in same visual position
            newOffset = CGPoint(x: currentOffset.x, y: max(0, currentOffset.y - navBarHeight))
        }
        
        // Apply offset instantly before animating the navigation bar
        scrollView.contentOffset = newOffset
        
        // Then animate just the navigation bar
        UIView.animate(withDuration: 0.3) {
            navigationController.setNavigationBarHidden(!show, animated: false)
        }
    }
    
    @objc private func undoLastDrawing() {
        let wasUndone = pdfDrawer.undoLastDrawing()
        
        if wasUndone {
            updateDrawingControls()
            updateAIAnalysisButton()
        }
    }
    
    @objc private func clearAllAnnotations() {
        pdfDrawer.clearAllAnnotations()
        
        updateDrawingControls()
        updateAIAnalysisButton()
    }
    
    @objc private func analyzeSelectedArea() {
        guard pdfDrawer.newAnnotationCount > 0,
              let pdfDocument = pdfView.document,
              let documentHash = document.fileHash else {
            print("❌ [AIAnalysis] Missing required data for analysis")
            return
        }
        
        // Switch out of drawing mode
        isDrawingEnabled = false
        
        // Generate a new analysis ID
        let analysisID = UUID()
        
        // Mark all current annotations for generation (changes color to green and moves to saved)
        let annotationsToAnalyze = pdfDrawer.markAllAnnotationsForGeneration(analysisID: analysisID)
        
        guard let firstAnnotation = annotationsToAnalyze.first else {
            print("❌ [AIAnalysis] No annotations to analyze")
            return
        }
        
        // Use the first annotation's page for the page index
        let pageIndex = pdfDocument.index(for: firstAnnotation.page)
        
        // Request notification permission if needed
        Task {
            await NotificationManager.shared.requestAuthorization()
        }
        
        // Update UI immediately (hide the Explain button since no more fresh annotations)
        updateAIAnalysisButton()
        updateDrawingControls()
        
        // Start the analysis via AIAnalysisManager
        Task {
            let analysis = await AIAnalysisManager.shared.requestAnalysis(
                annotation: firstAnnotation.annotation,
                path: firstAnnotation.path,
                page: firstAnnotation.page,
                pageIndex: pageIndex,
                documentFileHash: documentHash,
                color: PDFDrawer.generatedColor,
                lineWidth: pdfDrawer.drawingTool.width,
                analysisID: analysisID
            )
            
            if let analysis = analysis {
                currentAnalysis = analysis
                
                // Show indicator with the same image stored in the analysis
                if let imageData = analysis.imageData, let image = UIImage(data: imageData) {
                    showGeneratingIndicator(image: image, analysisID: analysisID)
                }
            }
        }
    }
    
    // MARK: - Generating Indicator
    
    private func showGeneratingIndicator(image: UIImage, analysisID: UUID) {
        // Remove any existing indicator
        hideGeneratingIndicator()
        
        // Create and configure the indicator view
        let indicator = AIGeneratingIndicatorView()
        view.addSubview(indicator)
        
        // Set up tap handler to open the bottom sheet and hide indicator
        indicator.onTap = { [weak self] in
            guard let self = self,
                  let analysisID = self.generatingAnalysisID,
                  let analysis = AIAnalysisManager.shared.getAnalysis(byID: analysisID) else { return }
            self.showAnalysisResult(analysis)
            self.hideGeneratingIndicator()
        }
        
        // Show with animation (this sizes the view)
        indicator.show(with: image, animated: true)
        
        // Position centered horizontally, above the page indicator with small margin
        let size = indicator.sizeThatFits(.zero)
        let insets = view.safeAreaInsets
        let pageIndicatorBottomOffset: CGFloat = (insets.bottom > 0 ? insets.bottom : 24) + 8
        let pageIndicatorHeight: CGFloat = 32 + 16 // container height with padding
        let marginAbovePageIndicator: CGFloat = 8
        
        indicator.pin
            .size(size)
            .hCenter()
            .bottom(pageIndicatorBottomOffset + pageIndicatorHeight + marginAbovePageIndicator)
        
        generatingIndicator = indicator
        generatingAnalysisID = analysisID
    }
    
    private func showGeneratingComplete() {
        generatingIndicator?.showComplete()
    }
    
    private func hideGeneratingIndicator() {
        generatingIndicator?.hide(animated: true)
        generatingIndicator = nil
        generatingAnalysisID = nil
    }
    
    // MARK: - UI Updates
    
    private func updateDrawingToggleButton() {
        // Change tint color to blue when in drawing mode
        drawingToggleBarButton.tintColor = isDrawingEnabled ? .systemBlue : .label
        
        // Update the toolbar items
        updateToolbarItems()
    }
    
    private func updateDrawingControls() {
        let hasAnnotations = pdfDrawer.canUndo
        
        // Update button states
        undoBarButton.isEnabled = hasAnnotations
        clearAllBarButton.isEnabled = hasAnnotations
        
        // Update tint colors based on enabled state
        undoBarButton.tintColor = hasAnnotations ? .label : .secondaryLabel
        clearAllBarButton.tintColor = hasAnnotations ? .secondaryLabel : .tertiaryLabel
    }
    
    private func updateAIAnalysisButton() {
        // Show AI button only if there are new (unsaved) annotations
        let hasNewAnnotation = pdfDrawer.newAnnotationCount > 0
        let isAnalyzing = currentAnalysis?.isPending ?? false
        
        // Animate visibility changes with opacity only
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            self.aiAnalysisButton.alpha = hasNewAnnotation ? 1.0 : 0.0
        }
        
        aiAnalysisButton.isEnabled = !isAnalyzing
        
        if isAnalyzing {
            aiAnalysisButton.setImage(UIImage(systemName: "brain.fill"), for: .normal)
            aiAnalysisButton.tintColor = .systemBlue
        } else {
            aiAnalysisButton.setImage(UIImage(systemName: "brain"), for: .normal)
            aiAnalysisButton.tintColor = .label
        }
    }
    
    private func showAIAnalysisSheet() {
        let analysisVC = AIAnalysisViewController()
        analysisVC.setLoading(true)
        
        let nav = UINavigationController(rootViewController: analysisVC)
        nav.modalPresentationStyle = .pageSheet

        present(nav, animated: true)
        aiAnalysisViewController = analysisVC
        lastProcessedTextLength = 0
    }
    
    private func updatePagePreviewVisibility() {
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            self.pagePreviewView.alpha = self.isPagePreviewVisible ? 1.0 : 0
        }
    }
    
    // MARK: - Reading State Management
    
    private func setupPageChangeObserver() {
        // Observe page changes only to update the preview UI
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pdfViewPageChanged),
            name: .PDFViewPageChanged,
            object: pdfView
        )
    }
    
    /// Restores reading state after view loads (refines the early restoration)
    private func restoreReadingState() {
        guard let pdfDocument = pdfView.document else { return }

        performProgrammaticNavigation {
            // Restore zoom level (in case it didn't take effect earlier)
//            if let scaleFactor = document.scaleFactor {
//                pdfView.scaleFactor = scaleFactor
//            }
            
            // Restore current page (ensuring it's set correctly after view setup)
            let pageIndexToRestore: Int
            if let currentPageIndex = document.currentPage,
               currentPageIndex >= 0,
               currentPageIndex < pdfDocument.pageCount {
                pageIndexToRestore = currentPageIndex
                if let page = pdfDocument.page(at: currentPageIndex) {
                    pdfView.go(to: page)
                    print("🔧 [View Setup] Confirmed page \(currentPageIndex + 1) of \(pdfDocument.pageCount)")
                }
            } else {
                // Default to first page if no saved state
                pageIndexToRestore = 0
                if let firstPage = pdfDocument.page(at: 0) {
                    pdfView.go(to: firstPage)
                }
            }
            
            // Update page preview to show the correct page
            pagePreviewView.updateCurrentPage(pageIndexToRestore, animated: false)
        }
    }
    
    /// Performs a block of code with programmatic navigation flag set, automatically resetting it
    private func performProgrammaticNavigation(_ block: () -> Void) {
        isProgrammaticNavigation = true
        defer {
            // Reset flag after a delay to allow scroll events to settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.isProgrammaticNavigation = false
            }
        }
        block()
    }
    
    private func saveReadingState() {
        guard let pdfDocument = pdfView.document,
              let currentPage = pdfView.currentPage else { return }
        
        // Save current page index
        let pageIndex = pdfDocument.index(for: currentPage)
        
        print("💾 [PDFViewController] Saving reading state - Page \(pageIndex + 1) of \(pdfDocument.pageCount)")
        
        document.currentPage = pageIndex
        
        // Calculate and save reading progress (0.0 to 1.0)
        if pdfDocument.pageCount > 0 {
            let progress = Double(pageIndex) / Double(pdfDocument.pageCount - 1)
            document.pageProgress = max(0.0, min(1.0, progress))
        }
        
        // Save zoom level
        document.scaleFactor = pdfView.scaleFactor
    }
    
    @objc private func pdfViewPageChanged() {
        // Update page preview selection only - no saving to iCloud
        if let pdfDocument = pdfView.document,
           let currentPage = pdfView.currentPage {
            let pageIndex = pdfDocument.index(for: currentPage)
            pagePreviewView.updateCurrentPage(pageIndex, animated: true)
            
            // Update page indicator
            updatePageIndicator(pageIndex: pageIndex, totalPages: pdfDocument.pageCount)
        }
    }
    
    // MARK: - Page Indicator
    
    private func showInitialPageIndicator() {
        guard let pdfDocument = pdfView.document,
              let currentPage = pdfView.currentPage else { return }
        
        let pageIndex = pdfDocument.index(for: currentPage)
        updatePageIndicator(pageIndex: pageIndex, totalPages: pdfDocument.pageCount)
    }
    
    private func updatePageIndicator(pageIndex: Int, totalPages: Int) {
        // Update the label text
        pageIndicatorLabel.text = "\(pageIndex + 1) of \(totalPages)"
        
        // Trigger layout to resize the pill
        view.setNeedsLayout()
        view.layoutIfNeeded()
        
        // Show the indicator
        showPageIndicator()
        
        // Reset the hide timer
        pageIndicatorHideTimer?.invalidate()
        pageIndicatorHideTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.hidePageIndicator()
        }
    }
    
    private func showPageIndicator() {
        guard pageIndicatorContainer.alpha < 1.0 else { return }
        
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
            self.pageIndicatorContainer.alpha = 1.0
        }
    }
    
    private func hidePageIndicator() {
        guard pageIndicatorContainer.alpha > 0 else { return }
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseIn) {
            self.pageIndicatorContainer.alpha = 0
        }
    }
    
    // MARK: - Custom Title View
    
    private func setupCustomTitleView() {
        // Make navigation bar completely transparent
        if let navigationController = navigationController {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = .clear
            appearance.backgroundEffect = nil // Remove any blur effect
            appearance.shadowColor = .clear // Remove shadow/separator line
            
            navigationController.navigationBar.standardAppearance = appearance
            navigationController.navigationBar.scrollEdgeAppearance = appearance
            navigationController.navigationBar.compactAppearance = appearance
            
            // Ensure the navigation bar itself is transparent
            navigationController.navigationBar.isTranslucent = true
            navigationController.navigationBar.backgroundColor = .clear
        }
        
        // Set up the pill container with the title label
        titlePillContainer.contentView.addSubview(titleLabel)
        titleLabel.text = document.title ?? "Document"
        
        // Size the title label
        titleLabel.sizeToFit()
        
        // Add padding
        let horizontalPadding: CGFloat = 16
        let verticalPadding: CGFloat = 8
        
        let pillWidth = titleLabel.frame.width + (horizontalPadding * 2)
        let pillHeight: CGFloat = 32
        
        // Configure the pill container frame
        titlePillContainer.frame = CGRect(x: 0, y: 0, width: pillWidth, height: pillHeight)
        
        // Center the title label in the pill
        titleLabel.frame = CGRect(
            x: horizontalPadding,
            y: verticalPadding,
            width: titleLabel.frame.width,
            height: pillHeight - (verticalPadding * 2)
        )
        
        // Set the pill as the navigation item's title view
        navigationItem.titleView = titlePillContainer
    }
}

// MARK: - PDFDrawerDelegate

extension PDFViewController: PDFDrawerDelegate {
    func pdfDrawerDidCompleteDrawing() {
        updateDrawingControls()
        updateAIAnalysisButton()
    }
}

// MARK: - Helper Extension

extension NSObject {
    @discardableResult
    func apply(_ closure: (Self) -> Void) -> Self {
        closure(self)
        return self
    }
}

// MARK: - PDFPagePreviewDelegate

extension PDFViewController: PDFPagePreviewDelegate {
    func didSelectPage(at index: Int) {
        guard let pdfDocument = pdfView.document,
              index >= 0,
              index < pdfDocument.pageCount,
              let page = pdfDocument.page(at: index) else { return }
        
        // Navigate to the selected page - state will be saved when view is dismissed
        performProgrammaticNavigation {
            pdfView.go(to: page)
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension PDFViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow tap gesture to work alongside PDFView's gestures
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Don't trigger tap on buttons or page preview
        if touch.view is UIButton { return false }
        if touch.view?.isDescendant(of: pagePreviewView) == true { return false }
        
        // Only trigger if not in drawing mode
        return !isDrawingEnabled
    }
}
