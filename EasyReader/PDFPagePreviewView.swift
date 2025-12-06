//
//  PDFPagePreviewView.swift
//  EasyReader
//
//  Created by Sammy Yousif on 11/11/25.
//

import UIKit
import PDFKit

protocol PDFPagePreviewDelegate: AnyObject {
    func didSelectPage(at index: Int)
}

class PDFPagePreviewView: UIView {
    
    weak var delegate: PDFPagePreviewDelegate?
    
    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 16, left: 8, bottom: 16, right: 8)
        
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsVerticalScrollIndicator = true
        cv.delegate = self
        cv.dataSource = self
        cv.register(PageThumbnailCell.self, forCellWithReuseIdentifier: PageThumbnailCell.reuseIdentifier)
        return cv
    }()
    
    private let containerView: UIVisualEffectView = {
        let blurEffect = UIBlurEffect(style: .systemMaterial)
        let view = UIVisualEffectView(effect: blurEffect)
        return view
    }()
    
    private var pdfDocument: PDFDocument?
    private var currentPageIndex: Int = 0
    
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
        containerView.contentView.addSubview(collectionView)
        
        // Add subtle shadow for depth (right side for vertical sidebar)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.15
        layer.shadowOffset = CGSize(width: 2, height: 0)
        layer.shadowRadius = 8
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        containerView.frame = bounds
        collectionView.frame = containerView.contentView.bounds
    }
    
    func configure(with document: PDFDocument?, currentPage: Int = 0) {
        self.pdfDocument = document
        self.currentPageIndex = currentPage
        collectionView.reloadData()
        
        // Scroll to current page
        if currentPage >= 0, let document = document, currentPage < document.pageCount {
            DispatchQueue.main.async {
                self.collectionView.scrollToItem(
                    at: IndexPath(item: currentPage, section: 0),
                    at: .centeredVertically,
                    animated: false
                )
            }
        }
    }
    
    func updateCurrentPage(_ pageIndex: Int, animated: Bool = true) {
        guard pageIndex != currentPageIndex else { return }
        
        let previousIndex = currentPageIndex
        currentPageIndex = pageIndex
        
        // Reload both old and new cells to update selection state
        collectionView.reloadItems(at: [
            IndexPath(item: previousIndex, section: 0),
            IndexPath(item: pageIndex, section: 0)
        ])
        
        // Scroll to show current page
        collectionView.scrollToItem(
            at: IndexPath(item: pageIndex, section: 0),
            at: .centeredVertically,
            animated: animated
        )
    }
}

// MARK: - UICollectionViewDataSource

extension PDFPagePreviewView: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return pdfDocument?.pageCount ?? 0
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: PageThumbnailCell.reuseIdentifier,
            for: indexPath
        ) as! PageThumbnailCell
        
        if let page = pdfDocument?.page(at: indexPath.item) {
            let isSelected = indexPath.item == currentPageIndex
            cell.configure(with: page, pageNumber: indexPath.item + 1, isSelected: isSelected)
        }
        
        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension PDFPagePreviewView: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        delegate?.didSelectPage(at: indexPath.item)
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension PDFPagePreviewView: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width - 16 // Account for padding
        let height = width * 1.4 // Maintain aspect ratio for vertical layout
        return CGSize(width: width, height: height)
    }
}

// MARK: - PageThumbnailCell

class PageThumbnailCell: UICollectionViewCell {
    static let reuseIdentifier = "PageThumbnailCell"
    
    private let thumbnailImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .white
        imageView.layer.cornerRadius = 8
        imageView.layer.cornerCurve = .continuous
        imageView.clipsToBounds = true
        imageView.layer.borderWidth = 2
        imageView.layer.borderColor = UIColor.clear.cgColor
        return imageView
    }()
    
    private let pageNumberLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()
    
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        contentView.addSubview(thumbnailImageView)
        contentView.addSubview(pageNumberLabel)
        contentView.addSubview(loadingIndicator)
        
        // Add shadow to the cell
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 4
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let labelHeight: CGFloat = 18
        pageNumberLabel.frame = CGRect(
            x: 0,
            y: bounds.height - labelHeight,
            width: bounds.width,
            height: labelHeight
        )
        
        thumbnailImageView.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: bounds.height - labelHeight - 4
        )
        
        loadingIndicator.center = CGPoint(
            x: thumbnailImageView.bounds.midX,
            y: thumbnailImageView.bounds.midY
        )
    }
    
    func configure(with page: PDFPage, pageNumber: Int, isSelected: Bool) {
        pageNumberLabel.text = "\(pageNumber)"
        
        // Update selection state
        if isSelected {
            thumbnailImageView.layer.borderColor = UIColor.systemBlue.cgColor
            pageNumberLabel.textColor = .systemBlue
            pageNumberLabel.font = .systemFont(ofSize: 11, weight: .bold)
        } else {
            thumbnailImageView.layer.borderColor = UIColor.systemGray5.cgColor
            pageNumberLabel.textColor = .secondaryLabel
            pageNumberLabel.font = .systemFont(ofSize: 11, weight: .medium)
        }
        
        // Generate thumbnail
        loadingIndicator.startAnimating()
        thumbnailImageView.image = nil
        
        Task { @MainActor in
            let thumbnail = await generateThumbnail(for: page)
            self.thumbnailImageView.image = thumbnail
            self.loadingIndicator.stopAnimating()
        }
    }
    
    private func generateThumbnail(for page: PDFPage) async -> UIImage {
        return await Task.detached(priority: .userInitiated) {
            let thumbnailSize = CGSize(width: 120, height: 170)
            let pageRect = page.bounds(for: .mediaBox)
            
            let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
            let thumbnail = renderer.image { context in
                // Fill with white background
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: thumbnailSize))
                
                // Calculate scale to fit
                let scaleX = thumbnailSize.width / pageRect.width
                let scaleY = thumbnailSize.height / pageRect.height
                let scale = min(scaleX, scaleY)
                
                let scaledSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
                let drawRect = CGRect(
                    x: (thumbnailSize.width - scaledSize.width) / 2,
                    y: (thumbnailSize.height - scaledSize.height) / 2,
                    width: scaledSize.width,
                    height: scaledSize.height
                )
                
                context.cgContext.saveGState()
                context.cgContext.translateBy(x: drawRect.minX, y: drawRect.maxY)
                context.cgContext.scaleBy(x: scale, y: -scale)
                context.cgContext.translateBy(x: -pageRect.minX, y: -pageRect.minY)
                
                page.draw(with: .mediaBox, to: context.cgContext)
                
                context.cgContext.restoreGState()
            }
            
            return thumbnail
        }.value
    }
}
