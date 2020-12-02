import Foundation
import Postbox
import SwiftSignalKit

import SyncCore

private struct RecentHashtagItemId {
    public let rawValue: MemoryBuffer
    
    var value: String {
        return String(data: self.rawValue.makeData(), encoding: .utf8) ?? ""
    }
    
    init(_ rawValue: MemoryBuffer) {
        self.rawValue = rawValue
    }
    
    init?(_ value: String) {
        if let data = value.data(using: .utf8) {
            self.rawValue = MemoryBuffer(data: data)
        } else {
            return nil
        }
    }
}

func addRecentlyUsedHashtag(transaction: Transaction, string: String) {
    if let itemId = RecentHashtagItemId(string) {
        transaction.addOrMoveToFirstPositionOrderedItemListItem(collectionId: Namespaces.OrderedItemList.RecentlyUsedHashtags, item: OrderedItemListEntry(id: itemId.rawValue, contents: RecentHashtagItem()), removeTailIfCountExceeds: 100)
    }
}

public func removeRecentlyUsedHashtag(postbox: Postbox, string: String) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Void in
        if let itemId = RecentHashtagItemId(string) {
            transaction.removeOrderedItemListItem(collectionId: Namespaces.OrderedItemList.RecentlyUsedHashtags, itemId: itemId.rawValue)
        }
    }
}

public func recentlyUsedHashtags(postbox: Postbox) -> Signal<[String], NoError> {
    return postbox.combinedView(keys: [.orderedItemList(id: Namespaces.OrderedItemList.RecentlyUsedHashtags)])
        |> mapToSignal { view -> Signal<[String], NoError> in
            return postbox.transaction { transaction -> [String] in
                var result: [String] = []
                if let view = view.views[.orderedItemList(id: Namespaces.OrderedItemList.RecentlyUsedHashtags)] as? OrderedItemListView {
                    for item in view.items {
                        let value = RecentHashtagItemId(item.id).value
                        result.append(value)
                    }
                }
                return result
            }
    }
}

