//
//  PDFDrawer.swift
//  PDFKit Demo
//
//  Created by Tim on 31/01/2019.
//  Copyright © 2019 Tim. All rights reserved.
//

import Foundation
import PDFKit

protocol PDFDrawerDelegate: AnyObject {
    func pdfDrawerDidCompleteDrawing()
}

enum DrawingTool: Int {
    case eraser = 0
    case pencil = 1
    case pen = 2
    case highlighter = 3
    
    var width: CGFloat {
        switch self {
        case .pencil:
            return 1
        case .pen:
            return 2
        case .highlighter:
            return 10
        default:
            return 0
        }
    }
    
    var alpha: CGFloat {
        switch self {
        case .highlighter:
            return 0.3 //0,5
        default:
            return 0.6
        }
    }
}

class PDFDrawer {
    weak var pdfView: PDFView!
    weak var delegate: PDFDrawerDelegate?
    private var path: UIBezierPath?
    private var currentAnnotation : DrawingAnnotation?
    private var currentPage: PDFPage?
    var drawingTool = DrawingTool.pen
    
    // Colors for different annotation states
    static let freshColor = UIColor.systemBlue      // Fresh strokes without AI generation
    static let generatedColor = UIColor.systemGreen // Strokes with AI generation
    
    // Track all new annotations (fresh strokes without AI generation)
    private var annotations: [(annotation: PDFAnnotation, page: PDFPage, path: UIBezierPath)] = []
    
    // Track annotations that have AI analyses (either pending or completed)
    private var savedAnnotations: [(annotation: PDFAnnotation, page: PDFPage, analysisID: UUID)] = []
}

extension PDFDrawer: DrawingGestureRecognizerDelegate {
    func gestureRecognizerBegan(_ location: CGPoint) {
        guard let page = pdfView.page(for: location, nearest: true) else { return }
        currentPage = page
        let convertedPoint = pdfView.convert(location, to: currentPage!)
        path = UIBezierPath()
        path?.move(to: convertedPoint)
    }
    
    func gestureRecognizerMoved(_ location: CGPoint) {
        guard let page = currentPage else { return }
        let convertedPoint = pdfView.convert(location, to: page)
        
        if drawingTool == .eraser {
            removeAnnotationAtPoint(point: convertedPoint, page: page)
            return
        }
        
        path?.addLine(to: convertedPoint)
        path?.move(to: convertedPoint)
        drawAnnotation(onPage: page)
    }
    
    func gestureRecognizerEnded(_ location: CGPoint) {
        guard let page = currentPage else { return }
        let convertedPoint = pdfView.convert(location, to: page)
        
        // Erasing
        if drawingTool == .eraser {
            removeAnnotationAtPoint(point: convertedPoint, page: page)
            return
        }
        
        // Drawing
        guard let _ = currentAnnotation else { return }
        
        path?.addLine(to: convertedPoint)
        path?.move(to: convertedPoint)
        
        // Final annotation
        page.removeAnnotation(currentAnnotation!)
        let finalAnnotation = createFinalAnnotation(path: path!, page: page)
        currentAnnotation = nil
    }
    
    private func createAnnotation(path: UIBezierPath, page: PDFPage) -> DrawingAnnotation {
        let border = PDFBorder()
        border.lineWidth = drawingTool.width
        
        let annotation = DrawingAnnotation(bounds: page.bounds(for: pdfView.displayBox), forType: .ink, withProperties: nil)
        annotation.color = PDFDrawer.freshColor.withAlphaComponent(drawingTool.alpha)
        annotation.border = border
        return annotation
    }
    
    private func drawAnnotation(onPage: PDFPage) {
        guard let path = path else { return }
        
        if currentAnnotation == nil {
            currentAnnotation = createAnnotation(path: path, page: onPage)
        }
        
        currentAnnotation?.path = path
        forceRedraw(annotation: currentAnnotation!, onPage: onPage)
    }
    
    private func createFinalAnnotation(path: UIBezierPath, page: PDFPage) -> PDFAnnotation {
        let border = PDFBorder()
        border.lineWidth = drawingTool.width
        
        let bounds = CGRect(x: path.bounds.origin.x - 5,
                            y: path.bounds.origin.y - 5,
                            width: path.bounds.size.width + 10,
                            height: path.bounds.size.height + 10)
        var signingPathCentered = UIBezierPath()
        signingPathCentered.cgPath = path.cgPath
        signingPathCentered.moveCenter(to: bounds.center)
        
        let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        annotation.color = PDFDrawer.freshColor.withAlphaComponent(drawingTool.alpha)
        annotation.border = border
        annotation.add(signingPathCentered)
        page.addAnnotation(annotation)
        
        // Add the new annotation to the list with the path
        annotations.append((annotation: annotation, page: page, path: signingPathCentered))
        
        // Notify delegate that a drawing was completed
        delegate?.pdfDrawerDidCompleteDrawing()
                
        return annotation
    }
    
