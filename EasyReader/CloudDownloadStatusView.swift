//
//  CloudDownloadStatusView.swift
//  EasyReader
//
//  Created by Sammy Yousif on 11/10/25.
//

import UIKit
import Combine

class CloudDownloadStatusView: UIView {
    
    private let cloudIconView = UIImageView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        // Configure cloud icon
        cloudIconView.image = UIImage(systemName: "icloud.and.arrow.down")
        cloudIconView.tintColor = UIColor.systemBlue
        cloudIconView.contentMode = .scaleAspectFit
        addSubview(cloudIconView)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Position cloud icon with small padding
        cloudIconView.frame = bounds
    }
    
    /// Configure this view for a specific document
    func configure(with document: ReadableDoc, downloadManager: DocumentDownloadManager = .shared) {
        let status = document.getDownloadStatus()
        
        if status.isDownloaded {
            // File is downloaded, hide the view
            isHidden = true
        } else {
            // File is not downloaded, show cloud icon
            isHidden = false
        }
    }
}
