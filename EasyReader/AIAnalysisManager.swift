//
//  AIAnalysisManager.swift
//  EasyReader
//
//  Created by Sammy Yousif on 12/1/25.
//

import Foundation
import UIKit
import CoreData
import PDFKit
import FirebaseAI

/// Notification posted when an AI analysis completes
extension Notification.Name {
    static let aiAnalysisDidComplete = Notification.Name("aiAnalysisDidComplete")
    static let didDeleteAIAnalysis = Notification.Name("didDeleteAIAnalysis")
}

/// Manages AI analysis requests, persistence, and notifications
class AIAnalysisManager {
    static let shared = AIAnalysisManager()
    
    private init() {}
    
    // MARK: - Core Data Context
    
    private var context: NSManagedObjectContext {
        return AppDelegate.getManagedContext()
    }
    
    // MARK: - Create Analysis
    
    let defaultPrompt: String = """
Explain this to me in comprehensive, simple terms. Use LaTeX for math expressions when necessary. Use example matrices and example equations to illustrate concepts.

LaTeX formatting rules:
- Use $...$ for inline math and $$...$$ for display math
- NEVER use environment blocks like \\begin{...} or \\end{...} - these are not supported
  This includes: array, matrix, pmatrix, bmatrix, align, aligned, cases, equation, etc.
- For matrices, represent them as: $A = \\binom{a \\quad b}{c \\quad d}$ for a 2x2 matrix
  For vectors use: $\\binom{x}{y}$ which renders as a column vector
- For systems of equations, write each equation on a separate line using plain text, with inline LaTeX for each equation
  Example: Instead of using \\begin{array}, write:
  $2x_1 + 3x_2 - x_3 = 5$
  $x_1 - x_2 + 4x_3 = 10$
- Avoid \\text{}, \\textbf{}, \\textit{}, \\boldsymbol{}, \\operatorname{} - use plain text outside LaTeX instead
- Avoid \\underset{} - use subscripts like x_{subscript} instead
- For dots, use \\cdots only (not \\dots, \\ldots, \\vdots, \\hdots)
- For arrows: use \\Rightarrow instead of \\implies, \\Leftrightarrow instead of \\iff, \\Leftarrow instead of \\impliedby
- Keep LaTeX expressions simple and avoid complex nested structures
"""
    
    /// Creates a new AI analysis request and starts processing
    @MainActor
    func requestAnalysis(
        annotation: PDFAnnotation,
        path: UIBezierPath,
        page: PDFPage,
        pageIndex: Int,
        documentFileHash: String,
        color: UIColor,
        lineWidth: CGFloat,
        analysisID: UUID = UUID(),
        prompt: String? = nil
    ) async -> AIAnalysisResult? {
        
        // Capture the image from the annotation area
        guard let image = captureAnnotationImage(annotation: annotation, page: page) else {
            print("❌ [AIAnalysis] Failed to capture annotation image")
            return nil
        }
        
        // Create the Core Data object
        let analysis = AIAnalysisResult(context: context)
        analysis.id = analysisID
        analysis.documentFileHash = documentFileHash
        analysis.pageIndex = Int16(pageIndex)
        analysis.prompt = prompt
        analysis.status = "processing"
        analysis.createdAt = Date()
        
        // Serialize and store annotation data
        analysis.setAnnotationBounds(annotation.bounds)
        analysis.setAnnotationPath(path)
        analysis.setAnnotationColor(color)
        analysis.lineWidth = lineWidth
        
        // Store the image
        if let imageData = image.jpegData(compressionQuality: 0.8) {
            analysis.imageData = imageData
        }
        
        // Save immediately
        do {
            try context.save()
            print("✅ [AIAnalysis] Created analysis request: \(analysis.id?.uuidString ?? "unknown")")
        } catch {
            print("❌ [AIAnalysis] Failed to save analysis: \(error)")
            context.delete(analysis)
            return nil
        }
        
        // Start the AI analysis in the background (don't await)
        Task {
            await performAnalysis(analysis, image: image, prompt: prompt ?? defaultPrompt)
        }
        
        return analysis
    }
    
    // MARK: - Perform Analysis
    
