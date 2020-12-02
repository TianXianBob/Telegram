import Foundation
import TelegramApi
import Postbox
import SwiftSignalKit

import SyncCore

func applyMediaResourceChanges(from: Media, to: Media, postbox: Postbox) {
    if let fromImage = from as? TelegramMediaImage, let toImage = to as? TelegramMediaImage {
        let fromSmallestRepresentation = smallestImageRepresentation(fromImage.representations)
        if let fromSmallestRepresentation = fromSmallestRepresentation, let toSmallestRepresentation = smallestImageRepresentation(toImage.representations) {
            let leeway: Int32 = 4
            let widthDifference = fromSmallestRepresentation.dimensions.width - toSmallestRepresentation.dimensions.width
            let heightDifference = fromSmallestRepresentation.dimensions.height - toSmallestRepresentation.dimensions.height
            if abs(widthDifference) < leeway && abs(heightDifference) < leeway {
                postbox.mediaBox.moveResourceData(from: fromSmallestRepresentation.resource.id, to: toSmallestRepresentation.resource.id)
            }
        }
        if let fromLargestRepresentation = largestImageRepresentation(fromImage.representations), let toLargestRepresentation = largestImageRepresentation(toImage.representations) {
            postbox.mediaBox.moveResourceData(from: fromLargestRepresentation.resource.id, to: toLargestRepresentation.resource.id)
        }
    } else if let fromFile = from as? TelegramMediaFile, let toFile = to as? TelegramMediaFile {
        if let fromPreview = smallestImageRepresentation(fromFile.previewRepresentations), let toPreview = smallestImageRepresentation(toFile.previewRepresentations) {
            postbox.mediaBox.moveResourceData(from: fromPreview.resource.id, to: toPreview.resource.id)
        }
        if (fromFile.size == toFile.size || fromFile.resource.size == toFile.resource.size) && fromFile.mimeType == toFile.mimeType {
            postbox.mediaBox.moveResourceData(from: fromFile.resource.id, to: toFile.resource.id)
        }
    }
}

