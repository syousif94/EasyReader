//
//  AIFollowUpImage+Extensions.swift
//  EasyReader
//
//  Created by Sammy Yousif on 12/15/25.
//

import Foundation
import UIKit
import CoreData

extension AIFollowUpImage {
    
    // MARK: - Image Access
    
    /// Get the image from stored data
    func getImage() -> UIImage? {
        guard let data = imageData else { return nil }
        return UIImage(data: data)
    }
    
    // MARK: - Create
    
    /// Create and save a new follow-up image
    @discardableResult
    static func create(
        image: UIImage,
        analysisID: UUID,
        context: NSManagedObjectContext
    ) -> AIFollowUpImage? {
        // Use PNG to preserve image quality and transparency
        guard let imageData = image.pngData() else {
            print("[AIFollowUpImage] Failed to create PNG data")
            return nil
        }
        
        let followUpImage = AIFollowUpImage(context: context)
        followUpImage.id = UUID()
        followUpImage.imageData = imageData
        followUpImage.createdAt = Date()
        followUpImage.analysisID = analysisID
        
        do {
            try context.save()
            print("[AIFollowUpImage] Created image: \(followUpImage.id?.uuidString ?? "unknown"), size: \(imageData.count) bytes")
            return followUpImage
        } catch {
            print("[AIFollowUpImage] Failed to save: \(error)")
            context.delete(followUpImage)
            return nil
        }
    }
    
    // MARK: - Fetch
    
    /// Fetch a follow-up image by ID
    static func fetch(byID imageID: UUID, context: NSManagedObjectContext) -> AIFollowUpImage? {
        let request: NSFetchRequest<AIFollowUpImage> = AIFollowUpImage.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", imageID as CVarArg)
        request.fetchLimit = 1
        
        do {
            return try context.fetch(request).first
        } catch {
            print("[AIFollowUpImage] Fetch failed: \(error)")
            return nil
        }
    }
    
    /// Fetch all follow-up images for an analysis
    static func fetchAll(forAnalysisID analysisID: UUID, context: NSManagedObjectContext) -> [AIFollowUpImage] {
        let request: NSFetchRequest<AIFollowUpImage> = AIFollowUpImage.fetchRequest()
        request.predicate = NSPredicate(format: "analysisID == %@", analysisID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("[AIFollowUpImage] FetchAll failed: \(error)")
            return []
        }
    }
    
    // MARK: - Delete
    
    /// Delete all follow-up images for an analysis
    static func deleteAll(forAnalysisID analysisID: UUID, context: NSManagedObjectContext) {
        let request: NSFetchRequest<AIFollowUpImage> = AIFollowUpImage.fetchRequest()
        request.predicate = NSPredicate(format: "analysisID == %@", analysisID as CVarArg)
        
        do {
            let images = try context.fetch(request)
            for image in images {
                context.delete(image)
            }
            try context.save()
            print("[AIFollowUpImage] Deleted \(images.count) images for analysis: \(analysisID)")
        } catch {
            print("[AIFollowUpImage] Delete failed: \(error)")
        }
    }
    
    /// Delete a specific follow-up image
    static func delete(imageID: UUID, context: NSManagedObjectContext) {
        guard let image = fetch(byID: imageID, context: context) else { return }
        
        context.delete(image)
        
        do {
            try context.save()
            print("[AIFollowUpImage] Deleted image: \(imageID)")
        } catch {
            print("[AIFollowUpImage] Delete failed: \(error)")
        }
    }
}