    @MainActor
    private func performAnalysis(_ analysis: AIAnalysisResult, image: UIImage, prompt: String) async {
        do {
            // Initialize Firebase AI
            let ai = FirebaseAI.firebaseAI(backend: .googleAI())
            let model = ai.generativeModel(modelName: "gemini-2.5-flash-lite")
            
            // Start a chat session with the image and prompt
            let chat = model.startChat()
            
            // Send the initial message with image
            let contentStream = try chat.sendMessageStream(image, prompt)
            
            var fullResponse = ""
            
            // Process the stream
            for try await chunk in contentStream {
                if let text = chunk.text {
                    fullResponse += text
                    
                    // Update the response incrementally
                    analysis.response = fullResponse
                    
                    // Post notification for UI updates (streaming)
                    NotificationCenter.default.post(
                        name: .aiAnalysisDidComplete,
                        object: nil,
                        userInfo: [
                            "analysisID": analysis.id as Any,
                            "isStreaming": true,
                            "text": fullResponse
                        ]
                    )
                }
            }
            
            // Mark as completed
            analysis.status = "completed"
            analysis.completedAt = Date()
            analysis.response = fullResponse
            
            // Store the chat history (user prompt + model response)
            analysis.setChatHistory([
                AIAnalysisResult.ChatMessage(role: "user", content: prompt),
                AIAnalysisResult.ChatMessage(role: "model", content: fullResponse)
            ])
            
            try context.save()
            print("✅ [AIAnalysis] Analysis completed: \(analysis.id?.uuidString ?? "unknown")")
            
            // Send local notification if app is in background
            await NotificationManager.shared.sendAnalysisCompleteNotification(for: analysis)
            
            // Post final completion notification
            NotificationCenter.default.post(
                name: .aiAnalysisDidComplete,
                object: nil,
                userInfo: [
                    "analysisID": analysis.id as Any,
                    "isStreaming": false,
                    "text": fullResponse
                ]
            )
            
        } catch {
            print("❌ [AIAnalysis] Analysis failed: \(error)")
            analysis.status = "failed"
            analysis.errorMessage = error.localizedDescription
            analysis.completedAt = Date()
            
            try? context.save()
            
            // Post error notification
            NotificationCenter.default.post(
                name: .aiAnalysisDidComplete,
                object: nil,
                userInfo: [
                    "analysisID": analysis.id as Any,
                    "isStreaming": false,
                    "error": error.localizedDescription
                ]
            )
        }
    }
    
    // MARK: - Follow-up Questions
    
    /// Sends a follow-up question for an existing analysis (with optional image)
    /// Note: The caller should add the user message to chat history BEFORE calling this method
    /// This method will only append the AI's response to the chat history
    @MainActor
    func sendFollowUp(
        question: String,
        image: UIImage? = nil,
        analysis: AIAnalysisResult,
        onChunk: @escaping (String) -> Void
    ) async {
        do {
            // Initialize Firebase AI
            let ai = FirebaseAI.firebaseAI(backend: .googleAI())
            let model = ai.generativeModel(modelName: "gemini-2.5-flash-lite")
            
            // Build ModelContent history from stored chat history
            // EXCLUDE the last user message since we'll send it as the new message
            var history: [ModelContent] = []
            
            let chatHistory = analysis.getChatHistory()
            let historyWithoutLast = chatHistory.dropLast() // Remove the message we just added
            
            for (index, message) in historyWithoutLast.enumerated() {
                if index == 0, let imageData = analysis.imageData, let originalImage = UIImage(data: imageData) {
                    // First user message includes the original image
                    history.append(ModelContent(role: message.role, parts: originalImage, message.content))
                } else if let messageImage = analysis.getFollowUpImage(for: message) {
                    // Message has an attached follow-up image
                    history.append(ModelContent(role: message.role, parts: messageImage, message.content))
                } else {
                    history.append(ModelContent(role: message.role, parts: message.content))
                }
            }
            
            // Start chat with the conversation history (excluding the new user message)
            let chat = model.startChat(history: history)
            
            // Send the new user message (with or without image)
            let contentStream: AsyncThrowingStream<GenerateContentResponse, Error>
            if let followUpImage = image {
                contentStream = try chat.sendMessageStream(followUpImage, question)
            } else {
                contentStream = try chat.sendMessageStream(question)
            }
            
            var fullFollowUpResponse = ""
            
            // Process the stream
            for try await chunk in contentStream {
                if let text = chunk.text {
                    fullFollowUpResponse += text
                    onChunk(text)
                }
            }
            
            // Append only the AI response to the stored chat history
            analysis.appendToChatHistory(role: "model", content: fullFollowUpResponse)
            
            try context.save()
            print("✅ [AIAnalysis] Follow-up completed")
            
        } catch {
            print("❌ [AIAnalysis] Follow-up failed: \(error)")
            onChunk("\n\n*Error: \(error.localizedDescription)*")
        }
    }
    
    // MARK: - Retry Analysis
    
