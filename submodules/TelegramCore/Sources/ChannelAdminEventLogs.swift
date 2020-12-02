import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit

import SyncCore

public typealias AdminLogEventId = Int64

public struct AdminLogEvent: Comparable {
    public let id: AdminLogEventId
    public let peerId: PeerId
    public let date: Int32
    public let action: AdminLogEventAction
    
    public static func ==(lhs: AdminLogEvent, rhs: AdminLogEvent) -> Bool {
        return lhs.id == rhs.id
    }
    
    public static func <(lhs: AdminLogEvent, rhs: AdminLogEvent) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date < rhs.date
        } else {
            return lhs.id < rhs.id
        }
    }
}

public struct AdminLogEventsResult {
    public let peerId: PeerId
    public let peers: [PeerId: Peer]
    public let events: [AdminLogEvent]
}

public enum AdminLogEventAction {
    case changeTitle(prev: String, new: String)
    case changeAbout(prev: String, new: String)
    case changeUsername(prev: String, new: String)
    case changePhoto(prev: [TelegramMediaImageRepresentation], new: [TelegramMediaImageRepresentation])
    case toggleInvites(Bool)
    case toggleSignatures(Bool)
    case updatePinned(Message?)
    case editMessage(prev: Message, new: Message)
    case deleteMessage(Message)
    case participantJoin
    case participantLeave
    case participantInvite(RenderedChannelParticipant)
    case participantToggleBan(prev: RenderedChannelParticipant, new: RenderedChannelParticipant)
    case participantToggleAdmin(prev: RenderedChannelParticipant, new: RenderedChannelParticipant)
    case changeStickerPack(prev: StickerPackReference?, new: StickerPackReference?)
    case togglePreHistoryHidden(Bool)
    case updateDefaultBannedRights(prev: TelegramChatBannedRights, new: TelegramChatBannedRights)
    case pollStopped(Message)
    case linkedPeerUpdated(previous: Peer?, updated: Peer?)
    case changeGeoLocation(previous: PeerGeoLocation?, updated: PeerGeoLocation?)
    case updateSlowmode(previous: Int32?, updated: Int32?)
}

public enum ChannelAdminLogEventError {
    case generic
}

public struct AdminLogEventsFlags: OptionSet {
    public var rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    public init() {
        self.rawValue = 0
    }
    public static let join = AdminLogEventsFlags(rawValue: 1 << 0)
    public static let leave = AdminLogEventsFlags(rawValue: 1 << 1)
    public static let invite = AdminLogEventsFlags(rawValue: 1 << 2)
    public static let ban = AdminLogEventsFlags(rawValue: 1 << 3)
    public static let unban = AdminLogEventsFlags(rawValue: 1 << 4)
    public static let kick = AdminLogEventsFlags(rawValue: 1 << 5)
    public static let unkick = AdminLogEventsFlags(rawValue: 1 << 6)
    public static let promote = AdminLogEventsFlags(rawValue: 1 << 7)
    public static let demote = AdminLogEventsFlags(rawValue: 1 << 8)
    public static let info = AdminLogEventsFlags(rawValue: 1 << 9)
    public static let settings = AdminLogEventsFlags(rawValue: 1 << 10)
    public static let pinnedMessages = AdminLogEventsFlags(rawValue: 1 << 11)
    public static let editMessages = AdminLogEventsFlags(rawValue: 1 << 12)
    public static let deleteMessages = AdminLogEventsFlags(rawValue: 1 << 13)
    
    public static var all: AdminLogEventsFlags {
        return [.join, .leave, .invite, .ban, .unban, .kick, .unkick, .promote, .demote, .info, .settings, .pinnedMessages, .editMessages, .deleteMessages]
    }
    public static var flags: AdminLogEventsFlags {
        return [.join, .leave, .invite, .ban, .unban, .kick, .unkick, .promote, .demote, .info, .settings, .pinnedMessages, .editMessages, .deleteMessages]
    }
}

private func boolFromApiValue(_ value: Api.Bool) -> Bool {
    switch value {
        case .boolFalse:
            return false
        case .boolTrue:
            return true
    }
}

