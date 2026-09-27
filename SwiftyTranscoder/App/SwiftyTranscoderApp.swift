import AppKit
import SwiftUI

@main
struct SwiftyTranscoderApp: App {
    init() {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 900, height: 760)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About SwiftyTranscoder") {
                    SwiftyTranscoderAboutPanel.show()
                }
            }
        }
    }
}

@MainActor
private enum SwiftyTranscoderAboutPanel {
    static func show() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            options[.applicationIcon] = icon
        }
        options[.applicationName] = "SwiftyTranscoder"
        options[.applicationVersion] = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0.0"
        options[.version] = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "10"
        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
    }
}
