import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit

import SyncCore

private func messageFilterForTagMask(_ tagMask: MessageTags) -> Api.MessagesFilter? {
    if tagMask == .photoOrVideo {
        return Api.MessagesFilter.inputMessagesFilterPhotoVideo
    } else if tagMask == .file {
        return Api.MessagesFilter.inputMessagesFilterDocument
    } else if tagMask == .music {
        return Api.MessagesFilter.inputMessagesFilterMusic
    } else if tagMask == .webPage {
        return Api.MessagesFilter.inputMessagesFilterUrl
    } else if tagMask == .voiceOrInstantVideo {
        return Api.MessagesFilter.inputMessagesFilterRoundVoice
    } else {
        return nil
    }
}

enum FetchMessageHistoryHoleSource {
    case network(Network)
    case download(Download)
    
    func request<T>(_ data: (FunctionDescription, Buffer, DeserializeFunctionResponse<T>)) -> Signal<T, MTRpcError> {
        switch self {
            case let .network(network):
                return network.request(data)
            case let .download(download):
                return download.request(data)
        }
    }
}

func withResolvedAssociatedMessages(postbox: Postbox, source: FetchMessageHistoryHoleSource, peers: [PeerId: Peer], storeMessages: [StoreMessage], _ f: @escaping (Transaction, [Peer], [StoreMessage]) -> Void) -> Signal<Never, NoError> {
    return postbox.transaction { transaction -> Signal<Never, NoError> in
        var storedIds = Set<MessageId>()
        var referencedIds = Set<MessageId>()
        for message in storeMessages {
            guard case let .Id(id) = message.id else {
                continue
            }
            storedIds.insert(id)
            for attribute in message.attributes {
                referencedIds.formUnion(attribute.associatedMessageIds)
            }
        }
        referencedIds.subtract(storedIds)
        referencedIds.subtract(transaction.filterStoredMessageIds(referencedIds))
        
        if referencedIds.isEmpty {
            f(transaction, [], [])
            return .complete()
        } else {
            var signals: [Signal<([Api.Message], [Api.Chat], [Api.User]), NoError>] = []
            for (peerId, messageIds) in messagesIdsGroupedByPeerId(referencedIds) {
                if let peer = transaction.getPeer(peerId) ?? peers[peerId] {
                    var signal: Signal<Api.messages.Messages, MTRpcError>?
                    if peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.CloudGroup {
                        signal = source.request(Api.functions.messages.getMessages(id: messageIds.map({ Api.InputMessage.inputMessageID(id: $0.id) })))
                    } else if peerId.namespace == Namespaces.Peer.CloudChannel {
                        if let inputChannel = apiInputChannel(peer) {
                            signal = source.request(Api.functions.channels.getMessages(channel: inputChannel, id: messageIds.map({ Api.InputMessage.inputMessageID(id: $0.id) })))
                        }
                    }
                    if let signal = signal {
                        signals.append(signal
                        |> map { result in
                            switch result {
                                case let .messages(messages, chats, users):
                                    return (messages, chats, users)
                                case let .messagesSlice(_, _, _, messages, chats, users):
                                    return (messages, chats, users)
                                case let .channelMessages(_, _, _, messages, chats, users):
                                    return (messages, chats, users)
                                case .messagesNotModified:
                                    return ([], [], [])
                            }
                        }
                        |> `catch` { _ in
                            return Signal<([Api.Message], [Api.Chat], [Api.User]), NoError>.single(([], [], []))
                        })
                    }
                }
            }
            
            let fetchMessages = combineLatest(signals)
            
            return fetchMessages
            |> mapToSignal { results -> Signal<Never, NoError> in
                var additionalPeers: [Peer] = []
                var additionalMessages: [StoreMessage] = []
                for (messages, chats, users) in results {
                    if !messages.isEmpty {
                        for message in messages {
                            if let message = StoreMessage(apiMessage: message) {
                                additionalMessages.append(message)
                            }
                        }
                    }
                    for chat in chats {
                        if let peer = parseTelegramGroupOrChannel(chat: chat) {
                            additionalPeers.append(peer)
                        }
                    }
                    for user in users {
                        additionalPeers.append(TelegramUser(user: user))
                    }
                }
                return postbox.transaction { transaction -> Void in
                    f(transaction, additionalPeers, additionalMessages)
                }
                |> ignoreValues
            }
        }
    }
    |> switchToLatest
}

