import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import SyncCore
import TelegramPresentationData
import LegacyComponents
import ItemListUI
import PresentationDataUtils
import AccountContext
import AlertUI
import PresentationDataUtils
import LegacyUI
import ItemListAvatarAndNameInfoItem
import WebSearchUI
import PeerInfoUI
import MapResourceToAvatarSizes

private struct CreateChannelArguments {
    let context: AccountContext
    
    let updateEditingName: (ItemListAvatarAndNameInfoItemName) -> Void
    let updateEditingDescriptionText: (String) -> Void
    let done: () -> Void
    let changeProfilePhoto: () -> Void
}

private enum CreateChannelSection: Int32 {
    case info
    case description
}

private enum CreateChannelEntryTag: ItemListItemTag {
    case info
    
    func isEqual(to other: ItemListItemTag) -> Bool {
        if let other = other as? CreateChannelEntryTag {
            switch self {
                case .info:
                    if case .info = other {
                        return true
                    } else {
                        return false
                    }
            }
        } else {
            return false
        }
    }
}

private enum CreateChannelEntry: ItemListNodeEntry {
    case channelInfo(PresentationTheme, PresentationStrings, PresentationDateTimeFormat, Peer?, ItemListAvatarAndNameInfoItemState, ItemListAvatarAndNameInfoItemUpdatingAvatar?)
    case setProfilePhoto(PresentationTheme, String)
    
    case descriptionSetup(PresentationTheme, String, String)
    case descriptionInfo(PresentationTheme, String)
    
    var section: ItemListSectionId {
        switch self {
            case .channelInfo, .setProfilePhoto:
                return CreateChannelSection.info.rawValue
            case .descriptionSetup, .descriptionInfo:
                return CreateChannelSection.description.rawValue
        }
    }
    
    var stableId: Int32 {
        switch self {
            case .channelInfo:
                return 0
            case .setProfilePhoto:
                return 1
            case .descriptionSetup:
                return 2
            case .descriptionInfo:
                return 3
        }
    }
    
