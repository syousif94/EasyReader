//
//  AppDelegate.swift
//  EasyReader
//
//  Created by Sammy Yousif on 10/17/25.
//

import UIKit
import CoreData
import FirebaseCore
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    // Defer iCloud updates until after initial UI has loaded
    private var shouldDeferICloudUpdates = true
    private var deferredICloudNotifications: [Notification] = []
    private let iCloudDeferralLock = NSLock()
    
    // Coalesce multiple rapid iCloud notifications into a single update
    private var iCloudCoalesceTimer: Timer?
    private var pendingICloudNotificationCount = 0

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()
        
        // Setup notification delegate
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        
        // Observe persistent store remote change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeRemoteChange(_:)),
            name: .NSPersistentStoreRemoteChange,
            object: persistentContainer.persistentStoreCoordinator
        )
        
        // Observe notification taps to open AI analysis
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenAIAnalysis(_:)),
            name: .openAIAnalysisFromNotification,
            object: nil
        )
        
        return true
    }
    
    // MARK: - Handle AI Analysis Notification Tap
    
    @objc private func handleOpenAIAnalysis(_ notification: Notification) {
        guard let analysisID = notification.userInfo?["analysisID"] as? UUID,
              let analysis = AIAnalysisManager.shared.getAnalysis(byID: analysisID) else {
            return
        }
        
        print("📬 [AppDelegate] Opening AI analysis from notification: \(analysisID)")
        
        // Post a notification that the SceneDelegate can pick up to navigate to the document
        NotificationCenter.default.post(
            name: .navigateToAIAnalysis,
            object: nil,
            userInfo: [
                "analysisID": analysisID,
                "documentFileHash": analysis.documentFileHash ?? ""
            ]
        )
    }
    
    // MARK: - iCloud Update Deferral
    
    /// Call this after the document list has appeared to enable iCloud updates
    func enableICloudUpdates() {
        iCloudDeferralLock.lock()
        defer { iCloudDeferralLock.unlock() }
        
        guard shouldDeferICloudUpdates else { return }
        
        print("✅ [iCloud] Enabling deferred iCloud updates (\(deferredICloudNotifications.count) queued)")
        shouldDeferICloudUpdates = false
        
        // Process any deferred notifications
        let notifications = deferredICloudNotifications
        deferredICloudNotifications.removeAll()
        
        DispatchQueue.main.async { [weak self] in
            for notification in notifications {
                self?.processStoreRemoteChange(notification)
            }
        }
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        
        // Check if this is an AI Analysis scene request
        if let userActivity = options.userActivities.first,
           userActivity.activityType == AIAnalysisActivity.activityType {
            return UISceneConfiguration(name: "AI Analysis Configuration", sessionRole: connectingSceneSession.role)
        }
        
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

    // MARK: - Core Data stack

    lazy var persistentContainer: NSPersistentCloudKitContainer = {
        /*
         The persistent container for the application. This implementation
         creates and returns a container, having loaded the store for the
         application to it. This property is optional since there are legitimate
         error conditions that could cause the creation of the store to fail.
        */
        let container = NSPersistentCloudKitContainer(name: "EasyReader")
        
        let description = container.persistentStoreDescriptions.first
        
        description?.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.me.syousif.EasyReader")
        
        // Enable remote change notifications
        description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                 
                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
            else {
                #if DEBUG
                do {
                    try container.initializeCloudKitSchema(options: [])
                } catch {
                    print("Failed to initialize CloudKit schema: \(error)")
                }
                #endif
            }
        })
        
        // Automatically merge changes from iCloud
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        return container
    }()

    // MARK: - Core Data Saving support

    func saveContext () {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }
    
    static func getManagedContext() -> NSManagedObjectContext {
        return (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext
    }
    
    // MARK: - iCloud Sync Notifications
    
    @objc private func storeRemoteChange(_ notification: Notification) {
        iCloudDeferralLock.lock()
        let shouldDefer = shouldDeferICloudUpdates
        iCloudDeferralLock.unlock()
        
        if shouldDefer {
            // Defer this update until after the UI has loaded
            iCloudDeferralLock.lock()
            deferredICloudNotifications.append(notification)
            iCloudDeferralLock.unlock()
            print("⏳ [iCloud] Deferring Core Data change until UI loads")
            return
        }
        
        processStoreRemoteChange(notification)
    }
    
    private func processStoreRemoteChange(_ notification: Notification) {
        print("📱 [iCloud] Remote Core Data change detected")
        
        // Log additional details about what changed
        if let userInfo = notification.userInfo {
            if let historyToken = userInfo[NSPersistentHistoryTokenKey] {
                print("📱 [iCloud] History token: \(historyToken)")
            }
            if let storeUUID = userInfo[NSStoreUUIDKey] {
                print("📱 [iCloud] Store UUID: \(storeUUID)")
            }
        }
        
        // Coalesce rapid notifications into a single update
        pendingICloudNotificationCount += 1
        iCloudCoalesceTimer?.invalidate()
        
        iCloudCoalesceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            let count = self.pendingICloudNotificationCount
            self.pendingICloudNotificationCount = 0
            
            print("📱 [iCloud] Posting batched update (\(count) changes coalesced)")
            
            // Post a single notification that metadata was updated from iCloud
            // This will trigger UI updates in cells
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .documentMetadataDidUpdateFromCloud,
                    object: nil,
                    userInfo: ["isRemoteChange": true, "changeCount": count]
                )
            }
        }
    }

}