    /// Retries a failed or completed analysis
    @MainActor
    func retryAnalysis(
        _ analysis: AIAnalysisResult,
        onChunk: @escaping (String) -> Void
    ) async {
        guard let imageData = analysis.imageData,
              let image = UIImage(data: imageData) else {
            print("❌ [AIAnalysis] Cannot retry: no image data")
            onChunk("Error: No image data available for retry")
            return
        }
        
        // Reset the analysis state
        analysis.status = "processing"
        analysis.response = nil
        analysis.errorMessage = nil
        analysis.completedAt = nil
        analysis.chatHistoryData = nil
        
        try? context.save()
        
        let prompt = analysis.prompt ?? defaultPrompt
        
        do {
            // Initialize Firebase AI
            let ai = FirebaseAI.firebaseAI(backend: .googleAI())
            let model = ai.generativeModel(modelName: "gemini-2.5-flash-lite")
            
            // Start a new chat session with the image and prompt
            let chat = model.startChat()
            let contentStream = try chat.sendMessageStream(image, prompt)
            
            var fullResponse = ""
            
            // Process the stream
            for try await chunk in contentStream {
                if let text = chunk.text {
                    fullResponse += text
                    
                    // Update the response incrementally
                    analysis.response = fullResponse
                    onChunk(text)
                }
            }
            
            // Mark as completed
            analysis.status = "completed"
            analysis.completedAt = Date()
            analysis.response = fullResponse
            
            // Store the chat history
            analysis.setChatHistory([
                AIAnalysisResult.ChatMessage(role: "user", content: prompt),
                AIAnalysisResult.ChatMessage(role: "model", content: fullResponse)
            ])
            
            try context.save()
            print("✅ [AIAnalysis] Retry completed: \(analysis.id?.uuidString ?? "unknown")")
            
        } catch {
            print("❌ [AIAnalysis] Retry failed: \(error)")
            analysis.status = "failed"
            analysis.errorMessage = error.localizedDescription
            analysis.completedAt = Date()
            
            try? context.save()
            onChunk("\n\n*Error: \(error.localizedDescription)*")
        }
    }
    
    // MARK: - Capture Image
    
    private func captureAnnotationImage(annotation: PDFAnnotation, page: PDFPage) -> UIImage? {
        // Create a larger region around the annotation for better context
        let expandedBounds = annotation.bounds.insetBy(dx: -20, dy: -20)
        
        // Render the selected area as an image
        let renderer = UIGraphicsImageRenderer(size: expandedBounds.size)
        let image = renderer.image { context in
            // Fill with white background
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: expandedBounds.size))
            
            // Transform the context to match PDF coordinate system
            context.cgContext.translateBy(x: -expandedBounds.minX, y: expandedBounds.maxY)
            context.cgContext.scaleBy(x: 1.0, y: -1.0)
            
            // Draw the PDF page content in the selected region
            page.draw(with: .mediaBox, to: context.cgContext)
            
