import AppKit
import SwiftUI

@main
struct ClipPressApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        FontLoader.registerBundledFonts()
    }

    var body: some Scene {
        Window("ClipPress", id: "main") {
            ContentView()
                .environmentObject(appDelegate.model)
        }
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands(model: appDelegate.model)
        }
    }
}

private struct AppCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Videos…") { model.chooseFiles() }
                .keyboardShortcut("o")
                .disabled(model.isExporting)
        }
    }
}

/// Owns the model so quitting can check for a running export first.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched with `swift run`, which starts the binary outside an .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.isExporting else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Stop the export and quit?"
        alert.informativeText = "The video being exported will be deleted. You'll have to start the export again."
        alert.addButton(withTitle: "Keep exporting")
        let stop = alert.addButton(withTitle: "Stop and quit")
        stop.hasDestructiveAction = true

        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        model.abandonExportForQuit()
        return .terminateNow
    }
}
