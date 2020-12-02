import Postbox
import MtProtoKit
import SwiftSignalKit
import TelegramApi

import SyncCore

public func secureIdConfiguration(postbox: Postbox, network: Network) -> Signal<SecureIdConfiguration, NoError> {
    let cached: Signal<CachedSecureIdConfiguration?, NoError> = postbox.transaction { transaction -> CachedSecureIdConfiguration? in
        if let entry = transaction.retrieveItemCacheEntry(id: ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.cachedSecureIdConfiguration, key: ValueBoxKey(length: 0))) as? CachedSecureIdConfiguration {
            return entry
        } else {
            return nil
        }
    }
    return cached
    |> mapToSignal { cached -> Signal<SecureIdConfiguration, NoError> in
        return network.request(Api.functions.help.getPassportConfig(hash: cached?.hash ?? 0))
        |> retryRequest
        |> mapToSignal { result -> Signal<SecureIdConfiguration, NoError> in
            let parsed: CachedSecureIdConfiguration
            switch result {
                case .passportConfigNotModified:
                    if let cached = cached {
                        return .single(cached.value)
                    } else {
                        assertionFailure()
                        return .complete()
                    }
                case let .passportConfig(hash, countriesLangs):
                    switch countriesLangs {
                        case let .dataJSON(data):
                            let value = SecureIdConfiguration(jsonString: data)
                            parsed = CachedSecureIdConfiguration(value: value, hash: hash)
                    }
            }
            return postbox.transaction { transaction -> SecureIdConfiguration in
                transaction.putItemCacheEntry(id: ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.cachedSecureIdConfiguration, key: ValueBoxKey(length: 0)), entry: parsed, collectionSpec: ItemCacheCollectionSpec(lowWaterItemCount: 1, highWaterItemCount: 1))
                return parsed.value
            }
        }
    }
}
