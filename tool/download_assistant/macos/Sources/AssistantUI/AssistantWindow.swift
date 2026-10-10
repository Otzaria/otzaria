import AppKit
import SwiftUI

/// חלון אחד בגודל קבוע, 400×660 עם שורת הכותרת של macOS (רמזורים ושם החלון), בגוון שורת
/// הכותרת של העיצוב. בהיר בלבד. הרמזור האדום בזמן עבודה שואל לפני יציאה.
public final class AssistantWindowController: NSObject, NSWindowDelegate {
    public let window: NSWindow
    private let model: AssistantModel

    public init(model: AssistantModel) {
        self.model = model
        let hosting = NSHostingView(rootView: AssistantRootView(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: Metrics.windowWidth, height: Metrics.contentHeight)
        window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        // השם נשאר ב-window.title בשביל VoiceOver ו-Mission Control, אבל הכותרת המרוכזת של
        // המערכת מוסתרת: בעברית היא צמודה לימין ובאנגלית אחרי הרמזורים, כמו ב-Windows.
        window.title = model.strings(.appTitle)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Palette.nsTitleBar
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenNone]
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.center()
        super.init()
        window.delegate = self
        addTitle(model.strings)
    }

    /// הכותרת כאביזר של שורת הכותרת: גופן רגיל, 13 נקודות, בצבע הטקסט; גרירה דרכה מזיזה את החלון.
    private func addTitle(_ strings: Strings) {
        let label = TitleBarLabel(labelWithString: strings(.appTitle))
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = NSColor(hex: 0x201B13)
        label.lineBreakMode = .byTruncatingTail
        // VoiceOver קורא את שם החלון עצמו; התווית היא קישוט בלבד.
        label.setAccessibilityElement(false)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.sizeToFit()

        // אנגלית: ריווח אחרי הרמזורים. עברית: שוליים מהקצה הימני, כמו UiTitleLabel ב-Windows.
        let lead: CGFloat = strings.english ? 6 : 8
        let trail: CGFloat = strings.english ? 8 : 12
        let container = TitleBarView(frame: NSRect(x: 0, y: 0, width: ceil(label.frame.width) + lead + trail, height: 28))
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leftAnchor.constraint(equalTo: container.leftAnchor, constant: lead),
            label.rightAnchor.constraint(equalTo: container.rightAnchor, constant: -trail),
        ])

        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = container
        accessory.layoutAttribute = strings.english ? .left : .right
        window.addTitlebarAccessoryViewController(accessory)
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.requestClose()
    }
}

/// לחיצה על הכותרת המצוירת מזיזה את החלון, כמו כותרת המערכת.
private final class TitleBarView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

private final class TitleBarLabel: NSTextField {
    override var mouseDownCanMoveWindow: Bool { true }
}

/// תפריט מינימלי בשפת הממשק: הסתרה ויציאה, העתקה (פרטים טכניים, נתיבים), מזעור וסגירה.
public enum AssistantMenu {
    public static func make(strings: Strings) -> NSMenu {
        let name = strings(.appShortName)
        let main = NSMenu()

        let app = NSMenu(title: name)
        app.addItem(withTitle: strings(.menuHide, name), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = app.addItem(
            withTitle: strings(.menuHideOthers),
            action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h"
        )
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: strings(.menuShowAll), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: strings(.menuQuit, name), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(app))

        let edit = NSMenu(title: strings(.menuEdit))
        edit.addItem(withTitle: strings(.menuCopy), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: strings(.menuSelectAll), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu(edit))

        let window = NSMenu(title: strings(.menuWindow))
        window.addItem(withTitle: strings(.menuMinimize), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: strings(.menuCloseWindow), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu(window))
        NSApplication.shared.windowsMenu = window
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
