import AppKit
import SwiftUI

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

@main
enum SwiftyTranscoderEntryPoint {
    @MainActor
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        // Finder launches (including legacy -psn arguments) retain the GUI path.
        if arguments.isEmpty || arguments.first?.hasPrefix("-psn_") == true {
            SwiftyTranscoderApp.main()
        } else {
            exit(await CommandLineRunner.run(arguments))
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
