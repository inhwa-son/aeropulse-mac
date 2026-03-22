import ProjectDescription

let project = Project(
    name: "AeroPulse",
    organizationName: "Dan",
    options: .options(
        automaticSchemesOptions: .enabled()
    ),
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.2",
            "MACOSX_DEPLOYMENT_TARGET": "15.0",
            "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
            "CURRENT_PROJECT_VERSION": "5",
            "MARKETING_VERSION": "1.0.4"
        ]
    ),
    targets: [
        .target(
            name: "AeroPulsePrivilegedHelper",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "com.dan.aeropulse.helperd2",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .default,
            sources: [
                "App/Sources/Daemon/**",
                "App/Sources/Shared/PrivilegedFanControlProtocol.swift",
                "App/Sources/Shared/PrivilegedFanSnapshotPayload.swift",
                "App/Sources/Shared/SMC/AeroPulseSMCBridge.c",
                "App/Sources/Shared/SMC/AeroPulseSMCBridge.h",
                "App/Sources/Shared/SMC/SMCRawFanReader.swift"
            ],
            dependencies: [
                .sdk(name: "IOKit", type: .framework)
            ],
            settings: .settings(
                base: [
                    "SWIFT_OBJC_BRIDGING_HEADER": "App/Sources/Shared/AeroPulse-Bridging-Header.h"
                ]
            )
        ),
        .target(
            name: "AeroPulseControlService",
            destinations: .macOS,
            product: .xpc,
            bundleId: "com.dan.aeropulse.controlservice",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "AeroPulse Control Service",
                "XPCService": [
                    "ServiceType": "Application"
                ]
            ]),
            sources: [
                "App/Sources/Shared/**",
                "App/Sources/Service/**",
                "App/Sources/Domain/Models.swift",
                "App/Sources/Infrastructure/CommandRunner.swift",
                "App/Sources/Infrastructure/FanCLIService.swift"
            ],
            dependencies: [
                .sdk(name: "IOKit", type: .framework)
            ],
            settings: .settings(
                base: [
                    "SWIFT_OBJC_BRIDGING_HEADER": "App/Sources/Shared/AeroPulse-Bridging-Header.h"
                ]
            )
        ),
        .target(
            name: "AeroPulse",
            destinations: .macOS,
            product: .app,
            bundleId: "com.dan.aeropulse",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "AeroPulse",
                "CFBundleShortVersionString": "1.0.4",
                "CFBundleVersion": "5",
                "LSApplicationCategoryType": "public.app-category.utilities",
                "NSPrincipalClass": "NSApplication",
                "NSMainStoryboardFile": "",
                "NSSupportsAutomaticTermination": false,
                "NSSupportsSuddenTermination": false,
                "SMPrivilegedExecutables": [
                    "com.dan.aeropulse.helperd2": "identifier \\\"com.dan.aeropulse.helperd2\\\" and anchor apple generic and certificate leaf[subject.OU] = \\\"Y9TRXFZMR5\\\""
                ]
            ]),
            sources: ["App/Sources/App/**", "App/Sources/Domain/**", "App/Sources/Infrastructure/**", "App/Sources/Features/**", "App/Sources/Shared/**"],
            resources: ["App/Resources/**"],
            scripts: [
                .post(
                    script: """
                    set -eu
                    helper_source=\"$BUILT_PRODUCTS_DIR/AeroPulsePrivilegedHelper\"
                    helper_destination=\"$TARGET_BUILD_DIR/$WRAPPER_NAME/Contents/Library/PrivilegedHelperTools/AeroPulsePrivilegedHelper\"
                    plist_source=\"$SRCROOT/App/Support/LaunchDaemons/com.dan.aeropulse.helperd2.plist\"
                    plist_destination=\"$TARGET_BUILD_DIR/$WRAPPER_NAME/Contents/Library/LaunchDaemons/com.dan.aeropulse.helperd2.plist\"

                    mkdir -p \"$(dirname \"$helper_destination\")\"
                    mkdir -p \"$(dirname \"$plist_destination\")\"
                    cp \"$helper_source\" \"$helper_destination\"
                    chmod 755 \"$helper_destination\"
                    cp \"$plist_source\" \"$plist_destination\"
                    """,
                    name: "Embed Privileged Helper",
                    basedOnDependencyAnalysis: false
                )
            ],
            dependencies: [
                .sdk(name: "IOKit", type: .framework),
                .sdk(name: "Charts", type: .framework),
                .target(name: "AeroPulsePrivilegedHelper"),
                .target(name: "AeroPulseControlService")
            ],
            settings: .settings(
                base: [
                    "SWIFT_OBJC_BRIDGING_HEADER": "App/Sources/Shared/AeroPulse-Bridging-Header.h"
                ]
            )
        ),
        .target(
            name: "AeroPulseTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.dan.aeropulse.tests",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .default,
            sources: ["App/Tests/**"],
            dependencies: [
                .target(name: "AeroPulse")
            ]
        )
    ]
)
