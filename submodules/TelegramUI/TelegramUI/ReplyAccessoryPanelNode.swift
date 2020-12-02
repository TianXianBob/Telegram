import Foundation
import UIKit
import AsyncDisplayKit
import TelegramCore
import SyncCore
import Postbox
import SwiftSignalKit
import Display
import TelegramPresentationData
import TelegramUIPreferences
import AccountContext
import LocalizedPeerData
import PhotoResources
import TelegramStringFormatting

final class ReplyAccessoryPanelNode: AccessoryPanelNode {
    private let messageDisposable = MetaDisposable()
    let messageId: MessageId
    
    private var previousMediaReference: AnyMediaReference?
    
    let closeButton: ASButtonNode
    let lineNode: ASImageNode
    let titleNode: ImmediateTextNode
    let textNode: ImmediateTextNode
    let imageNode: TransformImageNode
    
    private let actionArea: AccessibilityAreaNode
    
    var theme: PresentationTheme
    
    init(context: AccountContext, messageId: MessageId, theme: PresentationTheme, strings: PresentationStrings, nameDisplayOrder: PresentationPersonNameOrder) {
        self.messageId = messageId
        
        self.theme = theme
        
        self.closeButton = ASButtonNode()
        self.closeButton.accessibilityLabel = strings.VoiceOver_DiscardPreparedContent
        self.closeButton.hitTestSlop = UIEdgeInsets(top: -8.0, left: -8.0, bottom: -8.0, right: -8.0)
        self.closeButton.setImage(PresentationResourcesChat.chatInputPanelCloseIconImage(theme), for: [])
        self.closeButton.displaysAsynchronously = false
        
        self.lineNode = ASImageNode()
        self.lineNode.displayWithoutProcessing = true
        self.lineNode.displaysAsynchronously = false
        self.lineNode.image = PresentationResourcesChat.chatInputPanelVerticalSeparatorLineImage(theme)
        
        self.titleNode = ImmediateTextNode()
        self.titleNode.maximumNumberOfLines = 1
        self.titleNode.displaysAsynchronously = false
        
        self.textNode = ImmediateTextNode()
        self.textNode.maximumNumberOfLines = 1
        self.textNode.displaysAsynchronously = false
        
        self.imageNode = TransformImageNode()
        self.imageNode.contentAnimations = [.subsequentUpdates]
        self.imageNode.isHidden = true
        
        self.actionArea = AccessibilityAreaNode()
        
        super.init()
        
        self.closeButton.addTarget(self, action: #selector(self.closePressed), forControlEvents: [.touchUpInside])
        self.addSubnode(self.closeButton)
        
        self.addSubnode(self.lineNode)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.textNode)
        self.addSubnode(self.imageNode)
        self.addSubnode(self.actionArea)
        
        self.messageDisposable.set((context.account.postbox.messageAtId(messageId)
        |> deliverOnMainQueue).start(next: { [weak self] message in
            if let strongSelf = self {
                var authorName = ""
                var text = ""
                if let author = message?.effectiveAuthor {
                    authorName = author.displayTitle(strings: strings, displayOrder: nameDisplayOrder)
                }
                if let message = message {
                    (text, _) = descriptionStringForMessage(contentSettings: context.currentContentSettings.with { $0 }, message: message, strings: strings, nameDisplayOrder: nameDisplayOrder, accountPeerId: context.account.peerId)
                }
                
                var updatedMediaReference: AnyMediaReference?
                var imageDimensions: CGSize?
                var isRoundImage = false
                if let message = message, !message.containsSecretMedia {
                    for media in message.media {
                        if let image = media as? TelegramMediaImage {
                            updatedMediaReference = .message(message: MessageReference(message), media: image)
                            if let representation = largestRepresentationForPhoto(image) {
                                imageDimensions = representation.dimensions.cgSize
                            }
                            break
                        } else if let file = media as? TelegramMediaFile {
                            updatedMediaReference = .message(message: MessageReference(message), media: file)
                            isRoundImage = file.isInstantVideo
                            if let representation = largestImageRepresentation(file.previewRepresentations), !file.isSticker && !file.isAnimatedSticker {
                                imageDimensions = representation.dimensions.cgSize
                            }
                            break
                        }
                    }
                }
                
                let imageNodeLayout = strongSelf.imageNode.asyncLayout()
                var applyImage: (() -> Void)?
                if let imageDimensions = imageDimensions {
                    let boundingSize = CGSize(width: 35.0, height: 35.0)
                    var radius: CGFloat = 2.0
                    var imageSize = imageDimensions.aspectFilled(boundingSize)
                    if isRoundImage {
                        radius = floor(boundingSize.width / 2.0)
                        imageSize.width += 2.0
                        imageSize.height += 2.0
                    }
                    applyImage = imageNodeLayout(TransformImageArguments(corners: ImageCorners(radius: radius), imageSize: imageSize, boundingSize: boundingSize, intrinsicInsets: UIEdgeInsets()))
                }
                
                var mediaUpdated = false
                if let updatedMediaReference = updatedMediaReference, let previousMediaReference = strongSelf.previousMediaReference {
                    mediaUpdated = !updatedMediaReference.media.isEqual(to: previousMediaReference.media)
                } else if (updatedMediaReference != nil) != (strongSelf.previousMediaReference != nil) {
                    mediaUpdated = true
                }
                strongSelf.previousMediaReference = updatedMediaReference
                
                var updateImageSignal: Signal<(TransformImageArguments) -> DrawingContext?, NoError>?
                if mediaUpdated {
                    if let updatedMediaReference = updatedMediaReference, imageDimensions != nil {
                        if let imageReference = updatedMediaReference.concrete(TelegramMediaImage.self) {
                            updateImageSignal = chatMessagePhotoThumbnail(account: context.account, photoReference: imageReference)
                        } else if let fileReference = updatedMediaReference.concrete(TelegramMediaFile.self) {
                            if fileReference.media.isVideo {
                                updateImageSignal = chatMessageVideoThumbnail(account: context.account, fileReference: fileReference)
                            } else if let iconImageRepresentation = smallestImageRepresentation(fileReference.media.previewRepresentations) {
                                updateImageSignal = chatWebpageSnippetFile(account: context.account, fileReference: fileReference, representation: iconImageRepresentation)
                            }
                        }
                    } else {
                        updateImageSignal = .single({ _ in return nil })
                    }
                }
                
                let isMedia: Bool
                if let message = message {
                    switch messageContentKind(contentSettings: context.currentContentSettings.with { $0 }, message: message, strings: strings, nameDisplayOrder: nameDisplayOrder, accountPeerId: context.account.peerId) {
                        case .text:
                            isMedia = false
                        default:
                            isMedia = true
                    }
                } else {
                    isMedia = false
                }
                
                strongSelf.titleNode.attributedText = NSAttributedString(string: authorName, font: Font.medium(15.0), textColor: strongSelf.theme.chat.inputPanel.panelControlAccentColor)
                strongSelf.textNode.attributedText = NSAttributedString(string: text, font: Font.regular(15.0), textColor: isMedia ? strongSelf.theme.chat.inputPanel.secondaryTextColor : strongSelf.theme.chat.inputPanel.primaryTextColor)
                
                let headerString: String
                if let message = message, message.flags.contains(.Incoming), let author = message.author {
                    headerString = "Reply to message. From: \(author.displayTitle(strings: strings, displayOrder: nameDisplayOrder))"
                } else if let message = message, !message.flags.contains(.Incoming) {
                    headerString = "Reply to your message"
                } else {
                    headerString = "Reply to message"
                }
                strongSelf.actionArea.accessibilityLabel = "\(headerString).\n\(text)"
                
                if let applyImage = applyImage {
                    applyImage()
                    strongSelf.imageNode.isHidden = false
                } else {
                    strongSelf.imageNode.isHidden = true
                }
                
                if let updateImageSignal = updateImageSignal {
                    strongSelf.imageNode.setSignal(updateImageSignal)
                }
                
                strongSelf.setNeedsLayout()
            }
        }))
    }
    
