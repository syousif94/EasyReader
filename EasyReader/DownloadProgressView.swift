//
//  DownloadProgressView.swift
//  EasyReader
//
//  Created by Sammy Yousif on 11/10/25.
//

import UIKit

class DownloadProgressView: UIView {
    
    private let progressLayer = CAShapeLayer()
    private let backgroundLayer = CAShapeLayer()
    private let cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.9)
        return button
    }()
    
    var onCancelTapped: (() -> Void)?
    
    var downloadProgress: Double = 0 {
        didSet {
            updateProgress()
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
        // Background circle layer
        backgroundLayer.fillColor = UIColor.clear.cgColor
        backgroundLayer.strokeColor = UIColor.systemGray5.cgColor
        backgroundLayer.lineWidth = 4
        layer.addSublayer(backgroundLayer)
        
        // Progress circle layer
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = UIColor.systemBlue.cgColor
        progressLayer.lineWidth = 4
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0
        layer.addSublayer(progressLayer)
        
        // Cancel button
        addSubview(cancelButton)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        
        // Initially hidden
        isHidden = true
        alpha = 0
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 4
        
        // Create circular path
        let circularPath = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: 3 * .pi / 2,
            clockwise: true
        )
        
        backgroundLayer.path = circularPath.cgPath
        progressLayer.path = circularPath.cgPath
        
        // Position cancel button in center
        let buttonSize: CGFloat = radius * 1.2
        cancelButton.frame = CGRect(
            x: center.x - buttonSize / 2,
            y: center.y - buttonSize / 2,
            width: buttonSize,
            height: buttonSize
        )
        cancelButton.layer.cornerRadius = buttonSize / 2
        cancelButton.clipsToBounds = true
    }
    
    private func updateProgress() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        progressLayer.strokeEnd = CGFloat(downloadProgress)
        CATransaction.commit()
    }
    
    @objc private func cancelTapped() {
        onCancelTapped?()
    }
    
    func show() {
        isHidden = false
        UIView.animate(withDuration: 0.3) {
            self.alpha = 1.0
        }
    }
    
    func hide() {
        UIView.animate(withDuration: 0.3) {
            self.alpha = 0
        } completion: { _ in
            self.isHidden = true
        }
    }
}