public func channelAdminLogEvents(postbox: Postbox, network: Network, peerId: PeerId, maxId: AdminLogEventId, minId: AdminLogEventId, limit: Int32 = 100, query: String? = nil, filter: AdminLogEventsFlags? = nil, admins: [PeerId]? = nil) -> Signal<AdminLogEventsResult, ChannelAdminLogEventError> {
    return postbox.transaction { transaction -> (Peer?, [Peer]?) in
        return (transaction.getPeer(peerId), admins?.compactMap { transaction.getPeer($0) })
    }
    |> castError(ChannelAdminLogEventError.self)
    |> mapToSignal { (peer, admins) -> Signal<AdminLogEventsResult, ChannelAdminLogEventError> in
        if let peer = peer, let inputChannel = apiInputChannel(peer) {
            let inputAdmins = admins?.compactMap { apiInputUser($0) }
            
            var flags: Int32 = 0
            var eventsFilter: Api.ChannelAdminLogEventsFilter? = nil
            if let filter = filter {
                flags += Int32(1 << 0)
                eventsFilter = Api.ChannelAdminLogEventsFilter.channelAdminLogEventsFilter(flags: Int32(filter.rawValue))
            }
            if let _ = inputAdmins {
                flags += Int32(1 << 1)
            }
            return network.request(Api.functions.channels.getAdminLog(flags: flags, channel: inputChannel, q: query ?? "", eventsFilter: eventsFilter, admins: inputAdmins, maxId: maxId, minId: minId, limit: limit)) |> mapToSignal { result in
                
                switch result {
                case let .adminLogResults(apiEvents, apiChats, apiUsers):
                    var peers: [PeerId: Peer] = [:]
                    for apiChat in apiChats {
                        if let peer = parseTelegramGroupOrChannel(chat: apiChat) {
                            peers[peer.id] = peer
                        }
                    }
                    for apiUser in apiUsers {
                        let peer = TelegramUser(user: apiUser)
                        peers[peer.id] = peer
                    }
                    
                    var events: [AdminLogEvent] = []
                    
                    for event in apiEvents {
                        switch event {
                            case let .channelAdminLogEvent(id, date, userId, apiAction):
                                var action: AdminLogEventAction?
                                switch apiAction {
                                    case let .channelAdminLogEventActionChangeTitle(prev, new):
                                        action = .changeTitle(prev: prev, new: new)
                                    case let .channelAdminLogEventActionChangeAbout(prev, new):
                                        action = .changeAbout(prev: prev, new: new)
                                    case let .channelAdminLogEventActionChangeUsername(prev, new):
                                        action = .changeUsername(prev: prev, new: new)
                                    case let .channelAdminLogEventActionChangePhoto(prev, new):
                                        action = .changePhoto(prev: telegramMediaImageFromApiPhoto(prev)?.representations ?? [], new: telegramMediaImageFromApiPhoto(new)?.representations ?? [])
                                    case let .channelAdminLogEventActionToggleInvites(new):
                                        action = .toggleInvites(boolFromApiValue(new))
                                    case let .channelAdminLogEventActionToggleSignatures(new):
                                        action = .toggleSignatures(boolFromApiValue(new))
                                    case let .channelAdminLogEventActionUpdatePinned(new):
                                        switch new {
                                        case .messageEmpty:
                                            action = .updatePinned(nil)
                                        default:
                                            if let message = StoreMessage(apiMessage: new), let rendered = locallyRenderedMessage(message: message, peers: peers) {
                                                action = .updatePinned(rendered)
                                            }
                                        }
                                    case let .channelAdminLogEventActionEditMessage(prev, new):
                                        if let prev = StoreMessage(apiMessage: prev), let prevRendered = locallyRenderedMessage(message: prev, peers: peers), let new = StoreMessage(apiMessage: new), let newRendered = locallyRenderedMessage(message: new, peers: peers) {
                                            action = .editMessage(prev: prevRendered, new: newRendered)
                                        }
                                    case let .channelAdminLogEventActionDeleteMessage(message):
                                        if let message = StoreMessage(apiMessage: message), let rendered = locallyRenderedMessage(message: message, peers: peers) {
                                            action = .deleteMessage(rendered)
                                        }
                                    case .channelAdminLogEventActionParticipantJoin:
                                        action = .participantJoin
                                    case .channelAdminLogEventActionParticipantLeave:
                                        action = .participantLeave
                                    case let .channelAdminLogEventActionParticipantInvite(participant):
                                        let participant = ChannelParticipant(apiParticipant: participant)
                                        
                                        if let peer = peers[participant.peerId] {
                                            action = .participantInvite(RenderedChannelParticipant(participant: participant, peer: peer))
                                        }
                                    case let .channelAdminLogEventActionParticipantToggleBan(prev, new):
                                        let prevParticipant = ChannelParticipant(apiParticipant: prev)
                                        let newParticipant = ChannelParticipant(apiParticipant: new)
                                        
                                        if let prevPeer = peers[prevParticipant.peerId], let newPeer = peers[newParticipant.peerId] {
                                            action = .participantToggleBan(prev: RenderedChannelParticipant(participant: prevParticipant, peer: prevPeer), new: RenderedChannelParticipant(participant: newParticipant, peer: newPeer))
                                        }
                                    case let .channelAdminLogEventActionParticipantToggleAdmin(prev, new):
                                        let prevParticipant = ChannelParticipant(apiParticipant: prev)
                                        let newParticipant = ChannelParticipant(apiParticipant: new)
                                        
                                        if let prevPeer = peers[prevParticipant.peerId], let newPeer = peers[newParticipant.peerId] {
                                            action = .participantToggleAdmin(prev: RenderedChannelParticipant(participant: prevParticipant, peer: prevPeer), new: RenderedChannelParticipant(participant: newParticipant, peer: newPeer))
                                            }
                                    case let .channelAdminLogEventActionChangeStickerSet(prevStickerset, newStickerset):
                                        action = .changeStickerPack(prev: StickerPackReference(apiInputSet: prevStickerset), new: StickerPackReference(apiInputSet: newStickerset))
                                    case let .channelAdminLogEventActionTogglePreHistoryHidden(value):
                                        action = .togglePreHistoryHidden(value == .boolTrue)
                                    case let .channelAdminLogEventActionDefaultBannedRights(prevBannedRights, newBannedRights):
                                        action = .updateDefaultBannedRights(prev: TelegramChatBannedRights(apiBannedRights: prevBannedRights), new: TelegramChatBannedRights(apiBannedRights: newBannedRights))
                                    case let .channelAdminLogEventActionStopPoll(message):
                                        if let message = StoreMessage(apiMessage: message), let rendered = locallyRenderedMessage(message: message, peers: peers) {
                                            action = .pollStopped(rendered)
                                        }
                                    case let .channelAdminLogEventActionChangeLinkedChat(prevValue, newValue):
                                        action = .linkedPeerUpdated(previous: prevValue == 0 ? nil : peers[PeerId(namespace: Namespaces.Peer.CloudChannel, id: prevValue)], updated: newValue == 0 ? nil : peers[PeerId(namespace: Namespaces.Peer.CloudChannel, id: newValue)])
                                    case let .channelAdminLogEventActionChangeLocation(prevValue, newValue):
                                        action = .changeGeoLocation(previous: PeerGeoLocation(apiLocation: prevValue), updated: PeerGeoLocation(apiLocation: newValue))
                                    case let .channelAdminLogEventActionToggleSlowMode(prevValue, newValue):
                                        action = .updateSlowmode(previous: prevValue == 0 ? nil : prevValue, updated: newValue == 0 ? nil : newValue)
                                }
                                let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: userId)
                                if let action = action {
                                    events.append(AdminLogEvent(id: id, peerId: peerId, date: date, action: action))
                                }
                        }
                    }
                    
                    return postbox.transaction { transaction -> AdminLogEventsResult in
                        updatePeers(transaction: transaction, peers: peers.map { $0.1 }, update: { return $1 })
                        return AdminLogEventsResult(peerId: peerId, peers: peers, events: events)
                    } |> castError(MTRpcError.self)
                }
                
            } |> mapError {_ in return .generic}
        }
        
        return .complete()
    }
}
