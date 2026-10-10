import AppKit
import AssistantUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AssistantModel(language: UILanguage.detect(), embeddedTag: embeddedReleaseTag)
    private var controller: AssistantWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // בהיר בלבד: העיצוב אינו מוגדר למצב כהה.
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.mainMenu = AssistantMenu.make(strings: model.strings)
        let controller = AssistantWindowController(model: model)
        self.controller = controller
        controller.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Cmd-Q בזמן הורדה שואל באותו חלון מעוצב כמו הרמזור האדום.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.requestClose() ? .terminateNow : .terminateCancel
    }
}

// חלון אחד בלבד, בלי WindowGroup: "חלון חדש" היה פותח מסייע שני על אותו מטמון.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
