import Foundation
import UIKit
import AsyncDisplayKit

final class NavigationBarBadgeNode: ASDisplayNode {
    private var fillColor: UIColor
    private var strokeColor: UIColor
    private var textColor: UIColor
    
    private let textNode: ASTextNode
    private let backgroundNode: ASImageNode
    
    private let font: UIFont = Font.regular(13.0)
    
    var text: String = "" {
        didSet {
            self.textNode.attributedText = NSAttributedString(string: self.text, font: self.font, textColor: self.textColor)
            self.invalidateCalculatedLayout()
        }
    }
    
    init(fillColor: UIColor, strokeColor: UIColor, textColor: UIColor) {
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.textColor = textColor
        
        self.textNode = ASTextNode()
        self.textNode.isUserInteractionEnabled = false
        self.textNode.displaysAsynchronously = false
        
        self.backgroundNode = ASImageNode()
        self.backgroundNode.isLayerBacked = true
        self.backgroundNode.displayWithoutProcessing = true
        self.backgroundNode.displaysAsynchronously = false
        self.backgroundNode.image = generateStretchableFilledCircleImage(diameter: 18.0, color: fillColor, strokeColor: strokeColor, strokeWidth: 1.0)
        
        super.init()
        
        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.textNode)
    }
    
    func updateTheme(fillColor: UIColor, strokeColor: UIColor, textColor: UIColor) {
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.textColor = textColor
        self.backgroundNode.image = generateStretchableFilledCircleImage(diameter: 18.0, color: fillColor, strokeColor: strokeColor, strokeWidth: 1.0)
        self.textNode.attributedText = NSAttributedString(string: self.text, font: self.font, textColor: self.textColor)
    }
    
    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        let badgeSize = self.textNode.measure(constrainedSize)
        let backgroundSize = CGSize(width: max(18.0, badgeSize.width + 10.0 + 1.0), height: 18.0)
        let backgroundFrame = CGRect(origin: CGPoint(), size: backgroundSize)
        self.backgroundNode.frame = backgroundFrame
        self.textNode.frame = CGRect(origin: CGPoint(x: floorToScreenPixels(backgroundFrame.midX - badgeSize.width / 2.0), y: floorToScreenPixels((backgroundFrame.size.height - badgeSize.height) / 2.0)), size: badgeSize)
        
        return backgroundSize
    }
}
