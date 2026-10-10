import AppKit
import SwiftUI

/// התמונות של העיצוב הנעוץ (installer/assistant_art.pin.json): סמלי הכרטיסים, תגי המצב ופריימי
/// הספר של הפתיחה. build_app.sh מעתיק אותן ל-Contents/Resources/Art; הטקסט כולו מצויר כאן.
/// בלי התמונות המסייע עובד — אריח בלי סמל, ותג מצויר.
public final class Art {
    public static let shared = Art(directory: Art.defaultDirectory())

    public static let bookFrameCount = 24
    static let iconScale = 200
    static let bookScale = 250

    let directory: URL?
    private var cache: [String: NSImage] = [:]

    public init(directory: URL?) {
        self.directory = directory
    }

    /// `OTZARIA_ASSISTANT_ART` (פיתוח וצילומי מסך) גובר על התיקייה שבתוך ה-.app.
    public static func defaultDirectory() -> URL? {
        if let path = ProcessInfo.processInfo.environment["OTZARIA_ASSISTANT_ART"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return Bundle.main.resourceURL?.appendingPathComponent("Art", isDirectory: true)
    }

    private func image(_ file: String, points: CGFloat) -> NSImage? {
        if let cached = cache[file] { return cached }
        guard let url = directory?.appendingPathComponent(file),
              let image = NSImage(contentsOf: url) else { return nil }
        // הקבצים בקנה מידה 200%/250%: הגודל בנקודות הופך אותם לתמונות Retina.
        image.size = NSSize(width: points, height: points * image.size.height / max(1, image.size.width))
        cache[file] = image
        return image
    }

    func icon(_ name: String) -> NSImage? {
        image("ico_\(name)_\(Self.iconScale).png", points: Metrics.icon)
    }

    func badge(_ name: String) -> NSImage? {
        image("badge_\(name)_\(Self.iconScale).png", points: Metrics.badge)
    }

    func bookFrame(_ index: Int) -> NSImage? {
        image(String(format: "book_%02d_%d.png", index, Self.bookScale), points: 220)
    }

    var hasBook: Bool { bookFrame(Self.bookFrameCount - 1) != nil }
}

/// אריח הסמל בגודל 40 (התמונה כוללת את רקע האריח), ובלעדיה — אריח בצבע הטונאלי.
struct IconTile: View {
    let name: String

    var body: some View {
        Group {
            if let image = Art.shared.icon(name) {
                Image(nsImage: image)
                    .resizable()
            } else {
                RoundedRectangle(cornerRadius: Metrics.radius).fill(Palette.tonal)
            }
        }
        .frame(width: Metrics.icon, height: Metrics.icon)
        .accessibilityHidden(true)
    }
}

enum BadgeKind: String {
    case ok, err, offline, paused
}

/// תג המצב בגודל 72: הצלחה, שגיאה, אין חיבור, עצירה.
struct StatusBadge: View {
    let kind: BadgeKind

    var body: some View {
        Group {
            if let image = Art.shared.badge(kind.rawValue) {
                Image(nsImage: image).resizable()
            } else {
                ZStack {
                    Circle().fill(halo.opacity(0.11))
                    Circle().fill(fill).padding(10)
                    Text(glyph).font(.system(size: 26, weight: .bold)).foregroundColor(onFill)
                }
            }
        }
        .frame(width: Metrics.badge, height: Metrics.badge)
        .accessibilityHidden(true)
    }

    private var fill: Color {
        switch kind {
        case .ok: return Palette.primary
        case .err: return Palette.error
        case .offline, .paused: return Palette.tonal
        }
    }

    private var halo: Color { kind == .err ? Palette.error : (kind == .ok ? Palette.primary : Palette.muted) }
    private var onFill: Color { kind == .ok || kind == .err ? .white : Palette.muted }

    private var glyph: String {
        switch kind {
        case .ok: return "✓"
        case .err: return "!"
        case .offline: return "⌀"
        case .paused: return "❙❙"
        }
    }
}
