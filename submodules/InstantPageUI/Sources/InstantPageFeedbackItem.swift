import Foundation
import UIKit
import Postbox
import TelegramCore
import SyncCore
import AsyncDisplayKit
import TelegramPresentationData
import TelegramUIPreferences
import AccountContext

final class InstantPageFeedbackItem: InstantPageItem {
    var frame: CGRect
    let wantsNode: Bool = true
    let separatesTiles: Bool = false
    let medias: [InstantPageMedia] = []
    
    let webPage: TelegramMediaWebpage
    
    init(frame: CGRect, webPage: TelegramMediaWebpage) {
        self.frame = frame
        self.webPage = webPage
    }
    
    func node(context: AccountContext, strings: PresentationStrings, nameDisplayOrder: PresentationPersonNameOrder, theme: InstantPageTheme, openMedia: @escaping (InstantPageMedia) -> Void, longPressMedia: @escaping (InstantPageMedia) -> Void, openPeer: @escaping (PeerId) -> Void, openUrl: @escaping (InstantPageUrlItem) -> Void, updateWebEmbedHeight: @escaping (CGFloat) -> Void, updateDetailsExpanded: @escaping (Bool) -> Void, currentExpandedDetails: [Int : Bool]?) -> (InstantPageNode & ASDisplayNode)? {
        return InstantPageFeedbackNode(context: context, strings: strings, theme: theme, webPage: self.webPage, openUrl: openUrl)
    }
    
    func matchesAnchor(_ anchor: String) -> Bool {
        return false
    }
    
    func matchesNode(_ node: InstantPageNode) -> Bool {
        if node is InstantPageFeedbackNode {
            return true
        }
        return false
    }
    
    func distanceThresholdGroup() -> Int? {
        return 8
    }
    
    func distanceThresholdWithGroupCount(_ count: Int) -> CGFloat {
        return CGFloat.greatestFiniteMagnitude
    }
    
    func linkSelectionRects(at point: CGPoint) -> [CGRect] {
        return []
    }
    
    func drawInTile(context: CGContext) {
    }
}
