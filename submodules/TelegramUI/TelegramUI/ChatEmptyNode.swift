import Foundation
import UIKit
import AsyncDisplayKit
import Display
import Postbox
import TelegramCore
import SyncCore
import TelegramPresentationData
import AppBundle
import LocalizedPeerData

private protocol ChatEmptyNodeContent {
    func updateLayout(interfaceState: ChatPresentationInterfaceState, size: CGSize, transition: ContainedViewLayoutTransition) -> CGSize
}

private let titleFont = Font.medium(15.0)
private let messageFont = Font.regular(14.0)

private final class ChatEmptyNodeRegularChatContent: ASDisplayNode, ChatEmptyNodeContent {
    private let textNode: ImmediateTextNode
    
    private var currentTheme: PresentationTheme?
    private var currentStrings: PresentationStrings?
    
    override init() {
        self.textNode = ImmediateTextNode()
        
        super.init()
        
        self.addSubnode(self.textNode)
    }
    
    func updateLayout(interfaceState: ChatPresentationInterfaceState, size: CGSize, transition: ContainedViewLayoutTransition) -> CGSize {
        if self.currentTheme !== interfaceState.theme || self.currentStrings !== interfaceState.strings {
            self.currentTheme = interfaceState.theme
            self.currentStrings = interfaceState.strings
            
            let serviceColor = serviceMessageColorComponents(theme: interfaceState.theme, wallpaper: interfaceState.chatWallpaper)
            self.textNode.attributedText = NSAttributedString(string: interfaceState.isScheduledMessages ? interfaceState.strings.ScheduledMessages_EmptyPlaceholder : interfaceState.strings.Conversation_EmptyPlaceholder, font: messageFont, textColor: serviceColor.primaryText)
        }
        
        let insets = UIEdgeInsets(top: 6.0, left: 10.0, bottom: 6.0, right: 10.0)
        
        let textSize = self.textNode.updateLayout(CGSize(width: size.width - insets.left - insets.right, height: CGFloat.greatestFiniteMagnitude))
        
        let contentWidth = textSize.width
        let contentHeight = textSize.height
        let contentRect = CGRect(origin: CGPoint(x: insets.left, y: insets.top), size: CGSize(width: contentWidth, height: contentHeight))
        
        transition.updateFrame(node: self.textNode, frame: CGRect(origin: CGPoint(x: contentRect.minX + floor((contentRect.width - textSize.width) / 2.0), y: insets.top), size: textSize))
        
        return contentRect.insetBy(dx: -insets.left, dy: -insets.top).size
    }
}

private final class ChatEmptyNodeSecretChatContent: ASDisplayNode, ChatEmptyNodeContent {
    private let titleNode: ImmediateTextNode
    private let subtitleNode: ImmediateTextNode
    private var lineNodes: [(ASImageNode, ImmediateTextNode)] = []
    
    private var currentTheme: PresentationTheme?
    private var currentStrings: PresentationStrings?
    
    override init() {
        self.titleNode = ImmediateTextNode()
        self.titleNode.maximumNumberOfLines = 0
        self.titleNode.lineSpacing = 0.25
        self.titleNode.textAlignment = .center
        self.titleNode.isUserInteractionEnabled = false
        self.titleNode.displaysAsynchronously = false
        
        self.subtitleNode = ImmediateTextNode()
        self.subtitleNode.maximumNumberOfLines = 0
        self.subtitleNode.lineSpacing = 0.25
        self.subtitleNode.isUserInteractionEnabled = false
        self.subtitleNode.displaysAsynchronously = false
        
        super.init()
        
        self.addSubnode(self.titleNode)
        self.addSubnode(self.subtitleNode)
    }
    
