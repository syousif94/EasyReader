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
        let pasteAction = UIAction(title: "Paste", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in
            self?.handlePaste()
        }
        let menu = UIMenu(title: "", children: [pasteAction, filePickerAction])
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
    
    private func handlePaste() {
        let pasteboard = UIPasteboard.general
        
        // Check for file data (PDF or EPUB)
        if let pdfData = pasteboard.data(forPasteboardType: UTType.pdf.identifier) {
            importData(pdfData, withExtension: "pdf")
        } else if let epubData = pasteboard.data(forPasteboardType: UTType.epub.identifier) {
            importData(epubData, withExtension: "epub")
        } else if pasteboard.hasURLs, let url = pasteboard.urls?.first, url.isFileURL {
            // Handle file URLs from pasteboard
            let result = DocumentImporter.shared.importDocument(from: url)
            handleImportResult(result)
        } else {
            // Show alert that no valid document found
            let alert = UIAlertController(
                title: "No Document Found",
                message: "No PDF or EPUB document found in clipboard.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
    
    private func importData(_ data: Data, withExtension ext: String) {
        // Create a temporary file to import
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        
        do {
            try data.write(to: tempURL)
            let result = DocumentImporter.shared.importDocument(from: tempURL)
            handleImportResult(result)
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            print("❌ [Paste] Failed to write temp file: \(error.localizedDescription)")
        }
    }
    
    private func handleImportResult(_ result: DocumentImportResult) {
        switch result {
        case .imported(let destinationUrl):
            print("✅ [Paste] Imported: \(destinationUrl.lastPathComponent)")
        case .duplicate(let existingUrl):
            print("📄 [Paste] Duplicate skipped: \(existingUrl.lastPathComponent)")
        case .failed(let error):
            print("❌ [Paste] Failed: \(error.localizedDescription)")
        }
    }
}
