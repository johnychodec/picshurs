import SwiftUI

@main
struct PicshursApp: App {
    @State private var settings = AppSettings()
    @State private var viewModel: AppViewModel
    @Environment(\.openWindow) private var openWindow

    init() {
        let s = AppSettings()
        _settings = State(wrappedValue: s)
        _viewModel = State(wrappedValue: AppViewModel(settings: s))

        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
                .environment(settings)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Picshurs") {
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    let credits = NSAttributedString(
                        string: "Local-first photo organizer.\nYour files, your disk, your control.\n\ngithub.com/johnychodec/picshurs",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 11),
                            .foregroundColor: NSColor.secondaryLabelColor,
                            .paragraphStyle: style,
                        ]
                    )
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Picshurs",
                        .applicationVersion: "1.0",
                        .version: "Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")",
                        .credits: credits,
                        .init(rawValue: "Copyright"): "2026 Picshurs",
                    ])
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    openWindow(id: "settings")
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("Navigation") {
                Button("Refresh") {
                    viewModel.refreshCurrentView()
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Open Photo") {
                    viewModel.openSelectedPhoto()
                }
                .keyboardShortcut(.return, modifiers: [])

                Button("Close Viewer") {
                    viewModel.closeViewer()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Delete Photo") {
                    viewModel.deleteCurrentPhoto()
                }
                .keyboardShortcut(.delete, modifiers: [])
            }
        }

        Window("Picshurs Settings", id: "settings") {
            SettingsView()
                .environment(viewModel)
                .environment(settings)
        }
        .windowResizability(.contentMinSize)
    }
}