    func updateLayout(interfaceState: ChatPresentationInterfaceState, size: CGSize, transition: ContainedViewLayoutTransition) -> CGSize {
        if self.currentTheme !== interfaceState.theme || self.currentStrings !== interfaceState.strings {
            self.currentTheme = interfaceState.theme
            self.currentStrings = interfaceState.strings
            
            var title = " "
            var incoming = false
            if let renderedPeer = interfaceState.renderedPeer {
                if let chatPeer = renderedPeer.peers[renderedPeer.peerId] as? TelegramSecretChat {
                    if case .participant = chatPeer.role {
                        incoming = true
                    }
                    if let user = renderedPeer.peers[chatPeer.regularPeerId] {
                        title = user.compactDisplayTitle
                    }
                }
            }
            
            let titleString: String
            if incoming {
                titleString = interfaceState.strings.Conversation_EncryptedPlaceholderTitleIncoming(title).0
            } else {
                titleString = interfaceState.strings.Conversation_EncryptedPlaceholderTitleOutgoing(title).0
            }
            
            let serviceColor = serviceMessageColorComponents(theme: interfaceState.theme, wallpaper: interfaceState.chatWallpaper)
            
            self.titleNode.attributedText = NSAttributedString(string: titleString, font: titleFont, textColor: serviceColor.primaryText)
            
            self.subtitleNode.attributedText = NSAttributedString(string: interfaceState.strings.Conversation_EncryptedDescriptionTitle, font: messageFont, textColor: serviceColor.primaryText)
            
            let strings: [String] = [
                interfaceState.strings.Conversation_EncryptedDescription1,
                interfaceState.strings.Conversation_EncryptedDescription2,
                interfaceState.strings.Conversation_EncryptedDescription3,
                interfaceState.strings.Conversation_EncryptedDescription4
            ]
            
            let lines: [NSAttributedString] = strings.map { NSAttributedString(string: $0, font: messageFont, textColor: serviceColor.primaryText) }
            
            let graphics = PresentationResourcesChat.additionalGraphics(interfaceState.theme, wallpaper: interfaceState.chatWallpaper)
            let lockIcon = graphics.chatEmptyItemLockIcon
            
            for i in 0 ..< lines.count {
                if i >= self.lineNodes.count {
                    let iconNode = ASImageNode()
                    iconNode.isLayerBacked = true
                    iconNode.displaysAsynchronously = false
                    iconNode.displayWithoutProcessing = true
                    let textNode = ImmediateTextNode()
                    textNode.maximumNumberOfLines = 0
                    textNode.isUserInteractionEnabled = false
                    textNode.displaysAsynchronously = false
                    self.addSubnode(iconNode)
                    self.addSubnode(textNode)
                    self.lineNodes.append((iconNode, textNode))
                }
                
                self.lineNodes[i].0.image = lockIcon
                self.lineNodes[i].1.attributedText = lines[i]
            }
        }
        
        let insets = UIEdgeInsets(top: 15.0, left: 15.0, bottom: 15.0, right: 15.0)
        let titleSpacing: CGFloat = 5.0
        let subtitleSpacing: CGFloat = 11.0
        let iconInset: CGFloat = 14.0
        
        var contentWidth: CGFloat = 100.0
        var contentHeight: CGFloat = 0.0
        
        var lineNodes: [(CGSize, ASImageNode, ImmediateTextNode)] = []
        for (iconNode, textNode) in self.lineNodes {
            let textSize = textNode.updateLayout(CGSize(width: size.width - insets.left - insets.right - 10.0, height: CGFloat.greatestFiniteMagnitude))
            contentWidth = max(contentWidth, iconInset + textSize.width)
            contentHeight += textSize.height + subtitleSpacing
            lineNodes.append((textSize, iconNode, textNode))
        }
        
        let titleSize = self.titleNode.updateLayout(CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude))
        let subtitleSize = self.subtitleNode.updateLayout(CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude))
        
        contentWidth = max(contentWidth, max(titleSize.width, subtitleSize.width))
        
        contentHeight += titleSize.height + titleSpacing + subtitleSize.height
        
        let contentRect = CGRect(origin: CGPoint(x: insets.left, y: insets.top), size: CGSize(width: contentWidth, height: contentHeight))
        
        let titleFrame = CGRect(origin: CGPoint(x: contentRect.minX + floor((contentRect.width - titleSize.width) / 2.0), y: contentRect.minY), size: titleSize)
        transition.updateFrame(node: self.titleNode, frame: titleFrame)
        let subtitleFrame = CGRect(origin: CGPoint(x: contentRect.minX, y: titleFrame.maxY + titleSpacing), size: subtitleSize)
        transition.updateFrame(node: self.subtitleNode, frame: subtitleFrame)
        
        var lineOffset = subtitleFrame.maxY + subtitleSpacing / 2.0
        for (textSize, iconNode, textNode) in lineNodes {
            if let image = iconNode.image {
                transition.updateFrame(node: iconNode, frame: CGRect(origin: CGPoint(x: contentRect.minX, y: lineOffset + 1.0), size: image.size))
            }
            transition.updateFrame(node: textNode, frame: CGRect(origin: CGPoint(x: contentRect.minX + iconInset, y: lineOffset), size: textSize))
            lineOffset += textSize.height + subtitleSpacing
        }
        
        return contentRect.insetBy(dx: -insets.left, dy: -insets.top).size
    }
}

