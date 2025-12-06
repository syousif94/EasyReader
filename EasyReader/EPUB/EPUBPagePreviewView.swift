//
//  EPUBPagePreviewView.swift
//  EasyReader
//
//  Created by Sammy Yousif on 12/2/25.
//

import UIKit
import PinLayout

protocol EPUBPagePreviewDelegate: AnyObject {
    func didSelectPage(at index: Int)
}

class EPUBPagePreviewView: UIView {
    
    weak var delegate: EPUBPagePreviewDelegate?
    
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
        cv.register(EPUBPageThumbnailCell.self, forCellWithReuseIdentifier: EPUBPageThumbnailCell.reuseIdentifier)
        return cv
    }()
    
    private let containerView: UIVisualEffectView = {
        let blurEffect = UIBlurEffect(style: .systemMaterial)
        let view = UIVisualEffectView(effect: blurEffect)
        return view
    }()
    
    private var pageCount: Int = 0
    private var currentPageIndex: Int = 0
    private var chapterTitles: [String] = []
    
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
        
        // Add subtle shadow for depth
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
    
    func configure(pageCount: Int, currentPage: Int = 0, chapterTitles: [String] = []) {
        self.pageCount = pageCount
        self.currentPageIndex = currentPage
        self.chapterTitles = chapterTitles
        collectionView.reloadData()
        
        // Scroll to current page
        if currentPage >= 0 && currentPage < pageCount {
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
        guard pageIndex != currentPageIndex, pageIndex >= 0, pageIndex < pageCount else { return }
        
        let previousIndex = currentPageIndex
        currentPageIndex = pageIndex
        
        // Reload both old and new cells to update selection state
        var indexPathsToReload = [IndexPath(item: pageIndex, section: 0)]
        if previousIndex >= 0 && previousIndex < pageCount {
            indexPathsToReload.append(IndexPath(item: previousIndex, section: 0))
        }
        collectionView.reloadItems(at: indexPathsToReload)
        
        // Scroll to show current page
        collectionView.scrollToItem(
            at: IndexPath(item: pageIndex, section: 0),
            at: .centeredVertically,
            animated: animated
        )
    }
}

// MARK: - UICollectionViewDataSource

extension EPUBPagePreviewView: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return pageCount
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EPUBPageThumbnailCell.reuseIdentifier, for: indexPath) as! EPUBPageThumbnailCell
        
        let isSelected = indexPath.item == currentPageIndex
        cell.configure(pageNumber: indexPath.item + 1, isCurrentPage: isSelected)
        
        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension EPUBPagePreviewView: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        delegate?.didSelectPage(at: indexPath.item)
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension EPUBPagePreviewView: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width - 16 // Subtract section insets
        let height: CGFloat = 50
        return CGSize(width: width, height: height)
    }
}

// MARK: - EPUBPageThumbnailCell

class EPUBPageThumbnailCell: UICollectionViewCell {
    
    static let reuseIdentifier = "EPUBPageThumbnailCell"
    
    private let pageLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .label
        label.textAlignment = .center
        return label
    }()
    
    private let selectionIndicator: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBlue
        view.layer.cornerRadius = 2
        view.isHidden = true
        return view
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true
        
        contentView.addSubview(pageLabel)
        contentView.addSubview(selectionIndicator)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        selectionIndicator.pin
            .left(4)
            .vCenter()
            .width(4)
            .height(contentView.bounds.height - 16)
        
        pageLabel.pin
            .left(to: selectionIndicator.edge.right).marginLeft(8)
            .right(8)
            .vCenter()
            .sizeToFit(.width)
    }
    
    func configure(pageNumber: Int, isCurrentPage: Bool) {
        pageLabel.text = "Page \(pageNumber)"
        pageLabel.textColor = isCurrentPage ? .systemBlue : .label
        pageLabel.font = isCurrentPage ? .systemFont(ofSize: 14, weight: .semibold) : .systemFont(ofSize: 14, weight: .regular)
        
        selectionIndicator.isHidden = !isCurrentPage
        contentView.backgroundColor = isCurrentPage ? .systemBlue.withAlphaComponent(0.1) : .secondarySystemBackground
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        pageLabel.text = nil
        selectionIndicator.isHidden = true
        contentView.backgroundColor = .secondarySystemBackground
    }
}
