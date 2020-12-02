import Foundation
import UIKit
import AsyncDisplayKit
import Postbox
import TelegramCore
import SyncCore
import SwiftSignalKit
import Display
import TelegramPresentationData
import TelegramUIPreferences
import MergeLists
import AvatarNode
import AccountContext
import PeerPresenceStatusManager
import AppBundle

private let subtitleFont = Font.regular(12.0)

private struct SharePeerEntry: Comparable, Identifiable {
    let index: Int32
    let peer: RenderedPeer
    let presence: PeerPresence?
    let theme: PresentationTheme
    let strings: PresentationStrings
    
    var stableId: Int64 {
        return self.peer.peerId.toInt64()
    }
    
    static func ==(lhs: SharePeerEntry, rhs: SharePeerEntry) -> Bool {
        if lhs.index != rhs.index {
            return false
        }
        if lhs.peer != rhs.peer {
            return false
        }
        if let lhsPresence = lhs.presence, let rhsPresence = rhs.presence {
            if !lhsPresence.isEqual(to: rhsPresence) {
                return false
            }
        } else if (lhs.presence != nil) != (rhs.presence != nil) {
            return false
        }
        return true
    }
    
    static func <(lhs: SharePeerEntry, rhs: SharePeerEntry) -> Bool {
        return lhs.index < rhs.index
    }
    
    func item(context: AccountContext, interfaceInteraction: ShareControllerInteraction) -> GridItem {
        return ShareControllerPeerGridItem(context: context, theme: self.theme, strings: self.strings, peer: self.peer, presence: self.presence, controllerInteraction: interfaceInteraction, search: false)
    }
}

private struct ShareGridTransaction {
    let deletions: [Int]
    let insertions: [GridNodeInsertItem]
    let updates: [GridNodeUpdateItem]
    let animated: Bool
}

private let avatarFont = avatarPlaceholderFont(size: 17.0)

private func preparedGridEntryTransition(context: AccountContext, from fromEntries: [SharePeerEntry], to toEntries: [SharePeerEntry], interfaceInteraction: ShareControllerInteraction) -> ShareGridTransaction {
    let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: fromEntries, rightList: toEntries)
    
    let deletions = deleteIndices
    let insertions = indicesAndItems.map { GridNodeInsertItem(index: $0.0, item: $0.1.item(context: context, interfaceInteraction: interfaceInteraction), previousIndex: $0.2) }
    let updates = updateIndices.map { GridNodeUpdateItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(context: context, interfaceInteraction: interfaceInteraction)) }
    
    return ShareGridTransaction(deletions: deletions, insertions: insertions, updates: updates, animated: false)
}

final class SharePeersContainerNode: ASDisplayNode, ShareContentContainerNode {
    private let sharedContext: SharedAccountContext
    private let context: AccountContext
    private let theme: PresentationTheme
    private let strings: PresentationStrings
    private let nameDisplayOrder: PresentationPersonNameOrder
    private let controllerInteraction: ShareControllerInteraction
    private let switchToAnotherAccount: () -> Void
    
    let accountPeer: Peer
    private let foundPeers = Promise<[RenderedPeer]>([])
    
    private let disposable = MetaDisposable()
    private var entries: [SharePeerEntry] = []
    private var enqueuedTransitions: [(ShareGridTransaction, Bool)] = []
    
    private let contentGridNode: GridNode
    private let contentTitleNode: ASTextNode
    private let contentSubtitleNode: ASTextNode
    private let contentTitleAccountNode: AvatarNode
    private let contentSeparatorNode: ASDisplayNode
    private let searchButtonNode: HighlightableButtonNode
    private let shareButtonNode: HighlightableButtonNode
    
    private var contentOffsetUpdated: ((CGFloat, ContainedViewLayoutTransition) -> Void)?
    
    var openSearch: (() -> Void)?
    var openShare: (() -> Void)?
    