private final class ChatEmptyNodeGroupChatContent: ASDisplayNode, ChatEmptyNodeContent {
    private let titleNode: ImmediateTextNode
    private let subtitleNode: ImmediateTextNode
    private var lineNodes: [(ASImageNode, ImmediateTextNode)] = []
    
    private var currentTheme: PresentationTheme?
    private var currentStrings: PresentationStrings?
    
    override init() {
        self.titleNode = ImmediateTextNode()
        self.titleNode.maximumNumberOfLines = 0
        self.titleNode.lineSpacing = 0.25
        self.titleNode.textAlignment = .center
        self.titleNode.isUserInteractionEnabled = false
        self.titleNode.displaysAsynchronously = false
        
        self.subtitleNode = ImmediateTextNode()
        self.subtitleNode.maximumNumberOfLines = 0
        self.subtitleNode.lineSpacing = 0.25
        self.subtitleNode.isUserInteractionEnabled = false
        self.subtitleNode.displaysAsynchronously = false
        
        super.init()
        
        self.addSubnode(self.titleNode)
        self.addSubnode(self.subtitleNode)
    }
    
    func updateLayout(interfaceState: ChatPresentationInterfaceState, size: CGSize, transition: ContainedViewLayoutTransition) -> CGSize {
        if self.currentTheme !== interfaceState.theme || self.currentStrings !== interfaceState.strings {
            self.currentTheme = interfaceState.theme
            self.currentStrings = interfaceState.strings
            
            let titleString: String = interfaceState.strings.EmptyGroupInfo_Title
            
            let serviceColor = serviceMessageColorComponents(theme: interfaceState.theme, wallpaper: interfaceState.chatWallpaper)
            
            self.titleNode.attributedText = NSAttributedString(string: titleString, font: titleFont, textColor: serviceColor.primaryText)
            
            self.subtitleNode.attributedText = NSAttributedString(string: interfaceState.strings.EmptyGroupInfo_Subtitle, font: messageFont, textColor: serviceColor.primaryText)
            
            let strings: [String] = [
                interfaceState.strings.EmptyGroupInfo_Line1("\(interfaceState.limitsConfiguration.maxSupergroupMemberCount)").0,
                interfaceState.strings.EmptyGroupInfo_Line2,
                interfaceState.strings.EmptyGroupInfo_Line3,
                interfaceState.strings.EmptyGroupInfo_Line4
            ]
            
            let lines: [NSAttributedString] = strings.map { NSAttributedString(string: $0, font: messageFont, textColor: serviceColor.primaryText) }
            
            let graphics = PresentationResourcesChat.additionalGraphics(interfaceState.theme, wallpaper: interfaceState.chatWallpaper)
            let lockIcon = graphics.emptyChatListCheckIcon
            
            for i in 0 ..< lines.count {
                if i >= self.lineNodes.count {
                    let iconNode = ASImageNode()
                    iconNode.isLayerBacked = true
                    iconNode.displaysAsynchronously = false
                    iconNode.displayWithoutProcessing = true
                    let textNode = ImmediateTextNode()
                    textNode.maximumNumberOfLines = 0
                    textNode.isUserInteractionEnabled = false
                    textNode.displaysAsynchronously = false
                    self.addSubnode(iconNode)
                    self.addSubnode(textNode)
                    self.lineNodes.append((iconNode, textNode))
                }
                
                self.lineNodes[i].0.image = lockIcon
                self.lineNodes[i].1.attributedText = lines[i]
            }
        }
        
        let insets = UIEdgeInsets(top: 15.0, left: 15.0, bottom: 15.0, right: 15.0)
        let titleSpacing: CGFloat = 5.0
        let subtitleSpacing: CGFloat = 11.0
        let iconInset: CGFloat = 19.0
        
        var contentWidth: CGFloat = 100.0
        var contentHeight: CGFloat = 0.0
        
        var lineNodes: [(CGSize, ASImageNode, ImmediateTextNode)] = []
        for (iconNode, textNode) in self.lineNodes {
            let textSize = textNode.updateLayout(CGSize(width: size.width - insets.left - insets.right - 10.0, height: CGFloat.greatestFiniteMagnitude))
            contentWidth = max(contentWidth, iconInset + textSize.width)
            contentHeight += textSize.height + subtitleSpacing
            lineNodes.append((textSize, iconNode, textNode))
        }
        
        let titleSize = self.titleNode.updateLayout(CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude))
        let subtitleSize = self.subtitleNode.updateLayout(CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude))
        
        contentWidth = max(contentWidth, max(titleSize.width, subtitleSize.width))
        
        contentHeight += titleSize.height + titleSpacing + subtitleSize.height
        
        let contentRect = CGRect(origin: CGPoint(x: insets.left, y: insets.top), size: CGSize(width: contentWidth, height: contentHeight))
        
        let titleFrame = CGRect(origin: CGPoint(x: contentRect.minX + floor((contentRect.width - titleSize.width) / 2.0), y: contentRect.minY), size: titleSize)
        transition.updateFrame(node: self.titleNode, frame: titleFrame)
        let subtitleFrame = CGRect(origin: CGPoint(x: contentRect.minX, y: titleFrame.maxY + titleSpacing), size: subtitleSize)
        transition.updateFrame(node: self.subtitleNode, frame: subtitleFrame)
        
        var lineOffset = subtitleFrame.maxY + subtitleSpacing / 2.0
        for (textSize, iconNode, textNode) in lineNodes {
            if let image = iconNode.image {
                transition.updateFrame(node: iconNode, frame: CGRect(origin: CGPoint(x: contentRect.minX, y: lineOffset + 2.0), size: image.size))
            }
            transition.updateFrame(node: textNode, frame: CGRect(origin: CGPoint(x: contentRect.minX + iconInset, y: lineOffset), size: textSize))
            lineOffset += textSize.height + subtitleSpacing
        }
        
        return contentRect.insetBy(dx: -insets.left, dy: -insets.top).size
    }
}