func applyUpdateMessage(postbox: Postbox, stateManager: AccountStateManager, message: Message, result: Api.Updates) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Void in
        let messageId: Int32?
        var apiMessage: Api.Message?
        
        for resultMessage in result.messages {
            if let id = resultMessage.id() {
                if id.peerId == message.id.peerId {
                    apiMessage = resultMessage
                    break
                }
            }
        }
        
        if let apiMessage = apiMessage, let id = apiMessage.id() {
            messageId = id.id
        } else {
            messageId = result.rawMessageIds.first
        }
        
        var updatedTimestamp: Int32?
        if let apiMessage = apiMessage {
            switch apiMessage {
                case let .message(message):
                    updatedTimestamp = message.date
                case .messageEmpty:
                    break
                case let .messageService(messageService):
                    updatedTimestamp = messageService.date
            }
        } else {
            switch result {
                case let .updateShortSentMessage(_, _, _, _, date, _, _):
                    updatedTimestamp = date
                default:
                    break
            }
        }
        
        let channelPts = result.channelPts
        
        var sentStickers: [TelegramMediaFile] = []
        var sentGifs: [TelegramMediaFile] = []
        
        if let updatedTimestamp = updatedTimestamp {
            transaction.offsetPendingMessagesTimestamps(lowerBound: message.id, excludeIds: Set([message.id]), timestamp: updatedTimestamp)
        }
        
        transaction.updateMessage(message.id, update: { currentMessage in
            let updatedId: MessageId
            if let messageId = messageId {
                var namespace: MessageId.Namespace = Namespaces.Message.Cloud
                if let updatedTimestamp = updatedTimestamp {
                    if message.scheduleTime != nil && message.scheduleTime == updatedTimestamp {
                        namespace = Namespaces.Message.ScheduledCloud
                    }
                } else if Namespaces.Message.allScheduled.contains(message.id.namespace) {
                    namespace = Namespaces.Message.ScheduledCloud
                }
                updatedId = MessageId(peerId: currentMessage.id.peerId, namespace: namespace, id: messageId)
            } else {
                updatedId = currentMessage.id
            }
            
            let media: [Media]
            var attributes: [MessageAttribute]
            let text: String
            let forwardInfo: StoreMessageForwardInfo?
            if let apiMessage = apiMessage, let updatedMessage = StoreMessage(apiMessage: apiMessage) {
                media = updatedMessage.media
                attributes = updatedMessage.attributes
                text = updatedMessage.text
                forwardInfo = updatedMessage.forwardInfo
            } else if case let .updateShortSentMessage(_, _, _, _, _, apiMedia, entities) = result {
                let (mediaValue, _) = textMediaAndExpirationTimerFromApiMedia(apiMedia, currentMessage.id.peerId)
                if let mediaValue = mediaValue {
                    media = [mediaValue]
                } else {
                    media = []
                }
                
                var updatedAttributes: [MessageAttribute] = currentMessage.attributes
                if let entities = entities, !entities.isEmpty {
                    for i in 0 ..< updatedAttributes.count {
                        if updatedAttributes[i] is TextEntitiesMessageAttribute {
                            updatedAttributes.remove(at: i)
                            break
                        }
                    }
                    updatedAttributes.append(TextEntitiesMessageAttribute(entities: messageTextEntitiesFromApiEntities(entities)))
                }
                
                if Namespaces.Message.allScheduled.contains(message.id.namespace) && updatedId.namespace == Namespaces.Message.Cloud {
                    for i in 0 ..< updatedAttributes.count {
                        if updatedAttributes[i] is OutgoingScheduleInfoMessageAttribute {
                            updatedAttributes.remove(at: i)
                            break
                        }
                    }
                }
                
                attributes = updatedAttributes
                text = currentMessage.text
                
                forwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
            } else {
                media = currentMessage.media
                attributes = currentMessage.attributes
                text = currentMessage.text
                forwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
            }
            
            if let channelPts = channelPts {
                for i in 0 ..< attributes.count {
                    if let _ = attributes[i] as? ChannelMessageStateVersionAttribute {
                        attributes.remove(at: i)
                        break
                    }
                }
                attributes.append(ChannelMessageStateVersionAttribute(pts: channelPts))
            }
            
            if let fromMedia = currentMessage.media.first, let toMedia = media.first {
                applyMediaResourceChanges(from: fromMedia, to: toMedia, postbox: postbox)
            }
            
            if forwardInfo == nil {
                inner: for media in media {
                    if let file = media as? TelegramMediaFile {
                        for attribute in file.attributes {
                            switch attribute {
                            case let .Sticker(_, packReference, _):
                                if packReference != nil {
                                    sentStickers.append(file)
                                }
                            case .Animated:
                                sentGifs.append(file)
                            default:
                                break
                            }
                        }
                        break inner
                    }
                }
            }
            
            var entitiesAttribute: TextEntitiesMessageAttribute?
            for attribute in attributes {
                if let attribute = attribute as? TextEntitiesMessageAttribute {
                    entitiesAttribute = attribute
                    break
                }
            }
            
            let (tags, globalTags) = tagsForStoreMessage(incoming: currentMessage.flags.contains(.Incoming), attributes: attributes, media: media, textEntities: entitiesAttribute?.entities)
            
            if currentMessage.id.peerId.namespace == Namespaces.Peer.CloudChannel, !currentMessage.flags.contains(.Incoming), !Namespaces.Message.allScheduled.contains(currentMessage.id.namespace) {
                let peerId = currentMessage.id.peerId
                if let peer = transaction.getPeer(peerId) {
                    if let peer = peer as? TelegramChannel {
                        inner: switch peer.info {
                        case let .group(info):
                            if info.flags.contains(.slowModeEnabled), peer.adminRights == nil && !peer.flags.contains(.isCreator) {
                                transaction.updatePeerCachedData(peerIds: [peerId], update: { peerId, current in
                                    var cachedData = current as? CachedChannelData ?? CachedChannelData()
                                    if let slowModeTimeout = cachedData.slowModeTimeout {
                                        cachedData = cachedData.withUpdatedSlowModeValidUntilTimestamp(currentMessage.timestamp + slowModeTimeout)
                                        return cachedData
                                    } else {
                                        return current
                                    }
                                })
                            }
                        default:
                            break inner
                        }
                    }
                }
            }
            
            return .update(StoreMessage(id: updatedId, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, timestamp: updatedTimestamp ?? currentMessage.timestamp, flags: [], tags: tags, globalTags: globalTags, localTags: currentMessage.localTags, forwardInfo: forwardInfo, authorId: currentMessage.author?.id, text: text, attributes: attributes, media: media))
        })
        for file in sentStickers {
            transaction.addOrMoveToFirstPositionOrderedItemListItem(collectionId: Namespaces.OrderedItemList.CloudRecentStickers, item: OrderedItemListEntry(id: RecentMediaItemId(file.fileId).rawValue, contents: RecentMediaItem(file)), removeTailIfCountExceeds: 20)
        }
        for file in sentGifs {
            transaction.addOrMoveToFirstPositionOrderedItemListItem(collectionId: Namespaces.OrderedItemList.CloudRecentGifs, item: OrderedItemListEntry(id: RecentMediaItemId(file.fileId).rawValue, contents: RecentMediaItem(file)), removeTailIfCountExceeds: 200)
        }
        
        stateManager.addUpdates(result)
    }
}

