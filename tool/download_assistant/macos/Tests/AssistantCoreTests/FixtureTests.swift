import Foundation
import XCTest
@testable import AssistantCore

/// אותם קובצי ייחוס שמימוש הייחוס ב-Dart מפיק (generate_fixtures.dart): המסייע חייב
/// להציג ולהפיק בדיוק את מה שכתוב ב-expected-selections.json.
final class FixtureTests: XCTestCase {
    private static let fixturesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // AssistantCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // macos
        .deletingLastPathComponent() // download_assistant
        .appendingPathComponent("fixtures", isDirectory: true)

    /// העתק של kOsReleaseSamples ב-generate_fixtures.dart; הבדיקה נכשלת אם המפתחות נפרדים.
    private static let osReleaseSamples: [String: String?] = [
        "ubuntu": "NAME=\"Ubuntu\"\nID=ubuntu\nID_LIKE=debian\nVERSION_ID=\"24.04\"\n",
        "linuxmint": "ID=linuxmint\nID_LIKE=\"ubuntu debian\"\n",
        "fedora": "NAME=\"Fedora Linux\"\nID=fedora\nVERSION_ID=40\n",
        "opensuse-tumbleweed": "ID=\"opensuse-tumbleweed\"\nID_LIKE=\"opensuse suse\"\n",
        "arch": "NAME=\"Arch Linux\"\nID=arch\n",
        "not-linux": nil,
    ]

    private var manifest: ReleaseManifest!
    private var expected: [String: Any]!

    override func setUpWithError() throws {
        let loaded = try Self.load("release-manifest.json", "expected-selections.json")
        manifest = loaded.manifest
        expected = loaded.expected
    }

    private static func load(_ manifestName: String, _ expectedName: String) throws
        -> (manifest: ReleaseManifest, expected: [String: Any]) {
        let manifestData = try Data(contentsOf: fixturesDirectory.appendingPathComponent(manifestName))
        let expectedData = try Data(contentsOf: fixturesDirectory.appendingPathComponent(expectedName))
        let manifest = try ReleaseManifest.parse(manifestData)
        let expected = try XCTUnwrap(JSONSerialization.jsonObject(with: expectedData) as? [String: Any])
        return (manifest, expected)
    }

    func testPlatformChoices() {
        XCTAssertEqual(platformChoices(manifest), expected["platformChoices"] as? [String])
    }

    func testArchitectureChoices() throws {
        let table = try XCTUnwrap(expected["architectureChoices"] as? [String: [String]])
        XCTAssertEqual(Set(table.keys), Set(assistantPlatforms))
        for (platform, choices) in table {
            XCTAssertEqual(architectureChoices(manifest, platform), choices, platform)
        }
    }

    func testPackageFormatChoices() throws {
        let table = try XCTUnwrap(expected["packageFormatChoices"] as? [String: [String]])
        XCTAssertFalse(table.isEmpty)
        for (key, choices) in table {
            let architecture = String(key.dropFirst("linux/".count))
            XCTAssertEqual(packageFormatChoices(manifest, "linux", architecture), choices, key)
        }
    }

    func testDefaultPackageFormat() throws {
        let table = try XCTUnwrap(expected["defaultPackageFormat"] as? [String: String])
        XCTAssertEqual(Set(table.keys), Set(Self.osReleaseSamples.keys))
        let choices = packageFormatChoices(manifest, "linux", "x64")
        for (key, format) in table {
            let sample = Self.osReleaseSamples[key] ?? nil
            XCTAssertEqual(defaultPackageFormat(sample, choices), format, key)
        }
    }

    func testEveryTarget() throws {
        let targets = try XCTUnwrap(expected["targets"] as? [[String: Any]])
        XCTAssertEqual(targets.count, 10)
        try checkTargets(manifest, targets)
    }

    /// מתקין ה-FULL הגיע ל-4 GiB ואינו רץ: "מלאה" עוברת למתקין הרגיל וחלקי הספרייה.
    func testLargeFullVariant() throws {
        let large = try Self.load("release-manifest-large-full.json", "expected-selections-large-full.json")
        let targets = try XCTUnwrap(large.expected["targets"] as? [[String: Any]])
        XCTAssertEqual(targets.count, 2)
        try checkTargets(large.manifest, targets)
    }

