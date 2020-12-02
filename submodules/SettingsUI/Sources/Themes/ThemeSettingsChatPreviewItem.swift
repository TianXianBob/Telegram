import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import SyncCore
import Postbox
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext

struct ChatPreviewMessageItem: Equatable {
    static func == (lhs: ChatPreviewMessageItem, rhs: ChatPreviewMessageItem) -> Bool {
        if lhs.outgoing != rhs.outgoing {
            return false
        }
        if let lhsReply = lhs.reply, let rhsReply = rhs.reply, lhsReply.0 != rhsReply.0 || lhsReply.1 != rhsReply.1 {
            return false
        } else if (lhs.reply == nil) != (rhs.reply == nil) {
            return false
        }
        if lhs.text != rhs.text {
            return false
        }
        return true
    }
    
    let outgoing: Bool
    let reply: (String, String)?
    let text: String
}

class ThemeSettingsChatPreviewItem: ListViewItem, ItemListItem {
    let context: AccountContext
    let theme: PresentationTheme
    let componentTheme: PresentationTheme
    let strings: PresentationStrings
    let sectionId: ItemListSectionId
    let fontSize: PresentationFontSize
    let wallpaper: TelegramWallpaper
    let dateTimeFormat: PresentationDateTimeFormat
    let nameDisplayOrder: PresentationPersonNameOrder
    let messageItems: [ChatPreviewMessageItem]
    
    init(context: AccountContext, theme: PresentationTheme, componentTheme: PresentationTheme, strings: PresentationStrings, sectionId: ItemListSectionId, fontSize: PresentationFontSize, wallpaper: TelegramWallpaper, dateTimeFormat: PresentationDateTimeFormat, nameDisplayOrder: PresentationPersonNameOrder, messageItems: [ChatPreviewMessageItem]) {
        self.context = context
        self.theme = theme
        self.componentTheme = componentTheme
        self.strings = strings
        self.sectionId = sectionId
        self.fontSize = fontSize
        self.wallpaper = wallpaper
        self.dateTimeFormat = dateTimeFormat
        self.nameDisplayOrder = nameDisplayOrder
        self.messageItems = messageItems
    }
    
    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ThemeSettingsChatPreviewItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }
    
    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? ThemeSettingsChatPreviewItemNode {
                let makeLayout = nodeValue.asyncLayout()
                
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                    Queue.mainQueue().async {
                        completion(layout, { _ in
                            apply()
                        })
                    }
                }
            }
        }
    }
}

class ThemeSettingsChatPreviewItemNode: ListViewItemNode {
    private let backgroundNode: ASImageNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let maskNode: ASImageNode
    
    private let containerNode: ASDisplayNode
    private var messageNodes: [ListViewItemNode]?
    
    private var item: ThemeSettingsChatPreviewItem?
    private var finalImage = true
    
    private let disposable = MetaDisposable()
    
    init() {
        self.backgroundNode = ASImageNode()
        self.backgroundNode.isLayerBacked = true
        self.backgroundNode.displaysAsynchronously = false
        self.backgroundNode.displayWithoutProcessing = true
        self.backgroundNode.contentMode = .scaleAspectFill
        
        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true
        
        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true
        
        self.maskNode = ASImageNode()
        
        self.containerNode = ASDisplayNode()
        self.containerNode.subnodeTransform = CATransform3DMakeRotation(CGFloat.pi, 0.0, 0.0, 1.0)
        
        super.init(layerBacked: false, dynamicBounce: false)
        
        self.clipsToBounds = true
        
        self.addSubnode(self.containerNode)
    }
    
    deinit {
        self.disposable.dispose()
    }
    
