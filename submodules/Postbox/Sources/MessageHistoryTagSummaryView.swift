import Foundation

final class MutableMessageHistoryTagSummaryView: MutablePostboxView {
    private let tag: MessageTags
    private let peerId: PeerId
    private let namespace: MessageId.Namespace
    
    fileprivate var count: Int32?
    
    init(postbox: Postbox, tag: MessageTags, peerId: PeerId, namespace: MessageId.Namespace) {
        self.tag = tag
        self.peerId = peerId
        self.namespace = namespace
        
        self.count = postbox.messageHistoryTagsSummaryTable.get(MessageHistoryTagsSummaryKey(tag: tag, peerId: peerId, namespace: namespace))?.count
    }
    
    func replay(postbox: Postbox, transaction: PostboxTransaction) -> Bool {
        var hasChanges = false
        
        if let summary = transaction.currentUpdatedMessageTagSummaries[MessageHistoryTagsSummaryKey(tag: self.tag, peerId: self.peerId, namespace: self.namespace)] {
            self.count = summary.count
            hasChanges = true
        }
        
        return hasChanges
    }
    
    func immutableView() -> PostboxView {
        return MessageHistoryTagSummaryView(self)
    }
}

public final class MessageHistoryTagSummaryView: PostboxView {
    public let count: Int32?
    
    init(_ view: MutableMessageHistoryTagSummaryView) {
        self.count = view.count
    }
}
