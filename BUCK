load("//Config:utils.bzl",
    "library_configs",
)

load("//Config:configs.bzl",
    "app_binary_configs",
    "share_extension_configs",
    "widget_extension_configs",
    "notification_content_extension_configs",
    "notification_service_extension_configs",
    "intents_extension_configs",
    "watch_extension_binary_configs",
    "watch_binary_configs",
    "info_plist_substitutions",
    "app_info_plist_substitutions",
    "share_extension_info_plist_substitutions",
    "widget_extension_info_plist_substitutions",
    "notification_content_extension_info_plist_substitutions",
    "notification_service_extension_info_plist_substitutions",
    "intents_extension_info_plist_substitutions",
    "watch_extension_info_plist_substitutions",
    "watch_info_plist_substitutions",
    "DEVELOPMENT_LANGUAGE",
)

load("//Config:buck_rule_macros.bzl",
    "apple_lib",
    "framework_binary_dependencies",
    "framework_bundle_dependencies",
    "glob_map",
    "glob_sub_map",
    "merge_maps",
)

framework_dependencies = [
    "//submodules/MtProtoKit:MtProtoKit",
    "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    "//submodules/Postbox:Postbox",
    "//submodules/TelegramApi:TelegramApi",
    "//submodules/SyncCore:SyncCore",
    "//submodules/TelegramCore:TelegramCore",
    "//submodules/AsyncDisplayKit:AsyncDisplayKit",
    "//submodules/Display:Display",
    "//submodules/TelegramUI:TelegramUI",
]

resource_dependencies = [
    "//submodules/LegacyComponents:LegacyComponentsResources",
    "//submodules/TelegramUI:TelegramUIAssets",
    "//submodules/TelegramUI:TelegramUIResources",
    "//submodules/WalletUI:WalletUIAssets",
    "//submodules/WalletUI:WalletUIResources",
    "//submodules/PasswordSetupUI:PasswordSetupUIResources",
    "//submodules/PasswordSetupUI:PasswordSetupUIAssets",
    "//submodules/OverlayStatusController:OverlayStatusControllerResources",
    "//:AppResources",
    "//:AppStringResources",
    "//:InfoPlistStringResources",
    "//:AppIntentVocabularyResources",
    "//:Icons",
    "//:AdditionalIcons",
    "//:LaunchScreen",
]

build_phase_scripts = [
]

apple_resource(
    name = "AppResources",
    files = glob([
        "Telegram-iOS/Resources/**/*",
    ], exclude = ["Telegram-iOS/Resources/**/.*"]),
    visibility = ["PUBLIC"],
)

apple_resource(
    name = "AppStringResources",
    files = [],
    variants = glob([
        "Telegram-iOS/*.lproj/Localizable.strings",
    ]),
    visibility = ["PUBLIC"],
)

apple_resource(
    name = "AppIntentVocabularyResources",
    files = [],
    variants = glob([
        "Telegram-iOS/*.lproj/AppIntentVocabulary.plist",
    ]),
    visibility = ["PUBLIC"],
)

apple_resource(
    name = "InfoPlistStringResources",
    files = [],
    variants = glob([
        "Telegram-iOS/*.lproj/InfoPlist.strings",
    ]),
    visibility = ["PUBLIC"],
)

apple_asset_catalog(
  name = "Icons",
  dirs = [
    "Telegram-iOS/Icons.xcassets",
    "Telegram-iOS/AppIcons.xcassets",
  ],
  app_icon = "AppIconLLC",
  visibility = ["PUBLIC"],
)

apple_resource(
    name = "AdditionalIcons",
    files = glob([
        "Telegram-iOS/*.png",
    ]),
    visibility = ["PUBLIC"],
)

apple_resource(
    name = "LaunchScreen",
    files = [
        "Telegram-iOS/Base.lproj/LaunchScreen.xib",
    ],
    visibility = ["PUBLIC"],
)

