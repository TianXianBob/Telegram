import UIKit
import AsyncDisplayKit

private var backArrowImageCache: [Int32: UIImage] = [:]

public final class NavigationBarTheme {
    public static func generateBackArrowImage(color: UIColor) -> UIImage? {
        return generateImage(CGSize(width: 13.0, height: 22.0), rotatedContext: { size, context in
            context.clear(CGRect(origin: CGPoint(), size: size))
            context.setFillColor(color.cgColor)
            
            context.translateBy(x: 0.0, y: -UIScreenPixel)
            
            let _ = try? drawSvgPath(context, path: "M3.60751322,11.5 L11.5468531,3.56066017 C12.1326395,2.97487373 12.1326395,2.02512627 11.5468531,1.43933983 C10.9610666,0.853553391 10.0113191,0.853553391 9.42553271,1.43933983 L0.449102936,10.4157696 C-0.149700979,11.0145735 -0.149700979,11.9854265 0.449102936,12.5842304 L9.42553271,21.5606602 C10.0113191,22.1464466 10.9610666,22.1464466 11.5468531,21.5606602 C12.1326395,20.9748737 12.1326395,20.0251263 11.5468531,19.4393398 L3.60751322,11.5 Z ")
        })
    }
    
    public let buttonColor: UIColor
    public let disabledButtonColor: UIColor
    public let primaryTextColor: UIColor
    public let backgroundColor: UIColor
    public let separatorColor: UIColor
    public let badgeBackgroundColor: UIColor
    public let badgeStrokeColor: UIColor
    public let badgeTextColor: UIColor
    
    public init(buttonColor: UIColor, disabledButtonColor: UIColor, primaryTextColor: UIColor, backgroundColor: UIColor, separatorColor: UIColor, badgeBackgroundColor: UIColor, badgeStrokeColor: UIColor, badgeTextColor: UIColor) {
        self.buttonColor = buttonColor
        self.disabledButtonColor = disabledButtonColor
        self.primaryTextColor = primaryTextColor
        self.backgroundColor = backgroundColor
        self.separatorColor = separatorColor
        self.badgeBackgroundColor = badgeBackgroundColor
        self.badgeStrokeColor = badgeStrokeColor
        self.badgeTextColor = badgeTextColor
    }
    
    public func withUpdatedSeparatorColor(_ color: UIColor) -> NavigationBarTheme {
        return NavigationBarTheme(buttonColor: self.buttonColor, disabledButtonColor: self.disabledButtonColor, primaryTextColor: self.primaryTextColor, backgroundColor: self.backgroundColor, separatorColor: color, badgeBackgroundColor: self.badgeBackgroundColor, badgeStrokeColor: self.badgeStrokeColor, badgeTextColor: self.badgeTextColor)
    }
}

public final class NavigationBarStrings {
    public let back: String
    public let close: String
    
    public init(back: String, close: String) {
        self.back = back
        self.close = close
    }
}

public final class NavigationBarPresentationData {
    public let theme: NavigationBarTheme
    public let strings: NavigationBarStrings
    
    public init(theme: NavigationBarTheme, strings: NavigationBarStrings) {
        self.theme = theme
        self.strings = strings
    }
}

private func backArrowImage(color: UIColor) -> UIImage? {
    var red: CGFloat = 0.0
    var green: CGFloat = 0.0
    var blue: CGFloat = 0.0
    var alpha: CGFloat = 0.0
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    
    let key = (Int32(alpha * 255.0) << 24) | (Int32(red * 255.0) << 16) | (Int32(green * 255.0) << 8) | Int32(blue * 255.0)
    if let image = backArrowImageCache[key] {
        return image
    } else {
        if let image = NavigationBarTheme.generateBackArrowImage(color: color) {
            backArrowImageCache[key] = image
            return image
        } else {
            return nil
        }
    }
}

enum NavigationPreviousAction: Equatable {
    case item(UINavigationItem)
    case close
    
    static func ==(lhs: NavigationPreviousAction, rhs: NavigationPreviousAction) -> Bool {
        switch lhs {
            case let .item(lhsItem):
                if case let .item(rhsItem) = rhs, lhsItem === rhsItem {
                    return true
                } else {
                    return false
                }
            case .close:
                if case .close = rhs {
                    return true
                } else {
                    return false
                }
        }
    }
}

open class NavigationBar: ASDisplayNode {
    private var presentationData: NavigationBarPresentationData
    
    private var validLayout: (CGSize, CGFloat, CGFloat, CGFloat)?
    private var requestedLayout: Bool = false
    var requestContainerLayout: (ContainedViewLayoutTransition) -> Void = { _ in }
    
    public var backPressed: () -> () = { }
    
    private var collapsed: Bool {
        get {
            return self.frame.size.height.isLess(than: 44.0)
        }
    }
    
    private let stripeNode: ASDisplayNode
    private let clippingNode: ASDisplayNode
    
    public private(set) var contentNode: NavigationBarContentNode?
    
    private var itemTitleListenerKey: Int?
    private var itemTitleViewListenerKey: Int?
    
    private var itemLeftButtonListenerKey: Int?
    private var itemLeftButtonSetEnabledListenerKey: Int?
    
    private var itemRightButtonListenerKey: Int?
    private var itemRightButtonsListenerKey: Int?
    
    private var itemBadgeListenerKey: Int?
    
    private var hintAnimateTitleNodeOnNextLayout: Bool = false
    
