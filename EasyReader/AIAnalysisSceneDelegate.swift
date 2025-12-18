//
//  AIAnalysisSceneDelegate.swift
//  EasyReader
//
//  Created by Sammy Yousif on 12/9/25.
//

import UIKit

/// Activity type for AI Analysis window
struct AIAnalysisActivity {
    static let activityType = "com.easyreader.aianalysis"
    
    struct UserInfoKeys {
        static let analysisID = "analysisID"
        static let imageData = "imageData"
        static let isNewAnalysis = "isNewAnalysis"
    }
}

/// Scene delegate for AI Analysis windows on Mac Catalyst
class AIAnalysisSceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    var window: UIWindow?
    private var analysisViewController: AIAnalysisViewController?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        
        // Create the window
        let window = UIWindow(windowScene: windowScene)
        
        // Create the AI Analysis view controller
        let analysisVC = AIAnalysisViewController()
        analysisViewController = analysisVC
        
        // Configure from user activity if available
        if let userActivity = connectionOptions.userActivities.first ?? session.stateRestorationActivity {
            configureAnalysisVC(analysisVC, from: userActivity)
        }
        
        // Wrap in navigation controller
        let nav = UINavigationController(rootViewController: analysisVC)
        
        window.rootViewController = nav
        window.makeKeyAndVisible()
        self.window = window
        
        // Configure window size for Mac
        #if targetEnvironment(macCatalyst)
        if let titlebar = windowScene.titlebar {
            titlebar.titleVisibility = .hidden
            titlebar.toolbar = nil
        }
        
        // Set preferred window size
        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 400, height: 500)
        windowScene.sizeRestrictions?.maximumSize = CGSize(width: 800, height: 1200)
        #endif
    }
    
    private func configureAnalysisVC(_ analysisVC: AIAnalysisViewController, from activity: NSUserActivity) {
        guard activity.activityType == AIAnalysisActivity.activityType else { return }
        
        let userInfo = activity.userInfo
        
        // Set image if available from userInfo
        if let imageData = userInfo?[AIAnalysisActivity.UserInfoKeys.imageData] as? Data,
           let image = UIImage(data: imageData) {
            analysisVC.setImage(image)
        }
        
        // Load existing analysis if ID is provided
        if let analysisIDString = userInfo?[AIAnalysisActivity.UserInfoKeys.analysisID] as? String,
           let analysisID = UUID(uuidString: analysisIDString),
           let analysis = AIAnalysisManager.shared.getAnalysis(byID: analysisID) {
            
            analysisVC.currentAnalysis = analysis
            
            // Load image from analysis if not already set from userInfo (e.g., during state restoration)
            if analysisVC.screenshotImage == nil,
               let imageData = analysis.imageData,
               let image = UIImage(data: imageData) {
                analysisVC.setImage(image)
            }
            
            if analysis.isCompleted {
                analysisVC.setLoading(false)
                analysisVC.loadChatHistory(from: analysis)
                if let timestamp = analysis.formattedCompletedDate {
                    analysisVC.setTimestamp("Analyzed \(timestamp)")
                }
            } else if analysis.isPending {
                analysisVC.setLoading(true)
                if let response = analysis.response, !response.isEmpty {
                    analysisVC.setText(response)
                }
            } else if analysis.isFailed {
                analysisVC.setLoading(false)
                analysisVC.setText("Analysis failed: \(analysis.errorMessage ?? "Unknown error")")
            }
        } else {
            // New analysis - show loading state
            let isNewAnalysis = userInfo?[AIAnalysisActivity.UserInfoKeys.isNewAnalysis] as? Bool ?? false
            if isNewAnalysis {
                analysisVC.setLoading(true)
            }
        }
    }
    
    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        // Return an activity that can restore this scene's state
        guard let analysis = analysisViewController?.currentAnalysis,
              let analysisID = analysis.id else {
            return nil
        }
        
        let activity = NSUserActivity(activityType: AIAnalysisActivity.activityType)
        activity.userInfo = [
            AIAnalysisActivity.UserInfoKeys.analysisID: analysisID.uuidString
        ]
        return activity
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
        // Clean up resources
        analysisViewController = nil
    }
    
    // MARK: - Public Access
    
    /// Get the analysis view controller for this scene (used for streaming updates)
    func getAnalysisViewController() -> AIAnalysisViewController? {
        return analysisViewController
    }
}

