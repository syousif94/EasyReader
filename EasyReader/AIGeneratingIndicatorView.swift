//
//  AIGeneratingIndicatorView.swift
//  EasyReader
//
//  Created by Sammy Yousif on 12/1/25.
//

import UIKit
import PinLayout

/// A pill-shaped indicator shown while AI is generating a response
class AIGeneratingIndicatorView: UIView {
    
    // Callback when tapped
    var onTap: (() -> Void)?
    
    // Glass background
    private let glassView: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .systemUltraThinMaterial)
        let view = UIVisualEffectView(effect: blur)
        view.layer.cornerRadius = 30 // Half of 60px height for pill shape
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }()
    
    // Labels container
    private let labelsContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()
    
    // Main status label ("Explaining" / "Explained")
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Explaining"
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .left
        return label
    }()
    
    // Subtitle label ("Tap to view")
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Tap to view"
        label.font = .systemFont(ofSize: 10, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .left
        return label
    }()
    
    // Screenshot image view container (for activity indicator overlay)
    private let imageContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()
    
    // Screenshot image view
    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 8
        iv.layer.cornerCurve = .continuous
        iv.backgroundColor = .secondarySystemBackground
        return iv
    }()
    
    // Activity indicator over the image
    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = .white
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    // Semi-transparent overlay for the activity indicator
    private let activityOverlay: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        view.layer.cornerRadius = 8
        view.layer.cornerCurve = .continuous
        return view
    }()
    
    // Size constants
    private let pillWidth: CGFloat = 180
    private let pillHeight: CGFloat = 60
    private let padding: CGFloat = 10
    private let imageSize: CGFloat = 44
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        // Add subviews
        addSubview(glassView)
        glassView.contentView.addSubview(labelsContainer)
        labelsContainer.addSubview(statusLabel)
        labelsContainer.addSubview(subtitleLabel)
        glassView.contentView.addSubview(imageContainer)
        imageContainer.addSubview(imageView)
        imageContainer.addSubview(activityOverlay)
        imageContainer.addSubview(activityIndicator)
        
        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)
        
        // Initial state
        alpha = 0
    }
    
    @objc private func handleTap() {
        onTap?()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Size self
        pin.size(CGSize(width: pillWidth, height: pillHeight))
        
        // Glass view fills self
        glassView.pin.all()
        
        // Image container on the right
        imageContainer.pin
            .right(padding)
            .vCenter()
            .size(imageSize)
        
        // Image view fills container
        imageView.pin.all()
        
        // Activity overlay fills image
        activityOverlay.pin.all()
        
        // Activity indicator centered in image
        activityIndicator.pin.center()
        
        // Labels container to the left of the image
        labelsContainer.pin
            .left(padding + 8)
            .before(of: imageContainer)
            .marginRight(padding)
            .vCenter()
            .height(36)
        
        // Status label at top of labels container
        statusLabel.pin
            .top()
            .left()
            .right()
            .sizeToFit(.width)
        
        // Subtitle label below status label
        subtitleLabel.pin
            .below(of: statusLabel)
            .marginTop(2)
            .left()
            .right()
            .sizeToFit(.width)
    }
    
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        return CGSize(width: pillWidth, height: pillHeight)
    }
    
    override var intrinsicContentSize: CGSize {
        return sizeThatFits(.zero)
    }
    
    /// Configure with a screenshot and start animating
    func show(with screenshot: UIImage?, animated: Bool = true) {
        imageView.image = screenshot
        activityIndicator.startAnimating()
        activityOverlay.alpha = 1
        statusLabel.text = "Explaining"
        
        // Force layout to get correct size
        setNeedsLayout()
        layoutIfNeeded()
        
        if animated {
            // Animate in with scale and fade
            transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
                self.alpha = 1
                self.transform = .identity
            }
        } else {
            alpha = 1
            transform = .identity
        }
    }
    
    /// Show completion state
    func showComplete() {
        activityIndicator.stopAnimating()
        
        UIView.animate(withDuration: 0.25) {
            self.activityOverlay.alpha = 0
        }
        
        statusLabel.text = "Explained"
    }
    
    /// Hide and remove the indicator
    func hide(animated: Bool = true, completion: (() -> Void)? = nil) {
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn) {
                self.alpha = 0
                self.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            } completion: { _ in
                self.activityIndicator.stopAnimating()
                self.removeFromSuperview()
                completion?()
            }
        } else {
            activityIndicator.stopAnimating()
            removeFromSuperview()
            completion?()
        }
    }
}
