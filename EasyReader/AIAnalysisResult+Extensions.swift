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
}
