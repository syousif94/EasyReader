//
//  EPUBViewController.swift
//  EasyReader
//
//  Created by Sammy Yousif on 12/2/25.
//

import UIKit
import Combine
import PinLayout
import EPUBKit

class EPUBViewController: UIViewController {
    var document: ReadableDoc
    weak var viewModel: AppViewModel?
    
    private var cancellables: Set<AnyCancellable> = []
    
    // EPUB parsing
    private var epubDocument: EPUBDocument?
    private var contentParser: EPUBContentParser?
    private var isLoading = true
    
    // Collection view for chapters (vertical scrolling)
    lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.isPagingEnabled = false
        cv.showsHorizontalScrollIndicator = false
        cv.showsVerticalScrollIndicator = true
        cv.backgroundColor = .systemBackground
        cv.delegate = self
        cv.dataSource = self
        cv.contentInsetAdjustmentBehavior = .always
        cv.register(EPUBPageCell.self, forCellWithReuseIdentifier: EPUBPageCell.reuseIdentifier)
        return cv
    }()
    
    // Loading indicator
    let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        return indicator
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
    
    // Page indicator view
    let pageIndicatorView = PageIndicatorView()
    
    // Track drawing state
    private var isDrawingEnabled = false {
        didSet {
            updateDrawingToggleButton()
            updateDrawingControls()
            updateDrawingModeForVisibleCells()
        }
    }
    
    // Current page index
    private var currentPageIndex: Int = 0
    
    // Current stable reading position
    private var currentPosition: EPUBPosition?
    
    // AI Analysis bottom sheet
    private var aiAnalysisViewController: AIAnalysisViewController?
    private var lastProcessedTextLength = 0
    private var currentAnalysis: AIAnalysisResult? // Track current/displayed analysis
    
    // AI generating indicator
    private var generatingIndicator: AIGeneratingIndicatorView?
    private var generatingAnalysisID: UUID?
    
    // Flag to prevent saving state during programmatic navigation
    private var isProgrammaticNavigation = false
    
    // Navigation bar toggle tracking
    private var isTogglingUI = false
    private var lastScrollOffset: CGFloat = 0
    private var hasInitializedScrollOffset = false
    
    // Track last known width for resize detection
    private var lastKnownWidth: CGFloat = 0
    private var isHandlingWidthChange = false
    
    // Debounce timer for width changes
    private var widthChangeDebounceTimer: Timer?
    
    // Page indicator timer
    private var pageIndicatorHideTimer: Timer?
    
    init(document: ReadableDoc, viewModel: AppViewModel? = nil) {
        self.document = document
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        
        setupViews()
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupNotificationObservers()
        setupAIAnalysisObservers()
        
        // Load EPUB content
        loadEPUBContent()
    }
    
    private func loadEPUBContent() {
        loadingIndicator.startAnimating()
        
        Task {
            do {
                // Parse EPUB document
                guard let epub = EPUBDocument(url: document.url) else {
                    throw NSError(domain: "EPUBViewController", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse EPUB"])
                }
                
                self.epubDocument = epub
                
                // Create content parser
                let parser = EPUBContentParser(document: epub)
                self.contentParser = parser
                
                // Calculate page size (after layout is ready)
                await MainActor.run {
                    let pageSize = self.collectionView.bounds.size.width > 0 
                        ? self.collectionView.bounds.size 
                        : self.view.bounds.size
                    
                    // Store initial width to prevent resize detection on first layout
                    self.lastKnownWidth = pageSize.width
                    
                    Task {
                        try await parser.parse(pageSize: pageSize)
                        
                        await MainActor.run {
                            self.isLoading = false
                            self.loadingIndicator.stopAnimating()
                            self.collectionView.reloadData()
                            
                            // Save total page count for use by DocCell
                            self.document.totalPages = parser.pageCount
                            
                            // Restore reading state
                            self.restoreReadingState()
                            
                            // Show initial page indicator after restoration
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                self.showInitialPageIndicator()
                            }
                            
                            // Load saved annotations
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                self.loadSavedAnnotations()
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.loadingIndicator.stopAnimating()
                    self.showErrorAlert(error: error)
                }
            }
        }
    }
    
    private func showErrorAlert(error: Error) {
        let alert = UIAlertController(
            title: "Error Loading EPUB",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }
    
    private func setupNotificationObservers() {
        // Observe iCloud metadata updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataUpdatedFromCloud(_:)),
            name: .documentMetadataDidUpdateFromCloud,
            object: nil
        )
    }
    
    @objc private func metadataUpdatedFromCloud(_ notification: Notification) {
        guard notification.userInfo?["isRemoteChange"] as? Bool == true else { return }
        print("🚫 [EPUBViewController] Ignoring iCloud metadata update - document is being actively viewed")
    }
    
    private func setupAIAnalysisObservers() {
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
        
        guard currentAnalysis?.id == analysisID else { return }
        
        if isStreaming {
            // Stream new text to sheet
            if text.count > lastProcessedTextLength {
                let newTextRange = text.index(text.startIndex, offsetBy: lastProcessedTextLength)..<text.endIndex
                let newChunk = String(text[newTextRange])
                aiAnalysisViewController?.appendText(newChunk)
                aiAnalysisViewController?.setLoading(false)
                lastProcessedTextLength = text.count
            }
        } else {
            // Final update when streaming completes
            aiAnalysisViewController?.setLoading(false)
            
            if let error = userInfo["error"] as? String {
                aiAnalysisViewController?.appendText("\n\nError: \(error)")
            }
        }
    }
    
    private func setupViews() {
        view.backgroundColor = .systemBackground
        view.addSubview(collectionView)
        view.addSubview(loadingIndicator)
        view.addSubview(pageIndicatorView)
        view.addSubview(drawingControlsToolbar)
        view.addSubview(aiAnalysisButton)
        
        // Add target to AI analysis button
        aiAnalysisButton.addTarget(self, action: #selector(analyzeSelectedArea), for: .touchUpInside)
        
        // Setup custom title view
        setupCustomTitleView()
        
        // Setup toolbar items
        updateToolbarItems()
        
        // Add tap gesture to handle annotation taps and toggle UI
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleCollectionViewTap))
        tapGesture.delegate = self
        collectionView.addGestureRecognizer(tapGesture)
        
        updateDrawingToggleButton()
        updateDrawingControls()
        updateAIAnalysisButton()
    }
    
    private func loadSavedAnnotations() {
        guard let documentHash = document.fileHash else {
            print("⚠️ [AIAnalysis] Cannot load annotations - missing hash")
            return
        }
        
        let savedAnalyses = AIAnalysisManager.shared.getAnalyses(forDocumentHash: documentHash)
        print("📝 [AIAnalysis] Loading \(savedAnalyses.count) saved EPUB annotations")
        
        // Annotations will be loaded per-cell when cells become visible
        // Store the analysis data for later use
        
        updateDrawingControls()
        updateAIAnalysisButton()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if let navigationController = navigationController {
            navigationController.setNavigationBarHidden(false, animated: false)
        }
        
        NotificationCenter.default.post(
            name: .documentViewerDidOpen,
            object: nil,
            userInfo: ["documentURL": document.url]
        )
        print("👁️ [EPUBViewController] Document viewer opened for '\(document.title ?? "Unknown")'")
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        saveReadingState()
        
        NotificationCenter.default.post(
            name: .documentViewerDidClose,
            object: nil,
            userInfo: ["documentURL": document.url]
        )
        print("👁️ [EPUBViewController] Document viewer closed for '\(document.title ?? "Unknown")'")
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        collectionView.pin.all()
        loadingIndicator.pin.center()
        
        // Layout title view
        layoutTitleView()
        
        // Layout page indicator
        let indicatorSize = pageIndicatorView.sizeThatFits(.zero)
        let insets = view.safeAreaInsets
        let bottomOffset: CGFloat = (insets.bottom > 0 ? insets.bottom : 24) + 8
        
        pageIndicatorView.pin
            .size(indicatorSize)
            .hCenter()
            .bottom(bottomOffset)
        
        // Position the buttons
        let bottomInsets = insets.bottom
        
        // Layout the drawing controls toolbar
        layoutDrawingControlsToolbar(bottomInset: bottomInsets)
        
        // Position AI analysis button above the drawing controls
        aiAnalysisButton.pin
            .height(54)
            .width(160)
            .bottom(to: drawingControlsToolbar.edge.top).marginBottom(16)
            .right(20)
        
        // Check if width changed and we need to re-layout content
        let currentWidth = collectionView.bounds.width
        if currentWidth > 0 && lastKnownWidth > 0 && abs(currentWidth - lastKnownWidth) > 1 && !isHandlingWidthChange {
            lastKnownWidth = currentWidth
            scheduleWidthChangeHandler(newWidth: currentWidth)
        } else if !isHandlingWidthChange {
            lastKnownWidth = currentWidth
        }
    }
    
    private func scheduleWidthChangeHandler(newWidth: CGFloat) {
        // Cancel any pending debounce timer
        widthChangeDebounceTimer?.invalidate()
        
        // Debounce width changes - wait for resize to stabilize
        widthChangeDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            self?.handleWidthChange(newWidth: newWidth)
        }
    }
    
    private func handleWidthChange(newWidth: CGFloat) {
        guard !isLoading, !isHandlingWidthChange, let parser = contentParser else { return }
        
        isHandlingWidthChange = true
        isProgrammaticNavigation = true
        
        // Save current position before re-layout
        let savedPosition = calculateCurrentPosition()
        
        // Update visible cells' container width (updates text insets)
        for cell in collectionView.visibleCells {
            if let epubCell = cell as? EPUBPageCell {
                epubCell.updateContainerWidth(newWidth)
            }
        }
        
        // Invalidate layout to recalculate cell sizes - NO re-parsing needed!
        // The cells will recalculate their height via preferredLayoutAttributesFitting
        collectionView.collectionViewLayout.invalidateLayout()
        
        // Give layout time to recalculate, then restore position
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Force layout update
            self.collectionView.layoutIfNeeded()
            
            // Restore position after layout
            if let position = savedPosition {
                let (pageIndex, characterOffset) = parser.resolvePosition(position)
                self.currentPageIndex = pageIndex
                self.currentPosition = position
                
                if pageIndex < parser.pageCount {
                    // Scroll to the specific position
                    self.scrollToCharacterOffset(characterOffset, inPage: pageIndex)
                }
            }
            
            // Clear flags after resize completes
            DispatchQueue.main.async {
                self.isProgrammaticNavigation = false
                self.isHandlingWidthChange = false
            }
        }
    }
    
    private func layoutDrawingControlsToolbar(bottomInset: CGFloat) {
        let toolbarHeight: CGFloat = 60
        drawingControlsToolbar.sizeToFit()
        
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
            items = [flexibleSpace, undoBarButton, clearAllBarButton, drawingToggleBarButton]
        } else {
            items = [flexibleSpace, drawingToggleBarButton]
        }
        
        drawingControlsToolbar.setItems(items, animated: true)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        pageIndicatorHideTimer?.invalidate()
        widthChangeDebounceTimer?.invalidate()
    }
    
    // MARK: - Button Actions
    
    @objc private func toggleDrawing() {
        isDrawingEnabled.toggle()
    }
    
    @objc private func handleCollectionViewTap(_ gesture: UITapGestureRecognizer) {
        let tapLocation = gesture.location(in: collectionView)
        
        // Check if tap is on a saved annotation
        if let indexPath = collectionView.indexPathForItem(at: tapLocation),
           let cell = collectionView.cellForItem(at: indexPath) as? EPUBPageCell {
            let locationInCell = gesture.location(in: cell.drawingOverlay)
            if let analysisID = cell.drawingOverlay.findAnalysisID(at: locationInCell),
               let analysis = AIAnalysisManager.shared.getAnalysis(byID: analysisID) {
                showAnalysisResult(analysis)
                return
            }
        }
        
        // Set flag to prevent scroll observer from interfering
        isTogglingUI = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.isTogglingUI = false
            }
        }
        
        // Toggle navigation bar visibility
        if let navigationController = navigationController {
            let shouldShow = navigationController.isNavigationBarHidden
            toggleNavigationBarWithoutJump(show: shouldShow)
        }
    }
    
    private func showAnalysisResult(_ analysis: AIAnalysisResult) {
        currentAnalysis = analysis
        lastProcessedTextLength = 0  // Reset for new analysis
        
        let analysisVC = AIAnalysisViewController()
        
        if let image = analysis.getImage() {
            analysisVC.setImage(image)
        }
        
        analysisVC.onDelete = { [weak self] in
            self?.deleteAnalysis(analysis)
        }
        
        if analysis.isCompleted {
            analysisVC.setLoading(false)
            analysisVC.setText(analysis.response ?? "")
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
    
    private func deleteAnalysis(_ analysis: AIAnalysisResult) {
        guard let analysisID = analysis.id else { return }
        
        // Remove annotation from current visible cell if applicable
        let pageIndex = Int(analysis.pageIndex)
        if let cell = collectionView.cellForItem(at: IndexPath(item: pageIndex, section: 0)) as? EPUBPageCell {
            cell.drawingOverlay.removeSavedAnnotation(for: analysisID)
        }
        
        // Delete from Core Data
        AIAnalysisManager.shared.deleteAnalysis(analysis)
        
        updateDrawingControls()
        updateAIAnalysisButton()
    }
    
    @objc private func undoLastDrawing() {
        guard let cell = currentVisibleCell else { return }
        cell.drawingOverlay.undoLastAnnotation()
        updateDrawingControls()
        updateAIAnalysisButton()
    }
    
    @objc private func clearAllAnnotations() {
        guard let cell = currentVisibleCell else { return }
        cell.drawingOverlay.clearFreshAnnotations()
        updateDrawingControls()
        updateAIAnalysisButton()
    }
    
    @objc private func analyzeSelectedArea() {
        guard let cell = currentVisibleCell,
              cell.drawingOverlay.freshAnnotationCount > 0,
              let documentHash = document.fileHash else {
            print("❌ [AIAnalysis] Missing required data for analysis")
            return
        }
        
        // Switch out of drawing mode
        isDrawingEnabled = false
        
        // Generate a new analysis ID
        let analysisID = UUID()
        
        // Get annotation bounds and paths
        guard let bounds = cell.drawingOverlay.annotationsBounds else {
            print("❌ [AIAnalysis] No annotation bounds")
            return
        }
        
        let annotationPaths = cell.drawingOverlay.annotationPaths
        
        // Capture screenshot of the annotated area for the analysis (with padding)
        let padding: CGFloat = 20
        let expandedBounds = bounds.insetBy(dx: -padding, dy: -padding)
        let screenshotImage = cell.captureSnapshot(in: expandedBounds)
        
        // Mark annotations as saved
        cell.drawingOverlay.markAnnotationsAsSaved(analysisID: analysisID)
        
        // Request notification permission if needed
        Task {
            await NotificationManager.shared.requestAuthorization()
        }
        
        // Update UI immediately
        updateAIAnalysisButton()
        updateDrawingControls()
        
        // Start the analysis
        Task {
            guard let analysisImage = screenshotImage else { return }
            
            let analysis = await AIAnalysisManager.shared.requestEPUBAnalysis(
                image: analysisImage,
                annotationBounds: bounds,
                annotationPaths: annotationPaths,
                pageIndex: currentPageIndex,
                documentFileHash: documentHash,
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
        hideGeneratingIndicator()
        
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
        
        indicator.show(with: image, animated: true)
        
        let size = indicator.sizeThatFits(.zero)
        let insets = view.safeAreaInsets
        let bottomOffset: CGFloat = (insets.bottom > 0 ? insets.bottom : 24) + 16
        
        indicator.pin
            .size(size)
            .hCenter()
            .bottom(bottomOffset)
        
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
        drawingToggleBarButton.tintColor = isDrawingEnabled ? .systemBlue : .label
        updateToolbarItems()
    }
    
    private func updateDrawingControls() {
        let hasAnnotations = currentVisibleCell?.drawingOverlay.canUndo ?? false
        
        undoBarButton.isEnabled = hasAnnotations
        clearAllBarButton.isEnabled = hasAnnotations
        
        undoBarButton.tintColor = hasAnnotations ? .label : .secondaryLabel
        clearAllBarButton.tintColor = hasAnnotations ? .secondaryLabel : .tertiaryLabel
    }
    
    private func updateAIAnalysisButton() {
        let hasNewAnnotation = currentVisibleCell?.drawingOverlay.freshAnnotationCount ?? 0 > 0
        let isAnalyzing = currentAnalysis?.isPending ?? false
        
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
    
    private func updateDrawingModeForVisibleCells() {
        for cell in collectionView.visibleCells {
            if let epubCell = cell as? EPUBPageCell {
                epubCell.setDrawingEnabled(isDrawingEnabled)
            }
        }
    }
    
    // MARK: - Navigation Bar & Page Indicator
    
    private func toggleNavigationBarWithoutJump(show: Bool) {
        guard let navigationController = navigationController else { return }
        
        DispatchQueue.main.async {
            navigationController.setNavigationBarHidden(!show, animated: true)
        }
    }
    
    var isNavigationBarHidden: Bool = false
    
    private func hideNavigationBar() {
        
        guard !isNavigationBarHidden else { return }
        
        toggleNavigationBarWithoutJump(show: false)
        
        isNavigationBarHidden = true
    }
    
    private func showNavigationBar() {
        guard isNavigationBarHidden else { return }
        
        toggleNavigationBarWithoutJump(show: true)
        
        isNavigationBarHidden = false
    }
    
    private func showInitialPageIndicator() {
        updatePageIndicator()
        pageIndicatorView.show()
        scheduleHidePageIndicator()
    }
    
    private func updatePageIndicator() {
        guard let parser = contentParser else { return }
        
        // Use actual page count now that we have proper pagination
        let totalPages = parser.pageCount
        let currentPage = currentPageIndex + 1  // 1-indexed for display
        
        pageIndicatorView.currentPage = currentPage
        pageIndicatorView.totalPages = totalPages
        
        // Relayout page indicator only (not the whole view)
        let indicatorSize = pageIndicatorView.sizeThatFits(.zero)
        let insets = view.safeAreaInsets
        let bottomOffset: CGFloat = (insets.bottom > 0 ? insets.bottom : 24) + 8
        
        pageIndicatorView.pin
            .size(indicatorSize)
            .hCenter()
            .bottom(bottomOffset)
    }
    
    private func showPageIndicator() {
        pageIndicatorView.show()
    }
    
    private func hidePageIndicator() {
        pageIndicatorView.hide()
    }
    
    private func scheduleHidePageIndicator() {
        pageIndicatorHideTimer?.invalidate()
        pageIndicatorHideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.pageIndicatorView.hide()
        }
    }
    
    // MARK: - Helper Properties
    
    private var currentVisibleCell: EPUBPageCell? {
        let visibleRect = CGRect(origin: collectionView.contentOffset, size: collectionView.bounds.size)
        let visiblePoint = CGPoint(x: visibleRect.midX, y: visibleRect.midY)
        
        if let indexPath = collectionView.indexPathForItem(at: visiblePoint) {
            return collectionView.cellForItem(at: indexPath) as? EPUBPageCell
        }
        return nil
    }
    
    // MARK: - Reading State Management
    
    private func restoreReadingState() {
        guard let parser = contentParser, parser.pageCount > 0 else { return }
        
        isProgrammaticNavigation = true
        
        // Try to restore from stable position first
        if let positionString = document.epubPosition,
           let savedPosition = EPUBPosition.decode(from: positionString) {
            
            // Resolve the position to page index and character offset
            let (pageIndex, characterOffset) = parser.resolvePosition(savedPosition)
            currentPageIndex = pageIndex
            currentPosition = savedPosition
            
            // Scroll to page
            if pageIndex > 0 && pageIndex < parser.pageCount {
                collectionView.scrollToItem(
                    at: IndexPath(item: pageIndex, section: 0),
                    at: .top,
                    animated: false
                )
            }
            
            // After layout, scroll to the specific position within the page
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                self.scrollToCharacterOffset(characterOffset, inPage: pageIndex)
                // Initialize lastScrollOffset only on first mount
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if !self.hasInitializedScrollOffset {
                        self.lastScrollOffset = self.collectionView.contentOffset.y
                        self.hasInitializedScrollOffset = true
                    }
                    self.isProgrammaticNavigation = false
                }
            }
            
            return
        }
        
        // Fall back to legacy page-based restoration
        let pageIndexToRestore: Int
        if let savedPage = document.currentPage, savedPage < parser.pageCount {
            pageIndexToRestore = savedPage
        } else {
            pageIndexToRestore = 0
        }
        
        currentPageIndex = pageIndexToRestore
        
        if pageIndexToRestore > 0 {
            collectionView.scrollToItem(
                at: IndexPath(item: pageIndexToRestore, section: 0),
                at: .top,
                animated: false
            )
        }
        
        // Initialize lastScrollOffset only on first mount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            if !self.hasInitializedScrollOffset {
                self.lastScrollOffset = self.collectionView.contentOffset.y
                self.hasInitializedScrollOffset = true
            }
            self.isProgrammaticNavigation = false
        }
    }
    
    private func scrollToCharacterOffset(_ characterOffset: Int, inPage pageIndex: Int) {
        guard let cell = collectionView.cellForItem(at: IndexPath(item: pageIndex, section: 0)) as? EPUBPageCell else {
            return
        }
        
        // Get the y-position for this character offset
        let yPosition = cell.yPosition(forCharacterOffset: characterOffset)
        
        // Get the cell's frame in collection view coordinates
        let cellFrame = cell.frame
        
        // Calculate the target scroll offset
        let targetY = cellFrame.origin.y + yPosition
        
        // Scroll to position (with some padding from top)
        let topPadding: CGFloat = 50
        let scrollY = max(0, targetY - topPadding)
        
        collectionView.setContentOffset(CGPoint(x: 0, y: scrollY), animated: false)
    }
    
    private func saveReadingState() {
        guard !isProgrammaticNavigation,
              let parser = contentParser else { return }
        
        // Calculate current position based on scroll offset
        let position = calculateCurrentPosition()
        
        // Save stable position
        if let positionString = position?.encode() {
            document.epubPosition = positionString
        }
        
        // Also save legacy page index for backwards compatibility
        document.currentPage = currentPageIndex
        
        currentPosition = position
    }
    
    /// Calculate the current reading position based on scroll offset
    private func calculateCurrentPosition() -> EPUBPosition? {
        guard let parser = contentParser else { return nil }
        
        // Find the topmost visible cell
        let visibleRect = CGRect(origin: collectionView.contentOffset, size: collectionView.bounds.size)
        let topPoint = CGPoint(x: visibleRect.midX, y: visibleRect.minY + 50) // 50pt from top
        
        guard let indexPath = collectionView.indexPathForItem(at: topPoint),
              let cell = collectionView.cellForItem(at: indexPath) as? EPUBPageCell else {
            // Fall back to current page index
            return parser.createPosition(pageIndex: currentPageIndex, characterOffset: 0)
        }
        
        let pageIndex = indexPath.item
        
        // Calculate the y-offset within the cell
        let cellFrame = cell.frame
        let yOffsetInCell = collectionView.contentOffset.y - cellFrame.origin.y
        
        // Get the character offset at this y-position
        let characterOffset = cell.characterOffset(at: max(0, yOffsetInCell))
        
        return parser.createPosition(pageIndex: pageIndex, characterOffset: characterOffset)
    }
    
    // MARK: - Custom Title View
    
    private func setupCustomTitleView() {
        titlePillContainer.contentView.addSubview(titleLabel)
        titleLabel.text = document.title
        navigationItem.titleView = titlePillContainer
        layoutTitleView()
    }
    
    private func layoutTitleView() {
        let horizontalPadding: CGFloat = 16
        let verticalPadding: CGFloat = 8
        
        titleLabel.pin.sizeToFit()
        
        let containerWidth = titleLabel.frame.width + (horizontalPadding * 2)
        let containerHeight = titleLabel.frame.height + (verticalPadding * 2)
        
        titlePillContainer.frame = CGRect(x: 0, y: 0, width: containerWidth, height: containerHeight)
        titleLabel.pin.center()
    }
    
    func updateTitle(_ title: String?) {
        titleLabel.text = title
        layoutTitleView()
    }
}