    deinit {
        self.messageDisposable.dispose()
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:))))
    }
    
    override func updateThemeAndStrings(theme: PresentationTheme, strings: PresentationStrings) {
        if self.theme !== theme {
            self.theme = theme
            
            self.closeButton.setImage(PresentationResourcesChat.chatInputPanelCloseIconImage(theme), for: [])
            
            self.lineNode.image = PresentationResourcesChat.chatInputPanelVerticalSeparatorLineImage(theme)
            
            if let text = self.titleNode.attributedText?.string {
                self.titleNode.attributedText = NSAttributedString(string: text, font: Font.medium(15.0), textColor: self.theme.chat.inputPanel.panelControlAccentColor)
            }
            
            if let text = self.textNode.attributedText?.string {
                self.textNode.attributedText = NSAttributedString(string: text, font: Font.regular(15.0), textColor: self.theme.chat.inputPanel.primaryTextColor)
            }
            
            self.setNeedsLayout()
        }
    }
    
    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        return CGSize(width: constrainedSize.width, height: 45.0)
    }
    
    override func layout() {
        super.layout()
        
        let bounds = self.bounds
        let leftInset: CGFloat = 55.0
        let textLineInset: CGFloat = 10.0
        let rightInset: CGFloat = 55.0
        let textRightInset: CGFloat = 20.0
        
        let closeButtonSize = CGSize(width: 44.0, height: bounds.height)
        let closeButtonFrame = CGRect(origin: CGPoint(x: bounds.width - rightInset - closeButtonSize.width + 16.0, y: 2.0), size: closeButtonSize)
        self.closeButton.frame = closeButtonFrame
        
        self.actionArea.frame = CGRect(origin: CGPoint(x: leftInset, y: 2.0), size: CGSize(width: closeButtonFrame.minX - leftInset, height: bounds.height))
        
        self.lineNode.frame = CGRect(origin: CGPoint(x: leftInset, y: 8.0), size: CGSize(width: 2.0, height: bounds.size.height - 10.0))
        
        var imageTextInset: CGFloat = 0.0
        if !self.imageNode.isHidden {
            imageTextInset = 9.0 + 35.0
        }
        self.imageNode.frame = CGRect(origin: CGPoint(x: leftInset + 9.0, y: 8.0), size: CGSize(width: 35.0, height: 35.0))
        
        let titleSize = self.titleNode.updateLayout(CGSize(width: bounds.size.width - leftInset - textLineInset - rightInset - textRightInset - imageTextInset, height: bounds.size.height))
        self.titleNode.frame = CGRect(origin: CGPoint(x: leftInset + textLineInset + imageTextInset, y: 7.0), size: titleSize)
        
        let textSize = self.textNode.updateLayout(CGSize(width: bounds.size.width - leftInset - textLineInset - rightInset - textRightInset - imageTextInset, height: bounds.size.height))
        self.textNode.frame = CGRect(origin: CGPoint(x: leftInset + textLineInset + imageTextInset, y: 25.0), size: textSize)
    }
    
    @objc func closePressed() {
        if let dismiss = self.dismiss {
            dismiss()
        }
    }
    
    @objc func tapGesture(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            self.interfaceInteraction?.navigateToMessage(self.messageId)
        }
    }
}
