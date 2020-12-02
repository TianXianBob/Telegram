import Foundation

final class MutablePeerNotificationSettingsBehaviorTimestampView: MutablePostboxView {
    fileprivate var earliestTimestamp: Int32?
    
    init(postbox: Postbox) {
        self.earliestTimestamp = postbox.peerNotificationSettingsBehaviorTable.getEarliest()?.1
    }
    
    func replay(postbox: Postbox, transaction: PostboxTransaction) -> Bool {
        var updated = false
        if !transaction.currentUpdatedPeerNotificationBehaviorTimestamps.isEmpty {
            let earliestTimestamp = postbox.peerNotificationSettingsBehaviorTable.getEarliest()?.1
            if self.earliestTimestamp != earliestTimestamp {
                self.earliestTimestamp = earliestTimestamp
                updated = true
            }
        }
        
        return updated
    }
    
    func immutableView() -> PostboxView {
        return PeerNotificationSettingsBehaviorTimestampView(self)
    }
}

public final class PeerNotificationSettingsBehaviorTimestampView: PostboxView {
    public let earliestTimestamp: Int32?
    
    init(_ view: MutablePeerNotificationSettingsBehaviorTimestampView) {
        self.earliestTimestamp = view.earliestTimestamp
    }
}