    private var _item: UINavigationItem?
    public var item: UINavigationItem? {
        get {
            return self._item
        } set(value) {
            if let previousValue = self._item {
                if let itemTitleListenerKey = self.itemTitleListenerKey {
                    previousValue.removeSetTitleListener(itemTitleListenerKey)
                    self.itemTitleListenerKey = nil
                }
                
                if let itemLeftButtonListenerKey = self.itemLeftButtonListenerKey {
                    previousValue.removeSetLeftBarButtonItemListener(itemLeftButtonListenerKey)
                    self.itemLeftButtonListenerKey = nil
                }
                
                if let itemLeftButtonSetEnabledListenerKey = self.itemLeftButtonSetEnabledListenerKey {
                    previousValue.leftBarButtonItem?.removeSetEnabledListener(itemLeftButtonSetEnabledListenerKey)
                    self.itemLeftButtonSetEnabledListenerKey = nil
                }
                
                if let itemRightButtonListenerKey = self.itemRightButtonListenerKey {
                    previousValue.removeSetRightBarButtonItemListener(itemRightButtonListenerKey)
                    self.itemRightButtonListenerKey = nil
                }
                
                if let itemRightButtonsListenerKey = self.itemRightButtonsListenerKey {
                    previousValue.removeSetMultipleRightBarButtonItemsListener(itemRightButtonsListenerKey)
                    self.itemRightButtonsListenerKey = nil
                }
                
                if let itemBadgeListenerKey = self.itemBadgeListenerKey {
                    previousValue.removeSetBadgeListener(itemBadgeListenerKey)
                    self.itemBadgeListenerKey = nil
                }
            }
            self._item = value
            
            self.leftButtonNode.removeFromSupernode()
            self.rightButtonNode.removeFromSupernode()
            
            if let item = value {
                self.title = item.title
                self.itemTitleListenerKey = item.addSetTitleListener { [weak self] text, animated in
                    if let strongSelf = self {
                        let animateIn = animated && (strongSelf.title?.isEmpty ?? true)
                        strongSelf.title = text
                        if animateIn {
                            strongSelf.titleNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
                        }
                    }
                }
                
                self.titleView = item.titleView
                self.itemTitleViewListenerKey = item.addSetTitleViewListener { [weak self] titleView in
                    if let strongSelf = self {
                        strongSelf.titleView = titleView
                    }
                }
                
                self.itemLeftButtonListenerKey = item.addSetLeftBarButtonItemListener { [weak self] previousItem, _, animated in
                    if let strongSelf = self {
                        if let itemLeftButtonSetEnabledListenerKey = strongSelf.itemLeftButtonSetEnabledListenerKey {
                            previousItem?.removeSetEnabledListener(itemLeftButtonSetEnabledListenerKey)
                            strongSelf.itemLeftButtonSetEnabledListenerKey = nil
                        }
                        
                        strongSelf.updateLeftButton(animated: animated)
                        strongSelf.invalidateCalculatedLayout()
                        strongSelf.requestLayout()
                    }
                }
                
                self.itemRightButtonListenerKey = item.addSetRightBarButtonItemListener { [weak self] previousItem, currentItem, animated in
                    if let strongSelf = self {
                        strongSelf.updateRightButton(animated: animated)
                        strongSelf.invalidateCalculatedLayout()
                        strongSelf.requestLayout()
                    }
                }
                
                self.itemRightButtonsListenerKey = item.addSetMultipleRightBarButtonItemsListener { [weak self] items, animated in
                    if let strongSelf = self {
                        strongSelf.updateRightButton(animated: animated)
                        strongSelf.invalidateCalculatedLayout()
                        strongSelf.requestLayout()
                    }
                }
                
                self.itemBadgeListenerKey = item.addSetBadgeListener { [weak self] text in
                    if let strongSelf = self {
                        strongSelf.updateBadgeText(text: text)
                    }
                }
                self.updateBadgeText(text: item.badge)
                
                self.updateLeftButton(animated: false)
                self.updateRightButton(animated: false)
            } else {
                self.title = nil
                self.updateLeftButton(animated: false)
                self.updateRightButton(animated: false)
            }
            self.invalidateCalculatedLayout()
            self.requestLayout()
        }
    }
    
    private var title: String? {
        didSet {
            if let title = self.title {
                self.titleNode.attributedText = NSAttributedString(string: title, font: Font.bold(17.0), textColor: self.presentationData.theme.primaryTextColor)
                self.titleNode.accessibilityLabel = title
                if self.titleNode.supernode == nil {
                    self.clippingNode.addSubnode(self.titleNode)
                }
            } else {
                self.titleNode.removeFromSupernode()
            }
            
            self.updateAccessibilityElements()
            self.invalidateCalculatedLayout()
            self.requestLayout()
        }
    }
    
    private var titleView: UIView? {
        didSet {
            if let oldValue = oldValue {
                oldValue.removeFromSuperview()
            }
            
            if let titleView = self.titleView {
                self.clippingNode.view.addSubview(titleView)
            }
            
            self.invalidateCalculatedLayout()
            self.requestLayout()
        }
    }
    
    public var layoutSuspended: Bool = false
    
    private let titleNode: ASTextNode
    
    var previousItemListenerKey: Int?
    var previousItemBackListenerKey: Int?
    
    private func updateAccessibilityElements() {
        /*if !self.isNodeLoaded {
            return
        }
        var accessibilityElements: [AnyObject] = []
        
        if self.leftButtonNode.supernode != nil {
            accessibilityElements.append(self.leftButtonNode)
        }
        if self.titleNode.supernode != nil {
            accessibilityElements.append(self.titleNode)
        }
        if let titleView = self.titleView, titleView.superview != nil {
            accessibilityElements.append(titleView)
        }
        if self.rightButtonNode.supernode != nil {
            accessibilityElements.append(self.rightButtonNode)
        }
        
        var updated = false
        if let currentAccessibilityElements = self.accessibilityElements {
            if currentAccessibilityElements.count != accessibilityElements.count {
                updated = true
            } else {
                for i in 0 ..< accessibilityElements.count {
                    let element = currentAccessibilityElements[i] as AnyObject
                    if element !== accessibilityElements[i] {
                        updated = true
                    }
                }
            }
        }
        if updated {
            self.accessibilityElements = accessibilityElements
        }*/
    }
    
