import AppKit
import AssistantCore
import AssistantUI

// מצלם כל מסך של המסייע ל-PNG, בעברית ובאנגלית, מתוך החלון האמיתי (כולל שורת הכותרת).
//   OTZARIA_ASSISTANT_ART=<art> swift run AssistantSnapshots <release-manifest.json> <out-dir> [--hero]
// הגדלים במניפסט הייחוס הם בבתים בודדים; כאן הם מוכפלים ב-MiB כדי שהמסכים ייראו כמו release אמיתי.

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: AssistantSnapshots <manifest.json> <out-dir> [--hero]\n".utf8))
    exit(2)
}
let manifestURL = URL(fileURLWithPath: arguments[1])
let outDir = URL(fileURLWithPath: arguments[2], isDirectory: true)
let withHero = arguments.contains("--hero")

func scaled(_ value: Any) -> Any {
    if var object = value as? [String: Any] {
        for (key, item) in object {
            if key == "size" || key == "downloadSize", let number = item as? NSNumber {
                object[key] = NSNumber(value: number.int64Value * 1_048_576)
            } else {
                object[key] = scaled(item)
            }
        }
        return object
    }
    if let array = value as? [Any] { return array.map(scaled) }
    return value
}

func loadManifest() throws -> ReleaseManifest {
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
    return try ReleaseManifest.parse(JSONSerialization.data(withJSONObject: scaled(json)))
}

func pump(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

/// מסגרת החלון כולה (רמזורים, כותרת ותוכן) בקנה מידה נתון, דרך cacheDisplay.
func capture(_ window: NSWindow, scale: CGFloat) -> Data? {
    guard let frameView = window.contentView?.superview else { return nil }
    let bounds = frameView.bounds
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = bounds.size
    frameView.cacheDisplay(in: bounds, to: rep)
    return rep.representation(using: .png, properties: [:])
}

func render(_ model: AssistantModel, to file: URL, scale: CGFloat, settle: TimeInterval) throws {
    let controller = AssistantWindowController(model: model)
    let window = controller.window
    window.setFrameOrigin(NSPoint(x: 60, y: 60))
    window.orderFront(nil)
    pump(settle)
    guard let png = capture(window, scale: scale) else {
        throw NSError(domain: "AssistantSnapshots", code: 1, userInfo: [NSLocalizedDescriptionKey: "capture failed: \(file.lastPathComponent)"])
    }
    try png.write(to: file)
    window.orderOut(nil)
    withExtendedLifetime(controller) {}
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.appearance = NSAppearance(named: .aqua)

do {
    let manifest = try loadManifest()
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    for language in [UILanguage.hebrew, UILanguage.english] {
        let scenarios = SnapshotScenarios.all(language: language, manifest: manifest, outputBase: home)
        for (index, scenario) in scenarios.enumerated() {
            let file = outDir.appendingPathComponent(String(format: "%@_%02d_%@.png", language.rawValue, index + 1, scenario.name))
            try render(scenario.model, to: file, scale: 2, settle: 0.4)
            print("wrote \(file.lastPathComponent)")
        }
        if withHero {
            let heroDir = outDir.appendingPathComponent("hero_\(language.rawValue)", isDirectory: true)
            try FileManager.default.createDirectory(at: heroDir, withIntermediateDirectories: true)
            for (index, time) in SnapshotScenarios.heroTimes().enumerated() {
                let file = heroDir.appendingPathComponent(String(format: "frame_%03d_%04d.png", index, Int(time)))
                try render(SnapshotScenarios.hero(language: language, time: time), to: file, scale: 1, settle: 0.15)
            }
            print("wrote hero frames for \(language.rawValue)")
        }
    }
} catch {
    FileHandle.standardError.write(Data("AssistantSnapshots: \(error)\n".utf8))
    exit(1)
}
exit(0)
