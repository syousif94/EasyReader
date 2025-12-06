//
//  ReadableDocController.swift
//  EasyReader
//
//  Created by Sammy Yousif on 11/10/25.
//

import UIKit
import CoreData

class ReadableDocController<Cell: UICollectionViewCell, Item: Hashable>: NSObject {
    
    typealias CellRegistration = UICollectionView.CellRegistration<Cell, Item>
    typealias CellRegistrationHandler = CellRegistration.Handler
    
    enum Section: Int, CaseIterable {
        case main
    }
    
    weak var collectionView: UICollectionView?
    
    let dataSource: UICollectionViewDiffableDataSource<Section, Item>
    
    init(for collectionView: UICollectionView, in context: NSManagedObjectContext, handler: @escaping CellRegistrationHandler) {
        
        self.collectionView = collectionView
        
        let cellRegistration = CellRegistration(handler: handler)
        
        let diffableDataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { (collectionView, indexPath, item) -> UICollectionViewCell? in

            let cell = collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
            
            return cell
        }
        self.dataSource = diffableDataSource
    }
    
    func update(with items: [Item]) {
        guard let dataSource = collectionView?.dataSource as? UICollectionViewDiffableDataSource<Section, Item> else {
            assertionFailure("The data source has not implemented snapshot support while it should")
            return
        }
        
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections(Section.allCases)
        snapshot.appendItems(items, toSection: .main)
        
        let shouldAnimate = collectionView?.numberOfSections != 0
        dataSource.apply(snapshot, animatingDifferences: shouldAnimate)
    }
}