func fetchMessageHistoryHole(accountPeerId: PeerId, source: FetchMessageHistoryHoleSource, postbox: Postbox, peerId: PeerId, namespace: MessageId.Namespace, direction: MessageHistoryViewRelativeHoleDirection, space: MessageHistoryHoleSpace, count rawCount: Int) -> Signal<Never, NoError> {
    let count = min(100, rawCount)
    
    return postbox.stateView()
    |> mapToSignal { view -> Signal<AuthorizedAccountState, NoError> in
        if let state = view.state as? AuthorizedAccountState {
            return .single(state)
        } else {
            return .complete()
        }
    }
    |> take(1)
    |> mapToSignal { _ -> Signal<Never, NoError> in
        return postbox.loadedPeerWithId(peerId)
        |> take(1)
        |> mapToSignal { peer in
            if let inputPeer = forceApiInputPeer(peer) {
                print("fetchMessageHistoryHole for \(peer.id) \(peer.debugDisplayTitle) \(direction) space \(space)")
                Logger.shared.log("fetchMessageHistoryHole", "fetch for \(peer.id) \(peer.debugDisplayTitle) \(direction) space \(space)")
                let request: Signal<Api.messages.Messages, MTRpcError>
                var implicitelyFillHole = false
                let minMaxRange: ClosedRange<MessageId.Id>
                
                switch space {
                    case .everywhere:
                        let offsetId: Int32
                        let addOffset: Int32
                        let selectedLimit = count
                        let maxId: Int32
                        let minId: Int32
                        
                        switch direction {
                            case let .range(start, end):
                                if start.id <= end.id {
                                    offsetId = start.id <= 1 ? 1 : (start.id - 1)
                                    addOffset = Int32(-selectedLimit)
                                    maxId = end.id
                                    minId = start.id - 1
                                    
                                    let rangeStartId = start.id
                                    let rangeEndId = min(end.id, Int32.max - 1)
                                    if rangeStartId <= rangeEndId {
                                        minMaxRange = rangeStartId ... rangeEndId
                                    } else {
                                        minMaxRange = rangeStartId ... rangeStartId
                                        assertionFailure()
                                    }
                                } else {
                                    offsetId = start.id == Int32.max ? start.id : (start.id + 1)
                                    addOffset = 0
                                    maxId = start.id == Int32.max ? start.id : (start.id + 1)
                                    minId = end.id
                                    
                                    let rangeStartId = end.id
                                    let rangeEndId = min(start.id, Int32.max - 1)
                                    if rangeStartId <= rangeEndId {
                                        minMaxRange = rangeStartId ... rangeEndId
                                    } else {
                                        minMaxRange = rangeStartId ... rangeStartId
                                        assertionFailure()
                                    }
                                }
                            case let .aroundId(id):
                                offsetId = id.id
                                addOffset = Int32(-selectedLimit / 2)
                                maxId = Int32.max
                                minId = 1
                                minMaxRange = 1 ... Int32.max - 1
                        }
                        
                        request = source.request(Api.functions.messages.getHistory(peer: inputPeer, offsetId: offsetId, offsetDate: 0, addOffset: addOffset, limit: Int32(selectedLimit), maxId: maxId, minId: minId, hash: 0))
                    case let .tag(tag):
                        assert(tag.containsSingleElement)
                        if tag == .unseenPersonalMessage {
                            let offsetId: Int32
                            let addOffset: Int32
                            let selectedLimit = count
                            let maxId: Int32
                            let minId: Int32
                            
                            switch direction {
                                case let .range(start, end):
                                    if start.id <= end.id {
                                        offsetId = start.id <= 1 ? 1 : (start.id - 1)
                                        addOffset = Int32(-selectedLimit)
                                        maxId = end.id
                                        minId = start.id - 1
                                        
                                        let rangeStartId = start.id
                                        let rangeEndId = min(end.id, Int32.max - 1)
                                        if rangeStartId <= rangeEndId {
                                            minMaxRange = rangeStartId ... rangeEndId
                                        } else {
                                            minMaxRange = rangeStartId ... rangeStartId
                                            assertionFailure()
                                        }
                                    } else {
                                        offsetId = start.id == Int32.max ? start.id : (start.id + 1)
                                        addOffset = 0
                                        maxId = start.id == Int32.max ? start.id : (start.id + 1)
                                        minId = end.id
                                        
                                        let rangeStartId = end.id
                                        let rangeEndId = min(start.id, Int32.max - 1)
                                        if rangeStartId <= rangeEndId {
                                            minMaxRange = rangeStartId ... rangeEndId
                                        } else {
                                            minMaxRange = rangeStartId ... rangeStartId
                                            assertionFailure()
                                        }
                                    }
                                case let .aroundId(id):
                                    offsetId = id.id
                                    addOffset = Int32(-selectedLimit / 2)
                                    maxId = Int32.max
                                    minId = 1
                                
                                    minMaxRange = 1 ... Int32.max - 1
                            }
                            
                            request = source.request(Api.functions.messages.getUnreadMentions(peer: inputPeer, offsetId: offsetId, addOffset: addOffset, limit: Int32(selectedLimit), maxId: maxId, minId: minId))
                        } else if tag == .liveLocation {
                            let selectedLimit = count
                            
                            switch direction {
                                case .aroundId, .range:
                                    implicitelyFillHole = true
                            }
                            minMaxRange = 1 ... (Int32.max - 1)
                            request = source.request(Api.functions.messages.getRecentLocations(peer: inputPeer, limit: Int32(selectedLimit), hash: 0))
                        } else if let filter = messageFilterForTagMask(tag) {
                            let offsetId: Int32
                            let addOffset: Int32
                            let selectedLimit = count
                            let maxId: Int32
                            let minId: Int32
                            
                            switch direction {
                                case let .range(start, end):
                                    if start.id <= end.id {
                                        offsetId = start.id <= 1 ? 1 : (start.id - 1)
                                        addOffset = Int32(-selectedLimit)
                                        maxId = end.id
                                        minId = start.id - 1
                                        
                                        let rangeStartId = start.id
                                        let rangeEndId = min(end.id, Int32.max - 1)
                                        if rangeStartId <= rangeEndId {
                                            minMaxRange = rangeStartId ... rangeEndId
                                        } else {
                                            minMaxRange = rangeStartId ... rangeStartId
                                            assertionFailure()
                                        }
                                    } else {
                                        offsetId = start.id == Int32.max ? start.id : (start.id + 1)
                                        addOffset = 0
                                        maxId = start.id == Int32.max ? start.id : (start.id + 1)
                                        minId = end.id
                                        
                                        let rangeStartId = end.id
                                        let rangeEndId = min(start.id, Int32.max - 1)
                                        if rangeStartId <= rangeEndId {
                                            minMaxRange = rangeStartId ... rangeEndId
                                        } else {
                                            minMaxRange = rangeStartId ... rangeStartId
                                            assertionFailure()
                                        }
                                    }
                                case let .aroundId(id):
                                    offsetId = id.id
                                    addOffset = Int32(-selectedLimit / 2)
                                    maxId = Int32.max
                                    minId = 1
                                
                                    minMaxRange = 1 ... (Int32.max - 1)
                            }
                            
                            request = source.request(Api.functions.messages.search(flags: 0, peer: inputPeer, q: "", fromId: nil, filter: filter, minDate: 0, maxDate: 0, offsetId: offsetId, addOffset: addOffset, limit: Int32(selectedLimit), maxId: maxId, minId: minId, hash: 0))
                        } else {
                            assertionFailure()
                            minMaxRange = 1 ... 1
                            request = .never()
                    }
                }
                
                return request
                |> retryRequest
                |> mapToSignal { result -> Signal<Never, NoError> in
                    let messages: [Api.Message]
                    let chats: [Api.Chat]
                    let users: [Api.User]
                    var channelPts: Int32?
                    switch result {
                        case let .messages(messages: apiMessages, chats: apiChats, users: apiUsers):
                            messages = apiMessages
                            chats = apiChats
                            users = apiUsers
                        case let .messagesSlice(_, _, _, messages: apiMessages, chats: apiChats, users: apiUsers):
                            messages = apiMessages
                            chats = apiChats
                            users = apiUsers
                        case let .channelMessages(_, pts, _, apiMessages, apiChats, apiUsers):
                            messages = apiMessages
                            chats = apiChats
                            users = apiUsers
                            channelPts = pts
                        case .messagesNotModified:
                            messages = []
                            chats = []
                            users = []
                    }
                    
                    var peers: [Peer] = []
                    var peerPresences: [PeerId: PeerPresence] = [:]
                    for chat in chats {
                        if let groupOrChannel = parseTelegramGroupOrChannel(chat: chat) {
                            peers.append(groupOrChannel)
                        }
                    }
                    for user in users {
                        let telegramUser = TelegramUser(user: user)
                        peers.append(telegramUser)
                        if let presence = TelegramUserPresence(apiUser: user) {
                            peerPresences[telegramUser.id] = presence
                        }
                    }
                    
                    var storeMessages: [StoreMessage] = []
                    
                    for message in messages {
                        if let storeMessage = StoreMessage(apiMessage: message, namespace: namespace) {
                            if let channelPts = channelPts {
                                var attributes = storeMessage.attributes
                                attributes.append(ChannelMessageStateVersionAttribute(pts: channelPts))
                                storeMessages.append(storeMessage.withUpdatedAttributes(attributes))
                            } else {
                                storeMessages.append(storeMessage)
                            }
                        }
                    }
                    
                    return withResolvedAssociatedMessages(postbox: postbox, source: source, peers: Dictionary(peers.map({ ($0.id, $0) }), uniquingKeysWith: { lhs, _ in lhs }), storeMessages: storeMessages, { transaction, additionalPeers, additionalMessages in
                        let _ = transaction.addMessages(storeMessages, location: .Random)
                        let _ = transaction.addMessages(additionalMessages, location: .Random)
                        let filledRange: ClosedRange<MessageId.Id>
                        let ids = messages.compactMap({ $0.id()?.id })
                        if ids.count == 0 || implicitelyFillHole {
                            filledRange = minMaxRange
                        } else {
                            let messageRange = ids.min()! ... ids.max()!
                            switch direction {
                                case let .aroundId(aroundId):
                                    filledRange = min(aroundId.id, messageRange.lowerBound) ... max(aroundId.id, messageRange.upperBound)
                                case let .range(start, end):
                                    if start.id <= end.id {
                                        let minBound = start.id
                                        let maxBound = messageRange.upperBound
                                        filledRange = min(minBound, maxBound) ... max(minBound, maxBound)
                                    } else {
                                        let minBound = messageRange.lowerBound
                                        let maxBound = start.id
                                        filledRange = min(minBound, maxBound) ... max(minBound, maxBound)
                                    }
                            }
                        }
                        transaction.removeHole(peerId: peerId, namespace: namespace, space: space, range: filledRange)
                        
                        updatePeers(transaction: transaction, peers: peers + additionalPeers, update: { _, updated -> Peer in
                            return updated
                        })
                        updatePeerPresences(transaction: transaction, accountPeerId: accountPeerId, peerPresences: peerPresences)
                        
                        print("fetchMessageHistoryHole for \(peer.id) \(peer.debugDisplayTitle) space \(space) done")
                        
                        return
                    })
                }
            } else {
                return .complete()
            }
        }
    }
}

