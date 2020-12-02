import Foundation
import UIKit
import Display
import AsyncDisplayKit
import Postbox
import TelegramCore
import SyncCore
import SwiftSignalKit
import StickerResources
import AnimatedStickerNode
import TelegramAnimatedStickerNode

public enum StickerPreviewPeekItem: Equatable {
    case pack(StickerPackItem)
    case found(FoundStickerItem)
    
    public var file: TelegramMediaFile {
        switch self {
        case let .pack(item):
            return item.file
        case let .found(item):
            return item.file
        }
    }
}

public final class StickerPreviewPeekContent: PeekControllerContent {
    let account: Account
    public let item: StickerPreviewPeekItem
    let menu: [PeekControllerMenuItem]
    
    public init(account: Account, item: StickerPreviewPeekItem, menu: [PeekControllerMenuItem]) {
        self.account = account
        self.item = item
        self.menu = menu
    }
    
    public func presentation() -> PeekControllerContentPresentation {
        return .freeform
    }
    
    public func menuActivation() -> PeerkControllerMenuActivation {
        return .press
    }
    
    public func menuItems() -> [PeekControllerMenuItem] {
        return self.menu
    }
    
    public func node() -> PeekControllerContentNode & ASDisplayNode {
        return StickerPreviewPeekContentNode(account: self.account, item: self.item)
    }
    
    public func topAccessoryNode() -> ASDisplayNode? {
        return nil
    }
    
    public func isEqual(to: PeekControllerContent) -> Bool {
        if let to = to as? StickerPreviewPeekContent {
            return self.item == to.item
        } else {
            return false
        }
    }
}

private final class StickerPreviewPeekContentNode: ASDisplayNode, PeekControllerContentNode {
    private let account: Account
    private let item: StickerPreviewPeekItem
    
    private var textNode: ASTextNode
    private var imageNode: TransformImageNode
    private var animationNode: AnimatedStickerNode?
    
    private var containerLayout: (ContainerViewLayout, CGFloat)?
    
    init(account: Account, item: StickerPreviewPeekItem) {
        self.account = account
        self.item = item
        
        self.textNode = ASTextNode()
        self.imageNode = TransformImageNode()
        
        for case let .Sticker(text, _, _) in item.file.attributes {
            self.textNode.attributedText = NSAttributedString(string: text, font: Font.regular(32.0), textColor: .black)
            break
        }
        
        if item.file.isAnimatedSticker {
            let animationNode = AnimatedStickerNode()
            self.animationNode = animationNode
            
            let dimensions = item.file.dimensions ?? PixelDimensions(width: 512, height: 512)
            let fittedDimensions = dimensions.cgSize.aspectFitted(CGSize(width: 400.0, height: 400.0))
            
            self.animationNode?.setup(source: AnimatedStickerResourceSource(account: account, resource: item.file.resource), width: Int(fittedDimensions.width), height: Int(fittedDimensions.height), mode: .direct)
            self.animationNode?.visibility = true
            self.animationNode?.addSubnode(self.textNode)
        } else {
            self.imageNode.addSubnode(self.textNode)
            self.animationNode = nil
        }
        
        self.imageNode.setSignal(chatMessageSticker(account: account, file: item.file, small: false, fetched: true))
        
        super.init()
        
        self.isUserInteractionEnabled = false
        
        if let animationNode = self.animationNode {
            self.addSubnode(animationNode)
        } else {
            self.addSubnode(self.imageNode)
        }
    }
    
    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) -> CGSize {
        let boundingSize = CGSize(width: 180.0, height: 180.0).fitted(size)
        
        if let dimensitons = self.item.file.dimensions {
            let textSpacing: CGFloat = 10.0
            let textSize = self.textNode.measure(CGSize(width: 100.0, height: 100.0))
            
            let imageSize = dimensitons.cgSize.aspectFitted(boundingSize)
            self.imageNode.asyncLayout()(TransformImageArguments(corners: ImageCorners(), imageSize: imageSize, boundingSize: imageSize, intrinsicInsets: UIEdgeInsets()))()
            let imageFrame = CGRect(origin: CGPoint(x: floor((size.width - imageSize.width) / 2.0), y: textSize.height + textSpacing), size: imageSize)
            self.imageNode.frame = imageFrame
            if let animationNode = self.animationNode {
                animationNode.frame = imageFrame
                animationNode.updateLayout(size: imageSize)
            }
            
            self.textNode.frame = CGRect(origin: CGPoint(x: floor((imageFrame.size.width - textSize.width) / 2.0), y: -textSize.height - textSpacing), size: textSize)
            
            return CGSize(width: size.width, height: imageFrame.height + textSize.height + textSpacing)
        } else {
            return CGSize(width: size.width, height: 10.0)
        }
    }
}