private final class ChatEmptyNodeCloudChatContent: ASDisplayNode, ChatEmptyNodeContent {
    private let iconNode: ASImageNode
    private let titleNode: ImmediateTextNode
    private var lineNodes: [ImmediateTextNode] = []
    
    private var currentTheme: PresentationTheme?
    private var currentStrings: PresentationStrings?
    
    override init() {
        self.iconNode = ASImageNode()
        self.iconNode.isLayerBacked = true
        self.iconNode.displaysAsynchronously = false
        self.iconNode.displayWithoutProcessing = true
        
        self.titleNode = ImmediateTextNode()
        self.titleNode.maximumNumberOfLines = 0
        self.titleNode.lineSpacing = 0.15
        self.titleNode.textAlignment = .center
        self.titleNode.isUserInteractionEnabled = false
        self.titleNode.displaysAsynchronously = false
        
        super.init()
        
        self.addSubnode(self.iconNode)
        self.addSubnode(self.titleNode)
    }
    
    func updateLayout(interfaceState: ChatPresentationInterfaceState, size: CGSize, transition: ContainedViewLayoutTransition) -> CGSize {
        if self.currentTheme !== interfaceState.theme || self.currentStrings !== interfaceState.strings {
            self.currentTheme = interfaceState.theme
            self.currentStrings = interfaceState.strings
            
            let serviceColor = serviceMessageColorComponents(theme: interfaceState.theme, wallpaper: interfaceState.chatWallpaper)
            
            self.iconNode.image = generateTintedImage(image: UIImage(bundleImageName: "Chat/Empty Chat/Cloud"), color: serviceColor.primaryText)
            
            let titleString = interfaceState.strings.Conversation_CloudStorageInfo_Title
            self.titleNode.attributedText = NSAttributedString(string: titleString, font: titleFont, textColor: serviceColor.primaryText)
            
            let strings: [String] = [
                interfaceState.strings.Conversation_ClousStorageInfo_Description1,
                interfaceState.strings.Conversation_ClousStorageInfo_Description2,
                interfaceState.strings.Conversation_ClousStorageInfo_Description3,
                interfaceState.strings.Conversation_ClousStorageInfo_Description4
            ]
            
            let lines: [NSAttributedString] = strings.map { NSAttributedString(string: $0, font: messageFont, textColor: serviceColor.primaryText) }
            
            for i in 0 ..< lines.count {
                if i >= self.lineNodes.count {
                    let textNode = ImmediateTextNode()
                    textNode.maximumNumberOfLines = 0
                    textNode.isUserInteractionEnabled = false
                    textNode.displaysAsynchronously = false
                    self.addSubnode(textNode)
                    self.lineNodes.append(textNode)
                }
                
                self.lineNodes[i].attributedText = lines[i]
            }
        }
        
        let insets = UIEdgeInsets(top: 15.0, left: 15.0, bottom: 15.0, right: 15.0)
        
        let imageSpacing: CGFloat = 12.0
        let titleSpacing: CGFloat = 4.0
        
        var contentWidth: CGFloat = 100.0
        var contentHeight: CGFloat = 0.0
        
        if let image = self.iconNode.image {
            contentHeight += image.size.height
            contentHeight += imageSpacing
            contentWidth = max(contentWidth, image.size.width)
        }
        
        var lineNodes: [(CGSize, ImmediateTextNode)] = []
        for textNode in self.lineNodes {
            let textSize = textNode.updateLayout(CGSize(width: size.width - insets.left - insets.right - 10.0, height: CGFloat.greatestFiniteMagnitude))
            contentWidth = max(contentWidth, textSize.width)
            contentHeight += textSize.height + titleSpacing
            lineNodes.append((textSize, textNode))
        }
        
        let titleSize = self.titleNode.updateLayout(CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude))
        