    /// אינדקס שנבחר לבדו מגיע עם הספרייה ועם המתקין שקורא את שניהם, ב-x64 וב-ARM64.
    func testLibraryBringsItsInstaller() throws {
        let x64 = AssistantTarget(platform: "windows", architecture: "x64")
        XCTAssertEqual(
            withDependencies(manifest, ["library-index"], x64),
            ["otzaria-windows-x64", "library-full", "library-index"]
        )
        let arm64 = AssistantTarget(platform: "windows", architecture: "arm64")
        XCTAssertEqual(
            withDependencies(manifest, ["library-index"], arm64),
            ["otzaria-windows-arm64", "library-full", "library-index"]
        )
        let library = try XCTUnwrap(manifest.components.first { $0.id == "library-full" })
        XCTAssertFalse(componentIsOffered(
            manifest, library, AssistantTarget(platform: "linux", architecture: "x64", packageFormat: "deb")))
    }

    /// במניפסט ישן, "full-indexed" מופיעה כשחבילה מתקינה ספרייה.
    func testFullIndexedPresets() throws {
        let legacy = ReleaseManifest(
            schemaVersion: manifest.schemaVersion, releaseTag: manifest.releaseTag,
            releaseVersion: manifest.releaseVersion, components: [
                ManifestComponent(id: "otzaria-windows-full-indexed", type: "application-bundle",
                                  platform: "windows", architecture: "x64", downloadSize: 100),
                ManifestComponent(id: "library-full-indexed", type: "library", platform: "any",
                                  installedBy: ["otzaria-windows-full-indexed"], downloadSize: 100),
            ] + manifest.components)
        let presets = buildPresets(legacy, AssistantTarget(platform: "windows", architecture: "x64"))
        XCTAssertEqual(presets.map { $0.id }, ["basic", "full-indexed", "full"])
        XCTAssertEqual(buildPresets(manifest, AssistantTarget(platform: "windows", architecture: "x64"))
            .map { $0.id }, ["basic", "full"])
        XCTAssertEqual(presets.first?.id, defaultPresetId)
        let semantic = ["semantic-model-windows", "semantic-vectors-windows"]
        XCTAssertEqual(
            try XCTUnwrap(presets.first { $0.id == "full-indexed" }).members,
            ["otzaria-windows-full-indexed", "library-full-indexed"] + semantic
        )
        XCTAssertEqual(try XCTUnwrap(presets.first { $0.id == "full" }).members, ["otzaria-windows-full"] + semantic)
        for target in [AssistantTarget(platform: "macos"),
                       AssistantTarget(platform: "windows", architecture: "arm64")] {
            XCTAssertEqual(buildPresets(manifest, target).map { $0.id }, ["basic", "full"], target.platform)
        }
        XCTAssertEqual(
            try XCTUnwrap(buildPresets(manifest, AssistantTarget(platform: "android"))
                .first { $0.id == "full-indexed" }).members,
            ["otzaria-android", "library-full", "library-index"]
        )
    }

    /// המסומנת מראש: "basic", אחריה "full" (לא "full-indexed" הגדולה), אחרת הראשונה.
    func testDefaultPresetFallsBackToFull() {
        let portable = buildPresets(
            manifest, AssistantTarget(platform: "linux", architecture: "x64", packageFormat: portablePackageFormat)
        )
        XCTAssertEqual(defaultPresetIdFor(portable), "full")
        func only(_ ids: [String]) -> [AssistantPreset] {
            ids.map { AssistantPreset(id: $0, caption: "", description: "", members: []) }
        }
        XCTAssertEqual(defaultPresetIdFor(only(["full-indexed", "full"])), "full")
        XCTAssertEqual(defaultPresetIdFor(only(["full-indexed", "update"])), "full-indexed")
        XCTAssertNil(defaultPresetIdFor([]))
    }

    /// סדר ההצגה, והחבילה המאונדקסת היא הגדולה בסך הכול (עם הספרייה), לא לפי גודלה לבדה.
    func testDisplayOrderAndIndexedBundleChoice() {
        let x64 = AssistantTarget(platform: "windows", architecture: "x64")
        let synthetic = ReleaseManifest(components: [
            ManifestComponent(id: "app", type: "application", platform: "windows"),
            ManifestComponent(id: "runtime", type: "dependency", required: true, platform: "windows"),
            ManifestComponent(id: "full", type: "application-bundle", platform: "windows", downloadSize: 9),
            ManifestComponent(id: "indexed", type: "application-bundle", platform: "windows", downloadSize: 1),
            ManifestComponent(id: "lib", type: "library", platform: "windows", installedBy: ["indexed"]),
        ])
        let presets = buildPresets(synthetic, x64)
        XCTAssertEqual(presets.map { $0.id }, presetDisplayOrder)
        XCTAssertEqual(presets.map { $0.members }, [["app", "runtime"], ["indexed", "lib"], ["full"], ["app"]])

        let twoIndexed = ReleaseManifest(components: [
            ManifestComponent(id: "idx-a", type: "application-bundle", downloadSize: 10),
            ManifestComponent(id: "lib-a", type: "library", installedBy: ["idx-a"], downloadSize: 1),
            ManifestComponent(id: "idx-b", type: "application-bundle", downloadSize: 5),
            ManifestComponent(id: "lib-b", type: "library", installedBy: ["idx-b"], downloadSize: 50),
        ])
        XCTAssertEqual(buildPresets(twoIndexed, x64).map { $0.members }, [["idx-b", "lib-b"], ["idx-a", "lib-a"]])
    }