    override open var accessibilityElements: [Any]? {
        get {
            var accessibilityElements: [Any] = []
            if self.backButtonNode.supernode != nil {
                addAccessibilityChildren(of: self.backButtonNode, container: self, to: &accessibilityElements)
            }
            if self.leftButtonNode.supernode != nil {
                addAccessibilityChildren(of: self.leftButtonNode, container: self, to: &accessibilityElements)
            }
            if self.titleNode.supernode != nil {
                addAccessibilityChildren(of: self.titleNode, container: self, to: &accessibilityElements)
                accessibilityElements.append(self.titleNode)
            }
            if let titleView = self.titleView, titleView.superview != nil {
                titleView.accessibilityFrame = UIAccessibility.convertToScreenCoordinates(titleView.bounds, in: titleView)
                accessibilityElements.append(titleView)
            }
            if self.rightButtonNode.supernode != nil {
                addAccessibilityChildren(of: self.rightButtonNode, container: self, to: &accessibilityElements)
            }
            if let contentNode = self.contentNode {
                addAccessibilityChildren(of: contentNode, container: self, to: &accessibilityElements)
            }
            return accessibilityElements
        } set(value) {
        }
    }
    
    override open func didLoad() {
        super.didLoad()
        
        self.updateAccessibilityElements()
    }
    
    var _previousItem: NavigationPreviousAction?
    var previousItem: NavigationPreviousAction? {
        get {
            return self._previousItem
        } set(value) {
            if self._previousItem != value {
                if let previousValue = self._previousItem, case let .item(itemValue) = previousValue {
                    if let previousItemListenerKey = self.previousItemListenerKey {
                        itemValue.removeSetTitleListener(previousItemListenerKey)
                        self.previousItemListenerKey = nil
                    }
                    if let previousItemBackListenerKey = self.previousItemBackListenerKey {
                        itemValue.removeSetBackBarButtonItemListener(previousItemBackListenerKey)
                        self.previousItemBackListenerKey = nil
                    }
                }
                self._previousItem = value
                
                if let previousItem = value {
                    switch previousItem {
                        case let .item(itemValue):
                            self.previousItemListenerKey = itemValue.addSetTitleListener { [weak self] _, _ in
                                if let strongSelf = self, let previousItem = strongSelf.previousItem, case let .item(itemValue) = previousItem {
                                    if let backBarButtonItem = itemValue.backBarButtonItem {
                                        strongSelf.backButtonNode.updateManualText(backBarButtonItem.title ?? "")
                                    } else {
                                        strongSelf.backButtonNode.updateManualText(itemValue.title ?? "")
                                    }
                                    strongSelf.invalidateCalculatedLayout()
                                    strongSelf.requestLayout()
                                }
                            }
                            
                            self.previousItemBackListenerKey = itemValue.addSetBackBarButtonItemListener { [weak self] _, _, _ in
                                if let strongSelf = self, let previousItem = strongSelf.previousItem, case let .item(itemValue) = previousItem {
                                    if let backBarButtonItem = itemValue.backBarButtonItem {
                                        strongSelf.backButtonNode.updateManualText(backBarButtonItem.title ?? "")
                                    } else {
                                        strongSelf.backButtonNode.updateManualText(itemValue.title ?? "")
                                    }
                                    strongSelf.invalidateCalculatedLayout()
                                    strongSelf.requestLayout()
                                }
                            }
                        case .close:
                            break
                    }
                }
                self.updateLeftButton(animated: false)
                
                self.invalidateCalculatedLayout()
                self.requestLayout()
            }
        }
    }
    
    private func updateBadgeText(text: String?) {
        let actualText = text ?? ""
        if self.badgeNode.text != actualText {
            self.badgeNode.text = actualText
            self.badgeNode.isHidden = actualText.isEmpty
            
            self.invalidateCalculatedLayout()
            self.requestLayout()
        }
    }
    