func groupBoundaryPeer(_ peerId: PeerId, accountPeerId: PeerId) -> Api.Peer {
    switch peerId.namespace {
        case Namespaces.Peer.CloudUser:
            return Api.Peer.peerUser(userId: peerId.id)
        case Namespaces.Peer.CloudGroup:
            return Api.Peer.peerChat(chatId: peerId.id)
        case Namespaces.Peer.CloudChannel:
            return Api.Peer.peerChannel(channelId: peerId.id)
        default:
            return Api.Peer.peerUser(userId: accountPeerId.id)
    }
}

func fetchChatListHole(postbox: Postbox, network: Network, accountPeerId: PeerId, groupId: PeerGroupId, hole: ChatListHole) -> Signal<Never, NoError> {
    let location: FetchChatListLocation
    switch groupId {
        case .root:
            location = .general
        case .group:
            location = .group(groupId)
    }
    return fetchChatList(postbox: postbox, network: network, location: location, upperBound: hole.index, hash: 0, limit: 100)
    |> mapToSignal { fetchedChats -> Signal<Never, NoError> in
        guard let fetchedChats = fetchedChats else {
            return postbox.transaction { transaction -> Void in
                transaction.replaceChatListHole(groupId: groupId, index: hole.index, hole: nil)
            }
            |> ignoreValues
        }
        return withResolvedAssociatedMessages(postbox: postbox, source: .network(network), peers: Dictionary(fetchedChats.peers.map({ ($0.id, $0) }), uniquingKeysWith: { lhs, _ in lhs }), storeMessages: fetchedChats.storeMessages, { transaction, additionalPeers, additionalMessages in
            updatePeers(transaction: transaction, peers: fetchedChats.peers + additionalPeers, update: { _, updated -> Peer in
                return updated
            })
            
            updatePeerPresences(transaction: transaction, accountPeerId: accountPeerId, peerPresences: fetchedChats.peerPresences)
            transaction.updateCurrentPeerNotificationSettings(fetchedChats.notificationSettings)
            let _ = transaction.addMessages(fetchedChats.storeMessages, location: .UpperHistoryBlock)
            let _ = transaction.addMessages(additionalMessages, location: .Random)
            transaction.resetIncomingReadStates(fetchedChats.readStates)
            
            transaction.replaceChatListHole(groupId: groupId, index: hole.index, hole: fetchedChats.lowerNonPinnedIndex.flatMap(ChatListHole.init))
            
            for peerId in fetchedChats.chatPeerIds {
                if let peer = transaction.getPeer(peerId) {
                    transaction.updatePeerChatListInclusion(peerId, inclusion: .ifHasMessagesOrOneOf(groupId: groupId, pinningIndex: nil, minTimestamp: minTimestampForPeerInclusion(peer)))
                } else {
                    assertionFailure()
                }
            }
            
            for (peerId, peerGroupId) in fetchedChats.peerGroupIds {
                if let peer = transaction.getPeer(peerId) {
                    transaction.updatePeerChatListInclusion(peerId, inclusion: .ifHasMessagesOrOneOf(groupId: peerGroupId, pinningIndex: nil, minTimestamp: minTimestampForPeerInclusion(peer)))
                } else {
                    assertionFailure()
                }
            }
            
            for (peerId, chatState) in fetchedChats.chatStates {
                if let chatState = chatState as? ChannelState {
                    if let current = transaction.getPeerChatState(peerId) as? ChannelState {
                        transaction.setPeerChatState(peerId, state: current.withUpdatedPts(chatState.pts))
                    } else {
                        transaction.setPeerChatState(peerId, state: chatState)
                    }
                } else {
                    transaction.setPeerChatState(peerId, state: chatState)
                }
            }
            
            if let replacePinnedItemIds = fetchedChats.pinnedItemIds {
                transaction.setPinnedItemIds(groupId: groupId, itemIds: replacePinnedItemIds.map(PinnedItemId.peer))
            }
            
            for (peerId, summary) in fetchedChats.mentionTagSummaries {
                transaction.replaceMessageTagSummary(peerId: peerId, tagMask: .unseenPersonalMessage, namespace: Namespaces.Message.Cloud, count: summary.count, maxId: summary.range.maxId)
            }
            
            for (groupId, summary) in fetchedChats.folderSummaries {
                transaction.resetPeerGroupSummary(groupId: groupId, namespace: Namespaces.Message.Cloud, summary: summary)
            }
        })
    }
}

