// swift-tools-version:5.9
// מסייע ההורדה של אוצריא ל-macOS. build_app.sh בונה ממנו את ה-.app (Universal).
import PackageDescription

let package = Package(
    name: "OtzariaDownloadAssistant",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "DownloadAssistant", targets: ["DownloadAssistant"]),
        .executable(name: "AssistantSnapshots", targets: ["AssistantSnapshots"]),
    ],
    targets: [
        // כל הלוגיקה, בלי ממשק — כך היא נבדקת ב-XCTest בלי חלון.
        .target(name: "AssistantCore"),
        // החלון והעמודים. ספרייה, כדי שגם AssistantSnapshots יצייר אותם.
        .target(
            name: "AssistantUI",
            dependencies: ["AssistantCore"]
        ),
        .executableTarget(
            name: "DownloadAssistant",
            dependencies: ["AssistantUI"]
        ),
        // מצלם כל מסך ל-PNG, בעברית ובאנגלית (.github/workflows/macos-assistant-screenshots.yml).
        .executableTarget(
            name: "AssistantSnapshots",
            dependencies: ["AssistantUI", "AssistantCore"]
        ),
        .testTarget(
            name: "AssistantCoreTests",
            dependencies: ["AssistantCore"]
        ),
        .testTarget(
            name: "AssistantUITests",
            dependencies: ["AssistantUI", "AssistantCore"]
        ),
    ],
    // בדיקות ה-concurrency המחמירות של Swift 6 היו מפילות את הבנייה על ה-runner.
    swiftLanguageVersions: [.v5]
)