// MARK: - Helper to Find AI Analysis View Controller

extension AIAnalysisSceneDelegate {
    
    /// Find the AIAnalysisViewController for a given analysis ID across all scenes
    static func findAnalysisViewController(for analysisID: UUID) -> AIAnalysisViewController? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene,
                  let delegate = windowScene.delegate as? AIAnalysisSceneDelegate,
                  let analysisVC = delegate.analysisViewController,
                  analysisVC.currentAnalysis?.id == analysisID else {
                continue
            }
            return analysisVC
        }
        return nil
    }
    
    /// Find any AIAnalysisViewController that is waiting for a new analysis (isNewAnalysis = true)
    static func findPendingAnalysisViewController() -> AIAnalysisViewController? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene,
                  let delegate = windowScene.delegate as? AIAnalysisSceneDelegate,
                  let analysisVC = delegate.analysisViewController,
                  analysisVC.currentAnalysis == nil else {
                continue
            }
            return analysisVC
        }
        return nil
    }
}

// MARK: - Helper to Open AI Analysis Window

extension UIViewController {
    
    /// Opens the AI Analysis in a new window on Catalyst, or presents as sheet on iOS
    func presentAIAnalysis(
        analysis: AIAnalysisResult?,
        image: UIImage?,
        isNewAnalysis: Bool = false,
        onDelete: (() -> Void)? = nil,
        configure: ((AIAnalysisViewController) -> Void)? = nil
    ) -> AIAnalysisViewController {
        
        let analysisVC = AIAnalysisViewController()
        analysisVC.currentAnalysis = analysis
        
        if let image = image {
            analysisVC.setImage(image)
        }
        
        analysisVC.onDelete = onDelete
        
        // Apply any additional configuration
        configure?(analysisVC)
        
        #if targetEnvironment(macCatalyst)
        // On Catalyst, open in a new window
        openAIAnalysisWindow(analysisVC: analysisVC, analysis: analysis, image: image, isNewAnalysis: isNewAnalysis)
        #else
        // On iOS, present as sheet
        let nav = UINavigationController(rootViewController: analysisVC)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
        #endif
        
        return analysisVC
    }
    
    #if targetEnvironment(macCatalyst)
    private func openAIAnalysisWindow(
        analysisVC: AIAnalysisViewController,
        analysis: AIAnalysisResult?,
        image: UIImage?,
        isNewAnalysis: Bool
    ) {
        // Create user activity with analysis info
        let activity = NSUserActivity(activityType: AIAnalysisActivity.activityType)
        var userInfo: [String: Any] = [
            AIAnalysisActivity.UserInfoKeys.isNewAnalysis: isNewAnalysis
        ]
        
        if let analysisID = analysis?.id {
            userInfo[AIAnalysisActivity.UserInfoKeys.analysisID] = analysisID.uuidString
        }
        
        if let imageData = image?.jpegData(compressionQuality: 0.8) {
            userInfo[AIAnalysisActivity.UserInfoKeys.imageData] = imageData
        }
        
        activity.userInfo = userInfo
        
        // Request a new scene
        UIApplication.shared.requestSceneSessionActivation(
            nil,
            userActivity: activity,
            options: nil,
            errorHandler: { error in
                print("❌ [AIAnalysis] Failed to open window: \(error)")
                // Fallback to sheet presentation
                DispatchQueue.main.async {
                    let nav = UINavigationController(rootViewController: analysisVC)
                    nav.modalPresentationStyle = .pageSheet
                    self.present(nav, animated: true)
                }
            }
        )
    }
    #endif
}
