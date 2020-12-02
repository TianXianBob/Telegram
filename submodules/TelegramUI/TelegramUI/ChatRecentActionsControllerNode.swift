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
import SafariServices
import AccountContext
import TemporaryCachedPeerDataManager
import AlertUI
import PresentationDataUtils
import OpenInExternalAppUI
import InstantPageUI
import HashtagSearchUI
import StickerPackPreviewUI
import JoinLinkPreviewUI
import LanguageLinkPreviewUI
import PeerInfoUI

private final class ChatRecentActionsListOpaqueState {
    let entries: [ChatRecentActionsEntry]
    let canLoadEarlier: Bool
    
    init(entries: [ChatRecentActionsEntry], canLoadEarlier: Bool) {
        self.entries = entries
        self.canLoadEarlier = canLoadEarlier
    }
}

final class ChatRecentActionsControllerNode: ViewControllerTracingNode {
    private let context: AccountContext
    private let peer: Peer
    private var presentationData: PresentationData
    
    private let pushController: (ViewController) -> Void
    private let presentController: (ViewController, Any?) -> Void
    private let getNavigationController: () -> NavigationController?
    
    private let interaction: ChatRecentActionsInteraction
    private var controllerInteraction: ChatControllerInteraction!
    
    private let galleryHiddenMesageAndMediaDisposable = MetaDisposable()
    
    private var chatPresentationDataPromise: Promise<ChatPresentationData>
    private var presentationDataDisposable: Disposable?
    
    private var automaticMediaDownloadSettings: MediaAutoDownloadSettings
    
    private var state: ChatRecentActionsControllerState
    private var containerLayout: (ContainerViewLayout, CGFloat)?
    
    private let backgroundNode: ASDisplayNode
    private let panelBackgroundNode: ASDisplayNode
    private let panelSeparatorNode: ASDisplayNode
    private let panelButtonNode: HighlightableButtonNode
    
    private let listNode: ListView
    private let loadingNode: ChatLoadingNode
    private let emptyNode: ChatRecentActionsEmptyNode
    
    private let navigationActionDisposable = MetaDisposable()
    
    private var isLoading: Bool = false {
        didSet {
            if self.isLoading != oldValue {
                self.loadingNode.isHidden = !self.isLoading
            }
        }
    }
    
    private(set) var filter: ChannelAdminEventLogFilter = ChannelAdminEventLogFilter()
    private let eventLogContext: ChannelAdminEventLogContext
    
    private var enqueuedTransitions: [(ChatRecentActionsHistoryTransition, Bool)] = []
    
    private var historyDisposable: Disposable?
    private let resolvePeerByNameDisposable = MetaDisposable()
    private var adminsDisposable: Disposable?
    private var adminsState: ChannelMemberListState?
    private let banDisposables = DisposableDict<PeerId>()
    
    init(context: AccountContext, peer: Peer, presentationData: PresentationData, interaction: ChatRecentActionsInteraction, pushController: @escaping (ViewController) -> Void, presentController: @escaping (ViewController, Any?) -> Void, getNavigationController: @escaping () -> NavigationController?) {
        self.context = context
        self.peer = peer
        self.presentationData = presentationData
        self.interaction = interaction
        self.pushController = pushController
        self.presentController = presentController
        self.getNavigationController = getNavigationController
        
        self.automaticMediaDownloadSettings = context.sharedContext.currentAutomaticMediaDownloadSettings.with { $0 }
        
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        
        self.panelBackgroundNode = ASDisplayNode()
        self.panelBackgroundNode.backgroundColor = self.presentationData.theme.chat.inputPanel.panelBackgroundColor
        self.panelSeparatorNode = ASDisplayNode()
        self.panelSeparatorNode.backgroundColor = self.presentationData.theme.chat.inputPanel.panelSeparatorColor
        self.panelButtonNode = HighlightableButtonNode()
        self.panelButtonNode.setTitle(self.presentationData.strings.Channel_AdminLog_InfoPanelTitle, with: Font.regular(17.0), with: self.presentationData.theme.chat.inputPanel.panelControlAccentColor, for: [])
        
        self.listNode = ListView()
        self.listNode.dynamicBounceEnabled = !self.presentationData.disableAnimations
        self.listNode.transform = CATransform3DMakeRotation(CGFloat(Double.pi), 0.0, 0.0, 1.0)
        self.loadingNode = ChatLoadingNode(theme: self.presentationData.theme, chatWallpaper: self.presentationData.chatWallpaper)
        self.emptyNode = ChatRecentActionsEmptyNode(theme: self.presentationData.theme, chatWallpaper: self.presentationData.chatWallpaper)
        self.emptyNode.alpha = 0.0
        
        self.state = ChatRecentActionsControllerState(chatWallpaper: self.presentationData.chatWallpaper, theme: self.presentationData.theme, strings: self.presentationData.strings, fontSize: self.presentationData.fontSize)
        
        self.chatPresentationDataPromise = Promise(ChatPresentationData(theme: ChatPresentationThemeData(theme: self.presentationData.theme, wallpaper: self.presentationData.chatWallpaper), fontSize: self.presentationData.fontSize, strings: self.presentationData.strings, dateTimeFormat: self.presentationData.dateTimeFormat, nameDisplayOrder: self.presentationData.nameDisplayOrder, disableAnimations: self.presentationData.disableAnimations, largeEmoji: self.presentationData.largeEmoji))
        
        self.eventLogContext = ChannelAdminEventLogContext(postbox: self.context.account.postbox, network: self.context.account.network, peerId: self.peer.id)
        
        super.init()
        
        self.backgroundNode.contents = chatControllerBackgroundImage(theme: self.state.theme, wallpaper: self.state.chatWallpaper, mediaBox: context.sharedContext.accountManager.mediaBox, knockoutMode: context.sharedContext.immediateExperimentalUISettings.knockoutWallpaper)?.cgImage
        
        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.listNode)
        self.addSubnode(self.loadingNode)
        self.addSubnode(self.emptyNode)
        self.addSubnode(self.panelBackgroundNode)
        self.addSubnode(self.panelSeparatorNode)
        self.addSubnode(self.panelButtonNode)
        
