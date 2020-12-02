import Foundation
import Postbox
import SwiftSignalKit

import SyncCore

private let cachedSentMediaCollectionSpec = ItemCacheCollectionSpec(lowWaterItemCount: 10000, highWaterItemCount: 20000)

enum CachedSentMediaReferenceKey {
    case image(hash: Data)
    case file(hash: Data)
    
    var key: ValueBoxKey {
        switch self {
            case let .image(hash):
                let result = ValueBoxKey(length: 1 + hash.count)
                result.setUInt8(0, value: 0)
                hash.withUnsafeBytes { (bytes: UnsafePointer<Int8>) -> Void in
                    memcpy(result.memory.advanced(by: 1), bytes, hash.count)
                }
                return result
            case let .file(hash):
                let result = ValueBoxKey(length: 1 + hash.count)
                result.setUInt8(0, value: 1)
                hash.withUnsafeBytes { (bytes: UnsafePointer<Int8>) -> Void in
                    memcpy(result.memory.advanced(by: 1), bytes, hash.count)
                }
                return result
        }
    }
}

func cachedSentMediaReference(postbox: Postbox, key: CachedSentMediaReferenceKey) -> Signal<Media?, NoError> {
    return postbox.transaction { transaction -> Media? in
        return transaction.retrieveItemCacheEntry(id: ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.cachedSentMediaReferences, key: key.key)) as? Media
    }
}

func storeCachedSentMediaReference(transaction: Transaction, key: CachedSentMediaReferenceKey, media: Media) {
    transaction.putItemCacheEntry(id: ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.cachedSentMediaReferences, key: key.key), entry: media, collectionSpec: cachedSentMediaCollectionSpec)
}