        contentWidth = max(contentWidth, titleSize.width)
        
        contentHeight += titleSize.height + titleSpacing
        
        var imageAreaHeight: CGFloat = 0.0
        if let image = self.iconNode.image {
            imageAreaHeight += image.size.height
            imageAreaHeight += imageSpacing
            transition.updateFrame(node: self.iconNode, frame: CGRect(origin: CGPoint(x: insets.left + floor((contentWidth - image.size.width) / 2.0), y: insets.top), size: image.size))
        }
        
        let contentRect = CGRect(origin: CGPoint(x: insets.left, y: insets.top + imageAreaHeight), size: CGSize(width: contentWidth, height: contentHeight))
        
        let titleFrame = CGRect(origin: CGPoint(x: contentRect.minX + floor((contentRect.width - titleSize.width) / 2.0), y: contentRect.minY), size: titleSize)
        transition.updateFrame(node: self.titleNode, frame: titleFrame)
        
        var lineOffset = titleFrame.maxY + titleSpacing
        for (textSize, textNode) in lineNodes {
            let isRTL = textNode.cachedLayout?.hasRTL ?? false
            transition.updateFrame(node: textNode, frame: CGRect(origin: CGPoint(x: isRTL ? contentRect.maxX - textSize.width : contentRect.minX, y: lineOffset), size: textSize))
            lineOffset += textSize.height + 4.0
        }
        