apple_library(
    name = "AppLibrary",
    visibility = [
        "//:",
        "//...",
    ],
    configs = library_configs(),
    swift_version = native.read_config("swift", "version"),
    srcs = [
        "Telegram-iOS/main.m",
        "Telegram-iOS/Application.swift"
    ],
    deps = [
    ]
    + framework_binary_dependencies(framework_dependencies),
)

apple_binary(
    name = "AppBinary",
    visibility = [
        "//:",
        "//...",
    ],
    configs = app_binary_configs(),
    swift_version = native.read_config("swift", "version"),
    srcs = [
        "SupportFiles/Empty.swift",
    ],
    deps = [
        ":AppLibrary",
    ]
    + resource_dependencies,
)

apple_bundle(
    name = "Telegram",
    visibility = [
        "//:",
    ],
    extension = "app",
    binary = ":AppBinary",
    product_name = "Telegram",
    info_plist = "Telegram-iOS/Info.plist",
    info_plist_substitutions = app_info_plist_substitutions(),
    deps = [
        ":ShareExtension",
        ":WidgetExtension",
        ":NotificationContentExtension",
        ":NotificationServiceExtension",
        ":IntentsExtension",
        ":WatchApp#watch",
    ]
    + framework_bundle_dependencies(framework_dependencies),
)

# Share Extension

apple_binary(
    name = "ShareBinary",
    srcs = glob([
        "Share/**/*.swift",
    ]),
    configs = share_extension_configs(),
    linker_flags = [
        "-e",
        "_NSExtensionMain",
        "-Xlinker",
        "-rpath",
        "-Xlinker",
        "/usr/lib/swift",
        "-Xlinker",
        "-rpath",
        "-Xlinker",
        "@executable_path/../../Frameworks",
    ],
    deps = [
        "//submodules/TelegramUI:TelegramUI#shared",
    ],
    frameworks = [
        "$SDKROOT/System/Library/Frameworks/UIKit.framework",
        "$SDKROOT/System/Library/Frameworks/Foundation.framework",
    ],
)

apple_bundle(
    name = "ShareExtension",
    binary = ":ShareBinary",
    extension = "appex",
    info_plist = "Share/Info.plist",
    info_plist_substitutions = share_extension_info_plist_substitutions(),
    deps = [
    ],
    xcode_product_type = "com.apple.product-type.app-extension",
)

# Widget

apple_binary(
    name = "WidgetBinary",
    srcs = glob([
        "Widget/**/*.swift",
    ]),
    configs = widget_extension_configs(),
    swift_compiler_flags = [
        "-application-extension",
    ],
    linker_flags = [
        "-e",
        "_NSExtensionMain",
        "-Xlinker",
        "-rpath",
        "-Xlinker",
        "/usr/lib/swift",
        "-Xlinker",
        "-rpath",
        "-Xlinker",
        "@executable_path/../../Frameworks",
    ],
    deps = [
        "//submodules/BuildConfig:BuildConfig",
        "//submodules/WidgetItems:WidgetItems",
        "//submodules/AppLockState:AppLockState",
    ],
    frameworks = [
        "$SDKROOT/System/Library/Frameworks/UIKit.framework",
        "$SDKROOT/System/Library/Frameworks/Foundation.framework",
        "$SDKROOT/System/Library/Frameworks/NotificationCenter.framework",
    ],
)

apple_bundle(
    name = "WidgetExtension",
    binary = ":WidgetBinary",
    extension = "appex",
    info_plist = "Widget/Info.plist",
    info_plist_substitutions = widget_extension_info_plist_substitutions(),
    deps = [
    ],
    xcode_product_type = "com.apple.product-type.app-extension",
)

# Notification Content

apple_binary(
    name = "NotificationContentBinary",
    srcs = glob([
        "NotificationContent/**/*.swift",
    ]),
    configs = notification_content_extension_configs(),
    swift_compiler_flags = [
        "-application-extension",
    ],
    linker_flags = [
        "-e",
        "_NSExtensionMain",
        "-Xlinker",
        "-rpath",
        "-Xlinker",
        "/usr/lib/swift",
        "-Xlinker",
        "-rpath",
        "-Xlinker",
        "@executable_path/../../Frameworks",
    ],
    deps = [
        "//submodules/TelegramUI:TelegramUI#shared",
    ],
    frameworks = [
        "$SDKROOT/System/Library/Frameworks/UIKit.framework",
        "$SDKROOT/System/Library/Frameworks/Foundation.framework",
        "$SDKROOT/System/Library/Frameworks/UserNotificationsUI.framework",
    ],
)

