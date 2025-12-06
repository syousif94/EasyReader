//
//  ImportMenuViewController.swift
//  EasyReader
//
//  Created by Sammy Yousif on 11/10/25.
//

import UIKit
import UniformTypeIdentifiers
import PinLayout

class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {

        let hitView = super.hitTest(point, with: event)

        return hitView == self ? nil : hitView
    }
}

class ImportMenuViewController: UIViewController, UIDocumentPickerDelegate {
    
    let button = UIButton()
    
    override func loadView() {
        self.view = PassthroughView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }
    
    func setupViews() {
        let filePickerAction = UIAction(title: "Files", image: UIImage(systemName: "folder.fill")) { _ in
            let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .epub])
            documentPicker.delegate = self
            documentPicker.modalPresentationStyle = .formSheet
            self.present(documentPicker, animated: true)
        }
        let pasteAction = UIAction(title: "Paste", image: UIImage(systemName: "doc.on.clipboard")) { _ in
            
        }
        let urlAction = UIAction(title: "URL", image: UIImage(systemName: "link")) { _ in
            
        }
        let menu = UIMenu(title: "", children: [urlAction, pasteAction, filePickerAction])
        button.configuration = .glass()
        button.menu = menu
        button.showsMenuAsPrimaryAction = true
        button.setImage(.init(systemName: "plus"), for: .normal)
        view.addSubview(button)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        let insets = view.safeAreaInsets
        
        let bottomInsets = insets.bottom > 0 ? insets.bottom : 24
        
        button.pin.height(44).width(44).bottom(bottomInsets).right(24)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let sourceURL = urls.first else { return }
                
        guard sourceURL.startAccessingSecurityScopedResource() else {
            return
        }

        defer { sourceURL.stopAccessingSecurityScopedResource() }
        
        let result = DocumentImporter.shared.importDocument(from: sourceURL)
        
        switch result {
        case .imported(let destinationUrl):
            print("✅ [FilePicker] Imported: \(destinationUrl.lastPathComponent)")
        case .duplicate(let existingUrl):
            print("📄 [FilePicker] Duplicate skipped: \(existingUrl.lastPathComponent)")
            // Optionally show a toast/alert that file already exists
        case .failed(let error):
            print("❌ [FilePicker] Failed: \(error.localizedDescription)")
        }
    }
}