    private func removeAnnotationAtPoint(point: CGPoint, page: PDFPage) {
        if let selectedAnnotation = page.annotationWithHitTest(at: point) {
            selectedAnnotation.page?.removeAnnotation(selectedAnnotation)
        }
    }
    
    private func forceRedraw(annotation: PDFAnnotation, onPage: PDFPage) {
        onPage.removeAnnotation(annotation)
        onPage.addAnnotation(annotation)
    }
    
    // MARK: - Undo Functionality
    
    /// Removes the most recent NEW annotation (fresh strokes only)
    /// Saved annotations (with AI generation) cannot be undone
    @discardableResult
    func undoLastDrawing() -> Bool {
        // Only undo new (fresh) annotations, not saved ones
        guard !annotations.isEmpty else {
            return false
        }
        
        let lastAnnotation = annotations.removeLast()
        lastAnnotation.page.removeAnnotation(lastAnnotation.annotation)
        return true
    }
    
    /// Returns whether there are any NEW annotations that can be undone
    /// Saved annotations are not undoable
    var canUndo: Bool {
        return !annotations.isEmpty
    }
    
    /// Clears all NEW annotations (fresh strokes only)
    /// Saved annotations (with AI generation) are not cleared
    func clearAllAnnotations() {
        // Clear only new annotations
        for annotation in annotations {
            annotation.page.removeAnnotation(annotation.annotation)
        }
        annotations.removeAll()
    }
    
    /// Gets the most recent annotation for analysis
    var currentActiveAnnotation: PDFAnnotation? {
        return annotations.last?.annotation
    }
    
    /// Gets the path for the most recent annotation
    var currentActiveAnnotationPath: UIBezierPath? {
        return annotations.last?.path
    }
    
    /// Gets the page for the most recent annotation
    var currentActiveAnnotationPage: PDFPage? {
        return annotations.last?.page
    }
    
    /// Returns the number of annotations (both new and saved)
    var annotationCount: Int {
        return annotations.count + savedAnnotations.count
    }
    
    /// Returns just the count of new (unsaved) annotations
    var newAnnotationCount: Int {
        return annotations.count
    }
    
    // MARK: - Load Saved Annotations
    
    /// Load annotations from saved AI analyses
    func loadSavedAnnotation(
        annotation: PDFAnnotation,
        page: PDFPage,
        analysisID: UUID
    ) {
        page.addAnnotation(annotation)
        savedAnnotations.append((annotation: annotation, page: page, analysisID: analysisID))
    }
    
    /// Clear only the saved annotations (used when reloading)
    func clearSavedAnnotations() {
        for saved in savedAnnotations {
            saved.page.removeAnnotation(saved.annotation)
        }
        savedAnnotations.removeAll()
    }
    
    /// Remove a specific saved annotation by analysis ID
    func removeSavedAnnotation(for analysisID: UUID) {
        if let index = savedAnnotations.firstIndex(where: { $0.analysisID == analysisID }) {
            let saved = savedAnnotations[index]
            saved.page.removeAnnotation(saved.annotation)
            savedAnnotations.remove(at: index)
        }
    }
    
    /// Find which analysis ID corresponds to an annotation at a given point
    func findAnalysisID(atPoint point: CGPoint, page: PDFPage) -> UUID? {
        for saved in savedAnnotations {
            if saved.page == page && saved.annotation.bounds.contains(point) {
                return saved.analysisID
            }
        }
        return nil
    }
    
    /// Mark all current new annotations as saved and change their color to green
    /// Returns the annotations data (for creating the AI analysis)
    func markAllAnnotationsForGeneration(analysisID: UUID) -> [(annotation: PDFAnnotation, page: PDFPage, path: UIBezierPath)] {
        let annotationsToMark = annotations
        
        // Change color of all annotations to green (generated color)
        for item in annotationsToMark {
            // Update the annotation color
            item.annotation.color = PDFDrawer.generatedColor.withAlphaComponent(drawingTool.alpha)
            
            // Force redraw to show new color
            if let page = item.annotation.page {
                page.removeAnnotation(item.annotation)
                page.addAnnotation(item.annotation)
            }
            
            // Move to saved annotations
            savedAnnotations.append((annotation: item.annotation, page: item.page, analysisID: analysisID))
        }
        
        // Clear the new annotations list
        annotations.removeAll()
        
        return annotationsToMark
    }
}