        return contentRect.insetBy(dx: -insets.left, dy: -insets.top).size
    }
}

private enum ChatEmptyNodeContentType {
    case regular
    case secret
    case group
    case cloud
}

final class ChatEmptyNode: ASDisplayNode {
    private let accountPeerId: PeerId
    
    private let backgroundNode: ASImageNode
    
    private var currentTheme: PresentationTheme?
    private var currentStrings: PresentationStrings?
    
    private var content: (ChatEmptyNodeContentType, ASDisplayNode & ChatEmptyNodeContent)?
    
    init(accountPeerId: PeerId) {
        self.accountPeerId = accountPeerId
        
        self.backgroundNode = ASImageNode()
        self.backgroundNode.isLayerBacked = true
        self.backgroundNode.displayWithoutProcessing = true
        self.backgroundNode.displaysAsynchronously = false
        
        super.init()
        
        self.isUserInteractionEnabled = false
        
        self.addSubnode(self.backgroundNode)
    }
    
    func updateLayout(interfaceState: ChatPresentationInterfaceState, size: CGSize, insets: UIEdgeInsets, transition: ContainedViewLayoutTransition) {
        if self.currentTheme !== interfaceState.theme || self.currentStrings !== interfaceState.strings {
            self.currentTheme = interfaceState.theme
            self.currentStrings = interfaceState.strings
            
            let graphics = PresentationResourcesChat.additionalGraphics(interfaceState.theme, wallpaper: interfaceState.chatWallpaper)
            self.backgroundNode.image = graphics.chatEmptyItemBackgroundImage
        }
        
        let contentType: ChatEmptyNodeContentType
        if let peer = interfaceState.renderedPeer?.peer, !interfaceState.isScheduledMessages {
            if peer.id == self.accountPeerId {
                contentType = .cloud
            } else if let _ = peer as? TelegramSecretChat {
                contentType = .secret
            } else if let group = peer as? TelegramGroup, case .creator = group.role {
                contentType = .group
            } else if let channel = peer as? TelegramChannel, case .group = channel.info, channel.flags.contains(.isCreator) {
                contentType = .group
            } else {
                contentType = .regular
            }
        } else {
            contentType = .regular
        }
        
        var contentTransition = transition
        if self.content?.0 != contentType {
            if let node = self.content?.1 {
                node.removeFromSupernode()
            }
            let node: ASDisplayNode & ChatEmptyNodeContent
            switch contentType {
                case .regular:
                    node = ChatEmptyNodeRegularChatContent()
                case .secret:
                    node = ChatEmptyNodeSecretChatContent()
                case .group:
                    node = ChatEmptyNodeGroupChatContent()
                case .cloud:
                    node = ChatEmptyNodeCloudChatContent()
            }
            self.content = (contentType, node)
            self.addSubnode(node)
            contentTransition = .immediate
        }
        
        let displayRect = CGRect(origin: CGPoint(x: 0.0, y: insets.top), size: CGSize(width: size.width, height: size.height - insets.top - insets.bottom))
        
        var contentSize = CGSize()
        if let contentNode = self.content?.1 {
            contentSize = contentNode.updateLayout(interfaceState: interfaceState, size: displayRect.size, transition: contentTransition)
        }
        
        let contentFrame = CGRect(origin: CGPoint(x: displayRect.minX + floor((displayRect.width - contentSize.width) / 2.0), y: displayRect.minY + floor((displayRect.height - contentSize.height) / 2.0)), size: contentSize)
        if let contentNode = self.content?.1 {
            contentTransition.updateFrame(node: contentNode, frame: contentFrame)
        }
        
        transition.updateFrame(node: self.backgroundNode, frame: contentFrame)
    }
}


