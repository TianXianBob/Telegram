import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import SyncCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext

public func autodownloadDataSizeString(_ size: Int64, decimalSeparator: String = ".") -> String {
    if size >= 1024 * 1024 * 1024 {
        let remainder = (size % (1024 * 1024 * 1024)) / (1024 * 1024 * 102)
        if remainder != 0 {
            return "\(size / (1024 * 1024 * 1024))\(decimalSeparator)\(remainder) GB"
        } else {
            return "\(size / (1024 * 1024 * 1024)) GB"
        }
    } else if size >= 1024 * 1024 {
        let remainder = (size % (1024 * 1024)) / (1024 * 102)
        if size < 10 * 1024 * 1024 {
            return "\(size / (1024 * 1024))\(decimalSeparator)\(remainder) MB"
        } else {
            return "\(size / (1024 * 1024)) MB"
        }
    } else if size >= 1024 {
        return "\(size / 1024) KB"
    } else {
        return "\(size) B"
    }
}

enum AutomaticDownloadCategory {
    case photo
    case video
    case file
}

private enum AutomaticDownloadPeerType {
    case contact
    case otherPrivate
    case group
    case channel
}

private final class AutodownloadMediaCategoryControllerArguments {
    let togglePeer: (AutomaticDownloadPeerType) -> Void
    let adjustSize: (Int32) -> Void
    let toggleVideoPreload: () -> Void
    
    init(togglePeer: @escaping (AutomaticDownloadPeerType) -> Void, adjustSize: @escaping (Int32) -> Void, toggleVideoPreload: @escaping () -> Void) {
        self.togglePeer = togglePeer
        self.adjustSize = adjustSize
        self.toggleVideoPreload = toggleVideoPreload
    }
}

private enum AutodownloadMediaCategorySection: Int32 {
    case peer
    case size
}

private enum AutodownloadMediaCategoryEntry: ItemListNodeEntry {
    case peerHeader(PresentationTheme, String)
    case peerContacts(PresentationTheme, String, Bool)
    case peerOtherPrivate(PresentationTheme, String, Bool)
    case peerGroups(PresentationTheme, String, Bool)
    case peerChannels(PresentationTheme, String, Bool)
    
    case sizeHeader(PresentationTheme, String)
    case sizeItem(PresentationTheme, String, String, Int32)
    case sizePreload(PresentationTheme, String, Bool, Bool)
    case sizePreloadInfo(PresentationTheme, String)
    
    var section: ItemListSectionId {
        switch self {
            case .peerHeader, .peerContacts, .peerOtherPrivate, .peerGroups, .peerChannels:
                return AutodownloadMediaCategorySection.peer.rawValue
            case .sizeHeader, .sizeItem, .sizePreload, .sizePreloadInfo:
                return AutodownloadMediaCategorySection.size.rawValue
        }
    }
    
    var stableId: Int32 {
        switch self {
            case .peerHeader:
                return 0
            case .peerContacts:
                return 1
            case .peerOtherPrivate:
                return 2
            case .peerGroups:
                return 3
            case .peerChannels:
                return 4
            case .sizeHeader:
                return 5
            case .sizeItem:
                return 6
            case .sizePreload:
                return 7
            case .sizePreloadInfo:
                return 8
        }
    }
    
