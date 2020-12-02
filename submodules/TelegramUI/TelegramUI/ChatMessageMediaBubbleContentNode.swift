import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import SyncCore
import TelegramUIPreferences
import TelegramPresentationData
import AccountContext
import GridMessageSelectionNode

class ChatMessageMediaBubbleContentNode: ChatMessageBubbleContentNode {
    override var supportsMosaic: Bool {
        return true
    }
    
    private let interactiveImageNode: ChatMessageInteractiveMediaNode
    private let dateAndStatusNode: ChatMessageDateAndStatusNode
    private var selectionNode: GridMessageSelectionNode?
    private var highlightedState: Bool = false
    
    private var media: Media?
    private var automaticPlayback: Bool?
    
    override var visibility: ListViewItemNodeVisibility {
        didSet {
            self.interactiveImageNode.visibility = self.visibility != .none
        }
    }
    
    required init() {
        self.interactiveImageNode = ChatMessageInteractiveMediaNode()
        self.dateAndStatusNode = ChatMessageDateAndStatusNode()
        
        super.init()
        
        self.addSubnode(self.interactiveImageNode)
        
        self.interactiveImageNode.activateLocalContent = { [weak self] mode in
            if let strongSelf = self {
                if let item = strongSelf.item {
                    let openChatMessageMode: ChatControllerInteractionOpenMessageMode
                    switch mode {
                        case .default:
                            openChatMessageMode = .default
                        case .stream:
                            openChatMessageMode = .stream
                        case .automaticPlayback:
                            openChatMessageMode = .automaticPlayback
                    }
                    let _ = item.controllerInteraction.openMessage(item.message, openChatMessageMode)
                }
            }
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func asyncLayoutContent() -> (_ item: ChatMessageBubbleContentItem, _ layoutConstants: ChatMessageItemLayoutConstants, _ preparePosition: ChatMessageBubblePreparePosition, _ messageSelection: Bool?, _ constrainedSize: CGSize) -> (ChatMessageBubbleContentProperties, CGSize?, CGFloat, (CGSize, ChatMessageBubbleContentPosition) -> (CGFloat, (CGFloat) -> (CGSize, (ListViewItemUpdateAnimation, Bool) -> Void))) {
        let interactiveImageLayout = self.interactiveImageNode.asyncLayout()
        let statusLayout = self.dateAndStatusNode.asyncLayout()
        
        return { item, layoutConstants, preparePosition, selection, constrainedSize in
            var selectedMedia: Media?
            var automaticDownload: InteractiveMediaNodeAutodownloadMode = .none
            var automaticPlayback: Bool = false
            var contentMode: InteractiveMediaNodeContentMode = .aspectFit
            
            for media in item.message.media {
                if let telegramImage = media as? TelegramMediaImage {
                    selectedMedia = telegramImage
                    if shouldDownloadMediaAutomatically(settings: item.controllerInteraction.automaticMediaDownloadSettings, peerType: item.associatedData.automaticDownloadPeerType, networkType: item.associatedData.automaticDownloadNetworkType, authorPeerId: item.message.author?.id, contactsPeerIds: item.associatedData.contactsPeerIds, media: telegramImage) {
                        automaticDownload = .full
                    }
                } else if let telegramFile = media as? TelegramMediaFile {
                    selectedMedia = telegramFile
                    if shouldDownloadMediaAutomatically(settings: item.controllerInteraction.automaticMediaDownloadSettings, peerType: item.associatedData.automaticDownloadPeerType, networkType: item.associatedData.automaticDownloadNetworkType, authorPeerId: item.message.author?.id, contactsPeerIds: item.associatedData.contactsPeerIds, media: telegramFile) {
                        automaticDownload = .full
                    } else if shouldPredownloadMedia(settings: item.controllerInteraction.automaticMediaDownloadSettings, peerType: item.associatedData.automaticDownloadPeerType, networkType: item.associatedData.automaticDownloadNetworkType, media: telegramFile) {
                        automaticDownload = .prefetch
                    }
                    
                    if !item.message.containsSecretMedia {
                        if telegramFile.isAnimated && item.controllerInteraction.automaticMediaDownloadSettings.autoplayGifs {
                            if case .full = automaticDownload {
                                automaticPlayback = true
                            } else {
                                automaticPlayback = item.context.account.postbox.mediaBox.completedResourcePath(telegramFile.resource) != nil
                            }
                        } else if (telegramFile.isVideo && !telegramFile.isAnimated) && item.controllerInteraction.automaticMediaDownloadSettings.autoplayVideos {
                            if case .full = automaticDownload {
                                automaticPlayback = true
                            } else {
                                automaticPlayback = item.context.account.postbox.mediaBox.completedResourcePath(telegramFile.resource) != nil
                            }
                        }
                    }
                    contentMode = .aspectFill
                }
            }
            
            var hasReplyMarkup: Bool = false
            for attribute in item.message.attributes {
                if let attribute = attribute as? ReplyMarkupMessageAttribute, attribute.flags.contains(.inline), !attribute.rows.isEmpty {
                    hasReplyMarkup = true
                    break
                }
            }
            
            let bubbleInsets: UIEdgeInsets
            let sizeCalculation: InteractiveMediaNodeSizeCalculation
            
            switch preparePosition {
                case .linear:
                    if case .color = item.presentationData.theme.wallpaper {
                        let colors: PresentationThemeBubbleColorComponents
                        if item.message.effectivelyIncoming(item.context.account.peerId) {
                            colors = item.presentationData.theme.theme.chat.message.incoming.bubble.withoutWallpaper
                        } else {
                            colors = item.presentationData.theme.theme.chat.message.outgoing.bubble.withoutWallpaper
                        }
                        if colors.fill == colors.stroke {
                            bubbleInsets = UIEdgeInsets()
                        } else {
                            bubbleInsets = layoutConstants.bubble.strokeInsets
                        }
                    } else {
                        bubbleInsets = layoutConstants.image.bubbleInsets
                    }
                    
                    sizeCalculation = .constrained(CGSize(width: constrainedSize.width - bubbleInsets.left - bubbleInsets.right, height: constrainedSize.height))
                case .mosaic:
                    bubbleInsets = UIEdgeInsets()
                    sizeCalculation = .unconstrained
            }
            
            let (unboundSize, initialWidth, refineLayout) = interactiveImageLayout(item.context, item.presentationData.theme.theme, item.presentationData.strings, item.presentationData.dateTimeFormat, item.message, selectedMedia!, automaticDownload, item.associatedData.automaticDownloadPeerType, sizeCalculation, layoutConstants, contentMode)
            
            let forceFullCorners = false
            let contentProperties = ChatMessageBubbleContentProperties(hidesSimpleAuthorHeader: true, headerSpacing: 7.0, hidesBackground: .emptyWallpaper, forceFullCorners: forceFullCorners, forceAlignment: .none)
            
            return (contentProperties, unboundSize, initialWidth + bubbleInsets.left + bubbleInsets.right, { constrainedSize, position in
                var wideLayout = true
                if case let .mosaic(_, wide) = position {
                    wideLayout = wide
                    automaticPlayback = automaticPlayback && wide
                }
                
                var updatedPosition: ChatMessageBubbleContentPosition = position
                if forceFullCorners, case .linear = updatedPosition {
                    updatedPosition = .linear(top: .None(.None(.None)), bottom: .None(.None(.None)))
                } else if hasReplyMarkup, case let .linear(top, _) = updatedPosition {
                    updatedPosition = .linear(top: top, bottom: .Neighbour)
                }
                
                let imageCorners = chatMessageBubbleImageContentCorners(relativeContentPosition: updatedPosition, normalRadius: layoutConstants.image.defaultCornerRadius, mergedRadius: layoutConstants.image.mergedCornerRadius, mergedWithAnotherContentRadius: layoutConstants.image.contentMergedCornerRadius)
                
                let (refinedWidth, finishLayout) = refineLayout(CGSize(width: constrainedSize.width - bubbleInsets.left - bubbleInsets.right, height: constrainedSize.height), automaticPlayback, wideLayout, imageCorners)
                
                return (refinedWidth + bubbleInsets.left + bubbleInsets.right, { boundingWidth in
                    let (imageSize, imageApply) = finishLayout(boundingWidth - bubbleInsets.left - bubbleInsets.right)
                    
                    var edited = false
                    var viewCount: Int?
                    for attribute in item.message.attributes {
                        if let attribute = attribute as? EditedMessageAttribute {
                            if case .mosaic = preparePosition {
                            } else {
                                edited = !attribute.isHidden
                            }
                        } else if let attribute = attribute as? ViewCountMessageAttribute {
                            viewCount = attribute.count
                        }
                    }
                    
                    var dateReactions: [MessageReaction] = []
                    var dateReactionCount = 0
                    if let reactionsAttribute = mergedMessageReactions(attributes: item.message.attributes), !reactionsAttribute.reactions.isEmpty {
                        for reaction in reactionsAttribute.reactions {
                            if reaction.isSelected {
                                dateReactions.insert(reaction, at: 0)
                            } else {
                                dateReactions.append(reaction)
                            }
                            dateReactionCount += Int(reaction.count)
                        }
                    }
                    
                    let dateText = stringForMessageTimestampStatus(accountPeerId: item.context.account.peerId, message: item.message, dateTimeFormat: item.presentationData.dateTimeFormat, nameDisplayOrder: item.presentationData.nameDisplayOrder, strings: item.presentationData.strings, reactionCount: dateReactionCount)
                    
                    let statusType: ChatMessageDateAndStatusType?
                    switch position {
                        case .linear(_, .None):
                            if item.message.effectivelyIncoming(item.context.account.peerId) {
                                statusType = .ImageIncoming
                            } else {
                                if item.message.flags.contains(.Failed) {
                                    statusType = .ImageOutgoing(.Failed)
                                } else if item.message.flags.isSending && !item.message.isSentOrAcknowledged {
                                    statusType = .ImageOutgoing(.Sending)
                                } else {
                                    statusType = .ImageOutgoing(.Sent(read: item.read))
                                }
                            }
                        case .mosaic:
                            statusType = nil
                        default:
                            statusType = nil
                    }
                    
                    let imageLayoutSize = CGSize(width: imageSize.width + bubbleInsets.left + bubbleInsets.right, height: imageSize.height + bubbleInsets.top + bubbleInsets.bottom)
                    
                    var statusSize = CGSize()
                    var statusApply: ((Bool) -> Void)?
                    
                    if let statusType = statusType {
                        let (size, apply) = statusLayout(item.context, item.presentationData, edited, viewCount, dateText, statusType, CGSize(width: imageSize.width - 30.0, height: CGFloat.greatestFiniteMagnitude), dateReactions)
                        statusSize = size
                        statusApply = apply
                    }
                    
                    var layoutWidth = imageLayoutSize.width
                    if case .constrained = sizeCalculation {
                        layoutWidth = max(layoutWidth, statusSize.width + bubbleInsets.left + bubbleInsets.right + layoutConstants.image.statusInsets.left + layoutConstants.image.statusInsets.right)
                    }
                    
                    let layoutSize = CGSize(width: layoutWidth, height: imageLayoutSize.height)
                    
                    return (layoutSize, { [weak self] animation, synchronousLoads in
                        if let strongSelf = self {
                            strongSelf.item = item
                            strongSelf.media = selectedMedia
                            strongSelf.automaticPlayback = automaticPlayback
                            
                            let imageFrame = CGRect(origin: CGPoint(x: bubbleInsets.left, y: bubbleInsets.top), size: imageSize)
                            var transition: ContainedViewLayoutTransition = .immediate
                            if case let .System(duration) = animation {
                                transition = .animated(duration: duration, curve: .spring)
                            }
                            
                            transition.updateFrame(node: strongSelf.interactiveImageNode, frame: imageFrame)
                            
                            if let statusApply = statusApply {
                                if strongSelf.dateAndStatusNode.supernode == nil {
                                    strongSelf.interactiveImageNode.addSubnode(strongSelf.dateAndStatusNode)
                                }
                                var hasAnimation = true
                                if case .None = animation {
                                    hasAnimation = false
                                }
                                statusApply(hasAnimation)
 
                                let dateAndStatusFrame = CGRect(origin: CGPoint(x: layoutSize.width - bubbleInsets.right - layoutConstants.image.statusInsets.right - statusSize.width, y: layoutSize.height -  bubbleInsets.bottom - layoutConstants.image.statusInsets.bottom - statusSize.height), size: statusSize)
                                
                                strongSelf.dateAndStatusNode.frame = dateAndStatusFrame
                                strongSelf.dateAndStatusNode.bounds = CGRect(origin: CGPoint(), size: dateAndStatusFrame.size)
                            } else if strongSelf.dateAndStatusNode.supernode != nil {
                                strongSelf.dateAndStatusNode.removeFromSupernode()
                            }
                            
                            imageApply(transition, synchronousLoads)
                            
                            if let selection = selection {
                                if let selectionNode = strongSelf.selectionNode {
                                    selectionNode.frame = imageFrame
                                    selectionNode.updateSelected(selection, animated: animation.isAnimated)
                                } else {
                                    let selectionNode = GridMessageSelectionNode(theme: item.presentationData.theme.theme, toggle: { value in
                                        item.controllerInteraction.toggleMessagesSelection([item.message.id], value)
                                    })
                                    strongSelf.selectionNode = selectionNode
                                    strongSelf.addSubnode(selectionNode)
                                    selectionNode.frame = imageFrame
                                    selectionNode.updateSelected(selection, animated: false)
                                    if animation.isAnimated {
                                        selectionNode.animateIn()
                                    }
                                }
                            } else if let selectionNode = strongSelf.selectionNode {
                                strongSelf.selectionNode = nil
                                if animation.isAnimated {
                                    selectionNode.animateOut(completion: { [weak selectionNode] in
                                        selectionNode?.removeFromSupernode()
                                    })
                                } else {
                                    selectionNode.removeFromSupernode()
                                }
                            }
                        }
                    })
                })
            })
        }
    }
    
    override func transitionNode(messageId: MessageId, media: Media) -> (ASDisplayNode, CGRect, () -> (UIView?, UIView?))? {
        if self.item?.message.id == messageId, let currentMedia = self.media, currentMedia.isSemanticallyEqual(to: media) {
            return self.interactiveImageNode.transitionNode()
        }
        return nil
    }
    
    override func peekPreviewContent(at point: CGPoint) -> (Message, ChatMessagePeekPreviewContent)? {
        if let message = self.item?.message, let currentMedia = self.media, !message.containsSecretMedia {
            if self.interactiveImageNode.frame.contains(point), self.interactiveImageNode.isReadyForInteractivePreview() {
                return (message, .media(currentMedia))
            }
        }
        return nil
    }
    
    override func updateHiddenMedia(_ media: [Media]?) -> Bool {
        var mediaHidden = false
        if let currentMedia = self.media, let media = media {
            for item in media {
                if item.isSemanticallyEqual(to: currentMedia) {
                    mediaHidden = true
                    break
                }
            }
        }
        
        self.interactiveImageNode.isHidden = mediaHidden
        self.interactiveImageNode.updateIsHidden(mediaHidden)
        
        if let automaticPlayback = self.automaticPlayback {
            if !automaticPlayback {
                self.dateAndStatusNode.isHidden = false
            } else if self.dateAndStatusNode.isHidden != mediaHidden {
                if mediaHidden {
                    self.dateAndStatusNode.isHidden = true
                } else {
                    self.dateAndStatusNode.isHidden = false
                    self.dateAndStatusNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                }
            }
        }
        
        return mediaHidden
    }
    
    override func playMediaWithSound() -> ((Double?) -> Void, Bool, Bool, Bool, ASDisplayNode?)? {
        return self.interactiveImageNode.playMediaWithSound()
    }
    
    override func tapActionAtPoint(_ point: CGPoint, gesture: TapLongTapOrDoubleTapGesture) -> ChatMessageBubbleContentTapAction {
        return .none
    }
    
    override func animateInsertion(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
    }
    
    override func animateAdded(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
    }
    
    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.25, removeOnCompletion: false)
    }
    
    override func animateInsertionIntoBubble(_ duration: Double) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
    }
    
    override func updateHighlightedState(animated: Bool) -> Bool {
        guard let item = self.item else {
            return false
        }
        let highlighted = item.controllerInteraction.highlightedState?.messageStableId == item.message.stableId
        
        if self.highlightedState != highlighted {
            self.highlightedState = highlighted
            
            if highlighted {
                self.interactiveImageNode.setOverlayColor(item.presentationData.theme.theme.chat.message.mediaHighlightOverlayColor, animated: false)
            } else {
                self.interactiveImageNode.setOverlayColor(nil, animated: animated)
            }
        }
        
        return false
    }
    
    override func reactionTargetNode(value: String) -> (ASDisplayNode, Int)? {
        if !self.dateAndStatusNode.isHidden {
            return self.dateAndStatusNode.reactionNode(value: value)
        }
        return nil
    }
}
