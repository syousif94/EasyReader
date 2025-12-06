//
//  NotificationManager.swift
//  EasyReader
//
//  Created by Sammy Yousif on 12/1/25.
//

import Foundation
import UserNotifications
import UIKit

/// Manages local notifications for AI analysis completion
class NotificationManager: NSObject {
    static let shared = NotificationManager()
    
    private override init() {
        super.init()
    }
    
    // MARK: - Permission Request
    
    /// Request notification permissions
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            print("📬 [Notifications] Authorization \(granted ? "granted" : "denied")")
            return granted
        } catch {
            print("❌ [Notifications] Authorization error: \(error)")
            return false
        }
    }
    
    /// Check if notifications are authorized
    func isAuthorized() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
    }
    
    // MARK: - Send Notifications
    
    /// Send a notification when AI analysis completes
    @MainActor
    func sendAnalysisCompleteNotification(for analysis: AIAnalysisResult) async {
        // Only send notification if app is in background
        guard UIApplication.shared.applicationState != .active else {
            print("📬 [Notifications] App is active, skipping notification")
            return
        }
        
        // Check authorization
        guard await isAuthorized() else {
            print("📬 [Notifications] Not authorized, skipping notification")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "AI Analysis Ready"
        content.body = "Your explanation is ready. Tap to view."
        content.sound = .default
        
        // Store analysis ID for handling tap
        if let analysisID = analysis.id {
            content.userInfo = [
                "type": "aiAnalysisComplete",
                "analysisID": analysisID.uuidString,
                "documentFileHash": analysis.documentFileHash ?? ""
            ]
        }
        
        // Create trigger (immediate)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        // Create request
        let requestID = "aiAnalysis-\(analysis.id?.uuidString ?? UUID().uuidString)"
        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: trigger)
        
        // Schedule notification
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("📬 [Notifications] Scheduled analysis complete notification")
        } catch {
            print("❌ [Notifications] Failed to schedule notification: \(error)")
        }
    }
    
    // MARK: - Handle Notification Tap
    
    /// Handle when user taps on an AI analysis notification
    /// Returns the analysis ID if found
    func handleNotificationResponse(_ response: UNNotificationResponse) -> UUID? {
        let userInfo = response.notification.request.content.userInfo
        
        guard let type = userInfo["type"] as? String,
              type == "aiAnalysisComplete",
              let analysisIDString = userInfo["analysisID"] as? String,
              let analysisID = UUID(uuidString: analysisIDString) else {
            return nil
        }
        
        print("📬 [Notifications] User tapped analysis notification: \(analysisID)")
        return analysisID
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    
    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show banner even when app is in foreground
        return [.banner, .sound]
    }
    
    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if let analysisID = handleNotificationResponse(response) {
            // Post notification to open the analysis
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .openAIAnalysisFromNotification,
                    object: nil,
                    userInfo: ["analysisID": analysisID]
                )
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openAIAnalysisFromNotification = Notification.Name("openAIAnalysisFromNotification")
}