    static func ==(lhs: AutodownloadMediaCategoryEntry, rhs: AutodownloadMediaCategoryEntry) -> Bool {
        switch lhs {
            case let .peerHeader(lhsTheme, lhsText):
                if case let .peerHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .peerContacts(lhsTheme, lhsText, lhsValue):
                if case let .peerContacts(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .peerOtherPrivate(lhsTheme, lhsText, lhsValue):
                if case let .peerOtherPrivate(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .peerGroups(lhsTheme, lhsText, lhsValue):
                if case let .peerGroups(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .peerChannels(lhsTheme, lhsText, lhsValue):
                if case let .peerChannels(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .sizeHeader(lhsTheme, lhsText):
                if case let .sizeHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .sizeItem(lhsTheme, lhsDecimalSeparator, lhsText, lhsValue):
                if case let .sizeItem(rhsTheme, rhsDecimalSeparator, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsDecimalSeparator == rhsDecimalSeparator, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .sizePreload(lhsTheme, lhsText, lhsValue, lhsEnabled):
                if case let .sizePreload(rhsTheme, rhsText, rhsValue, rhsEnabled) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue, lhsEnabled == rhsEnabled {
                    return true
                } else {
                    return false
                }
            case let .sizePreloadInfo(lhsTheme, lhsText):
                if case let .sizePreloadInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
        }
    }
    
    static func <(lhs: AutodownloadMediaCategoryEntry, rhs: AutodownloadMediaCategoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AutodownloadMediaCategoryControllerArguments
        switch self {
            case let .peerHeader(theme, text):
                return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
            case let .peerContacts(theme, text, value):
                return ItemListSwitchItem(presentationData: presentationData, title: text, value: value, enableInteractiveChanges: true, enabled: true, sectionId: self.section, style: .blocks, updated: { value in
                    arguments.togglePeer(.contact)
                })
            case let .peerOtherPrivate(theme, text, value):
                return ItemListSwitchItem(presentationData: presentationData, title: text, value: value, enableInteractiveChanges: true, enabled: true, sectionId: self.section, style: .blocks, updated: { value in
                    arguments.togglePeer(.otherPrivate)
                })
            case let .peerGroups(theme, text, value):
                return ItemListSwitchItem(presentationData: presentationData, title: text, value: value, enableInteractiveChanges: true, enabled: true, sectionId: self.section, style: .blocks, updated: { value in
                    arguments.togglePeer(.group)
                })
            case let .peerChannels(theme, text, value):
                return ItemListSwitchItem(presentationData: presentationData, title: text, value: value, enableInteractiveChanges: true, enabled: true, sectionId: self.section, style: .blocks, updated: { value in
                    arguments.togglePeer(.channel)
                })
            case let .sizeHeader(theme, text):
                return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
            case let .sizeItem(theme, decimalSeparator, text, value):
                return AutodownloadSizeLimitItem(theme: theme, decimalSeparator: decimalSeparator, text: text, value: value, sectionId: self.section, updated: { value in
                    arguments.adjustSize(value)
                })
            case let .sizePreload(theme, text, value, enabled):
                return ItemListSwitchItem(presentationData: presentationData, title: text, value: value && enabled, enableInteractiveChanges: true, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                    arguments.toggleVideoPreload()
                })
            case let .sizePreloadInfo(theme, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private struct AutomaticDownloadPeers {
    let contacts: Bool
    let otherPrivate: Bool
    let groups: Bool
    let channels: Bool
    
    init(category: MediaAutoDownloadCategory) {
        self.contacts = category.contacts
        self.otherPrivate = category.otherPrivate
        self.groups = category.groups
        self.channels = category.channels
    }
}

private func autodownloadMediaCategoryControllerEntries(presentationData: PresentationData, connectionType: AutomaticDownloadConnectionType, category: AutomaticDownloadCategory, settings: MediaAutoDownloadSettings) -> [AutodownloadMediaCategoryEntry] {
    var entries: [AutodownloadMediaCategoryEntry] = []
    
    let categories = effectiveAutodownloadCategories(settings: settings, networkType: connectionType.automaticDownloadNetworkType)
    
    let peers: AutomaticDownloadPeers
    let size: Int32
    let predownload: Bool
    
    switch category {
        case .photo:
            peers = AutomaticDownloadPeers(category: categories.photo)
            size = categories.photo.sizeLimit
            predownload = categories.photo.predownload
        case .video:
            peers = AutomaticDownloadPeers(category: categories.video)
            size = categories.video.sizeLimit
            predownload = categories.video.predownload
        case .file:
            peers = AutomaticDownloadPeers(category: categories.file)
            size = categories.file.sizeLimit
            predownload = categories.file.predownload
    }
    
    let downloadTitle: String
    var sizeTitle: String?
    switch category {
        case .photo:
            downloadTitle = presentationData.strings.AutoDownloadSettings_AutodownloadPhotos
        case .video:
            downloadTitle = presentationData.strings.AutoDownloadSettings_AutodownloadVideos
            sizeTitle = presentationData.strings.AutoDownloadSettings_MaxVideoSize
        case .file:
            downloadTitle = presentationData.strings.AutoDownloadSettings_AutodownloadFiles
            sizeTitle = presentationData.strings.AutoDownloadSettings_MaxFileSize
    }
    
    entries.append(.peerHeader(presentationData.theme, downloadTitle))
    entries.append(.peerContacts(presentationData.theme, presentationData.strings.AutoDownloadSettings_Contacts, peers.contacts))
    entries.append(.peerOtherPrivate(presentationData.theme, presentationData.strings.AutoDownloadSettings_PrivateChats, peers.otherPrivate))
    entries.append(.peerGroups(presentationData.theme, presentationData.strings.AutoDownloadSettings_GroupChats, peers.groups))
    entries.append(.peerChannels(presentationData.theme, presentationData.strings.AutoDownloadSettings_Channels, peers.channels))
    
    switch category {
        case .video, .file:
            if let sizeTitle = sizeTitle {
                entries.append(.sizeHeader(presentationData.theme, sizeTitle))
            }
            
            let sizeText: String
            if size == Int32.max {
                sizeText = autodownloadDataSizeString(1536 * 1024 * 1024, decimalSeparator: presentationData.dateTimeFormat.decimalSeparator)
            } else {
                sizeText = autodownloadDataSizeString(Int64(size), decimalSeparator: presentationData.dateTimeFormat.decimalSeparator)
            }
            let text = presentationData.strings.AutoDownloadSettings_UpTo(sizeText).0
            entries.append(.sizeItem(presentationData.theme, presentationData.dateTimeFormat.decimalSeparator, text, size))
            if #available(iOSApplicationExtension 10.3, *), category == .video {
                entries.append(.sizePreload(presentationData.theme, presentationData.strings.AutoDownloadSettings_PreloadVideo, predownload, size > 2 * 1024 * 1024))
                entries.append(.sizePreloadInfo(presentationData.theme, presentationData.strings.AutoDownloadSettings_PreloadVideoInfo(sizeText).0))
            }
        default:
            break
    }
    
    return entries
}

func autodownloadMediaCategoryController(context: AccountContext, connectionType: AutomaticDownloadConnectionType, category: AutomaticDownloadCategory) -> ViewController {
    let arguments = AutodownloadMediaCategoryControllerArguments(togglePeer: { type in
        let _ = updateMediaDownloadSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
            var settings = settings
            var categories = effectiveAutodownloadCategories(settings: settings, networkType: connectionType.automaticDownloadNetworkType)
            switch category {
                case .photo:
                    switch type {
                        case .contact:
                            categories.photo.contacts = !categories.photo.contacts
                        case .otherPrivate:
                            categories.photo.otherPrivate = !categories.photo.otherPrivate
                        case .group:
                            categories.photo.groups = !categories.photo.groups
                        case .channel:
                            categories.photo.channels = !categories.photo.channels
                    }
                case .video:
                    switch type {
                        case .contact:
                            categories.video.contacts = !categories.video.contacts
                        case .otherPrivate:
                            categories.video.otherPrivate = !categories.video.otherPrivate
                        case .group:
                            categories.video.groups = !categories.video.groups
                        case .channel:
                            categories.video.channels = !categories.video.channels
                }
                case .file:
                    switch type {
                        case .contact:
                            categories.file.contacts = !categories.file.contacts
                        case .otherPrivate:
                            categories.file.otherPrivate = !categories.file.otherPrivate
                        case .group:
                            categories.file.groups = !categories.file.groups
                        case .channel:
                            categories.file.channels = !categories.file.channels
                }
            }
            switch connectionType {
                case .cellular:
                    settings.cellular.preset = .custom
                    settings.cellular.custom = categories
                case .wifi:
                    settings.wifi.preset = .custom
                    settings.wifi.custom = categories
            }
            return settings
        }).start()
    }, adjustSize: { size in
        let _ = updateMediaDownloadSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
            var settings = settings
            var categories = effectiveAutodownloadCategories(settings: settings, networkType: connectionType.automaticDownloadNetworkType)
            switch category {
                case .photo:
                    categories.photo.sizeLimit = size
                case .video:
                    categories.video.sizeLimit = size
                case .file:
                    categories.file.sizeLimit = size
            }
            switch connectionType {
                case .cellular:
                    settings.cellular.preset = .custom
                    settings.cellular.custom = categories
                case .wifi:
                    settings.wifi.preset = .custom
                    settings.wifi.custom = categories
            }
            return settings
        }).start()
    }, toggleVideoPreload: {
        let _ = updateMediaDownloadSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
            var settings = settings
            var categories = effectiveAutodownloadCategories(settings: settings, networkType: connectionType.automaticDownloadNetworkType)
            switch category {
                case .photo:
                    categories.photo.predownload = !categories.photo.predownload
                case .video:
                    categories.video.predownload = !categories.video.predownload
                case .file:
                    categories.file.predownload = !categories.file.predownload
            }
            switch connectionType {
                case .cellular:
                    settings.cellular.preset = .custom
                    settings.cellular.custom = categories
                case .wifi:
                    settings.wifi.preset = .custom
                    settings.wifi.custom = categories
            }
            return settings
        }).start()
    })
    
    let currentAutodownloadSettings = {
        return context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.automaticMediaDownloadSettings])
        |> take(1)
        |> map { sharedData -> MediaAutoDownloadSettings in
            if let value = sharedData.entries[ApplicationSpecificSharedDataKeys.automaticMediaDownloadSettings] as? MediaAutoDownloadSettings {
                return value
            } else {
                return .defaultSettings
            }
        }
    }
    
    let initialValuePromise: Promise<MediaAutoDownloadSettings> = Promise()
    initialValuePromise.set(currentAutodownloadSettings())
    
    let signal = combineLatest(context.sharedContext.presentationData, context.sharedContext.accountManager.sharedData(keys: [SharedDataKeys.autodownloadSettings, ApplicationSpecificSharedDataKeys.automaticMediaDownloadSettings])) |> deliverOnMainQueue
        |> map { presentationData, sharedData -> (ItemListControllerState, (ItemListNodeState, Any)) in
            var automaticMediaDownloadSettings: MediaAutoDownloadSettings
            if let value = sharedData.entries[ApplicationSpecificSharedDataKeys.automaticMediaDownloadSettings] as? MediaAutoDownloadSettings {
                automaticMediaDownloadSettings = value
            } else {
                automaticMediaDownloadSettings = .defaultSettings
            }
            
            var autodownloadSettings: AutodownloadSettings
            if let value = sharedData.entries[SharedDataKeys.autodownloadSettings] as? AutodownloadSettings {
                autodownloadSettings = value
                automaticMediaDownloadSettings = automaticMediaDownloadSettings.updatedWithAutodownloadSettings(autodownloadSettings)
            } else {
                autodownloadSettings = .defaultSettings
            }
            
            let title: String
            switch category {
                case .photo:
                    title = presentationData.strings.AutoDownloadSettings_PhotosTitle
                case .video:
                    title = presentationData.strings.AutoDownloadSettings_VideosTitle
                case .file:
                    title = presentationData.strings.AutoDownloadSettings_DocumentsTitle
            }
            
            let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
            let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: autodownloadMediaCategoryControllerEntries(presentationData: presentationData, connectionType: connectionType, category: category, settings: automaticMediaDownloadSettings), style: .blocks, emptyStateItem: nil, animateChanges: false)
            
            return (controllerState, (listState, arguments))
    }
    
    let controller = ItemListController(context: context, state: signal)
    controller.didDisappear = { _ in
        let _ = (combineLatest(initialValuePromise.get() |> take(1), currentAutodownloadSettings())
        |> mapToSignal { initialValue, currentValue -> Signal<Void, NoError> in
            let initialConnection = initialValue.connectionSettings(for: connectionType.automaticDownloadNetworkType)
            let currentConnection = currentValue.connectionSettings(for: connectionType.automaticDownloadNetworkType)
            if currentConnection != initialConnection, let categories = currentConnection.custom, currentConnection.preset == .custom {
                let preset: SavedAutodownloadPreset
                switch connectionType {
                    case .cellular:
                        preset = .medium
                    case .wifi:
                        preset = .high
                }
                let settings = AutodownloadPresetSettings(disabled: false, photoSizeMax: categories.photo.sizeLimit, videoSizeMax: categories.video.sizeLimit, fileSizeMax: categories.file.sizeLimit, preloadLargeVideo: categories.video.predownload, lessDataForPhoneCalls: false, videoUploadMaxbitrate: 0)
                return saveAutodownloadSettings(account: context.account, preset: preset, settings: settings)
            }
            return .complete()
        }).start()
    }
    return controller
}