    private var ensurePeerVisibleOnLayout: PeerId?
    private var validLayout: (CGSize, CGFloat)?
    private var overrideGridOffsetTransition: ContainedViewLayoutTransition?
    
    let peersValue = Promise<[(RenderedPeer, PeerPresence?)]>()
    
    init(sharedContext: SharedAccountContext, context: AccountContext, switchableAccounts: [AccountWithInfo], theme: PresentationTheme, strings: PresentationStrings, nameDisplayOrder: PresentationPersonNameOrder, peers: [(RenderedPeer, PeerPresence?)], accountPeer: Peer, controllerInteraction: ShareControllerInteraction, externalShare: Bool, switchToAnotherAccount: @escaping () -> Void) {
        self.sharedContext = sharedContext
        self.context = context
        self.theme = theme
        self.strings = strings
        self.nameDisplayOrder = nameDisplayOrder
        self.controllerInteraction = controllerInteraction
        self.accountPeer = accountPeer
        self.switchToAnotherAccount = switchToAnotherAccount
        
        self.peersValue.set(.single(peers))
        
        let items: Signal<[SharePeerEntry], NoError> = combineLatest(self.peersValue.get(), self.foundPeers.get())
        |> map { initialPeers, foundPeers -> [SharePeerEntry] in
            var entries: [SharePeerEntry] = []
            var index: Int32 = 0
            
            var existingPeerIds: Set<PeerId> = Set()
            
            entries.append(SharePeerEntry(index: index, peer: RenderedPeer(peer: accountPeer), presence: nil, theme: theme, strings: strings))
            index += 1
            
            for peer in foundPeers.reversed() {
                entries.append(SharePeerEntry(index: index, peer: peer, presence: nil, theme: theme, strings: strings))
                existingPeerIds.insert(peer.peerId)
                index += 1
            }
            
            for (peer, presence) in initialPeers {
                if !existingPeerIds.contains(peer.peerId) {
                    entries.append(SharePeerEntry(index: index, peer: peer, presence: presence, theme: theme, strings: strings))
                    existingPeerIds.insert(peer.peerId)
                    index += 1
                }
            }
            return entries
        }
        
        self.contentGridNode = GridNode()
        
        self.contentTitleNode = ASTextNode()
        self.contentTitleNode.attributedText = NSAttributedString(string: strings.ShareMenu_ShareTo, font: Font.medium(20.0), textColor: self.theme.actionSheet.primaryTextColor)
        
        self.contentSubtitleNode = ASTextNode()
        self.contentSubtitleNode.maximumNumberOfLines = 1
        self.contentSubtitleNode.isUserInteractionEnabled = false
        self.contentSubtitleNode.displaysAsynchronously = false
        self.contentSubtitleNode.truncationMode = .byTruncatingTail
        self.contentSubtitleNode.attributedText = NSAttributedString(string: strings.ShareMenu_SelectChats, font: subtitleFont, textColor: self.theme.actionSheet.secondaryTextColor)
        
        self.contentTitleAccountNode = AvatarNode(font: avatarFont)
        var hasOtherAccounts = false
        if switchableAccounts.count > 1, let info = switchableAccounts.first(where: { $0.account.id == context.account.id }) {
            hasOtherAccounts = true
            self.contentTitleAccountNode.setPeer(context: context, theme: theme, peer: info.peer, emptyColor: nil, synchronousLoad: false)
        } else {
            self.contentTitleAccountNode.isHidden = true
        }
        
        self.searchButtonNode = HighlightableButtonNode()
        self.searchButtonNode.setImage(generateTintedImage(image: UIImage(bundleImageName: "Share/SearchIcon"), color: self.theme.actionSheet.controlAccentColor), for: [])
        
        self.shareButtonNode = HighlightableButtonNode()
        self.shareButtonNode.setImage(generateTintedImage(image: UIImage(bundleImageName: "Share/ShareIcon"), color: self.theme.actionSheet.controlAccentColor), for: [])
        
        self.contentSeparatorNode = ASDisplayNode()
        self.contentSeparatorNode.isLayerBacked = true
        self.contentSeparatorNode.displaysAsynchronously = false
        self.contentSeparatorNode.backgroundColor = self.theme.actionSheet.opaqueItemSeparatorColor
        
        if !externalShare || hasOtherAccounts {
            self.shareButtonNode.isHidden = true
        }
        
        super.init()
        
        self.addSubnode(self.contentGridNode)
        
        self.addSubnode(self.contentTitleNode)
        self.addSubnode(self.contentSubtitleNode)
        self.addSubnode(self.contentTitleAccountNode)
        self.addSubnode(self.searchButtonNode)
        self.addSubnode(self.shareButtonNode)
        self.addSubnode(self.contentSeparatorNode)
        
        let previousItems = Atomic<[SharePeerEntry]?>(value: [])
        self.disposable.set((items
        |> deliverOnMainQueue).start(next: { [weak self] entries in
            if let strongSelf = self {
                let previousEntries = previousItems.swap(entries)
                strongSelf.entries = entries
                
                let firstTime = previousEntries == nil
                let transition = preparedGridEntryTransition(context: context, from: previousEntries ?? [], to: entries, interfaceInteraction: controllerInteraction)
                strongSelf.enqueueTransition(transition, firstTime: firstTime)
            }
        }))

        self.contentGridNode.presentationLayoutUpdated = { [weak self] presentationLayout, transition in
            self?.gridPresentationLayoutUpdated(presentationLayout, transition: transition)
        }
        
        self.searchButtonNode.addTarget(self, action: #selector(self.searchPressed), forControlEvents: .touchUpInside)
        self.shareButtonNode.addTarget(self, action: #selector(self.sharePressed), forControlEvents: .touchUpInside)
        self.contentTitleAccountNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.accountTapGesture(_:))))
    }
    
    deinit {
        self.disposable.dispose()
    }
    
    private func enqueueTransition(_ transition: ShareGridTransaction, firstTime: Bool) {
        self.enqueuedTransitions.append((transition, firstTime))
        
        if self.validLayout != nil {
            while !self.enqueuedTransitions.isEmpty {
                self.dequeueTransition()
            }
        }
    }
    
    private func dequeueTransition() {
        if let (transition, _) = self.enqueuedTransitions.first {
            self.enqueuedTransitions.remove(at: 0)
            
            var itemTransition: ContainedViewLayoutTransition = .immediate
            if transition.animated {
                itemTransition = .animated(duration: 0.3, curve: .spring)
            }
            self.contentGridNode.transaction(GridNodeTransaction(deleteItems: transition.deletions, insertItems: transition.insertions, updateItems: transition.updates, scrollToItem: nil, updateLayout: nil, itemTransition: itemTransition, stationaryItems: .none, updateFirstIndexInSectionOffset: nil), completion: { _ in })
        }
    }
    
    func setEnsurePeerVisibleOnLayout(_ peerId: PeerId?) {
        self.ensurePeerVisibleOnLayout = peerId
    }
    
    func setContentOffsetUpdated(_ f: ((CGFloat, ContainedViewLayoutTransition) -> Void)?) {
        self.contentOffsetUpdated = f
    }
    
    private func calculateMetrics(size: CGSize) -> (topInset: CGFloat, itemWidth: CGFloat) {
        let itemCount = self.entries.count
        
        let itemInsets = UIEdgeInsets(top: 0.0, left: 12.0, bottom: 0.0, right: 12.0)
        let minimalItemWidth: CGFloat = size.width > 301.0 ? 70.0 : 60.0
        let effectiveWidth = size.width - itemInsets.left - itemInsets.right
        
        let itemsPerRow = Int(effectiveWidth / minimalItemWidth)
        
        let itemWidth = floor(effectiveWidth / CGFloat(itemsPerRow))
        var rowCount = itemCount / itemsPerRow + (itemCount % itemsPerRow != 0 ? 1 : 0)
        rowCount = max(rowCount, 4)
        
        let minimallyRevealedRowCount: CGFloat = 3.7
        let initiallyRevealedRowCount = min(minimallyRevealedRowCount, CGFloat(rowCount))
        
        let gridTopInset = max(0.0, size.height - floor(initiallyRevealedRowCount * itemWidth) - 14.0)
        return (gridTopInset, itemWidth)
    }
    
    func activate() {
    }
    
    func deactivate() {
    }
    
    func updateLayout(size: CGSize, bottomInset: CGFloat, transition: ContainedViewLayoutTransition) {
        let firstLayout = self.validLayout == nil
        self.validLayout = (size, bottomInset)
        
        let gridLayoutTransition: ContainedViewLayoutTransition
        if firstLayout {
            gridLayoutTransition = .immediate
            self.overrideGridOffsetTransition = transition
        } else {
            gridLayoutTransition = transition
            self.overrideGridOffsetTransition = nil
        }
        
        let (gridTopInset, itemWidth) = self.calculateMetrics(size: size)
        
        var scrollToItem: GridNodeScrollToItem?
        if let ensurePeerVisibleOnLayout = self.ensurePeerVisibleOnLayout {
            self.ensurePeerVisibleOnLayout = nil
            if let index = self.entries.firstIndex(where: { $0.peer.peerId == ensurePeerVisibleOnLayout }) {
                scrollToItem = GridNodeScrollToItem(index: index, position: .visible, transition: transition, directionHint: .up, adjustForSection: false)
            }
        }
        
        let gridSize = CGSize(width: size.width - 12.0, height: size.height)
        
        self.contentGridNode.transaction(GridNodeTransaction(deleteItems: [], insertItems: [], updateItems: [], scrollToItem: scrollToItem, updateLayout: GridNodeUpdateLayout(layout: GridNodeLayout(size: gridSize, insets: UIEdgeInsets(top: gridTopInset, left: 0.0, bottom: bottomInset, right: 0.0), preloadSize: 80.0, type: .fixed(itemSize: CGSize(width: itemWidth, height: itemWidth + 25.0), fillWidth: nil, lineSpacing: 0.0, itemSpacing: nil)), transition: gridLayoutTransition), itemTransition: .immediate, stationaryItems: .none, updateFirstIndexInSectionOffset: nil), completion: { _ in })
        gridLayoutTransition.updateFrame(node: self.contentGridNode, frame: CGRect(origin: CGPoint(x: floor((size.width - gridSize.width) / 2.0), y: 0.0), size: gridSize))
        
        if firstLayout {
            while !self.enqueuedTransitions.isEmpty {
                self.dequeueTransition()
            }
        }
    }
    
    private func gridPresentationLayoutUpdated(_ presentationLayout: GridNodeCurrentPresentationLayout, transition: ContainedViewLayoutTransition) {
        guard let (size, _) = self.validLayout else {
            return
        }
        
        let actualTransition = self.overrideGridOffsetTransition ?? transition
        self.overrideGridOffsetTransition = nil
        
        let titleAreaHeight: CGFloat = 64.0
        
        let rawTitleOffset = -titleAreaHeight - presentationLayout.contentOffset.y
        let titleOffset = max(-titleAreaHeight, rawTitleOffset)
        
        let titleSize = self.contentTitleNode.measure(size)
        let titleFrame = CGRect(origin: CGPoint(x: floor((size.width - titleSize.width) / 2.0), y: titleOffset + 15.0), size: titleSize)
        transition.updateFrame(node: self.contentTitleNode, frame: titleFrame)
        
        let subtitleSize = self.contentSubtitleNode.measure(CGSize(width: size.width - 44.0 * 2.0 - 8.0 * 2.0, height: titleAreaHeight))
        let subtitleFrame = CGRect(origin: CGPoint(x: floor((size.width - subtitleSize.width) / 2.0), y: titleOffset + 40.0), size: subtitleSize)
        var originalSubtitleFrame = self.contentSubtitleNode.frame
        originalSubtitleFrame.origin.x = subtitleFrame.origin.x
        originalSubtitleFrame.size = subtitleFrame.size
        self.contentSubtitleNode.frame = originalSubtitleFrame
        transition.updateFrame(node: self.contentSubtitleNode, frame: subtitleFrame)
        
        let titleButtonSize = CGSize(width: 44.0, height: 44.0)
        let searchButtonFrame = CGRect(origin: CGPoint(x: 12.0, y: titleOffset + 12.0), size: titleButtonSize)
        transition.updateFrame(node: self.searchButtonNode, frame: searchButtonFrame)
        
        let shareButtonFrame = CGRect(origin: CGPoint(x: size.width - titleButtonSize.width - 12.0, y: titleOffset + 12.0), size: titleButtonSize)
        transition.updateFrame(node: self.shareButtonNode, frame: shareButtonFrame)
        
        let avatarButtonSize = CGSize(width: 36.0, height: 36.0)
        let avatarButtonFrame = CGRect(origin: CGPoint(x: size.width - avatarButtonSize.width - 20.0, y: titleOffset + 15.0), size: avatarButtonSize)
        transition.updateFrame(node: self.contentTitleAccountNode, frame: avatarButtonFrame)
        
        transition.updateFrame(node: self.contentSeparatorNode, frame: CGRect(origin: CGPoint(x: 0.0, y: titleOffset + titleAreaHeight), size: CGSize(width: size.width, height: UIScreenPixel)))
        
        if rawTitleOffset.isLess(than: -titleAreaHeight) {
            self.contentSeparatorNode.alpha = 1.0
        } else {
            self.contentSeparatorNode.alpha = 0.0
        }
        
        self.contentOffsetUpdated?(presentationLayout.contentOffset.y, actualTransition)
    }
    
    func updateVisibleItemsSelection(animated: Bool) {
        self.contentGridNode.forEachItemNode { itemNode in
            if let itemNode = itemNode as? ShareControllerPeerGridItemNode {
                itemNode.updateSelection(animated: animated)
            }
        }
    }
    
    func updateFoundPeers() {
        self.foundPeers.set(.single(self.controllerInteraction.foundPeers))
    }
    
    func updateSelectedPeers() {
        var subtitleText = self.strings.ShareMenu_SelectChats
        if !self.controllerInteraction.selectedPeers.isEmpty {
            subtitleText = self.controllerInteraction.selectedPeers.reduce("", { string, peer in
                let text: String
                if peer.peerId == self.accountPeer.id {
                    text = self.strings.DialogList_SavedMessages
                } else {
                    text = peer.chatMainPeer?.displayTitle(strings: self.strings, displayOrder: self.nameDisplayOrder) ?? ""
                }
                
                if !string.isEmpty {
                    return string + ", " + text
                } else {
                    return string + text
                }
            })
        }
        self.contentSubtitleNode.attributedText = NSAttributedString(string: subtitleText, font: subtitleFont, textColor: self.theme.actionSheet.secondaryTextColor)
        
        self.contentGridNode.forEachItemNode { itemNode in
            if let itemNode = itemNode as? ShareControllerPeerGridItemNode {
                itemNode.updateSelection(animated: true)
            }
        }
    }
    
    @objc func searchPressed() {
        self.openSearch?()
    }
    
    @objc func sharePressed() {
        self.openShare?()
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let nodes: [ASDisplayNode] = [self.searchButtonNode, self.shareButtonNode, self.contentTitleAccountNode]
        for node in nodes {
            let nodeFrame = node.frame
            if node.isHidden {
                continue
            }
            if let result = node.hitTest(point.offsetBy(dx: -nodeFrame.minX, dy: -nodeFrame.minY), with: event) {
                return result
            }
        }
        
        return super.hitTest(point, with: event)
    }
    
    @objc private func accountTapGesture(_ recognizer: UITapGestureRecognizer) {
        self.switchToAnotherAccount()
    }
}
