import Foundation
import UIKit
import Postbox
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext

private let titleFont = UIFont.systemFont(ofSize: 13.0)

class ChatUnreadItem: ListViewItem {
    let index: MessageIndex
    let presentationData: ChatPresentationData
    let header: ChatMessageDateHeader
    
    init(index: MessageIndex, presentationData: ChatPresentationData, context: AccountContext) {
        self.index = index
        self.presentationData = presentationData
        self.header = ChatMessageDateHeader(timestamp: index.timestamp, scheduled: false, presentationData: presentationData, context: context)
    }
    
    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ChatUnreadItemNode()
            node.layoutForParams(params, item: self, previousItem: previousItem, nextItem: nextItem)
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in })
                })
            }
        }
    }
    
    public func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? ChatUnreadItemNode {
                let nodeLayout = nodeValue.asyncLayout()
                
                async {
                    let dateAtBottom = !chatItemsHaveCommonDateHeader(self, nextItem)
                    
                    let (layout, apply) = nodeLayout(self, params, dateAtBottom)
                    Queue.mainQueue().async {
                        completion(layout, { _ in
                            apply()
                        })
                    }
                }
            } else {
                assertionFailure()
            }
        }
    }
}

class ChatUnreadItemNode: ListViewItemNode {
    var item: ChatUnreadItem?
    let backgroundNode: ASImageNode
    let labelNode: TextNode
    
    private var theme: ChatPresentationThemeData?
    
    private let layoutConstants = ChatMessageItemLayoutConstants.default
    
    init() {
        self.backgroundNode = ASImageNode()
        self.backgroundNode.isLayerBacked = true
        self.backgroundNode.displayWithoutProcessing = true
        
        self.labelNode = TextNode()
        self.labelNode.isUserInteractionEnabled = false
        
        super.init(layerBacked: false, dynamicBounce: true, rotated: true)
        
        self.addSubnode(self.backgroundNode)
        
        self.addSubnode(self.labelNode)
        
        self.transform = CATransform3DMakeRotation(CGFloat.pi, 0.0, 0.0, 1.0)
        
        self.scrollPositioningInsets = UIEdgeInsets(top: 5.0, left: 0.0, bottom: 6.0, right: 0.0)
        self.canBeUsedAsScrollToItemAnchor = false
    }
    
    override func animateInsertion(_ currentTimestamp: Double, duration: Double, short: Bool) {
        super.animateInsertion(currentTimestamp, duration: duration, short: short)
        
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
    }
    
    override func animateAdded(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
    }
    
    override func layoutForParams(_ params: ListViewItemLayoutParams, item: ListViewItem, previousItem: ListViewItem?, nextItem: ListViewItem?) {
            if let item = item as? ChatUnreadItem {
            let dateAtBottom = !chatItemsHaveCommonDateHeader(item, nextItem)
            let (layout, apply) = self.asyncLayout()(item, params, dateAtBottom)
            apply()
            self.contentSize = layout.contentSize
            self.insets = layout.insets
        }
    }
    
    func asyncLayout() -> (_ item: ChatUnreadItem, _ params: ListViewItemLayoutParams, _ dateAtBottom: Bool) -> (ListViewItemNodeLayout, () -> Void) {
        let labelLayout = TextNode.asyncLayout(self.labelNode)
        let layoutConstants = self.layoutConstants
        let currentTheme = self.theme
        
        return { item, params, dateAtBottom in
            var updatedBackgroundImage: UIImage?
            if currentTheme != item.presentationData.theme {
                updatedBackgroundImage = PresentationResourcesChat.chatUnreadBarBackgroundImage(item.presentationData.theme.theme)
            }
            
            let (size, apply) = labelLayout(TextNodeLayoutArguments(attributedString: NSAttributedString(string: item.presentationData.strings.Conversation_UnreadMessages, font: titleFont, textColor: item.presentationData.theme.theme.chat.serviceMessage.unreadBarTextColor), backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: params.width - params.leftInset - params.rightInset, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))
            
            let backgroundSize = CGSize(width: params.width, height: 25.0)
            
            return (ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: 25.0), insets: UIEdgeInsets(top: 6.0 + (dateAtBottom ? layoutConstants.timestampHeaderHeight : 0.0), left: 0.0, bottom: 5.0, right: 0.0)), { [weak self] in
                if let strongSelf = self {
                    strongSelf.item = item
                    strongSelf.theme = item.presentationData.theme
                    
                    if let updatedBackgroundImage = updatedBackgroundImage {
                        strongSelf.backgroundNode.image = updatedBackgroundImage
                    }
                    
                    let _ = apply()
                    
                    strongSelf.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: backgroundSize)
                    strongSelf.labelNode.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((backgroundSize.width - size.size.width) / 2.0), y: floorToScreenPixels((backgroundSize.height - size.size.height) / 2.0)), size: size.size)
                }
            })
        }
    }
    
    override public func header() -> ListViewItemHeader? {
        if let item = self.item {
            return item.header
        } else {
            return nil
        }
    }
    
    override public func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        super.animateRemoved(currentTimestamp, duration: duration)
        
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
    }
}