func applyUpdateGroupMessages(postbox: Postbox, stateManager: AccountStateManager, messages: [Message], result: Api.Updates) -> Signal<Void, NoError> {
    guard !messages.isEmpty else {
        return .complete()
    }
    
    return postbox.transaction { transaction -> Void in
        let updatedRawMessageIds = result.updatedRawMessageIds
        
        var namespace = Namespaces.Message.Cloud
        if let message = messages.first, let apiMessage = result.messages.first, message.scheduleTime != nil && message.scheduleTime == apiMessage.timestamp {
            namespace = Namespaces.Message.ScheduledCloud
        }
        
        var resultMessages: [MessageId: StoreMessage] = [:]
        for apiMessage in result.messages {
            if let resultMessage = StoreMessage(apiMessage: apiMessage, namespace: namespace), case let .Id(id) = resultMessage.id {
                resultMessages[id] = resultMessage
            }
        }

        var mapping: [(Message, MessageIndex, StoreMessage)] = []
        
        for message in messages {
            var uniqueId: Int64?
            inner: for attribute in message.attributes {
                if let outgoingInfo = attribute as? OutgoingMessageInfoAttribute {
                    uniqueId = outgoingInfo.uniqueId
                    break inner
                }
            }
            if let uniqueId = uniqueId {
                if let updatedId = updatedRawMessageIds[uniqueId] {
                    if let storeMessage = resultMessages[MessageId(peerId: message.id.peerId, namespace: namespace, id: updatedId)], case let .Id(id) = storeMessage.id {
                        mapping.append((message, MessageIndex(id: id, timestamp: storeMessage.timestamp), storeMessage))
                    }
                } else {
                    assertionFailure()
                }
            } else {
                assertionFailure()
            }
        }
        
        mapping.sort { $0.1 < $1.1 }
        
        let latestPreviousId = mapping.map({ $0.0.id }).max()
        
        var sentStickers: [TelegramMediaFile] = []
        var sentGifs: [TelegramMediaFile] = []
        
        var updatedGroupingKey: Int64?
        for (_, _, updatedMessage) in mapping {
            if let updatedGroupingKey = updatedGroupingKey {
                assert(updatedGroupingKey == updatedMessage.groupingKey)
            }
            updatedGroupingKey = updatedMessage.groupingKey
        }
        
        if let latestPreviousId = latestPreviousId, let latestIndex = mapping.last?.1 {
            transaction.offsetPendingMessagesTimestamps(lowerBound: latestPreviousId, excludeIds: Set(mapping.map { $0.0.id }), timestamp: latestIndex.timestamp)
        }
        
        if let updatedGroupingKey = updatedGroupingKey {
            transaction.updateMessageGroupingKeysAtomically(mapping.map { $0.0.id }, groupingKey: updatedGroupingKey)
        }
        
        for (message, _, updatedMessage) in mapping {
            transaction.updateMessage(message.id, update: { currentMessage in
                let updatedId: MessageId
                if case let .Id(id) = updatedMessage.id {
                    updatedId = id
                } else {
                    updatedId = currentMessage.id
                }
                
                let media: [Media]
                let attributes: [MessageAttribute]
                let text: String
 
                media = updatedMessage.media
                attributes = updatedMessage.attributes
                text = updatedMessage.text
                
                var storeForwardInfo: StoreMessageForwardInfo?
                if let forwardInfo = currentMessage.forwardInfo {
                    storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature)
                }
                
                if let fromMedia = currentMessage.media.first, let toMedia = media.first {
                    applyMediaResourceChanges(from: fromMedia, to: toMedia, postbox: postbox)
                }
                
                if storeForwardInfo == nil {
                    inner: for media in message.media {
                        if let file = media as? TelegramMediaFile {
                            for attribute in file.attributes {
                                switch attribute {
                                case let .Sticker(_, packReference, _):
                                    if packReference != nil {
                                        sentStickers.append(file)
                                    }
                                case .Animated:
                                    sentGifs.append(file)
                                default:
                                    break
                                }
                            }
                            break inner
                        }
                    }
                }
                
                var entitiesAttribute: TextEntitiesMessageAttribute?
                for attribute in attributes {
                    if let attribute = attribute as? TextEntitiesMessageAttribute {
                        entitiesAttribute = attribute
                        break
                    }
                }
                
                let (tags, globalTags) = tagsForStoreMessage(incoming: currentMessage.flags.contains(.Incoming), attributes: attributes, media: media, textEntities: entitiesAttribute?.entities)
                
                return .update(StoreMessage(id: updatedId, globallyUniqueId: nil, groupingKey: currentMessage.groupingKey, timestamp: updatedMessage.timestamp, flags: [], tags: tags, globalTags: globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: text, attributes: attributes, media: media))
            })
        }
        
        for file in sentStickers {
            transaction.addOrMoveToFirstPositionOrderedItemListItem(collectionId: Namespaces.OrderedItemList.CloudRecentStickers, item: OrderedItemListEntry(id: RecentMediaItemId(file.fileId).rawValue, contents: RecentMediaItem(file)), removeTailIfCountExceeds: 20)
        }
        for file in sentGifs {
            transaction.addOrMoveToFirstPositionOrderedItemListItem(collectionId: Namespaces.OrderedItemList.CloudRecentGifs, item: OrderedItemListEntry(id: RecentMediaItemId(file.fileId).rawValue, contents: RecentMediaItem(file)), removeTailIfCountExceeds: 200)
        }
        stateManager.addUpdates(result)
    }
}