    static func ==(lhs: CreateChannelEntry, rhs: CreateChannelEntry) -> Bool {
        switch lhs {
            case let .channelInfo(lhsTheme, lhsStrings, lhsDateTimeFormat, lhsPeer, lhsEditingState, lhsAvatar):
                if case let .channelInfo(rhsTheme, rhsStrings, rhsDateTimeFormat, rhsPeer, rhsEditingState, rhsAvatar) = rhs {
                    if lhsTheme !== rhsTheme {
                        return false
                    }
                    if lhsStrings !== rhsStrings {
                        return false
                    }
                    if lhsDateTimeFormat != rhsDateTimeFormat {
                        return false
                    }
                    if let lhsPeer = lhsPeer, let rhsPeer = rhsPeer {
                        if !lhsPeer.isEqual(rhsPeer) {
                            return false
                        }
                    } else if (lhsPeer != nil) != (rhsPeer != nil) {
                        return false
                    }
                    if lhsEditingState != rhsEditingState {
                        return false
                    }
                    if lhsAvatar != rhsAvatar {
                        return false
                    }
                    return true
                } else {
                    return false
                }
            case let .setProfilePhoto(lhsTheme, lhsText):
                if case let .setProfilePhoto(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .descriptionSetup(lhsTheme, lhsText, lhsValue):
                if case let .descriptionSetup(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .descriptionInfo(lhsTheme, lhsText):
                if case let .descriptionInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
        }
    }
    
    static func <(lhs: CreateChannelEntry, rhs: CreateChannelEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! CreateChannelArguments
        switch self {
            case let .channelInfo(theme, strings, dateTimeFormat, peer, state, avatar):
                return ItemListAvatarAndNameInfoItem(accountContext: arguments.context, presentationData: presentationData, dateTimeFormat: dateTimeFormat, mode: .editSettings, peer: peer, presence: nil, cachedData: nil, state: state, sectionId: ItemListSectionId(self.section), style: .blocks(withTopInset: false, withExtendedBottomInset: false), editingNameUpdated: { editingName in
                    arguments.updateEditingName(editingName)
                }, avatarTapped: {
                    arguments.changeProfilePhoto()
                }, updatingImage: avatar, tag: CreateChannelEntryTag.info)
            case let .setProfilePhoto(theme, text):
                return ItemListActionItem(presentationData: presentationData, title: text, kind: .generic, alignment: .natural, sectionId: ItemListSectionId(self.section), style: .blocks, action: {
                    arguments.changeProfilePhoto()
                })
            case let .descriptionSetup(theme, text, value):
                return ItemListMultilineInputItem(presentationData: presentationData, text: value, placeholder: text, maxLength: ItemListMultilineInputItemTextLimit(value: 255, display: true), sectionId: self.section, style: .blocks, textUpdated: { updatedText in
                    arguments.updateEditingDescriptionText(updatedText)
                })
            case let .descriptionInfo(theme, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private struct CreateChannelState: Equatable {
    var creating: Bool
    var editingName: ItemListAvatarAndNameInfoItemName
    var editingDescriptionText: String
    var avatar: ItemListAvatarAndNameInfoItemUpdatingAvatar?
    
    static func ==(lhs: CreateChannelState, rhs: CreateChannelState) -> Bool {
        if lhs.creating != rhs.creating {
            return false
        }
        if lhs.editingName != rhs.editingName {
            return false
        }
        if lhs.editingDescriptionText != rhs.editingDescriptionText {
            return false
        }
        if lhs.avatar != rhs.avatar {
            return false
        }
        return true
    }
}

private func CreateChannelEntries(presentationData: PresentationData, state: CreateChannelState) -> [CreateChannelEntry] {
    var entries: [CreateChannelEntry] = []
    
    let groupInfoState = ItemListAvatarAndNameInfoItemState(editingName: state.editingName, updatingName: nil)
    
    let peer = TelegramGroup(id: PeerId(namespace: -1, id: 0), title: state.editingName.composedTitle, photo: [], participantCount: 0, role: .creator(rank: nil), membership: .Member, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0)
    
    entries.append(.channelInfo(presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, peer, groupInfoState, state.avatar))
    
    entries.append(.descriptionSetup(presentationData.theme, presentationData.strings.Channel_Edit_AboutItem, state.editingDescriptionText))
    entries.append(.descriptionInfo(presentationData.theme, presentationData.strings.Channel_About_Help))
    
    return entries
}

public func createChannelController(context: AccountContext) -> ViewController {
    let initialState = CreateChannelState(creating: false, editingName: ItemListAvatarAndNameInfoItemName.title(title: "", type: .channel), editingDescriptionText: "", avatar: nil)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((CreateChannelState) -> CreateChannelState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }
    
    var replaceControllerImpl: ((ViewController) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController, Any?) -> Void)?
    var endEditingImpl: (() -> Void)?
    
    let actionsDisposable = DisposableSet()
    
    let currentAvatarMixin = Atomic<TGMediaAvatarMenuMixin?>(value: nil)
    
    let uploadedAvatar = Promise<UploadedPeerPhotoData>()
    
    let arguments = CreateChannelArguments(context: context, updateEditingName: { editingName in
        updateState { current in
            var current = current
            switch editingName {
            case let .title(title, type):
                current.editingName = .title(title: String(title.prefix(255)), type: type)
            case let  .personName(firstName, lastName, _):
                current.editingName = .personName(firstName: String(firstName.prefix(255)), lastName: String(lastName.prefix(255)), phone: "")
            }
            return current
        }
    }, updateEditingDescriptionText: { text in
        updateState { current in
            var current = current
            current.editingDescriptionText = String(text.prefix(255))
            return current
        }
    }, done: {
        let (creating, title, description) = stateValue.with { state -> (Bool, String, String) in
            return (state.creating, state.editingName.composedTitle, state.editingDescriptionText)
        }
        
        if !creating && !title.isEmpty {
            updateState { current in
                var current = current
                current.creating = true
                return current
            }
            
            endEditingImpl?()
            actionsDisposable.add((createChannel(account: context.account, title: title, description: description.isEmpty ? nil : description)
            |> deliverOnMainQueue
            |> afterDisposed {
                Queue.mainQueue().async {
                    updateState { current in
                        var current = current
                        current.creating = false
                        return current
                    }
                }
            }).start(next: { peerId in
                let updatingAvatar = stateValue.with {
                    return $0.avatar
                }
                if let _ = updatingAvatar {
                    let _ = updatePeerPhoto(postbox: context.account.postbox, network: context.account.network, stateManager: context.account.stateManager, accountPeerId: context.account.peerId, peerId: peerId, photo: uploadedAvatar.get(), mapResourceToAvatarSizes: { resource, representations in
                        return mapResourceToAvatarSizes(postbox: context.account.postbox, resource: resource, representations: representations)
                    }).start()
                }
                
                let controller = channelVisibilityController(context: context, peerId: peerId, mode: .initialSetup, upgradedToSupergroup: { _, f in f() })
                replaceControllerImpl?(controller)
            }, error: { error in
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let text: String?
                switch error {
                    case .generic, .tooMuchLocationBasedGroups:
                        text = presentationData.strings.Login_UnknownError
                    case .tooMuchJoined:
                        pushControllerImpl?(oldChannelsController(context: context, intent: .create))
                        return
                    case .restricted:
                        text = presentationData.strings.Common_ActionNotAllowedError
                    default:
                        text = nil
                }
                if let text = text {
                    presentControllerImpl?(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
                }
            }))
        }
    }, changeProfilePhoto: {
        endEditingImpl?()
        
        let title = stateValue.with { state -> String in
            return state.editingName.composedTitle
        }
        
        let _ = (context.account.postbox.transaction { transaction -> (Peer?, SearchBotsConfiguration) in
            return (transaction.getPeer(context.account.peerId), currentSearchBotsConfiguration(transaction: transaction))
        } |> deliverOnMainQueue).start(next: { peer, searchBotsConfiguration in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            
            let legacyController = LegacyController(presentation: .custom, theme: presentationData.theme)
            legacyController.statusBar.statusBarStyle = .Ignore
            
            let emptyController = LegacyEmptyController(context: legacyController.context)!
            let navigationController = makeLegacyNavigationController(rootController: emptyController)
            navigationController.setNavigationBarHidden(true, animated: false)
            navigationController.navigationBar.transform = CGAffineTransform(translationX: -1000.0, y: 0.0)
            
            legacyController.bind(controller: navigationController)
            
            endEditingImpl?()
            presentControllerImpl?(legacyController, nil)
            
            let completedImpl: (UIImage) -> Void = { image in
                if let data = image.jpegData(compressionQuality: 0.6) {
                    let resource = LocalFileMediaResource(fileId: arc4random64())
                    context.account.postbox.mediaBox.storeResourceData(resource.id, data: data)
                    let representation = TelegramMediaImageRepresentation(dimensions: PixelDimensions(width: 640, height: 640), resource: resource)
                    uploadedAvatar.set(uploadedPeerPhoto(postbox: context.account.postbox, network: context.account.network, resource: resource))
                    updateState { current in
                        var current = current
                        current.avatar = .image(representation, false)
                        return current
                    }
                }
            }
            
            let mixin = TGMediaAvatarMenuMixin(context: legacyController.context, parentController: emptyController, hasSearchButton: true, hasDeleteButton: stateValue.with({ $0.avatar }) != nil, hasViewButton: false, personalPhoto: false, saveEditedPhotos: false, saveCapturedMedia: false, signup: false)!
            let _ = currentAvatarMixin.swap(mixin)
            mixin.requestSearchController = { assetsController in
                let controller = WebSearchController(context: context, peer: peer, configuration: searchBotsConfiguration, mode: .avatar(initialQuery: title, completion: { result in
                    assetsController?.dismiss()
                    completedImpl(result)
                }))
                presentControllerImpl?(controller, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
            }
            mixin.didFinishWithImage = { image in
                if let image = image {
                    completedImpl(image)
                }
            }
            if stateValue.with({ $0.avatar }) != nil {
                mixin.didFinishWithDelete = {
                    updateState { current in
                        var current = current
                        current.avatar = nil
                        return current
                    }
                    uploadedAvatar.set(.never())
                }
            }
            mixin.didDismiss = { [weak legacyController] in
                let _ = currentAvatarMixin.swap(nil)
                legacyController?.dismiss()
            }
            let menuController = mixin.present()
            if let menuController = menuController {
                menuController.customRemoveFromParentViewController = { [weak legacyController] in
                    legacyController?.dismiss()
                }
            }
        })
    })
    
    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
        |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
            
            let rightNavigationButton: ItemListNavigationButton
            if state.creating {
                rightNavigationButton = ItemListNavigationButton(content: .none, style: .activity, enabled: true, action: {})
            } else {
                rightNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Next), style: .bold, enabled: !state.editingName.composedTitle.isEmpty, action: {
                    arguments.done()
                })
            }
            
            let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(presentationData.strings.ChannelIntro_CreateChannel), leftNavigationButton: nil, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
            let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: CreateChannelEntries(presentationData: presentationData, state: state), style: .blocks, focusItemTag: CreateChannelEntryTag.info)
            
            return (controllerState, (listState, arguments))
        } |> afterDisposed {
            actionsDisposable.dispose()
        }
    
    let controller = ItemListController(context: context, state: signal)
    replaceControllerImpl = { [weak controller] value in
        (controller?.navigationController as? NavigationController)?.replaceAllButRootController(value, animated: true)
    }
    pushControllerImpl = { [weak controller] value in
        controller?.push(value)
    }
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    controller.willDisappear = { _ in
        endEditingImpl?()
    }
    endEditingImpl = {
        [weak controller] in
        controller?.view.endEditing(true)
    }
    return controller
}
