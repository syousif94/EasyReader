//
//  PageIndicatorView.swift
//  EasyReader
//
//  Created by Sammy Yousif on 11/11/25.
//

import UIKit

class PageIndicatorView: UIView {
    
    private let containerView: UIVisualEffectView = {
        let blurEffect = UIBlurEffect(style: .systemMaterial)
        let view = UIVisualEffectView(effect: blurEffect)
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }()
    
    private let pageLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .label
        label.textAlignment = .center
        return label
    }()
    
    var currentPage: Int = 0 {
        didSet {
            updatePageLabel()
        }
    }
    
    var totalPages: Int = 0 {
        didSet {
            updatePageLabel()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        addSubview(containerView)
        containerView.contentView.addSubview(pageLabel)
        
        // Add subtle shadow for depth
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOpacity = 0.1
        containerView.layer.shadowOffset = CGSize(width: 0, height: 2)
        containerView.layer.shadowRadius = 8
        
        // Initially hidden with zero alpha
        alpha = 0
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        containerView.frame = bounds
        pageLabel.frame = containerView.contentView.bounds
    }
    
    private func updatePageLabel() {
        pageLabel.text = "\(currentPage) / \(totalPages)"
    }
    
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let labelSize = pageLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: size.height))
        // Add padding: 16pt horizontal, 8pt vertical
        return CGSize(width: labelSize.width + 32, height: max(32, labelSize.height + 16))
    }
    
    // MARK: - Show/Hide with animation
    
    func show(animated: Bool = true) {
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
                self.alpha = 1.0
            }
        } else {
            alpha = 1.0
        }
    }
    
    func hide(animated: Bool = true, after delay: TimeInterval = 0) {
        if animated {
            UIView.animate(withDuration: 0.2, delay: delay, options: .curveEaseIn) {
                self.alpha = 0
            }
        } else {
            alpha = 0
        }
    }
    
    func showBriefly(duration: TimeInterval = 2.0) {
        show(animated: true)
        hide(animated: true, after: duration)
    }
}