    private func updateLeftButton(animated: Bool) {
        if let item = self.item {
            var needsLeftButton = false
            if let leftBarButtonItem = item.leftBarButtonItem, !leftBarButtonItem.backButtonAppearance {
                needsLeftButton = true
            } else if let previousItem = self.previousItem, case .close = previousItem {
                needsLeftButton = true
            }
            
            if needsLeftButton {
                if animated {
                    if self.leftButtonNode.view.superview != nil {
                        if let snapshotView = self.leftButtonNode.view.snapshotContentTree() {
                            snapshotView.frame = self.leftButtonNode.frame
                            self.leftButtonNode.view.superview?.insertSubview(snapshotView, aboveSubview: self.leftButtonNode.view)
                            snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false, completion: { [weak snapshotView] _ in
                                snapshotView?.removeFromSuperview()
                            })
                        }
                    }
                    
                    if self.backButtonNode.view.superview != nil {
                        if let snapshotView = self.backButtonNode.view.snapshotContentTree() {
                            snapshotView.frame = self.backButtonNode.frame
                            self.backButtonNode.view.superview?.insertSubview(snapshotView, aboveSubview: self.backButtonNode.view)
                            snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false, completion: { [weak snapshotView] _ in
                                snapshotView?.removeFromSuperview()
                            })
                        }
                    }
                    
                    if self.backButtonArrow.view.superview != nil {
                        if let snapshotView = self.backButtonArrow.view.snapshotContentTree() {
                            snapshotView.frame = self.backButtonArrow.frame
                            self.backButtonArrow.view.superview?.insertSubview(snapshotView, aboveSubview: self.backButtonArrow.view)
                            snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false, completion: { [weak snapshotView] _ in
                                snapshotView?.removeFromSuperview()
                            })
                        }
                    }
                    
                    if self.badgeNode.view.superview != nil {
                        if let snapshotView = self.badgeNode.view.snapshotContentTree() {
                            snapshotView.frame = self.badgeNode.frame
                            self.badgeNode.view.superview?.insertSubview(snapshotView, aboveSubview: self.badgeNode.view)
                            snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false, completion: { [weak snapshotView] _ in
                                snapshotView?.removeFromSuperview()
                            })
                        }
                    }
                }
                
                self.backButtonNode.removeFromSupernode()
                self.backButtonArrow.removeFromSupernode()
                self.badgeNode.removeFromSupernode()
                
                if let leftBarButtonItem = item.leftBarButtonItem {
                    self.leftButtonNode.updateItems([leftBarButtonItem])
                } else {
                    self.leftButtonNode.updateItems([UIBarButtonItem(title: self.presentationData.strings.close, style: .plain, target: nil, action: nil)])
                }
                
                if self.leftButtonNode.supernode == nil {
                    self.clippingNode.addSubnode(self.leftButtonNode)
                }
                
                if animated {
                    self.leftButtonNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
                }
            } else {
                if animated {
                    if self.leftButtonNode.view.superview != nil {
                        if let snapshotView = self.leftButtonNode.view.snapshotContentTree() {
                            snapshotView.frame = self.leftButtonNode.frame
                            self.leftButtonNode.view.superview?.insertSubview(snapshotView, aboveSubview: self.leftButtonNode.view)
                            snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false, completion: { [weak snapshotView] _ in
                                snapshotView?.removeFromSuperview()
                            })
                        }
                    }
                }
                self.leftButtonNode.removeFromSupernode()
                
                var backTitle: String?
                if let leftBarButtonItem = item.leftBarButtonItem, leftBarButtonItem.backButtonAppearance {
                    backTitle = leftBarButtonItem.title
                } else if let previousItem = self.previousItem {
                    switch previousItem {
                        case let .item(itemValue):
                            if let backBarButtonItem = itemValue.backBarButtonItem {
                                backTitle = backBarButtonItem.title ?? self.presentationData.strings.back
                            } else {
                                backTitle = itemValue.title ?? self.presentationData.strings.back
                            }
                        case .close:
                            backTitle = nil
                    }
                }
                
                if let backTitle = backTitle {
                    self.backButtonNode.updateManualText(backTitle)
                    if self.backButtonNode.supernode == nil {
                        self.clippingNode.addSubnode(self.backButtonNode)
                        self.clippingNode.addSubnode(self.backButtonArrow)
                        self.clippingNode.addSubnode(self.badgeNode)
                    }
                    
                    if animated {
                        self.backButtonNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
                        self.backButtonArrow.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
                        self.badgeNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
                    }
                } else {
                    self.backButtonNode.removeFromSupernode()
                }
            }
        } else {
            self.leftButtonNode.removeFromSupernode()
            self.backButtonNode.removeFromSupernode()
            self.backButtonArrow.removeFromSupernode()
            self.badgeNode.removeFromSupernode()
        }
        
        self.updateAccessibilityElements()
        if animated {
            self.hintAnimateTitleNodeOnNextLayout = true
        }
    }
    
    private func updateRightButton(animated: Bool) {
        if let item = self.item {
            var items: [UIBarButtonItem] = []
            if let rightBarButtonItems = item.rightBarButtonItems, !rightBarButtonItems.isEmpty {
                items = rightBarButtonItems
            } else if let rightBarButtonItem = item.rightBarButtonItem {
                items = [rightBarButtonItem]
            }
            
            if !items.isEmpty {
                if animated, self.rightButtonNode.view.superview != nil {
                    if let snapshotView = self.rightButtonNode.view.snapshotContentTree() {
                        snapshotView.frame = self.rightButtonNode.frame
                        self.rightButtonNode.view.superview?.insertSubview(snapshotView, aboveSubview: self.rightButtonNode.view)
                        snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false, completion: { [weak snapshotView] _ in
                            snapshotView?.removeFromSuperview()
                        })
                    }
                }
                self.rightButtonNode.updateItems(items)
                if self.rightButtonNode.supernode == nil {
                    self.clippingNode.addSubnode(self.rightButtonNode)
                }
                if animated {
                    self.rightButtonNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.15)
                }
            } else {
                self.rightButtonNode.removeFromSupernode()
            }
        } else {
            self.rightButtonNode.removeFromSupernode()
        }
        
        if animated {
            self.hintAnimateTitleNodeOnNextLayout = true
        }
        self.updateAccessibilityElements()
    }
    
    private let backButtonNode: NavigationButtonNode
    private let badgeNode: NavigationBarBadgeNode
    private let backButtonArrow: ASImageNode
    private let leftButtonNode: NavigationButtonNode
    private let rightButtonNode: NavigationButtonNode
    
    
    private var _transitionState: NavigationBarTransitionState?
    var transitionState: NavigationBarTransitionState? {
        get {
            return self._transitionState
        } set(value) {
            let updateNodes = self._transitionState?.navigationBar !== value?.navigationBar
            
            self._transitionState = value
            
            if updateNodes {
                if let transitionTitleNode = self.transitionTitleNode {
                    transitionTitleNode.removeFromSupernode()
                    self.transitionTitleNode = nil
                }
                
                if let transitionBackButtonNode = self.transitionBackButtonNode {
                    transitionBackButtonNode.removeFromSupernode()
                    self.transitionBackButtonNode = nil
                }
                
                if let transitionBackArrowNode = self.transitionBackArrowNode {
                    transitionBackArrowNode.removeFromSupernode()
                    self.transitionBackArrowNode = nil
                }
                
                if let transitionBadgeNode = self.transitionBadgeNode {
                    transitionBadgeNode.removeFromSupernode()
                    self.transitionBadgeNode = nil
                }

                if let value = value {
                    switch value.role {
                        case .top:
                            if let transitionTitleNode = value.navigationBar?.makeTransitionTitleNode(foregroundColor: self.presentationData.theme.primaryTextColor) {
                                self.transitionTitleNode = transitionTitleNode
                                if self.leftButtonNode.supernode != nil {
                                    self.clippingNode.insertSubnode(transitionTitleNode, belowSubnode: self.leftButtonNode)
                                } else if self.backButtonNode.supernode != nil {
                                    self.clippingNode.insertSubnode(transitionTitleNode, belowSubnode: self.backButtonNode)
                                } else {
                                    self.clippingNode.addSubnode(transitionTitleNode)
                                }
                            }
                        case .bottom:
                            if let transitionBackButtonNode = value.navigationBar?.makeTransitionBackButtonNode(accentColor: self.presentationData.theme.buttonColor) {
                                self.transitionBackButtonNode = transitionBackButtonNode
                                self.clippingNode.addSubnode(transitionBackButtonNode)
                            }
                            if let transitionBackArrowNode = value.navigationBar?.makeTransitionBackArrowNode(accentColor: self.presentationData.theme.buttonColor) {
                                self.transitionBackArrowNode = transitionBackArrowNode
                                self.clippingNode.addSubnode(transitionBackArrowNode)
                            }
                            if let transitionBadgeNode = value.navigationBar?.makeTransitionBadgeNode() {
                                self.transitionBadgeNode = transitionBadgeNode
                                self.clippingNode.addSubnode(transitionBadgeNode)
                            }
                    }
                }
            }
            
            self.requestedLayout = true
            self.layout()
        }
    }
    
    private var transitionTitleNode: ASDisplayNode?
    private var transitionBackButtonNode: NavigationButtonNode?
    private var transitionBackArrowNode: ASDisplayNode?
    private var transitionBadgeNode: ASDisplayNode?
    
    public init(presentationData: NavigationBarPresentationData) {
        self.presentationData = presentationData
        self.stripeNode = ASDisplayNode()
        
        self.titleNode = ASTextNode()
        self.titleNode.isAccessibilityElement = true
        self.titleNode.accessibilityTraits = .header
        
        self.backButtonNode = NavigationButtonNode()
        self.badgeNode = NavigationBarBadgeNode(fillColor: self.presentationData.theme.badgeBackgroundColor, strokeColor: self.presentationData.theme.badgeStrokeColor, textColor: self.presentationData.theme.badgeTextColor)
        self.badgeNode.isUserInteractionEnabled = false
        self.badgeNode.isHidden = true
        self.backButtonArrow = ASImageNode()
        self.backButtonArrow.displayWithoutProcessing = true
        self.backButtonArrow.displaysAsynchronously = false
        self.leftButtonNode = NavigationButtonNode()
        self.rightButtonNode = NavigationButtonNode()
        self.rightButtonNode.hitTestSlop = UIEdgeInsets(top: -4.0, left: -4.0, bottom: -4.0, right: -10.0)
        
        self.clippingNode = ASDisplayNode()
        self.clippingNode.clipsToBounds = true
        
        self.backButtonNode.color = self.presentationData.theme.buttonColor
        self.backButtonNode.disabledColor = self.presentationData.theme.disabledButtonColor
        self.leftButtonNode.color = self.presentationData.theme.buttonColor
        self.leftButtonNode.disabledColor = self.presentationData.theme.disabledButtonColor
        self.rightButtonNode.color = self.presentationData.theme.buttonColor
        self.rightButtonNode.disabledColor = self.presentationData.theme.disabledButtonColor
        self.backButtonArrow.image = backArrowImage(color: self.presentationData.theme.buttonColor)
        if let title = self.title {
            self.titleNode.attributedText = NSAttributedString(string: title, font: Font.semibold(17.0), textColor: self.presentationData.theme.primaryTextColor)
            self.titleNode.accessibilityLabel = title
        }
        self.stripeNode.backgroundColor = self.presentationData.theme.separatorColor
        
        super.init()
        
        self.addSubnode(self.clippingNode)
        
        self.backgroundColor = self.presentationData.theme.backgroundColor
        
        self.stripeNode.isLayerBacked = true
        self.stripeNode.displaysAsynchronously = false
        self.addSubnode(self.stripeNode)
        
        self.titleNode.displaysAsynchronously = false
        self.titleNode.maximumNumberOfLines = 1
        self.titleNode.truncationMode = .byTruncatingTail
        self.titleNode.isOpaque = false
        
        self.backButtonNode.highlightChanged = { [weak self] index, highlighted in
            if let strongSelf = self, index == 0 {
                strongSelf.backButtonArrow.alpha = (highlighted ? 0.4 : 1.0)
            }
        }
        self.backButtonNode.pressed = { [weak self] index in
            if let strongSelf = self, index == 0 {
                if let leftBarButtonItem = strongSelf.item?.leftBarButtonItem, leftBarButtonItem.backButtonAppearance {
                    leftBarButtonItem.performActionOnTarget()
                } else {
                    strongSelf.backPressed()
                }
            }
        }
        
        self.leftButtonNode.pressed = { [weak self] index in
            if let item = self?.item {
                if index == 0 {
                    if let leftBarButtonItem = item.leftBarButtonItem {
                        leftBarButtonItem.performActionOnTarget()
                    } else if let previousItem = self?.previousItem, case .close = previousItem {
                        self?.backPressed()
                    }
                }
            }
        }
        
        self.rightButtonNode.pressed = { [weak self] index in
            if let item = self?.item {
                if let rightBarButtonItems = item.rightBarButtonItems, !rightBarButtonItems.isEmpty {
                    if index < rightBarButtonItems.count {
                        rightBarButtonItems[index].performActionOnTarget()
                    }
                } else if let rightBarButtonItem = item.rightBarButtonItem {
                    rightBarButtonItem.performActionOnTarget()
                }
            }
        }
    }
    
    public func updatePresentationData(_ presentationData: NavigationBarPresentationData) {
        if presentationData.theme !== self.presentationData.theme || presentationData.strings !== self.presentationData.strings {
            self.presentationData = presentationData
            
            self.backgroundColor = self.presentationData.theme.backgroundColor
            
            self.backButtonNode.color = self.presentationData.theme.buttonColor
            self.backButtonNode.disabledColor = self.presentationData.theme.disabledButtonColor
            self.leftButtonNode.color = self.presentationData.theme.buttonColor
            self.leftButtonNode.disabledColor = self.presentationData.theme.disabledButtonColor
            self.rightButtonNode.color = self.presentationData.theme.buttonColor
            self.rightButtonNode.disabledColor = self.presentationData.theme.disabledButtonColor
            self.backButtonArrow.image = backArrowImage(color: self.presentationData.theme.buttonColor)
            if let title = self.title {
                self.titleNode.attributedText = NSAttributedString(string: title, font: Font.semibold(17.0), textColor: self.presentationData.theme.primaryTextColor)
                self.titleNode.accessibilityLabel = title
            }
            self.stripeNode.backgroundColor = self.presentationData.theme.separatorColor
            
            self.badgeNode.updateTheme(fillColor: self.presentationData.theme.badgeBackgroundColor, strokeColor: self.presentationData.theme.badgeStrokeColor, textColor: self.presentationData.theme.badgeTextColor)
        }
    }
    
    private func requestLayout() {
        self.requestedLayout = true
        self.setNeedsLayout()
    }
    
    override open func layout() {
        super.layout()
        
        if let validLayout = self.validLayout, self.requestedLayout {
            self.requestedLayout = false
            self.updateLayout(size: validLayout.0, defaultHeight: validLayout.1, leftInset: validLayout.2, rightInset: validLayout.3, transition: .immediate)
        }
    }
    
    func updateLayout(size: CGSize, defaultHeight: CGFloat, leftInset: CGFloat, rightInset: CGFloat, transition: ContainedViewLayoutTransition) {
        if self.layoutSuspended {
            return
        }
        
        self.validLayout = (size, defaultHeight, leftInset, rightInset)
        
        let leftButtonInset: CGFloat = leftInset + 16.0
        let backButtonInset: CGFloat = leftInset + 27.0
        
        transition.updateFrame(node: self.clippingNode, frame: CGRect(origin: CGPoint(), size: size))
        var expansionHeight: CGFloat = 0.0
        if let contentNode = self.contentNode {
            let contentNodeFrame: CGRect
            switch contentNode.mode {
                case .replacement:
                    expansionHeight = contentNode.height - defaultHeight
                    contentNodeFrame = CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: size.width, height: size.height))
                case .expansion:
                    expansionHeight = contentNode.height
                    contentNodeFrame = CGRect(origin: CGPoint(x: 0.0, y: size.height - expansionHeight), size: CGSize(width: size.width, height: expansionHeight))
            }
            transition.updateFrame(node: contentNode, frame: contentNodeFrame)
            contentNode.updateLayout(size: contentNodeFrame.size, leftInset: leftInset, rightInset: rightInset, transition: transition)
        }
        
        transition.updateFrame(node: self.stripeNode, frame: CGRect(x: 0.0, y: size.height, width: size.width, height: UIScreenPixel))
        
        let nominalHeight: CGFloat = self.collapsed ? 32.0 : defaultHeight
        let contentVerticalOrigin = size.height - nominalHeight - expansionHeight
        
        var leftTitleInset: CGFloat = leftInset + 1.0
        var rightTitleInset: CGFloat = rightInset + 1.0
        if self.backButtonNode.supernode != nil {
            let backButtonSize = self.backButtonNode.updateLayout(constrainedSize: CGSize(width: size.width, height: nominalHeight))
            leftTitleInset += backButtonSize.width + backButtonInset + 1.0
            
            let topHitTestSlop = (nominalHeight - backButtonSize.height) * 0.5
            self.backButtonNode.hitTestSlop = UIEdgeInsets(top: -topHitTestSlop, left: -27.0, bottom: -topHitTestSlop, right: -8.0)
            
            if let transitionState = self.transitionState {
                let progress = transitionState.progress
                
                switch transitionState.role {
                    case .top:
                        let initialX: CGFloat = backButtonInset
                        let finalX: CGFloat = floor((size.width - backButtonSize.width) / 2.0) - size.width
                        
                        self.backButtonNode.frame = CGRect(origin: CGPoint(x: initialX * (1.0 - progress) + finalX * progress, y: contentVerticalOrigin + floor((nominalHeight - backButtonSize.height) / 2.0)), size: backButtonSize)
                        self.backButtonNode.alpha = (1.0 - progress) * (1.0 - progress)
                    
                        if let transitionTitleNode = self.transitionTitleNode {
                            let transitionTitleSize = transitionTitleNode.measure(CGSize(width: size.width, height: nominalHeight))
                            
                            let initialX: CGFloat = backButtonInset + floor((backButtonSize.width - transitionTitleSize.width) / 2.0)
                            let finalX: CGFloat = floor((size.width - transitionTitleSize.width) / 2.0) - size.width
                            
                            transitionTitleNode.frame = CGRect(origin: CGPoint(x: initialX * (1.0 - progress) + finalX * progress, y: contentVerticalOrigin + floor((nominalHeight - transitionTitleSize.height) / 2.0)), size: transitionTitleSize)
                            transitionTitleNode.alpha = progress * progress
                        }
                    
                        self.backButtonArrow.frame = CGRect(origin: CGPoint(x: leftInset + 8.0 - progress * size.width, y: contentVerticalOrigin + floor((nominalHeight - 22.0) / 2.0)), size: CGSize(width: 13.0, height: 22.0))
                        self.backButtonArrow.alpha = max(0.0, 1.0 - progress * 1.3)
                        self.badgeNode.alpha = max(0.0, 1.0 - progress * 1.3)
                    case .bottom:
                        self.backButtonNode.alpha = 1.0
                        self.backButtonNode.frame = CGRect(origin: CGPoint(x: backButtonInset, y: contentVerticalOrigin + floor((nominalHeight - backButtonSize.height) / 2.0)), size: backButtonSize)
                        self.backButtonArrow.alpha = 1.0
                        self.backButtonArrow.frame = CGRect(origin: CGPoint(x: leftInset + 8.0, y: contentVerticalOrigin + floor((nominalHeight - 22.0) / 2.0)), size: CGSize(width: 13.0, height: 22.0))
                        self.badgeNode.alpha = 1.0
                }
            } else {
                self.backButtonNode.alpha = 1.0
                self.backButtonNode.frame = CGRect(origin: CGPoint(x: backButtonInset, y: contentVerticalOrigin + floor((nominalHeight - backButtonSize.height) / 2.0)), size: backButtonSize)
                self.backButtonArrow.alpha = 1.0
                self.backButtonArrow.frame = CGRect(origin: CGPoint(x: leftInset + 8.0, y: contentVerticalOrigin + floor((nominalHeight - 22.0) / 2.0)), size: CGSize(width: 13.0, height: 22.0))
                self.badgeNode.alpha = 1.0
            }
        } else if self.leftButtonNode.supernode != nil {
            let leftButtonSize = self.leftButtonNode.updateLayout(constrainedSize: CGSize(width: size.width, height: nominalHeight))
            leftTitleInset += leftButtonSize.width + leftButtonInset + 1.0
            
            self.leftButtonNode.alpha = 1.0
            self.leftButtonNode.frame = CGRect(origin: CGPoint(x: leftButtonInset, y: contentVerticalOrigin + floor((nominalHeight - leftButtonSize.height) / 2.0)), size: leftButtonSize)
        }
        
        let badgeSize = self.badgeNode.measure(CGSize(width: 200.0, height: 100.0))
        let backButtonArrowFrame = self.backButtonArrow.frame
        self.badgeNode.frame = CGRect(origin: backButtonArrowFrame.origin.offsetBy(dx: 7.0, dy: -9.0), size: badgeSize)
        
        if self.rightButtonNode.supernode != nil {
            let rightButtonSize = self.rightButtonNode.updateLayout(constrainedSize: (CGSize(width: size.width, height: nominalHeight)))
            rightTitleInset += rightButtonSize.width + leftButtonInset + 1.0
            self.rightButtonNode.alpha = 1.0
            self.rightButtonNode.frame = CGRect(origin: CGPoint(x: size.width - leftButtonInset - rightButtonSize.width, y: contentVerticalOrigin + floor((nominalHeight - rightButtonSize.height) / 2.0)), size: rightButtonSize)
        }
        
        if let transitionState = self.transitionState {
            let progress = transitionState.progress
            
            switch transitionState.role {
                case .top:
                    break
                case .bottom:
                    if let transitionBackButtonNode = self.transitionBackButtonNode {
                        let transitionBackButtonSize = transitionBackButtonNode.updateLayout(constrainedSize: CGSize(width: size.width, height: nominalHeight))
                        let initialX: CGFloat = backButtonInset + size.width * 0.3
                        let finalX: CGFloat = floor((size.width - transitionBackButtonSize.width) / 2.0)
                        
                        transitionBackButtonNode.frame = CGRect(origin: CGPoint(x: initialX * (1.0 - progress) + finalX * progress, y: contentVerticalOrigin + floor((nominalHeight - transitionBackButtonSize.height) / 2.0)), size: transitionBackButtonSize)
                        transitionBackButtonNode.alpha = (1.0 - progress) * (1.0 - progress)
                    }
                
                    if let transitionBackArrowNode = self.transitionBackArrowNode {
                        let initialX: CGFloat = leftInset + 8.0 + size.width * 0.3
                        let finalX: CGFloat = leftInset + 8.0
                        
                        transitionBackArrowNode.frame = CGRect(origin: CGPoint(x: initialX * (1.0 - progress) + finalX * progress, y: contentVerticalOrigin + floor((nominalHeight - 22.0) / 2.0)), size: CGSize(width: 13.0, height: 22.0))
                        transitionBackArrowNode.alpha = max(0.0, 1.0 - progress * 1.3)
                        
                        if let transitionBadgeNode = self.transitionBadgeNode {
                            transitionBadgeNode.frame = CGRect(origin: transitionBackArrowNode.frame.origin.offsetBy(dx: 7.0, dy: -9.0), size: transitionBadgeNode.bounds.size)
                            transitionBadgeNode.alpha = transitionBackArrowNode.alpha
                        }
                    }
                }
        }
        
        leftTitleInset = floor(leftTitleInset)
        if Int(leftTitleInset) % 2 != 0 {
            leftTitleInset -= 1.0
        }
        
        if self.titleNode.supernode != nil {
            let titleSize = self.titleNode.measure(CGSize(width: max(1.0, size.width - max(leftTitleInset, rightTitleInset) * 2.0), height: nominalHeight))
            
            if let transitionState = self.transitionState, let otherNavigationBar = transitionState.navigationBar {
                let progress = transitionState.progress
                
                switch transitionState.role {
                    case .top:
                        let initialX = floor((size.width - titleSize.width) / 2.0)
                        let finalX: CGFloat = leftButtonInset
                        
                        self.titleNode.frame = CGRect(origin: CGPoint(x: initialX * (1.0 - progress) + finalX * progress, y: contentVerticalOrigin + floorToScreenPixels((nominalHeight - titleSize.height) / 2.0)), size: titleSize)
                        self.titleNode.alpha = (1.0 - progress) * (1.0 - progress)
                    case .bottom:
                        var initialX: CGFloat = backButtonInset
                        if otherNavigationBar.backButtonNode.supernode != nil {
                            initialX += floor((otherNavigationBar.backButtonNode.frame.size.width - titleSize.width) / 2.0)
                        }
                        initialX += size.width * 0.3
                        let finalX: CGFloat = floor((size.width - titleSize.width) / 2.0)
                        
                        self.titleNode.frame = CGRect(origin: CGPoint(x: initialX * (1.0 - progress) + finalX * progress, y: contentVerticalOrigin + floorToScreenPixels((nominalHeight - titleSize.height) / 2.0)), size: titleSize)
                    self.titleNode.alpha = progress * progress
                }
            } else {
                self.titleNode.alpha = 1.0
                self.titleNode.frame = CGRect(origin: CGPoint(x: floor((size.width - titleSize.width) / 2.0), y: contentVerticalOrigin + floorToScreenPixels((nominalHeight - titleSize.height) / 2.0)), size: titleSize)
            }
        }
        
        if let titleView = self.titleView {
            let titleSize = CGSize(width: max(1.0, size.width - max(leftTitleInset, rightTitleInset) * 2.0), height: nominalHeight)
            let titleFrame = CGRect(origin: CGPoint(x: leftTitleInset, y: contentVerticalOrigin), size: titleSize)
            titleView.frame = titleFrame
            
            if let titleView = titleView as? NavigationBarTitleView {
                let titleWidth = size.width - (leftTitleInset > 0.0 ? leftTitleInset : rightTitleInset) - (rightTitleInset > 0.0 ? rightTitleInset : leftTitleInset)
                
                titleView.updateLayout(size: titleFrame.size, clearBounds: CGRect(origin: CGPoint(x: leftTitleInset - titleFrame.minX, y: 0.0), size: CGSize(width: titleWidth, height: titleFrame.height)), transition: transition)
            }
            
            if let transitionState = self.transitionState, let otherNavigationBar = transitionState.navigationBar {
                let progress = transitionState.progress
                
                switch transitionState.role {
                    case .top:
                        let initialX = floor((size.width - titleSize.width) / 2.0)
                        let finalX: CGFloat = leftButtonInset
                        
                        titleView.frame = CGRect(origin: CGPoint(x: initialX * (1.0 - progress) + finalX * progress, y: contentVerticalOrigin + floorToScreenPixels((nominalHeight - titleSize.height) / 2.0)), size: titleSize)
                        titleView.alpha = (1.0 - progress) * (1.0 - progress)
                    case .bottom:
                        var initialX: CGFloat = backButtonInset
                        if otherNavigationBar.backButtonNode.supernode != nil {
                            initialX += floor((otherNavigationBar.backButtonNode.frame.size.width - titleSize.width) / 2.0)
                        }
                        initialX += size.width * 0.3
                        let finalX: CGFloat = floor((size.width - titleSize.width) / 2.0)
                        
                        titleView.frame = CGRect(origin: CGPoint(x: initialX * (1.0 - progress) + finalX * progress, y: contentVerticalOrigin + floorToScreenPixels((nominalHeight - titleSize.height) / 2.0)), size: titleSize)
                        titleView.alpha = progress * progress
                }
            } else {
                if self.hintAnimateTitleNodeOnNextLayout {
                    self.hintAnimateTitleNodeOnNextLayout = false
                    if let titleView = titleView as? NavigationBarTitleView {
                        titleView.animateLayoutTransition()
                    }
                }
                titleView.alpha = 1.0
                titleView.frame = CGRect(origin: CGPoint(x: floor((size.width - titleSize.width) / 2.0), y: contentVerticalOrigin + floorToScreenPixels((nominalHeight - titleSize.height) / 2.0)), size: titleSize)
            }
        }
    }
    
    public func makeTransitionTitleNode(foregroundColor: UIColor) -> ASDisplayNode? {
        if let titleView = self.titleView {
            if let transitionView = titleView as? NavigationBarTitleTransitionNode {
                return transitionView.makeTransitionMirrorNode()
            } else {
                return nil
            }
        } else if let title = self.title {
            let node = ASTextNode()
            node.attributedText = NSAttributedString(string: title, font: Font.semibold(17.0), textColor: foregroundColor)
            return node
        } else {
            return nil
        }
    }
    
    private func makeTransitionBackButtonNode(accentColor: UIColor) -> NavigationButtonNode? {
        if self.backButtonNode.supernode != nil {
            let node = NavigationButtonNode()
            node.updateManualText(self.backButtonNode.manualText)
            node.color = accentColor
            return node
        } else {
            return nil
        }
    }
    
    private func makeTransitionBackArrowNode(accentColor: UIColor) -> ASDisplayNode? {
        if self.backButtonArrow.supernode != nil {
            let node = ASImageNode()
            node.image = backArrowImage(color: accentColor)
            node.frame = self.backButtonArrow.frame
            node.displayWithoutProcessing = true
            node.displaysAsynchronously = false
            return node
        } else {
            return nil
        }
    }
    
    private func makeTransitionBadgeNode() -> ASDisplayNode? {
        if self.badgeNode.supernode != nil && !self.badgeNode.isHidden {
            let node = NavigationBarBadgeNode(fillColor: self.presentationData.theme.badgeBackgroundColor, strokeColor: self.presentationData.theme.badgeStrokeColor, textColor: self.presentationData.theme.badgeTextColor)
            node.text = self.badgeNode.text
            let nodeSize = node.measure(CGSize(width: 200.0, height: 100.0))
            node.frame = CGRect(origin: CGPoint(), size: nodeSize)
            return node
        } else {
            return nil
        }
    }
    
    public var intrinsicCanTransitionInline: Bool = true
    
    public var canTransitionInline: Bool {
        if let contentNode = self.contentNode, case .replacement = contentNode.mode {
            return false
        } else {
            return self.intrinsicCanTransitionInline
        }
    }
    
    public func contentHeight(defaultHeight: CGFloat) -> CGFloat {
        if let contentNode = self.contentNode {
            switch contentNode.mode {
                case .expansion:
                    return defaultHeight + contentNode.height
                case .replacement:
                    return contentNode.height
            }
        } else {
            return defaultHeight
        }
    }
    
    public func setContentNode(_ contentNode: NavigationBarContentNode?, animated: Bool) {
        if self.contentNode !== contentNode {
            if let previous = self.contentNode {
                if animated {
                    previous.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak self, weak previous] _ in
                        if let strongSelf = self, let previous = previous {
                            if previous !== strongSelf.contentNode {
                                previous.removeFromSupernode()
                            }
                        }
                    })
                } else {
                    previous.removeFromSupernode()
                }
            }
            self.contentNode = contentNode
            self.contentNode?.requestContainerLayout = { [weak self] transition in
                self?.requestContainerLayout(transition)
            }
            if let contentNode = contentNode {
                contentNode.clipsToBounds = true
                contentNode.layer.removeAnimation(forKey: "opacity")
                self.insertSubnode(contentNode, belowSubnode: self.stripeNode)
                if animated {
                    contentNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                }
                
                if case .replacement = contentNode.mode, !self.clippingNode.alpha.isZero {
                    self.clippingNode.alpha = 0.0
                    if animated {
                        self.clippingNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2)
                    }
                }
                
                if !self.bounds.size.width.isZero {
                    self.requestedLayout = true
                    self.layout()
                } else {
                    self.requestLayout()
                }
            } else if self.clippingNode.alpha.isZero {
                self.clippingNode.alpha = 1.0
                if animated {
                    self.clippingNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                }
            }
        }
    }
    
    public func executeBack() -> Bool {
        if self.backButtonNode.isInHierarchy {
            self.backButtonNode.pressed(0)
        } else if self.leftButtonNode.isInHierarchy {
            self.leftButtonNode.pressed(0)
        } else {
            self.backButtonNode.pressed(0)
        }
        return true
    }
    
    public func setHidden(_ hidden: Bool, animated: Bool) {
        if let contentNode = self.contentNode, case .replacement = contentNode.mode {
        } else {
            let targetAlpha: CGFloat = hidden ? 0.0 : 1.0
            let previousAlpha = self.clippingNode.alpha
            if previousAlpha != targetAlpha {
                self.clippingNode.alpha = targetAlpha
                if animated {
                    self.clippingNode.layer.animateAlpha(from: previousAlpha, to: targetAlpha, duration: 0.2)
                }
            }
        }
    }
}