apple_bundle(
    name = "NotificationContentExtension",
    binary = ":NotificationContentBinary",
    extension = "appex",
    info_plist = "NotificationContent/Info.plist",
    info_plist_substitutions = notification_content_extension_info_plist_substitutions(),
    deps = [
    ],
    xcode_product_type = "com.apple.product-type.app-extension",
)

#Notification Service

apple_binary(
    name = "NotificationServiceBinary",
    srcs = glob([
        "NotificationService/**/*.m",
        "NotificationService/**/*.swift",
    ]),
    headers = glob([
       "NotificationService/**/*.h", 
    ]),
    bridging_header = "NotificationService/NotificationService-Bridging-Header.h",
    configs = notification_service_extension_configs(),
    swift_compiler_flags = [
        "-application-extension",
    ],
    linker_flags = [
        "-e",
        "_NSExtensionMain",
        "-Xlinker",
        "-rpath",
        "-Xlinker",
        "/usr/lib/swift",
        "-Xlinker",
        "-rpath",
        "-Xlinker",
        "@executable_path/../../Frameworks",
    ],
    deps = [
        "//submodules/BuildConfig:BuildConfig",
        "//submodules/MtProtoKit:MtProtoKit#shared",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit#shared",
        "//submodules/EncryptionProvider:EncryptionProvider",
        "//submodules/Database/ValueBox:ValueBox",
        "//submodules/Database/PostboxDataTypes:PostboxDataTypes",
        "//submodules/Database/MessageHistoryReadStateTable:MessageHistoryReadStateTable",
        "//submodules/Database/MessageHistoryMetadataTable:MessageHistoryMetadataTable",
        "//submodules/Database/PreferencesTable:PreferencesTable",
        "//submodules/Database/PeerTable:PeerTable",
        "//submodules/sqlcipher:sqlcipher",
        "//submodules/AppLockState:AppLockState",
        "//submodules/NotificationsPresentationData:NotificationsPresentationData",
    ],
    frameworks = [
        "$SDKROOT/System/Library/Frameworks/Foundation.framework",
        "$SDKROOT/System/Library/Frameworks/UserNotifications.framework",
    ],
)

apple_bundle(
    name = "NotificationServiceExtension",
    binary = ":NotificationServiceBinary",
    extension = "appex",
    info_plist = "NotificationService/Info.plist",
    info_plist_substitutions = notification_service_extension_info_plist_substitutions(),
    deps = [
    ],
    xcode_product_type = "com.apple.product-type.app-extension",
)

# Intents

apple_binary(
    name = "IntentsBinary",
    srcs = glob([
        "SiriIntents/**/*.swift",
    ]),
    configs = intents_extension_configs(),
    swift_compiler_flags = [
        "-application-extension",
    ],
    linker_flags = [
        "-e",
        "_NSExtensionMain",
        "-Xlinker",
        "-rpath",
        "-Xlinker",
        "/usr/lib/swift",
        "-Xlinker",
        "-rpath",
        "-Xlinker",
        "@executable_path/../../Frameworks",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit#shared",
        "//submodules/Postbox:Postbox#shared",
        "//submodules/TelegramApi:TelegramApi#shared",
        "//submodules/SyncCore:SyncCore#shared",
        "//submodules/TelegramCore:TelegramCore#shared",
        "//submodules/BuildConfig:BuildConfig",
        "//submodules/OpenSSLEncryptionProvider:OpenSSLEncryptionProvider",
    ],
    frameworks = [
        "$SDKROOT/System/Library/Frameworks/Foundation.framework",
        "$SDKROOT/System/Library/Frameworks/Intents.framework",
        "$SDKROOT/System/Library/Frameworks/Contacts.framework",
    ],
)