        self.panelButtonNode.addTarget(self, action: #selector(self.infoButtonPressed), forControlEvents: .touchUpInside)
        
        let (adminsDisposable, _) = self.context.peerChannelMemberCategoriesContextsManager.admins(postbox: self.context.account.postbox, network: self.context.account.network, accountPeerId: context.account.peerId, peerId: self.peer.id, searchQuery: nil, updated: { [weak self] state in
            self?.adminsState = state
        })
        self.adminsDisposable = adminsDisposable
        
        let controllerInteraction = ChatControllerInteraction(openMessage: { [weak self] message, _ in
            if let strongSelf = self, let navigationController = strongSelf.getNavigationController() {
                guard let state = strongSelf.listNode.opaqueTransactionState as? ChatRecentActionsListOpaqueState else {
                    return false
                }
                for entry in state.entries {
                    if entry.entry.stableId == message.stableId {
                        switch entry.entry.event.action {
                            case let .changeStickerPack(_, new):
                                if let new = new {
                                    strongSelf.presentController(StickerPackScreen(context: strongSelf.context, mainStickerPack: new, stickerPacks: [new], parentNavigationController: strongSelf.getNavigationController()), nil)
                                    return true
                                }
                            default:
                                break
                        }
                        
                        break
                    }
                }
                return context.sharedContext.openChatMessage(OpenChatMessageParams(context: context, message: message, standalone: true, reverseMessageGalleryOrder: false, navigationController: navigationController, dismissInput: {
                    //self?.chatDisplayNode.dismissInput()
                }, present: { c, a in
                    self?.presentController(c, a)
                }, transitionNode: { messageId, media in
                    var selectedNode: (ASDisplayNode, CGRect, () -> (UIView?, UIView?))?
                    if let strongSelf = self {
                        strongSelf.listNode.forEachItemNode { itemNode in
                            if let itemNode = itemNode as? ChatMessageItemView {
                                if let result = itemNode.transitionNode(id: messageId, media: media) {
                                    selectedNode = result
                                }
                            }
                        }
                    }
                    return selectedNode
                }, addToTransitionSurface: { view in
                    if let strongSelf = self {
                        strongSelf.listNode.view.superview?.insertSubview(view, aboveSubview: strongSelf.listNode.view)
                    }
                }, openUrl: { url in
                    self?.openUrl(url)
                }, openPeer: { peer, navigation in
                    self?.openPeer(peerId: peer.id, peer: peer)
                }, callPeer: { peerId in
                    self?.controllerInteraction?.callPeer(peerId)
                }, enqueueMessage: { _ in
                }, sendSticker: nil, setupTemporaryHiddenMedia: { _, _, _ in }, chatAvatarHiddenMedia: { _, _ in }))
            }
            return false
        }, openPeer: { [weak self] peerId, _, message in
            if let peerId = peerId {
                self?.openPeer(peerId: peerId, peer: message?.peers[peerId])
            }
        }, openPeerMention: { [weak self] name in
            self?.openPeerMention(name)
        }, openMessageContextMenu: { [weak self] message, selectAll, node, frame, _ in
            self?.openMessageContextMenu(message: message, selectAll: selectAll, node: node, frame: frame)
        }, openMessageContextActions: { _, _, _, _ in
        }, navigateToMessage: { _, _ in }, tapMessage: nil, clickThroughMessage: { }, toggleMessagesSelection: { _, _ in }, sendCurrentMessage: { _ in }, sendMessage: { _ in }, sendSticker: { _, _, _, _ in return false }, sendGif: { _, _, _ in return false }, requestMessageActionCallback: { _, _, _ in }, requestMessageActionUrlAuth: { _, _, _ in }, activateSwitchInline: { _, _ in }, openUrl: { [weak self] url, _, _, _ in
            self?.openUrl(url)
        }, shareCurrentLocation: {}, shareAccountContact: {}, sendBotCommand: { _, _ in }, openInstantPage: { [weak self] message, associatedData in
            if let strongSelf = self, let navigationController = strongSelf.getNavigationController() {
                openChatInstantPage(context: strongSelf.context, message: message, sourcePeerType: associatedData?.automaticDownloadPeerType, navigationController: navigationController)
            }
        }, openWallpaper: { [weak self] message in
            if let strongSelf = self{
                openChatWallpaper(context: strongSelf.context, message: message, present: { [weak self] c, a in
                    self?.presentController(c, a)
                })
            }
        }, openTheme: { _ in      
        }, openHashtag: { [weak self] peerName, hashtag in
            guard let strongSelf = self else {
                return
            }
            let resolveSignal: Signal<Peer?, NoError>
            if let peerName = peerName {
                resolveSignal = resolvePeerByName(account: strongSelf.context.account, name: peerName)
                    |> mapToSignal { peerId -> Signal<Peer?, NoError> in
                        if let peerId = peerId {
                            return context.account.postbox.loadedPeerWithId(peerId)
                            |> map(Optional.init)
                        } else {
                            return .single(nil)
                        }
                }
            } else {
                resolveSignal = context.account.postbox.loadedPeerWithId(strongSelf.peer.id)
                |> map(Optional.init)
            }
            strongSelf.resolvePeerByNameDisposable.set((resolveSignal
            |> deliverOnMainQueue).start(next: { peer in
                if let strongSelf = self, !hashtag.isEmpty {
                    let searchController = HashtagSearchController(context: strongSelf.context, peer: peer, query: hashtag)
                    strongSelf.pushController(searchController)
                }
            }))
            }, updateInputState: { _ in }, updateInputMode: { _ in }, openMessageShareMenu: { _ in
        }, presentController: { _, _ in
        }, navigationController: { [weak self] in
            return self?.getNavigationController()
        }, chatControllerNode: { [weak self] in
            return self
        }, reactionContainerNode: {
            return nil
        }, presentGlobalOverlayController: { _, _ in }, callPeer: { _ in }, longTap: { [weak self] action, message in
            if let strongSelf = self {
                switch action {
                    case let .url(url):
                        var cleanUrl = url
                        let canOpenIn = availableOpenInOptions(context: strongSelf.context, item: .url(url: url)).count > 1
                        var canAddToReadingList = true
                        let mailtoString = "mailto:"
                        let telString = "tel:"
                        var openText = strongSelf.presentationData.strings.Conversation_LinkDialogOpen
                        if cleanUrl.hasPrefix(mailtoString) {
                            canAddToReadingList = false
                            cleanUrl = String(cleanUrl[cleanUrl.index(cleanUrl.startIndex, offsetBy: mailtoString.distance(from: mailtoString.startIndex, to: mailtoString.endIndex))...])
                        } else if cleanUrl.hasPrefix(telString) {
                            canAddToReadingList = false
                            cleanUrl = String(cleanUrl[cleanUrl.index(cleanUrl.startIndex, offsetBy: telString.distance(from: telString.startIndex, to: telString.endIndex))...])
                            openText = strongSelf.presentationData.strings.Conversation_Call
                        } else if canOpenIn {
                            openText = strongSelf.presentationData.strings.Conversation_FileOpenIn
                        }
                        let actionSheet = ActionSheetController(presentationData: strongSelf.presentationData)
                        
                        var items: [ActionSheetItem] = []
                        items.append(ActionSheetTextItem(title: cleanUrl))
                        items.append(ActionSheetButtonItem(title: openText, color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                            if let strongSelf = self {
                                strongSelf.openUrl(url)
                            }
                        }))
                        items.append(ActionSheetButtonItem(title: canAddToReadingList ? strongSelf.presentationData.strings.ShareMenu_CopyShareLink : strongSelf.presentationData.strings.Conversation_ContextMenuCopy, color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                            UIPasteboard.general.string = cleanUrl
                        }))
                        if canAddToReadingList {
                            items.append(ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_AddToReadingList, color: .accent, action: { [weak actionSheet] in
                                actionSheet?.dismissAnimated()
                                if let link = URL(string: url) {
                                    let _ = try? SSReadingList.default()?.addItem(with: link, title: nil, previewText: nil)
                                }
                            }))
                        }
                        actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
                            ActionSheetButtonItem(title: strongSelf.presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                                actionSheet?.dismissAnimated()
                            })
                        ])])
                        strongSelf.presentController(actionSheet, nil)
                    case let .peerMention(peerId, mention):
                        let actionSheet = ActionSheetController(presentationData: strongSelf.presentationData)
                        var items: [ActionSheetItem] = []
                        if !mention.isEmpty {
                            items.append(ActionSheetTextItem(title: mention))
                        }
                        items.append(ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_LinkDialogOpen, color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                            if let strongSelf = self {
                                strongSelf.openPeer(peerId: peerId, peer: nil)
                            }
                        }))
                        if !mention.isEmpty {
                            items.append(ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_LinkDialogCopy, color: .accent, action: { [weak actionSheet] in
                                actionSheet?.dismissAnimated()
                                UIPasteboard.general.string = mention
                            }))
                        }
                        actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
                            ActionSheetButtonItem(title: strongSelf.presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                                actionSheet?.dismissAnimated()
                            })
                        ])])
                        strongSelf.presentController(actionSheet, nil)
                    case let .mention(mention):
                        let actionSheet = ActionSheetController(presentationData: strongSelf.presentationData)
                        actionSheet.setItemGroups([ActionSheetItemGroup(items: [
                            ActionSheetTextItem(title: mention),
                            ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_LinkDialogOpen, color: .accent, action: { [weak actionSheet] in
                                actionSheet?.dismissAnimated()
                                if let strongSelf = self {
                                    strongSelf.openPeerMention(mention)
                                }
                            }),
                            ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_LinkDialogCopy, color: .accent, action: { [weak actionSheet] in
                                actionSheet?.dismissAnimated()
                                UIPasteboard.general.string = mention
                            })
                            ]), ActionSheetItemGroup(items: [
                                ActionSheetButtonItem(title: strongSelf.presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                                    actionSheet?.dismissAnimated()
                                })
                            ])])
                        strongSelf.presentController(actionSheet, nil)
                    case let .command(command):
                        let actionSheet = ActionSheetController(presentationData: strongSelf.presentationData)
                        actionSheet.setItemGroups([ActionSheetItemGroup(items: [
                            ActionSheetTextItem(title: command),
                            ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_LinkDialogCopy, color: .accent, action: { [weak actionSheet] in
                                actionSheet?.dismissAnimated()
                                UIPasteboard.general.string = command
                            })
                            ]), ActionSheetItemGroup(items: [
                                ActionSheetButtonItem(title: strongSelf.presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                                    actionSheet?.dismissAnimated()
                                })
                            ])])
                        strongSelf.presentController(actionSheet, nil)
                    case let .hashtag(hashtag):
                        let actionSheet = ActionSheetController(presentationData:  strongSelf.presentationData)
                        actionSheet.setItemGroups([ActionSheetItemGroup(items: [
                            ActionSheetTextItem(title: hashtag),
                            ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_LinkDialogOpen, color: .accent, action: { [weak actionSheet] in
                                actionSheet?.dismissAnimated()
                                if let strongSelf = self {
                                    let searchController = HashtagSearchController(context: strongSelf.context, peer: strongSelf.peer, query: hashtag)
                                    strongSelf.pushController(searchController)
                                }
                            }),
                            ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_LinkDialogCopy, color: .accent, action: { [weak actionSheet] in
                                actionSheet?.dismissAnimated()
                                UIPasteboard.general.string = hashtag
                            })
                            ]), ActionSheetItemGroup(items: [
                                ActionSheetButtonItem(title: strongSelf.presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                                    actionSheet?.dismissAnimated()
                                })
                            ])])
                        strongSelf.presentController(actionSheet, nil)
                    case let .timecode(timecode, text):
                        guard let message = message else {
                            return
                        }
                        let actionSheet = ActionSheetController(presentationData: strongSelf.presentationData)
                        actionSheet.setItemGroups([ActionSheetItemGroup(items: [
                            ActionSheetTextItem(title: text),
                            ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_LinkDialogOpen, color: .accent, action: { [weak actionSheet] in
                                actionSheet?.dismissAnimated()
                                if let strongSelf = self {
                                    strongSelf.controllerInteraction?.seekToTimecode(message, timecode, true)
                                }
                            }),
                            ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_LinkDialogCopy, color: .accent, action: { [weak actionSheet] in
                                actionSheet?.dismissAnimated()
                                UIPasteboard.general.string = text
                            })
                            ]), ActionSheetItemGroup(items: [
                                ActionSheetButtonItem(title: strongSelf.presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                                    actionSheet?.dismissAnimated()
                                })
                            ])])
                        strongSelf.presentController(actionSheet, nil)
                }
            }
        }, openCheckoutOrReceipt: { _ in
        }, openSearch: {
        }, setupReply: { _ in
        }, canSetupReply: { _ in
            return false
        }, navigateToFirstDateMessage: { _ in
        }, requestRedeliveryOfFailedMessages: { _ in
        }, addContact: { _ in
        }, rateCall: { _, _ in
        }, requestSelectMessagePollOption: { _, _ in
        }, openAppStorePage: { [weak self] in
            if let strongSelf = self {
                strongSelf.context.sharedContext.applicationBindings.openAppStorePage()
            }
        }, displayMessageTooltip: { _, _, _, _ in
        }, seekToTimecode: { _, _, _ in
        }, scheduleCurrentMessage: {
        }, sendScheduledMessagesNow: { _ in
        }, editScheduledMessagesTime: { _ in
        }, performTextSelectionAction: { _, _, _ in
        }, updateMessageReaction: { _, _ in
        }, openMessageReactions: { _ in
        }, displaySwipeToReplyHint: {
        }, dismissReplyMarkupMessage: { _ in
        }, requestMessageUpdate: { _ in
        }, cancelInteractiveKeyboardGestures: {
        }, automaticMediaDownloadSettings: self.automaticMediaDownloadSettings,
           pollActionState: ChatInterfacePollActionState(), stickerSettings: ChatInterfaceStickerSettings(loopAnimatedStickers: false))
        self.controllerInteraction = controllerInteraction
        
        self.listNode.displayedItemRangeChanged = { [weak self] displayedRange, opaqueTransactionState in
            if let strongSelf = self {
                if let state = (opaqueTransactionState as? ChatRecentActionsListOpaqueState), state.canLoadEarlier {
                    if let visible = displayedRange.visibleRange {
                        let indexRange = (state.entries.count - 1 - visible.lastIndex, state.entries.count - 1 - visible.firstIndex)
                        if indexRange.0 < 5 {
                            strongSelf.eventLogContext.loadMoreEntries()
                        }
                    }
                }
            }
        }
        
        self.eventLogContext.loadMoreEntries()
        
        let historyViewUpdate = self.eventLogContext.get()
        |> map { (entries, hasEarlier, type, hasEntries) in
            return (entries.filter { entry in
                if case let .participantToggleAdmin(prev, new) = entry.event.action, case .creator = prev.participant, case .member = new.participant {
                    return false
                }
                return true
            }, hasEarlier, type, hasEntries)
        }
        
        let previousView = Atomic<[ChatRecentActionsEntry]?>(value: nil)
        
        let historyViewTransition = combineLatest(historyViewUpdate, self.chatPresentationDataPromise.get())
        |> mapToQueue { update, chatPresentationData -> Signal<ChatRecentActionsHistoryTransition, NoError> in
            let processedView = chatRecentActionsEntries(entries: update.0, presentationData: chatPresentationData)
            let previous = previousView.swap(processedView)
            
            return .single(chatRecentActionsHistoryPreparedTransition(from: previous ?? [], to: processedView, type: update.2, canLoadEarlier: update.1, displayingResults: update.3, context: context, peer: peer, controllerInteraction: controllerInteraction))
        }
        
        let appliedTransition = historyViewTransition |> deliverOnMainQueue |> mapToQueue { [weak self] transition -> Signal<Void, NoError> in
            if let strongSelf = self {
                strongSelf.enqueueTransition(transition: transition, firstTime: false)
            }
            return .complete()
        }
        
        self.historyDisposable = appliedTransition.start()
        
        let mediaManager = self.context.sharedContext.mediaManager
        self.galleryHiddenMesageAndMediaDisposable.set(mediaManager.galleryHiddenMediaManager.hiddenIds().start(next: { [weak self] ids in
            if let strongSelf = self, let controllerInteraction = strongSelf.controllerInteraction {
                var messageIdAndMedia: [MessageId: [Media]] = [:]
                
                for id in ids {
                    if case let .chat(accountId, messageId, media) = id, accountId == strongSelf.context.account.id {
                        messageIdAndMedia[messageId] = [media]
                    }
                }
                
                controllerInteraction.hiddenMedia = messageIdAndMedia
                
                strongSelf.listNode.forEachItemNode { itemNode in
                    if let itemNode = itemNode as? ChatMessageItemView {
                        itemNode.updateHiddenMedia()
                    }
                }
            }
        }))
        
        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            if let strongSelf = self {
                strongSelf.presentationData = presentationData
                strongSelf.chatPresentationDataPromise.set(.single(ChatPresentationData(theme: ChatPresentationThemeData(theme: presentationData.theme, wallpaper: presentationData.chatWallpaper), fontSize: presentationData.fontSize, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, nameDisplayOrder: presentationData.nameDisplayOrder, disableAnimations: presentationData.disableAnimations, largeEmoji: presentationData.largeEmoji)))
                
                strongSelf.updateThemeAndStrings(theme: presentationData.theme, strings: presentationData.strings)
            }
        })
    }
    
    deinit {
        self.presentationDataDisposable?.dispose()
        self.historyDisposable?.dispose()
        self.navigationActionDisposable.dispose()
        self.galleryHiddenMesageAndMediaDisposable.dispose()
        self.resolvePeerByNameDisposable.dispose()
        self.adminsDisposable?.dispose()
        self.banDisposables.dispose()
    }
    
    func updateThemeAndStrings(theme: PresentationTheme, strings: PresentationStrings) {
        self.panelBackgroundNode.backgroundColor = theme.chat.inputPanel.panelBackgroundColor
        self.panelSeparatorNode.backgroundColor = theme.chat.inputPanel.panelSeparatorColor
        self.panelButtonNode.setTitle(presentationData.strings.Channel_AdminLog_InfoPanelTitle, with: Font.regular(17.0), with: theme.chat.inputPanel.panelControlAccentColor, for: [])
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let isFirstLayout = self.containerLayout == nil
        
        self.containerLayout = (layout, navigationBarHeight)
        
        var insets = layout.insets(options: [.input])
        insets.top += navigationBarHeight
        
        let cleanInsets = layout.insets(options: [])
        
        transition.updateFrame(node: self.backgroundNode, frame: CGRect(origin: CGPoint(), size: layout.size))
        
        let intrinsicPanelHeight: CGFloat = 47.0
        let panelHeight = intrinsicPanelHeight + cleanInsets.bottom
        transition.updateFrame(node: self.panelBackgroundNode, frame: CGRect(origin: CGPoint(x: 0.0, y: layout.size.height - panelHeight), size: CGSize(width: layout.size.width, height: panelHeight)))
        transition.updateFrame(node: self.panelSeparatorNode, frame: CGRect(origin: CGPoint(x: 0.0, y: layout.size.height - panelHeight), size: CGSize(width: layout.size.width, height: UIScreenPixel)))
        transition.updateFrame(node: self.panelButtonNode, frame: CGRect(origin: CGPoint(x: 0.0, y: layout.size.height - panelHeight), size: CGSize(width: layout.size.width, height: intrinsicPanelHeight)))
        
        transition.updateBounds(node: self.listNode, bounds: CGRect(origin: CGPoint(), size: layout.size))
        transition.updatePosition(node: self.listNode, position: CGRect(origin: CGPoint(), size: layout.size).center)
        
        transition.updateFrame(node: self.loadingNode, frame: CGRect(origin: CGPoint(), size: layout.size))
        loadingNode.updateLayout(size: layout.size, insets: insets, transition: transition)
        
        let emptyFrame = CGRect(origin: CGPoint(x: 0.0, y: navigationBarHeight), size: CGSize(width: layout.size.width, height: layout.size.height - navigationBarHeight - panelHeight))
        transition.updateFrame(node: self.emptyNode, frame: emptyFrame)
        self.emptyNode.updateLayout(size: emptyFrame.size, transition: transition)
        
        let contentBottomInset: CGFloat = panelHeight + 4.0
        let listInsets = UIEdgeInsets(top: contentBottomInset, left: layout.safeInsets.right, bottom: insets.top, right: layout.safeInsets.left)
        
        let (duration, curve) = listViewAnimationDurationAndCurve(transition: transition)
        let updateSizeAndInsets = ListViewUpdateSizeAndInsets(size: layout.size, insets: listInsets, duration: duration, curve: curve)
        
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: nil, additionalScrollDistance: 0.0, updateSizeAndInsets: updateSizeAndInsets, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
        
        if isFirstLayout {
            self.dequeueTransitions()
        }
    }
    
    private func enqueueTransition(transition: ChatRecentActionsHistoryTransition, firstTime: Bool) {
        self.enqueuedTransitions.append((transition, firstTime))
        if self.containerLayout != nil {
            self.dequeueTransitions()
        }
    }
    
    private func dequeueTransitions() {
        while true {
            if let (transition, firstTime) = self.enqueuedTransitions.first {
                self.enqueuedTransitions.remove(at: 0)
                
                var options = ListViewDeleteAndInsertOptions()
                if firstTime {
                    options.insert(.LowLatency)
                } else {
                    switch transition.type {
                        case .initial:
                            options.insert(.LowLatency)
                        case .generic:
                            options.insert(.AnimateInsertion)
                        case .load:
                            break
                    }
                }
                
                let displayingResults = transition.displayingResults
                let isEmpty = transition.isEmpty
                let displayEmptyNode = isEmpty && displayingResults
                self.listNode.transaction(deleteIndices: transition.deletions, insertIndicesAndItems: transition.insertions, updateIndicesAndItems: transition.updates, options: options, updateSizeAndInsets: nil, updateOpaqueState: ChatRecentActionsListOpaqueState(entries: transition.filteredEntries, canLoadEarlier: transition.canLoadEarlier), completion: { [weak self] _ in
                    if let strongSelf = self {
                        if displayEmptyNode != strongSelf.listNode.isHidden {
                            strongSelf.listNode.isHidden = displayEmptyNode
                            strongSelf.backgroundColor = !displayEmptyNode ? strongSelf.presentationData.theme.list.plainBackgroundColor : nil
                            
                            strongSelf.emptyNode.alpha = displayEmptyNode ? 1.0 : 0.0
                            strongSelf.emptyNode.layer.animateAlpha(from: displayEmptyNode ? 0.0 : 1.0, to: displayEmptyNode ? 1.0 : 0.0, duration: 0.25)
                            
                            let hasFilter: Bool = strongSelf.filter.events != .all || strongSelf.filter.query != nil
                            
                            var isSupergroup: Bool = false
                            if let peer = strongSelf.peer as? TelegramChannel {
                                switch peer.info {
                                case .group:
                                    isSupergroup = true
                                default:
                                    break
                                }
                            }
                            
                            if displayEmptyNode {
                                var text: String = ""
                                if let query = strongSelf.filter.query, hasFilter {
                                    text = strongSelf.presentationData.strings.Channel_AdminLog_EmptyFilterQueryText(query).0
                                } else {
                                    text = isSupergroup ? strongSelf.presentationData.strings.Group_AdminLog_EmptyText : strongSelf.presentationData.strings.Broadcast_AdminLog_EmptyText
                                }
                                strongSelf.emptyNode.setup(title: hasFilter ? strongSelf.presentationData.strings.Channel_AdminLog_EmptyFilterTitle : strongSelf.presentationData.strings.Channel_AdminLog_EmptyTitle, text: text)
                            }
                        }
                        let isLoading = !displayingResults
                        if !isLoading && strongSelf.isLoading {
                            strongSelf.listNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
                        }
                        strongSelf.isLoading = isLoading
                    }
                })
            } else {
                break
            }
        }
    }
    
    @objc func infoButtonPressed() {
        self.interaction.displayInfoAlert()
    }
    
    func updateSearchQuery(_ query: String) {
        self.filter = self.filter.withQuery(query.isEmpty ? nil : query)
        self.eventLogContext.setFilter(self.filter)
    }
    
    func updateFilter(events: AdminLogEventsFlags, adminPeerIds: [PeerId]?) {
        self.filter = self.filter.withEvents(events).withAdminPeerIds(adminPeerIds)
        self.eventLogContext.setFilter(self.filter)
    }
    
    private func openPeer(peerId: PeerId, peer: Peer?) {
        let peerSignal: Signal<Peer?, NoError>
        if let peer = peer {
            peerSignal = .single(peer)
        } else {
            peerSignal = self.context.account.postbox.loadedPeerWithId(peerId) |> map(Optional.init)
        }
        self.navigationActionDisposable.set((peerSignal |> take(1) |> deliverOnMainQueue).start(next: { [weak self] peer in
            if let strongSelf = self, let peer = peer {
                if peer is TelegramChannel, let navigationController = strongSelf.getNavigationController() {
                    strongSelf.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: strongSelf.context, chatLocation: .peer(peer.id), animated: true))
                } else {
                    if let infoController = strongSelf.context.sharedContext.makePeerInfoController(context: strongSelf.context, peer: peer, mode: .generic) {
                        strongSelf.pushController(infoController)
                    }
                }
            }
        }))
    }
    
    private func openPeerMention(_ name: String) {
        let postbox = self.context.account.postbox
        self.navigationActionDisposable.set((resolvePeerByName(account: self.context.account, name: name, ageLimit: 10)
        |> take(1)
        |> mapToSignal { peerId -> Signal<Peer?, NoError> in
            if let peerId = peerId {
                return postbox.loadedPeerWithId(peerId) |> map(Optional.init)
            } else {
                return .single(nil)
            }
        }
        |> deliverOnMainQueue).start(next: { [weak self] peer in
            if let strongSelf = self {
                if let peer = peer {
                    if let infoController = strongSelf.context.sharedContext.makePeerInfoController(context: strongSelf.context, peer: peer, mode: .generic) {
                        strongSelf.pushController(infoController)
                    }
                }
            }
        }))
    }
    
    private func openMessageContextMenu(message: Message, selectAll: Bool, node: ASDisplayNode, frame: CGRect) {
        var actions: [ContextMenuAction] = []
            if !message.text.isEmpty {
                actions.append(ContextMenuAction(content: .text(title: self.presentationData.strings.Conversation_ContextMenuCopy, accessibilityLabel: self.presentationData.strings.Conversation_ContextMenuCopy), action: {
                UIPasteboard.general.string = message.text
            }))
        }
        
        if let author = message.author, let adminsState = self.adminsState {
            var canBan = author.id != self.context.account.peerId
            if let channel = self.peer as? TelegramChannel {
                if !channel.hasPermission(.banMembers) {
                    canBan = false
                }
                if case .broadcast = channel.info {
                    canBan = false
                }
            }
            for member in adminsState.list {
                if member.peer.id == author.id {
                    canBan = member.participant.canBeBannedBy(peerId: self.context.account.peerId)
                }
            }
            
            if canBan {
                actions.append(ContextMenuAction(content: .text(title: self.presentationData.strings.Conversation_ContextMenuBan, accessibilityLabel: self.presentationData.strings.Conversation_ContextMenuBan), action: { [weak self] in
                    if let strongSelf = self {
                        strongSelf.banDisposables.set((fetchChannelParticipant(account: strongSelf.context.account, peerId: strongSelf.peer.id, participantId: author.id)
                        |> deliverOnMainQueue).start(next: { participant in
                            if let strongSelf = self {
                                strongSelf.presentController(channelBannedMemberController(context: strongSelf.context, peerId: strongSelf.peer.id, memberId: author.id, initialParticipant: participant, updated: { _ in }, upgradedToSupergroup: { _, f in f() }), ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
                            }
                        }), forKey: author.id)
                    }
                }))
            }
        }
        
        if !actions.isEmpty {
            let contextMenuController = ContextMenuController(actions: actions)
            
            self.controllerInteraction.highlightedState = ChatInterfaceHighlightedState(messageStableId: message.stableId)
            self.updateItemNodesHighlightedStates(animated: true)
            
            contextMenuController.dismissed = { [weak self] in
                if let strongSelf = self {
                    if strongSelf.controllerInteraction.highlightedState?.messageStableId == message.stableId {
                        strongSelf.controllerInteraction.highlightedState = nil
                        strongSelf.updateItemNodesHighlightedStates(animated: true)
                    }
                }
            }
            
            self.presentController(contextMenuController, ContextMenuControllerPresentationArguments(sourceNodeAndRect: { [weak self, weak node] in
                if let strongSelf = self, let node = node {
                    return (node, frame, strongSelf, strongSelf.bounds)
                } else {
                    return nil
                }
            }))
        }
    }
    
    private func updateItemNodesHighlightedStates(animated: Bool) {
        self.listNode.forEachItemNode { itemNode in
            if let itemNode = itemNode as? ChatMessageItemView {
                itemNode.updateHighlightedState(animated: animated)
            }
        }
    }
    
    private func openUrl(_ url: String) {
        self.navigationActionDisposable.set((self.context.sharedContext.resolveUrl(account: self.context.account, url: url) |> deliverOnMainQueue).start(next: { [weak self] result in
            if let strongSelf = self {
                switch result {
                    case let .externalUrl(url):
                        if let navigationController = strongSelf.getNavigationController() {
                            strongSelf.context.sharedContext.openExternalUrl(context: strongSelf.context, urlContext: .generic, url: url, forceExternal: false, presentationData: strongSelf.presentationData, navigationController: navigationController, dismissInput: {
                                self?.view.endEditing(true)
                            })
                        }
                    case let .peer(peerId, _):
                        if let peerId = peerId {
                            strongSelf.openPeer(peerId: peerId, peer: nil)
                        }
                    case .inaccessiblePeer:
                        strongSelf.controllerInteraction.presentController(textAlertController(context: strongSelf.context, title: nil, text: strongSelf.presentationData.strings.Conversation_ErrorInaccessibleMessage, actions: [TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_OK, action: {})]), nil)
                    case .botStart:
                        break
                    case .groupBotStart:
                        break
                    case let .channelMessage(peerId, messageId):
                        if let navigationController = strongSelf.getNavigationController() {
                            strongSelf.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: strongSelf.context, chatLocation: .peer(peerId), subject: .message(messageId)))
                        }
                    case let .stickerPack(name):
                        let packReference: StickerPackReference = .name(name)
                        strongSelf.presentController(StickerPackScreen(context: strongSelf.context, mainStickerPack: packReference, stickerPacks: [packReference], parentNavigationController: strongSelf.getNavigationController()), nil)
                    case let .instantView(webpage, anchor):
                        strongSelf.pushController(InstantPageController(context: strongSelf.context, webPage: webpage, sourcePeerType: .channel, anchor: anchor))
                    case let .join(link):
                        strongSelf.presentController(JoinLinkPreviewController(context: strongSelf.context, link: link, navigateToPeer: { peerId in
                            if let strongSelf = self {
                                strongSelf.openPeer(peerId: peerId, peer: nil)
                            }
                        }, parentNavigationController: strongSelf.getNavigationController()), nil)
                    case let .localization(identifier):
                        strongSelf.presentController(LanguageLinkPreviewController(context: strongSelf.context, identifier: identifier), nil)
                    case .proxy, .confirmationCode, .cancelAccountReset, .share:
                        strongSelf.context.sharedContext.openResolvedUrl(result, context: strongSelf.context, urlContext: .generic, navigationController: strongSelf.getNavigationController(), openPeer: { peerId, _ in
                            if let strongSelf = self {
                                strongSelf.openPeer(peerId: peerId, peer: nil)
                            }
                        }, sendFile: nil,
                        sendSticker: nil,
                        present: { c, a in
                            self?.presentController(c, a)
                        }, dismissInput: {
                            self?.view.endEditing(true)
                        }, contentContext: nil)
                    case .wallpaper:
                        break
                    case .theme:
                        break
                    case .wallet:
                        break
                    case .settings:
                        break
                }
            }
        }))
    }
}
