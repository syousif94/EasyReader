//
//  SceneDelegate.swift
//  EasyReader
//
//  Created by Sammy Yousif on 10/17/25.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    
    /// Stores a URL to open after the UI is ready
    private var pendingDocumentURL: URL?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
        guard let _ = (scene as? UIWindowScene) else { return }
        
        // Handle files/URLs passed when app is launched
        if let urlContext = connectionOptions.urlContexts.first {
            // Store the URL to process after UI is ready
            pendingDocumentURL = urlContext.url
        }
    }
    
    // MARK: - Handle URLs when app is already running
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let urlContext = URLContexts.first else { return }
        handleIncomingURL(urlContext.url)
    }
    
    // MARK: - Process pending URL after UI is ready
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
        
        // Process any pending document URL after the UI is ready
        if let url = pendingDocumentURL {
            pendingDocumentURL = nil
            // Small delay to ensure the navigation controller is fully set up
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.handleIncomingURL(url)
            }
        }
    }
    
    // MARK: - URL Handling
    
    private func handleIncomingURL(_ url: URL) {
        print("📄 [SceneDelegate] Received URL: \(url)")
        
        // Check if it's a file URL
        if url.isFileURL {
            handleIncomingFile(url)
        } else {
            // Handle custom URL schemes (e.g., easyreader://open?url=...)
            handleCustomURLScheme(url)
        }
    }
    
    private func handleIncomingFile(_ url: URL) {
        let result = DocumentImporter.shared.importDocument(from: url, accessSecurityScoped: true)
        
        switch result {
        case .imported(let destinationUrl):
            // Open the document after a short delay to let the directory monitor pick it up
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.openDocument(at: destinationUrl)
            }
        case .duplicate(let existingUrl):
            // Open the existing document
            openDocument(at: existingUrl)
        case .failed(let error):
            print("❌ [SceneDelegate] Import failed: \(error.localizedDescription)")
        }
    }
    
    private func handleCustomURLScheme(_ url: URL) {
        // Handle URLs like easyreader://open?url=https://example.com/document.pdf
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let host = components.host else {
            return
        }
        
        switch host {
        case "open":
            if let urlParam = components.queryItems?.first(where: { $0.name == "url" })?.value,
               let documentURL = URL(string: urlParam) {
                // Download and open the remote document
                downloadAndOpenDocument(from: documentURL)
            }
        default:
            print("⚠️ [SceneDelegate] Unknown URL scheme action: \(host)")
        }
    }
    
    private func downloadAndOpenDocument(from remoteURL: URL) {
        // TODO: Implement remote document downloading if needed
        print("📥 [SceneDelegate] Would download from: \(remoteURL)")
    }
    
    private func openDocument(at url: URL) {
        // Get the root navigation controller
        guard let navigationController = window?.rootViewController as? UINavigationController,
              let documentsVC = navigationController.viewControllers.first as? DocumentsViewController else {
            print("❌ [SceneDelegate] Could not find DocumentsViewController")
            return
        }
        
        // Pop to root if we're deep in navigation
        navigationController.popToRootViewController(animated: false)
        
        // Create a ReadableDoc and open it
        let fileExtension = url.pathExtension.lowercased()
        let docType: DocType
        
        switch fileExtension {
        case "pdf":
            docType = .pdf
        case "epub":
            docType = .epub
        default:
            print("⚠️ [SceneDelegate] Unsupported file type: \(fileExtension)")
            return
        }
        
        let document = ReadableDoc(id: UUID(), url: url, docType: docType)
        
        // Open the appropriate viewer
        switch docType {
        case .pdf:
            let readerVC = PDFViewController(document: document, viewModel: documentsVC.viewModel)
            navigationController.pushViewController(readerVC, animated: true)
        case .epub:
            let readerVC = EPUBViewController(document: document, viewModel: documentsVC.viewModel)
            navigationController.pushViewController(readerVC, animated: true)
        default:
            break
        }
        
        print("📖 [SceneDelegate] Opened document: \(url.lastPathComponent)")
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.

        // Save changes in the application's managed object context when the application transitions to the background.
        (UIApplication.shared.delegate as? AppDelegate)?.saveContext()
    }

}