            // Draw the annotation
            annotation.draw(with: .mediaBox, in: context.cgContext)
        }
        
        return resizeImageIfNeeded(image, maxWidth: 800)
    }
    
    /// Resizes an image to a maximum width while maintaining aspect ratio
    private func resizeImageIfNeeded(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        let originalSize = image.size
        let currentWidth = originalSize.width
        
        // If image is already smaller than max width, return as-is
        guard currentWidth > maxWidth else {
            print("📐 [AIAnalysis] Image dimensions: \(Int(originalSize.width))x\(Int(originalSize.height)) (no resize needed)")
            return image
        }
        
        // Calculate new size maintaining aspect ratio
        let scaleFactor = maxWidth / currentWidth
        let newHeight = originalSize.height * scaleFactor
        let newSize = CGSize(width: maxWidth, height: newHeight)
        
        print("📐 [AIAnalysis] Image resized: \(Int(originalSize.width))x\(Int(originalSize.height)) → \(Int(newSize.width))x\(Int(newSize.height))")
        
        // Render the resized image
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        return resizedImage
    }
    
    // MARK: - Query Methods
    
    /// Find an analysis at a specific point on a page
    func findAnalysis(atPoint point: CGPoint, pageIndex: Int, documentFileHash: String) -> AIAnalysisResult? {
        let analyses = getAnalyses(forDocumentHash: documentFileHash, pageIndex: pageIndex)
        
        for analysis in analyses {
            if let bounds = analysis.getAnnotationBounds(), bounds.contains(point) {
                return analysis
            }
        }
        
        return nil
    }
    
    /// Get all analyses for a document
    func getAnalyses(forDocumentHash documentHash: String) -> [AIAnalysisResult] {
        let request: NSFetchRequest<AIAnalysisResult> = AIAnalysisResult.fetchRequest()
        request.predicate = NSPredicate(format: "documentFileHash == %@", documentHash)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("❌ [AIAnalysis] Failed to fetch analyses: \(error)")
            return []
        }
    }
    
    /// Get all analyses for a specific page
    func getAnalyses(forDocumentHash documentHash: String, pageIndex: Int) -> [AIAnalysisResult] {
        let request: NSFetchRequest<AIAnalysisResult> = AIAnalysisResult.fetchRequest()
        request.predicate = NSPredicate(
            format: "documentFileHash == %@ AND pageIndex == %d",
            documentHash,
            Int16(pageIndex)
        )
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("❌ [AIAnalysis] Failed to fetch analyses: \(error)")
            return []
        }
    }
    
    /// Get a specific analysis by ID
    func getAnalysis(byID id: UUID) -> AIAnalysisResult? {
        let request: NSFetchRequest<AIAnalysisResult> = AIAnalysisResult.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        
        do {
            return try context.fetch(request).first
        } catch {
            print("❌ [AIAnalysis] Failed to fetch analysis: \(error)")
            return nil
        }
    }
    
    // MARK: - Delete Methods
    
    /// Delete a specific analysis and its follow-up images
    func deleteAnalysis(_ analysis: AIAnalysisResult) {
        // Delete all follow-up images first
        if let analysisID = analysis.id {
            AIFollowUpImage.deleteAll(forAnalysisID: analysisID, context: context)
        }
        
        context.delete(analysis)
        
        do {
            try context.save()
            print("✅ [AIAnalysis] Deleted analysis")
        } catch {
            print("❌ [AIAnalysis] Failed to delete analysis: \(error)")
        }
    }
    
    /// Delete all analyses for a document
    func deleteAnalyses(forDocumentHash documentHash: String) {
        let analyses = getAnalyses(forDocumentHash: documentHash)
        for analysis in analyses {
            // Delete follow-up images for each analysis
            if let analysisID = analysis.id {
                AIFollowUpImage.deleteAll(forAnalysisID: analysisID, context: context)
            }
            context.delete(analysis)
        }
        
        do {
            try context.save()
            print("✅ [AIAnalysis] Deleted \(analyses.count) analyses")
        } catch {
            print("❌ [AIAnalysis] Failed to delete analyses: \(error)")
        }
    }
    
    // MARK: - EPUB Analysis
    
    /// Creates a new AI analysis request for EPUB content
    @MainActor
    func requestEPUBAnalysis(
        image: UIImage,
        annotationBounds: CGRect,
        annotationPaths: [UIBezierPath],
        pageIndex: Int,
        documentFileHash: String,
        analysisID: UUID = UUID(),
        prompt: String? = nil
    ) async -> AIAnalysisResult? {
        
        // Create the Core Data object
        let analysis = AIAnalysisResult(context: context)
        analysis.id = analysisID
        analysis.documentFileHash = documentFileHash
        analysis.pageIndex = Int16(pageIndex)
        analysis.prompt = prompt
        analysis.status = "processing"
        analysis.createdAt = Date()
        
        // Store annotation bounds and combined path
        analysis.setAnnotationBounds(annotationBounds)
        
        // Combine all paths into a single path for storage
        let combinedPath = UIBezierPath()
        for path in annotationPaths {
            combinedPath.append(path)
        }
        analysis.setAnnotationPath(combinedPath)
        
        // Resize image if needed
        let resizedImage = resizeImageIfNeeded(image, maxWidth: 800)
        
        // Store the image
        if let imageData = resizedImage.jpegData(compressionQuality: 0.8) {
            analysis.imageData = imageData
        }
        
        // Save immediately
        do {
            try context.save()
            print("✅ [AIAnalysis] Created EPUB analysis request: \(analysis.id?.uuidString ?? "unknown")")
        } catch {
            print("❌ [AIAnalysis] Failed to save EPUB analysis: \(error)")
            context.delete(analysis)
            return nil
        }
        
        // Start the AI analysis in the background (don't await)
        Task {
            await performAnalysis(analysis, image: resizedImage, prompt: prompt ?? defaultPrompt)
        }
        
        return analysis
    }
    
    // MARK: - Annotation Recreation
    
    /// Recreate a PDFAnnotation from stored analysis data
    func createAnnotation(from analysis: AIAnalysisResult) -> PDFAnnotation? {
        guard let bounds = analysis.getAnnotationBounds(),
              let path = analysis.getAnnotationPath() else {
            return nil
        }
        
        // Always use green for saved/generated annotations
        let color = UIColor.systemGreen
        
        let border = PDFBorder()
        border.lineWidth = analysis.lineWidth
        
        let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        annotation.color = color.withAlphaComponent(0.6)
        annotation.border = border
        
        // Center the path in the bounds
        var centeredPath = UIBezierPath()
        centeredPath.cgPath = path.cgPath
        annotation.add(centeredPath)
        
        return annotation
    }
}