    private func checkTargets(_ manifest: ReleaseManifest, _ targets: [[String: Any]]) throws {
        for entry in targets {
            let raw = try XCTUnwrap(entry["target"] as? [String: String])
            let target = AssistantTarget(
                platform: raw["platform"] ?? "",
                architecture: raw["architecture"] ?? "",
                packageFormat: raw["packageFormat"] ?? ""
            )
            let label = "\(target.platform)/\(target.architecture)/\(target.packageFormat)"

            XCTAssertEqual(
                manifest.components.filter { componentIsOffered(manifest, $0, target) }.map { $0.id },
                entry["offeredComponents"] as? [String], label
            )

            let expectedCustom = try XCTUnwrap(entry["customChoices"] as? [[String: Any]])
            let custom = customChoices(manifest, target)
            XCTAssertEqual(custom.map { $0.component.id }, expectedCustom.map { $0["id"] as? String ?? "" }, label)
            for (choice, want) in zip(custom, expectedCustom) {
                XCTAssertEqual(customChoiceSize(manifest, choice.component, target), (want["downloadSize"] as? NSNumber)?.int64Value, label)
                XCTAssertEqual(choice.locked, want["locked"] as? Bool, label)
                XCTAssertEqual(choice.group, want["group"] as? String, label)
            }

            let expectedPresets = try XCTUnwrap(entry["presets"] as? [[String: Any]])
            let presets = buildPresets(manifest, target)
            XCTAssertEqual(presets.map { $0.id }, expectedPresets.map { $0["id"] as? String ?? "" }, label)
            for (preset, want) in zip(presets, expectedPresets) {
                XCTAssertEqual(preset.members, want["members"] as? [String], "\(label) \(preset.id)")
                let files = plannedOutputFiles(manifest, preset.members, target)
                XCTAssertEqual(files, want["outputFiles"] as? [String], "\(label) \(preset.id)")
                XCTAssertEqual(
                    plannedOutputSubfolder(files, target.platform),
                    want["outputSubfolder"] as? String, "\(label) \(preset.id)"
                )
                XCTAssertEqual(
                    plannedOutputNotes(manifest, preset.members),
                    want["outputNotes"] as? [String], "\(label) \(preset.id)"
                )

                // התוכנית שהמסייע מבצע בפועל מפיקה בדיוק את אותם קבצים.
                let plan = try PreparationPlan.make(manifest: manifest, selectedIds: preset.members, target: target)
                XCTAssertEqual(plan.outputFiles, files, "\(label) \(preset.id)")
                XCTAssertEqual(plan.actions.map { $0.outputPath }, files, "\(label) \(preset.id)")
                XCTAssertEqual(plan.outputNotes, want["outputNotes"] as? [String])
                XCTAssertEqual(plan.outputSubfolder, want["outputSubfolder"] as? String)
            }
        }
    }

    func testAssistantsAreNeverComponents() {
        let names = manifest.components.flatMap { $0.assets.map { $0.name } }
        XCTAssertFalse(names.contains { $0.hasPrefix("Otzaria-Download-Assistant") })
        XCTAssertFalse(names.contains("otzaria-macos.zip"))
    }

    func testFixtureTagIsTheBuildTag() {
        XCTAssertEqual(manifest.releaseTag, "0.10.3+143")
        let asset = manifest.components[0].assets[0]
        XCTAssertEqual(
            Endpoints.assetURL(repository: asset.repository, tag: asset.releaseTag, name: asset.name)?.absoluteString,
            "https://github.com/Otzaria/otzaria/releases/download/0.10.3+143/app-release.apk"
        )
    }

    func testUnsafeOutputFolderIsRejected() {
        XCTAssertTrue(isSafeOutputFolder("semantic-import/vectors"))
        for bad in ["", "../x", "/abs", "a//b", "a/..", "a/...", "a+b"] {
            XCTAssertFalse(isSafeOutputFolder(bad), bad)
        }
    }
}
