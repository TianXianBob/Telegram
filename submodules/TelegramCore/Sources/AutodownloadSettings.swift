import Foundation
import Postbox
import TelegramApi
import SwiftSignalKit

import SyncCore

public func updateAutodownloadSettingsInteractively(accountManager: AccountManager, _ f: @escaping (AutodownloadSettings) -> AutodownloadSettings) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(SharedDataKeys.autodownloadSettings, { entry in
            let currentSettings: AutodownloadSettings
            if let entry = entry as? AutodownloadSettings {
                currentSettings = entry
            } else {
                currentSettings = AutodownloadSettings.defaultSettings
            }
            return f(currentSettings)
        })
    }
}

extension AutodownloadPresetSettings {
    init(apiAutodownloadSettings: Api.AutoDownloadSettings) {
        switch apiAutodownloadSettings {
        case let .autoDownloadSettings(flags, photoSizeMax, videoSizeMax, fileSizeMax, videoUploadMaxbitrate):
                self.init(disabled: (flags & (1 << 0)) != 0, photoSizeMax: photoSizeMax, videoSizeMax: videoSizeMax, fileSizeMax: fileSizeMax, preloadLargeVideo: (flags & (1 << 1)) != 0, lessDataForPhoneCalls: (flags & (1 << 3)) != 0, videoUploadMaxbitrate: videoUploadMaxbitrate)
        case let .autoDownloadSettingsLegacy(flags, photoSizeMax, videoSizeMax, fileSizeMax):
            self.init(disabled: (flags & (1 << 0)) != 0, photoSizeMax: photoSizeMax, videoSizeMax: videoSizeMax, fileSizeMax: fileSizeMax, preloadLargeVideo: (flags & (1 << 1)) != 0, lessDataForPhoneCalls: (flags & (1 << 3)) != 0, videoUploadMaxbitrate: 0)
        }
    }
}

extension AutodownloadSettings {
    init(apiAutodownloadSettings: Api.account.AutoDownloadSettings) {
        switch apiAutodownloadSettings {
            case let .autoDownloadSettings(low, medium, high):
                self.init(lowPreset: AutodownloadPresetSettings(apiAutodownloadSettings: low), mediumPreset: AutodownloadPresetSettings(apiAutodownloadSettings: medium), highPreset: AutodownloadPresetSettings(apiAutodownloadSettings: high))
        }
    }
}

func apiAutodownloadPresetSettings(_ autodownloadPresetSettings: AutodownloadPresetSettings) -> Api.AutoDownloadSettings {
    var flags: Int32 = 0
    if autodownloadPresetSettings.disabled {
        flags |= (1 << 0)
    }
    if autodownloadPresetSettings.preloadLargeVideo {
        flags |= (1 << 1)
    }
    if autodownloadPresetSettings.lessDataForPhoneCalls {
        flags |= (1 << 3)
    }
    return .autoDownloadSettings(flags: flags, photoSizeMax: autodownloadPresetSettings.photoSizeMax, videoSizeMax: autodownloadPresetSettings.videoSizeMax, fileSizeMax: autodownloadPresetSettings.fileSizeMax, videoUploadMaxbitrate: autodownloadPresetSettings.videoUploadMaxbitrate)
}

