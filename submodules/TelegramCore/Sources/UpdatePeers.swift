import Foundation
import Postbox
import TelegramApi

import SyncCore

func updatePeerChatInclusionWithMinTimestamp(transaction: Transaction, id: PeerId, minTimestamp: Int32, forceRootGroupIfNotExists: Bool) {
    let currentInclusion = transaction.getPeerChatListInclusion(id)
    var updatedInclusion: PeerChatListInclusion?
    switch currentInclusion {
        case let .ifHasMessagesOrOneOf(groupId, pinningIndex, currentMinTimestamp):
            let updatedMinTimestamp: Int32
            if let currentMinTimestamp = currentMinTimestamp {
                if minTimestamp > currentMinTimestamp {
                    updatedMinTimestamp = minTimestamp
                } else {
                    updatedMinTimestamp = currentMinTimestamp
                }
            } else {
                updatedMinTimestamp = minTimestamp
            }
            updatedInclusion = .ifHasMessagesOrOneOf(groupId: groupId, pinningIndex: pinningIndex, minTimestamp: updatedMinTimestamp)
        default:
            if forceRootGroupIfNotExists {
                updatedInclusion = .ifHasMessagesOrOneOf(groupId: .root, pinningIndex: nil, minTimestamp: minTimestamp)
            }
    }
    if let updatedInclusion = updatedInclusion {
        transaction.updatePeerChatListInclusion(id, inclusion: updatedInclusion)
    }
}

func minTimestampForPeerInclusion(_ peer: Peer) -> Int32? {
    if let group = peer as? TelegramGroup {
        return group.creationDate
    } else if let channel = peer as? TelegramChannel {
        return channel.creationDate
    } else {
        return nil
    }
}

public func updatePeers(transaction: Transaction, peers: [Peer], update: (Peer?, Peer) -> Peer?) {
    transaction.updatePeersInternal(peers, update: { previous, updated in
        let peerId = updated.id
        
        switch peerId.namespace {
            case Namespaces.Peer.CloudUser:
                break
            case Namespaces.Peer.CloudGroup:
                if let group = updated as? TelegramGroup {
                    if group.flags.contains(.deactivated) {
                        transaction.updatePeerChatListInclusion(peerId, inclusion: .notIncluded)
                    } else {
                        switch group.membership {
                            case .Member:
                                updatePeerChatInclusionWithMinTimestamp(transaction: transaction, id: peerId, minTimestamp: group.creationDate, forceRootGroupIfNotExists: false)
                            default:
                                transaction.updatePeerChatListInclusion(peerId, inclusion: .notIncluded)
                        }
                    }
                } else {
                    assertionFailure()
                }
            case Namespaces.Peer.CloudChannel:
                if let channel = updated as? TelegramChannel {
                    switch channel.participationStatus {
                        case .member:
                            updatePeerChatInclusionWithMinTimestamp(transaction: transaction, id: peerId, minTimestamp: channel.creationDate, forceRootGroupIfNotExists: false)
                        case .left:
                            transaction.updatePeerChatListInclusion(peerId, inclusion: .notIncluded)
                        case .kicked where channel.creationDate == 0:
                            transaction.updatePeerChatListInclusion(peerId, inclusion: .notIncluded)
                        default:
                            transaction.updatePeerChatListInclusion(peerId, inclusion: .notIncluded)
                    }
                } else {
                    assertionFailure()
                }
            case Namespaces.Peer.SecretChat:
                if let secretChat = updated as? TelegramSecretChat {
                    let isActive: Bool
                    switch secretChat.embeddedState {
                        case .active, .handshake:
                            isActive = true
                        case .terminated:
                            isActive = false
                    }
                    updatePeerChatInclusionWithMinTimestamp(transaction: transaction, id: peerId, minTimestamp: secretChat.creationDate, forceRootGroupIfNotExists: isActive)
                } else {
                    assertionFailure()
                }
            default:
                assertionFailure()
                break
        }
        
        return update(previous, updated)
    })
}

func updatePeerPresences(transaction: Transaction, accountPeerId: PeerId, peerPresences: [PeerId: PeerPresence]) {
    var peerPresences = peerPresences
    if peerPresences[accountPeerId] != nil {
        peerPresences.removeValue(forKey: accountPeerId)
    }
    transaction.updatePeerPresencesInternal(presences: peerPresences, merge: { previous, updated in
        if let previous = previous as? TelegramUserPresence, let updated = updated as? TelegramUserPresence, previous.lastActivity != updated.lastActivity {
            return TelegramUserPresence(status: updated.status, lastActivity: max(previous.lastActivity, updated.lastActivity))
        }
        return updated
    })
}

func updatePeerPresenceLastActivities(transaction: Transaction, accountPeerId: PeerId, activities: [PeerId: Int32]) {
    var activities = activities
    if activities[accountPeerId] != nil {
        activities.removeValue(forKey: accountPeerId)
    }
    for (peerId, timestamp) in activities {
        transaction.updatePeerPresenceInternal(peerId: peerId, update: { previous in
            if let previous = previous as? TelegramUserPresence, previous.lastActivity < timestamp {
                var updatedStatus = previous.status
                switch updatedStatus {
                    case let .present(until):
                        if until < timestamp {
                            updatedStatus = .present(until: timestamp)
                        }
                    default:
                        break
                }
                return TelegramUserPresence(status: updatedStatus, lastActivity: timestamp)
            }
            return previous
        })
    }
}

func updateContacts(transaction: Transaction, apiUsers: [Api.User]) {
    if apiUsers.isEmpty {
        return
    }
    var contactIds = transaction.getContactPeerIds()
    var updated = false
    for user in apiUsers {
        let isContact: Bool
        switch user {
            case let .user(user):
                isContact = (user.flags & (1 << 11)) != 0
            case .userEmpty:
                isContact = false
        }
        if isContact {
            if !contactIds.contains(user.peerId) {
                contactIds.insert(user.peerId)
                updated = true
            }
        } else {
            if contactIds.contains(user.peerId) {
                contactIds.remove(user.peerId)
                updated = true
            }
        }
    }
    if updated {
        transaction.replaceContactPeerIds(contactIds)
    }
}
