//
//  AIAnalysisResult+Extensions.swift
//  EasyReader
//
//  Created by Sammy Yousif on 12/1/25.
//

import Foundation
import UIKit
import CoreData

extension AIAnalysisResult {
    
    // MARK: - Annotation Bounds
    
    /// Set the annotation bounds (CGRect -> Data)
    func setAnnotationBounds(_ bounds: CGRect) {
        let boundsDict: [String: CGFloat] = [
            "x": bounds.origin.x,
            "y": bounds.origin.y,
            "width": bounds.size.width,
            "height": bounds.size.height
        ]
        annotationBoundsData = try? JSONEncoder().encode(boundsDict)
    }
    
    /// Get the annotation bounds (Data -> CGRect)
    func getAnnotationBounds() -> CGRect? {
        guard let data = annotationBoundsData,
              let boundsDict = try? JSONDecoder().decode([String: CGFloat].self, from: data) else {
            return nil
        }
        
        guard let x = boundsDict["x"],
              let y = boundsDict["y"],
              let width = boundsDict["width"],
              let height = boundsDict["height"] else {
            return nil
        }
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    // MARK: - Annotation Path
    
    /// Set the annotation path (UIBezierPath -> Data)
    func setAnnotationPath(_ path: UIBezierPath) {
        annotationPathData = try? NSKeyedArchiver.archivedData(
            withRootObject: path,
            requiringSecureCoding: false
        )
    }
    
    /// Get the annotation path (Data -> UIBezierPath)
    func getAnnotationPath() -> UIBezierPath? {
        guard let data = annotationPathData else { return nil }
        
        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: UIBezierPath.self,
            from: data
        )
    }
    
    // MARK: - Annotation Color
    
    /// Set the annotation color (UIColor -> Data)
    func setAnnotationColor(_ color: UIColor) {
        annotationColor = try? NSKeyedArchiver.archivedData(
            withRootObject: color,
            requiringSecureCoding: false
        )
    }
    
    /// Get the annotation color (Data -> UIColor)
    func getAnnotationColor() -> UIColor? {
        guard let data = annotationColor else { return nil }
        
        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: UIColor.self,
            from: data
        )
    }
    
    // MARK: - Convenience Properties
    
    /// Check if the analysis is completed
    var isCompleted: Bool {
        return status == "completed"
    }
    
    /// Check if the analysis is pending or processing
    var isPending: Bool {
        return status == "pending" || status == "processing"
    }
    
    /// Check if the analysis failed
    var isFailed: Bool {
        return status == "failed"
    }
    
    /// Get the captured image
    func getImage() -> UIImage? {
        guard let data = imageData else { return nil }
        return UIImage(data: data)
    }
    
    /// Formatted creation date
    var formattedCreatedDate: String? {
        guard let date = createdAt else { return nil }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    /// Formatted completion date
    var formattedCompletedDate: String? {
        guard let date = completedAt else { return nil }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    // MARK: - Chat History
    
    /// A single message in the chat history
    struct ChatMessage: Codable {
        let role: String  // "user" or "model"
        let content: String
        var imageID: UUID?  // Reference to AIFollowUpImage entity (for follow-up images)
        
        init(role: String, content: String, imageID: UUID? = nil) {
            self.role = role
            self.content = content
            self.imageID = imageID
        }
    }
    
    /// Set the chat history
    func setChatHistory(_ messages: [ChatMessage]) {
        chatHistoryData = try? JSONEncoder().encode(messages)
    }
    
    /// Get the chat history
    func getChatHistory() -> [ChatMessage] {
        guard let data = chatHistoryData,
              let messages = try? JSONDecoder().decode([ChatMessage].self, from: data) else {
            return []
        }
        return messages
    }
    
    /// Append a message to the chat history
    func appendToChatHistory(role: String, content: String) {
        var history = getChatHistory()
        history.append(ChatMessage(role: role, content: content))
        setChatHistory(history)
    }
    
    /// Append a message with an image to the chat history
    /// The image is stored as a separate AIFollowUpImage entity
    func appendToChatHistory(role: String, content: String, image: UIImage) {
        guard let analysisID = self.id else {
            print("❌ [AIAnalysisResult] Cannot add image without analysis ID")
            appendToChatHistory(role: role, content: content)
            return
        }
        
        let context = self.managedObjectContext ?? AppDelegate.getManagedContext()
        
        // Create the follow-up image entity
        guard let followUpImage = AIFollowUpImage.create(image: image, analysisID: analysisID, context: context) else {
            print("❌ [AIAnalysisResult] Failed to create follow-up image")
            appendToChatHistory(role: role, content: content)
            return
        }
        
        var history = getChatHistory()
        history.append(ChatMessage(role: role, content: content, imageID: followUpImage.id))
        setChatHistory(history)
        
        // Save the context to persist the chat history with the imageID reference
        do {
            try context.save()
            print("✅ [AIAnalysisResult] Saved chat history with image ID: \(followUpImage.id?.uuidString ?? "unknown")")
        } catch {
            print("❌ [AIAnalysisResult] Failed to save chat history: \(error)")
        }
    }
    
    /// Get the image for a chat message (fetches from AIFollowUpImage)
    func getFollowUpImage(for message: ChatMessage) -> UIImage? {
        guard let imageID = message.imageID else { return nil }
        let context = self.managedObjectContext ?? AppDelegate.getManagedContext()
        return AIFollowUpImage.fetch(byID: imageID, context: context)?.getImage()
    }
}
