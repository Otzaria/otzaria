import AppKit
import SwiftUI

/// הצבעים והמידות של המסייע ל-Windows (assistant_art.isi), שהם צבעי התמה הבהירה של אוצריא.
enum Palette {
    static let page = Color(hex: 0xF6EDE5)
    static let titleBar = Color(hex: 0xF3E6DA)
    static let titleBarBorder = Color(hex: 0xE1D4C8)
    static let card = Color(hex: 0xFFF8F4)
    static let cardSelected = Color(hex: 0xFEF0E3)
    static let cardHover = Color(hex: 0xF5EBE2)
    static let divider = Color(hex: 0xD3C4B4)
    static let outline = Color(hex: 0x817567)
    static let primary = Color(hex: 0x805610)
    static let primaryPressed = Color(hex: 0x6B470C)
    static let onPrimary = Color.white
    static let tonal = Color(hex: 0xFBDEBC)
    static let tonalPressed = Color(hex: 0xF2CFA6)
    static let onTonal = Color(hex: 0x56442A)
    static let text = Color(hex: 0x201B13)
    static let muted = Color(hex: 0x4F4539)
    static let faint = Color(hex: 0x817567)
    static let disabled = Color(hex: 0xDDD3CC)
    static let disabledText = Color(hex: 0xA59D95)
    static let error = Color(hex: 0xBA1A1A)
    static let field = Color.white
    static let dotDone = Color(hex: 0xBBA27A)
    static let ornament = Color(hex: 0xB48A3E)
    static let dialog = Color(hex: 0xF3E6DA)
    /// barrierColor של הדו-שיח בתוכנה: שחור ב-13.3%.
    static let shade = Color.black.opacity(0.133)

    static let nsTitleBar = NSColor(hex: 0xF3E6DA)
    static let nsPage = NSColor(hex: 0xF6EDE5)
}

enum Metrics {
    static let windowWidth: CGFloat = 400
    /// החלון כולו 660 נקודות; שורת הכותרת של macOS היא 28 מהן.
    static let contentHeight: CGFloat = 632
    static let margin: CGFloat = 24
    static let contentWidth: CGFloat = 352
    static let radius: CGFloat = 8
    static let cardGap: CGFloat = 10
    static let stepsHeight: CGFloat = 44
    static let footerHeight: CGFloat = 72
    static let buttonHeight: CGFloat = 40
    static let wideButtonHeight: CGFloat = 44
    static let primaryButtonWidth: CGFloat = 160
    static let secondaryButtonWidth: CGFloat = 120
    static let icon: CGFloat = 40
    static let toggle: CGFloat = 20
    static let badge: CGFloat = 72
}

enum Fonts {
    static let pageTitle = Font.system(size: 20, weight: .semibold)
    static let pageDesc = Font.system(size: 14)
    static let pageHint = Font.system(size: 13)
    static let step = Font.system(size: 12)
    static let cardTitle = Font.system(size: 16)
    static let cardDesc = Font.system(size: 13)
    static let cardSide = Font.system(size: 12)
    static let button = Font.system(size: 14, weight: .semibold)
    static let percent = Font.system(size: 40, weight: .bold)
    static let progressCaption = Font.system(size: 14)
    static let progressDetail = Font.system(size: 13)
    static let heroTitle = Font.system(size: 24, weight: .semibold)
    static let heroSubtitle = Font.system(size: 16)
    static let heroNote = Font.system(size: 13)
    static let dialogTitle = Font.system(size: 18, weight: .semibold)
    static let dialogText = Font.system(size: 14)
    static let rowLabel = Font.system(size: 12)
    static let rowValue = Font.system(size: 16)
    static let mono = Font.system(size: 12, design: .monospaced)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// RLM אחרי כל פסיק במשפט עברי: בלעדיו רשימה של שמות לטיניים ("macOS, Linux")
/// מוצגת כגוש אחד משמאל לימין, והפריטים נקראים בסדר הפוך.
func bidi(_ text: String) -> String {
    guard text.unicodeScalars.contains(where: { (0x0590...0x05FF).contains($0.value) }) else { return text }
    // RLM בראש: משפט עברי שפותח במילה לטינית ("Windows — כמו המחשב הזה") נשאר מימין לשמאל.
    return "\u{200F}" + text.replacingOccurrences(of: ", ", with: ",\u{200F} ")
}