// MARK: - UICollectionViewDataSource

extension EPUBViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return contentParser?.pageCount ?? 0
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EPUBPageCell.reuseIdentifier, for: indexPath) as! EPUBPageCell
        
        if let page = contentParser?.pages[indexPath.item] {
            cell.configure(with: page, at: indexPath.item, containerWidth: collectionView.bounds.width)
            cell.setDrawingEnabled(isDrawingEnabled)
            cell.drawingOverlay.drawingDelegate = self
            
            // Load saved annotations for this page
            loadSavedAnnotationsForCell(cell, pageIndex: indexPath.item)
        }
        
        return cell
    }
    
    /// Load saved annotations for a specific cell
    private func loadSavedAnnotationsForCell(_ cell: EPUBPageCell, pageIndex: Int) {
        guard let documentHash = document.fileHash else { return }
        
        let savedAnalyses = AIAnalysisManager.shared.getAnalyses(forDocumentHash: documentHash, pageIndex: pageIndex)
        
        for analysis in savedAnalyses {
            guard let analysisID = analysis.id,
                  let bounds = analysis.getAnnotationBounds() else {
                continue
            }
            
            // Get the path if available, otherwise create a simple rect path
            let path: UIBezierPath
            if let savedPath = analysis.getAnnotationPath() {
                path = savedPath
            } else {
                // Fallback: create a simple rectangle path from bounds
                path = UIBezierPath(rect: bounds)
            }
            
            cell.drawingOverlay.loadSavedAnnotation(path: path, bounds: bounds, analysisID: analysisID)
        }
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension EPUBViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        let bottomInset: CGFloat = 68 // Space for drawing controls toolbar
        return .init(top: 0, left: 0, bottom: bottomInset, right: 0)
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Don't process scroll events during programmatic navigation, UI toggling, or width changes
        guard !isProgrammaticNavigation, !isTogglingUI, !isHandlingWidthChange else { return }
        
        // Only process scroll if width is stable
        let currentWidth = collectionView.bounds.width
        guard currentWidth > 0 && abs(currentWidth - lastKnownWidth) < 1 else { return }
        
        let currentOffset = scrollView.contentOffset.y
        let delta = currentOffset - lastScrollOffset
        
        // Require significant scroll (50px) before toggling nav bar
        let threshold: CGFloat = 50
        
        guard abs(delta) > threshold else { return }
        
        // Update last offset
        lastScrollOffset = currentOffset
        
        // Scrolling down (content moving up, delta positive) - hide nav bar
        // Scrolling up (content moving down, delta negative) - show nav bar
        if delta > 0 {
            hideNavigationBar()
        } else if delta < 0 {
            showNavigationBar()
        }
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard !isProgrammaticNavigation, !isHandlingWidthChange else { return }
        updateCurrentChapterFromScroll()
        saveReadingState()
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !isProgrammaticNavigation, !isHandlingWidthChange else { return }
        if !decelerate {
            updateCurrentChapterFromScroll()
            saveReadingState()
        }
    }
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard !isHandlingWidthChange else { return }
        updateCurrentChapterFromScroll()
    }
    
    private func updateCurrentChapterFromScroll() {
        // Find visible cell closest to top
        let visibleRect = CGRect(origin: collectionView.contentOffset, size: collectionView.bounds.size)
        let visiblePoint = CGPoint(x: visibleRect.midX, y: visibleRect.minY + 100)
        
        if let indexPath = collectionView.indexPathForItem(at: visiblePoint) {
            currentPageIndex = indexPath.item
            
            // Update current position for page indicator
            currentPosition = calculateCurrentPosition()
            
            // Always show page indicator when scrolling stops
            updatePageIndicator()
            showPageIndicator()
            scheduleHidePageIndicator()
            
            updateDrawingControls()
            updateAIAnalysisButton()
        }
    }
}

// MARK: - EPUBDrawerDelegate

extension EPUBViewController: EPUBDrawerDelegate {
    func epubDrawerDidCompleteDrawing() {
        updateDrawingControls()
        updateAIAnalysisButton()
    }
}

// MARK: - UIGestureRecognizerDelegate

extension EPUBViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Don't interfere with buttons
        if touch.view is UIButton || touch.view is UIControl {
            return false
        }
        return true
    }
}