func fetchCallListHole(network: Network, postbox: Postbox, accountPeerId: PeerId, holeIndex: MessageIndex, limit: Int32 = 100) -> Signal<Void, NoError> {
    let offset: Signal<(Int32, Int32, Api.InputPeer), NoError>
    offset = single((holeIndex.timestamp, min(holeIndex.id.id, Int32.max - 1) + 1, Api.InputPeer.inputPeerEmpty), NoError.self)
    return offset
    |> mapToSignal { (timestamp, id, peer) -> Signal<Void, NoError> in
        let searchResult = network.request(Api.functions.messages.search(flags: 0, peer: .inputPeerEmpty, q: "", fromId: nil, filter: .inputMessagesFilterPhoneCalls(flags: 0), minDate: 0, maxDate: holeIndex.timestamp, offsetId: 0, addOffset: 0, limit: limit, maxId: holeIndex.id.id, minId: 0, hash: 0))
        |> retryRequest
        |> mapToSignal { result -> Signal<Void, NoError> in
            let messages: [Api.Message]
            let chats: [Api.Chat]
            let users: [Api.User]
            switch result {
                case let .messages(messages: apiMessages, chats: apiChats, users: apiUsers):
                    messages = apiMessages
                    chats = apiChats
                    users = apiUsers
                case let .messagesSlice(_, _, _, messages: apiMessages, chats: apiChats, users: apiUsers):
                    messages = apiMessages
                    chats = apiChats
                    users = apiUsers
                case let .channelMessages(_, _, _, apiMessages, apiChats, apiUsers):
                    messages = apiMessages
                    chats = apiChats
                    users = apiUsers
                case .messagesNotModified:
                    messages = []
                    chats = []
                    users = []
            }
            return postbox.transaction { transaction -> Void in
                var storeMessages: [StoreMessage] = []
                var topIndex: MessageIndex?
                
                for message in messages {
                    if let storeMessage = StoreMessage(apiMessage: message) {
                        storeMessages.append(storeMessage)
                        if let index = storeMessage.index, topIndex == nil || index < topIndex! {
                            topIndex = index
                        }
                    }
                }
                
                var updatedIndex: MessageIndex?
                if let topIndex = topIndex {
                    updatedIndex = topIndex.predecessor()
                }
                
                transaction.replaceGlobalMessageTagsHole(globalTags: [.Calls, .MissedCalls], index: holeIndex, with: updatedIndex, messages: storeMessages)
                
                var peers: [Peer] = []
                var peerPresences: [PeerId: PeerPresence] = [:]
                for chat in chats {
                    if let groupOrChannel = parseTelegramGroupOrChannel(chat: chat) {
                        peers.append(groupOrChannel)
                    }
                }
                for user in users {
                    let telegramUser = TelegramUser(user: user)
                    peers.append(telegramUser)
                    if let presence = TelegramUserPresence(apiUser: user) {
                        peerPresences[telegramUser.id] = presence
                    }
                }
                
                updatePeers(transaction: transaction, peers: peers, update: { _, updated -> Peer in
                    return updated
                })
                updatePeerPresences(transaction: transaction, accountPeerId: accountPeerId, peerPresences: peerPresences)
            }
        }
        return searchResult
    }
}