apple_bundle(
    name = "IntentsExtension",
    binary = ":IntentsBinary",
    extension = "appex",
    info_plist = "SiriIntents/Info.plist",
    info_plist_substitutions = intents_extension_info_plist_substitutions(),
    deps = [
    ],
    xcode_product_type = "com.apple.product-type.app-extension",
)

# Watch

apple_resource(
    name = "WatchAppStringResources",
    files = [],
    variants = glob([
        "Telegram-iOS/*.lproj/Localizable.strings",
    ]),
    visibility = ["PUBLIC"],
)

apple_resource(
    name = "WatchAppExtensionResources",
    files = glob([
        "Watch/Extension/Resources/**/*",
    ], exclude = ["Watch/Extension/Resources/**/.*"]),
    visibility = ["PUBLIC"],
)

apple_binary(
    name = "WatchAppExtensionBinary",
    srcs = glob([
        "Watch/Extension/**/*.m",
        "Watch/SSignalKit/**/*.m",
        "Watch/Bridge/**/*.m",
        "Watch/WatchCommonWatch/**/*.m",
    ]),
    headers = merge_maps([
        glob_map(glob([
            "Watch/Extension/*.h",
            "Watch/Bridge/*.h",
        ])),
        glob_sub_map("Watch/Extension/", glob([
            "Watch/Extension/SSignalKit/*.h",
        ])),
        glob_sub_map("Watch/", glob([
            "Watch/WatchCommonWatch/*.h",
        ])),
    ]),
    compiler_flags = [
        "-DTARGET_OS_WATCH=1",
    ],
    linker_flags = [
        "-e",
        "_WKExtensionMain",
        "-lWKExtensionMainLegacy",
    ],
    configs = watch_extension_binary_configs(),
    frameworks = [
        "$SDKROOT/System/Library/Frameworks/UserNotifications.framework",
        "$SDKROOT/System/Library/Frameworks/CoreLocation.framework",
        "$SDKROOT/System/Library/Frameworks/CoreGraphics.framework",
    ],
    deps = [
        ":WatchAppStringResources",
        ":WatchAppExtensionResources",
    ],
)

apple_bundle(
    name = "WatchAppExtension",
    binary = ":WatchAppExtensionBinary",
    extension = "appex",
    info_plist = "Watch/Extension/Info.plist",
    info_plist_substitutions = watch_extension_info_plist_substitutions(),
    xcode_product_type = "com.apple.product-type.watchkit2-extension",
)

apple_resource(
    name = "WatchAppResources",
    dirs = [],
    files = glob(["Watch/Extension/Resources/*.png"])
)

apple_asset_catalog(
  name = "WatchAppAssets",
  dirs = [
    "Watch/App/Assets.xcassets",
  ],
  app_icon = "AppIcon",
  visibility = ["PUBLIC"],
)

apple_resource(
    name = "WatchAppInterface",
    files = [
        "Watch/App/Base.lproj/Interface.storyboard",
    ],
    visibility = ["PUBLIC"],
)

apple_binary(
    name = "WatchAppBinary",
    configs = watch_binary_configs(),
    deps = [
        ":WatchAppResources",
        ":WatchAppAssets",
        ":WatchAppInterface",
        ":WatchAppStringResources",
    ],
)

apple_bundle(
    name = "WatchApp",
    binary = ":WatchAppBinary",
    visibility = [
        "//:",
    ],
    extension = "app",
    info_plist = "Watch/App/Info.plist",
    info_plist_substitutions = watch_info_plist_substitutions(),
    xcode_product_type = "com.apple.product-type.application.watchapp2",
    deps = [
        ":WatchAppExtension",
    ],
)

# Package

apple_package(
    name = "AppPackage",
    bundle = ":Telegram",
)

xcode_workspace_config(
    name = "workspace",
    workspace_name = "Telegram_Buck",
    src_target = ":Telegram",
)