    func asyncLayout() -> (_ item: ThemeSettingsChatPreviewItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        let currentItem = self.item
        
        let currentNodes = self.messageNodes
        
        return { item, params, neighbors in
            var updatedBackgroundSignal: Signal<(UIImage?, Bool)?, NoError>?
            if currentItem?.wallpaper != item.wallpaper {
                updatedBackgroundSignal = chatControllerBackgroundImageSignal(wallpaper: item.wallpaper, mediaBox: item.context.account.postbox.mediaBox)
            }
            
            let insets: UIEdgeInsets
            let separatorHeight = UIScreenPixel
            
            let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: 1)
            let otherPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: 2)
            var items: [ListViewItem] = []
            for messageItem in item.messageItems.reversed() {
                var peers = SimpleDictionary<PeerId, Peer>()
                var messages = SimpleDictionary<MessageId, Message>()
                
                let replyMessageId = MessageId(peerId: peerId, namespace: 0, id: 3)
                if let (author, text) = messageItem.reply {
                    peers[peerId] = TelegramUser(id: peerId, accessHash: nil, firstName: author, lastName: "", username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [])
                    messages[replyMessageId] = Message(stableId: 3, stableVersion: 0, id: replyMessageId, globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, timestamp: 66000, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: peers[peerId], text: text, attributes: [], media: [], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                }
                
                let message = Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: messageItem.outgoing ? otherPeerId : peerId, namespace: 0, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, timestamp: 66000, flags: messageItem.outgoing ? [] : [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: messageItem.outgoing ? TelegramUser(id: otherPeerId, accessHash: nil, firstName: "", lastName: "", username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: []) : nil, text: messageItem.text, attributes: messageItem.reply != nil ? [ReplyMessageAttribute(messageId: replyMessageId)] : [], media: [], peers: peers, associatedMessages: messages, associatedMessageIds: [])
                items.append(item.context.sharedContext.makeChatMessagePreviewItem(context: item.context, message: message, theme: item.componentTheme, strings: item.strings, wallpaper: item.wallpaper, fontSize: item.fontSize, dateTimeFormat: item.dateTimeFormat, nameOrder: item.nameDisplayOrder, forcedResourceStatus: nil, tapMessage: nil, clickThroughMessage: nil))
            }
            
            var nodes: [ListViewItemNode] = []
            if let messageNodes = currentNodes {
                nodes = messageNodes
                for i in 0 ..< items.count {
                    let itemNode = messageNodes[i]
                    items[i].updateNode(async: { $0() }, node: {
                        return itemNode
                    }, params: params, previousItem: i == 0 ? nil : items[i - 1], nextItem: i == (items.count - 1) ? nil : items[i + 1], animation: .None, completion: { (layout, apply) in
                        let nodeFrame = CGRect(origin: itemNode.frame.origin, size: CGSize(width: layout.size.width, height: layout.size.height))
                        
                        itemNode.contentSize = layout.contentSize
                        itemNode.insets = layout.insets
                        itemNode.frame = nodeFrame
                        itemNode.isUserInteractionEnabled = false
                        
                        apply(ListViewItemApply(isOnScreen: true))
                    })
                }
            } else {
                var messageNodes: [ListViewItemNode] = []
                for i in 0 ..< items.count {
                    var itemNode: ListViewItemNode?
                    items[i].nodeConfiguredForParams(async: { $0() }, params: params, synchronousLoads: false, previousItem: i == 0 ? nil : items[i - 1], nextItem: i == (items.count - 1) ? nil : items[i + 1], completion: { node, apply in
                        itemNode = node
                        apply().1(ListViewItemApply(isOnScreen: true))
                    })
                    itemNode!.isUserInteractionEnabled = false
                    messageNodes.append(itemNode!)
                }
                nodes = messageNodes
            }
            
            var contentSize = CGSize(width: params.width, height: 4.0 + 4.0)
            for node in nodes {
                contentSize.height += node.frame.size.height
            }
            insets = itemListNeighborsGroupedInsets(neighbors)
            
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            let layoutSize = layout.size
            
            return (layout, { [weak self] in
                if let strongSelf = self {
                    strongSelf.item = item
                    
                    strongSelf.containerNode.frame = CGRect(origin: CGPoint(), size: contentSize)
                    
                    strongSelf.messageNodes = nodes
                    var topOffset: CGFloat = 4.0
                    for node in nodes {
                        if node.supernode == nil {
                            strongSelf.containerNode.addSubnode(node)
                        }
                        node.updateFrame(CGRect(origin: CGPoint(x: 0.0, y: topOffset), size: node.frame.size), within: layoutSize)
                        topOffset += node.frame.size.height
                    }
                    
                    if let updatedBackgroundSignal = updatedBackgroundSignal {
                        strongSelf.disposable.set((updatedBackgroundSignal
                        |> deliverOnMainQueue).start(next: { [weak self] image in
                            if let strongSelf = self, let (image, final) = image {
                                if final && !strongSelf.finalImage {
                                    let tempLayer = CALayer()
                                    tempLayer.frame = strongSelf.backgroundNode.bounds
                                    tempLayer.contentsGravity = strongSelf.backgroundNode.layer.contentsGravity
                                    tempLayer.contents = strongSelf.contents
                                    strongSelf.layer.addSublayer(tempLayer)
                                    tempLayer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false, completion: { [weak tempLayer] _ in
                                        tempLayer?.removeFromSuperlayer()
                                    })
                                }
                                strongSelf.backgroundNode.image = image
                            }
                        }))
                    }
                    strongSelf.topStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                    strongSelf.bottomStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                    
                    if strongSelf.backgroundNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.backgroundNode, at: 0)
                    }
                    if strongSelf.topStripeNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.topStripeNode, at: 1)
                    }
                    if strongSelf.bottomStripeNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.bottomStripeNode, at: 2)
                    }
                    if strongSelf.maskNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.maskNode, at: 3)
                    }
                    
                    let hasCorners = itemListHasRoundedBlockLayout(params)
                    var hasTopCorners = false
                    var hasBottomCorners = false
                    switch neighbors.top {
                        case .sameSection(false):
                            strongSelf.topStripeNode.isHidden = true
                        default:
                            hasTopCorners = true
                            strongSelf.topStripeNode.isHidden = hasCorners
                    }
                    let bottomStripeInset: CGFloat
                    let bottomStripeOffset: CGFloat
                    switch neighbors.bottom {
                        case .sameSection(false):
                            bottomStripeInset = 0.0
                            bottomStripeOffset = -separatorHeight
                        default:
                            bottomStripeInset = 0.0
                            bottomStripeOffset = 0.0
                            hasBottomCorners = true
                            strongSelf.bottomStripeNode.isHidden = hasCorners
                    }
                    
                    strongSelf.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(item.theme, top: hasTopCorners, bottom: hasBottomCorners) : nil
                    
                    let backgroundFrame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                    strongSelf.backgroundNode.frame = backgroundFrame.insetBy(dx: 0.0, dy: -100.0)
                    strongSelf.maskNode.frame = backgroundFrame.insetBy(dx: params.leftInset, dy: 0.0)
                    strongSelf.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: layoutSize.width, height: separatorHeight))
                    strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height + bottomStripeOffset), size: CGSize(width: layoutSize.width - bottomStripeInset, height: separatorHeight))
                }
            })
        }
    }
    
    override func animateInsertion(_ currentTimestamp: Double, duration: Double, short: Bool) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }
    
    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
}
