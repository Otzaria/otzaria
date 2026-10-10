import AssistantCore
@testable import AssistantUI
import XCTest

/// הניווט והטקסטים של הממשק על מניפסט הייחוס — בלי חלון ובלי רשת.
final class AssistantModelTests: XCTestCase {
    private static let manifestURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("fixtures/release-manifest.json")

    private func model(_ language: UILanguage = .hebrew) throws -> AssistantModel {
        let manifest = try ReleaseManifest.parse(Data(contentsOf: Self.manifestURL))
        let model = AssistantModel(
            language: language, embeddedTag: "",
            bundleURL: FileManager.default.temporaryDirectory.appendingPathComponent("A.app")
        )
        model.outputBase = FileManager.default.temporaryDirectory
        model.loaded(manifest)
        return model
    }

    func testEveryStringExistsInBothLanguages() {
        for key in StringKey.allCases {
            XCTAssertNotNil(Strings.hebrew[key], "hebrew.\(key)")
            XCTAssertNotNil(Strings.english[key], "english.\(key)")
        }
        XCTAssertEqual(Strings.hebrew.count, StringKey.allCases.count)
        XCTAssertEqual(Strings.english.count, StringKey.allCases.count)
    }

    func testPlaceholdersMatchBetweenLanguages() {
        for key in StringKey.allCases {
            let he = Strings.hebrew[key] ?? ""
            let en = Strings.english[key] ?? ""
            for marker in ["%1", "%2", "%3"] {
                XCTAssertEqual(he.contains(marker), en.contains(marker), "\(key) \(marker)")
            }
        }
    }

    /// כל משפט שהלוגיקה מציגה מתורגם, כדי שממשק באנגלית לא יציג עברית.
    func testCoreMessagesHaveEnglish() {
        let messages = [
            AssistantError.fileUnavailable, AssistantError.cannotConnect, AssistantError.cannotReadList,
            AssistantError.cannotPrepare, AssistantError.copyFailed, AssistantError.saveFailed,
            AssistantError.downloadDamaged, AssistantError.writeJoinedFailed, AssistantError.joinedDamaged,
        ]
        for message in messages {
            XCTAssertNotNil(AssistantError.english[message], message)
        }
        let titles = [
            PreparationStatus.checkingCacheTitle, PreparationStatus.verifyingPartialTitle,
            PreparationStatus.downloadingTitle, PreparationStatus.copyingTitle,
            PreparationStatus.assemblingTitle, PreparationStatus.verifyingAssemblyTitle,
        ]
        for title in titles {
            XCTAssertNotNil(PreparationStatus.englishTitles[title], title)
        }
    }

    func testLanguageDetection() {
        XCTAssertEqual(UILanguage.detect(environment: [:], preferred: ["he-IL", "en-US"]), .hebrew)
        XCTAssertEqual(UILanguage.detect(environment: [:], preferred: ["en-US", "he-IL"]), .english)
        XCTAssertEqual(UILanguage.detect(environment: [:], preferred: ["fr-FR"]), .english)
        XCTAssertEqual(UILanguage.detect(environment: ["OTZARIA_ASSISTANT_LANG": "he"], preferred: ["en"]), .hebrew)
    }

    /// המחשב הזה: macOS, חמישה שלבים, וההצעות של macOS — בסיסית מסומנת מראש.
    func testThisComputerFlow() throws {
        let model = try model()
        XCTAssertEqual(model.page, .mode)
        XCTAssertEqual(model.step?.current, 1)
        XCTAssertEqual(model.step?.total, 5)
        model.next()
        XCTAssertEqual(model.page, .presets)
        XCTAssertEqual(model.target, AssistantTarget(platform: "macos"))
        XCTAssertEqual(model.presetId, "basic")
        XCTAssertEqual(model.step?.current, 2)
        model.next()
        XCTAssertEqual(model.page, .folder)
        XCTAssertEqual(model.step?.current, 3)
        model.next()
        XCTAssertEqual(model.page, .ready)
        XCTAssertEqual(model.step?.current, 4)
        model.back()
        model.back()
        model.back()
        XCTAssertEqual(model.page, .mode)
        model.back()
        XCTAssertEqual(model.page, .welcome)
    }

    /// רשימת היעדים: כל מה שאינו macOS, בלי בחירה מראש, ו"המשך" בלי בחירה מבקש לבחור.
    func testOtherComputerList() throws {
        let model = try model()
        model.mode = .other
        model.next()
        XCTAssertEqual(model.page, .other)
        XCTAssertNil(model.otherIndex)
        XCTAssertFalse(model.otherTargets.contains { $0.platform == "macos" })
        XCTAssertEqual(model.otherTargets.first, AssistantTarget(platform: "windows", architecture: "x64"))
        XCTAssertTrue(model.otherTargets.contains(
            AssistantTarget(platform: "linux", architecture: "x64", packageFormat: "deb")
        ))
        model.next()
        XCTAssertEqual(model.page, .other)
        XCTAssertNotNil(model.dialog)
        model.dialog = nil
        model.otherIndex = 0
        model.next()
        XCTAssertEqual(model.page, .presets)
        XCTAssertEqual(model.step?.current, 3)
        XCTAssertEqual(model.step?.total, 6)
        XCTAssertEqual(model.presets.first { $0.id == "full" }?.members.first, "otzaria-windows-full")
    }

    func testOtherSummaryNamesThePlatforms() throws {
        XCTAssertEqual(try model(.english).otherSummary, "Windows, Linux or Android")
        XCTAssertEqual(try model(.hebrew).otherSummary, "Windows, Linux או Android")
    }

    func testCustomSelectionNeedsSomething() throws {
        let model = try model()
        model.next()
        model.presetId = customPresetId
        model.next()
        XCTAssertEqual(model.page, .custom)
        XCTAssertFalse(model.customChecked.isEmpty)
        model.customChecked.removeAll()
        model.next()
        XCTAssertEqual(model.page, .custom)
        XCTAssertEqual(model.dialog?.title, Strings(.hebrew)(.nothingTitle))
    }

    /// ממשק באנגלית: שם תת-התיקייה והטקסטים של רכיבי המניפסט באנגלית, כמו ב-Windows.
    func testEnglishPlanUsesEnglishNames() throws {
        let manifest = try ReleaseManifest.parse(Data(contentsOf: Self.manifestURL))
        let target = AssistantTarget(platform: "macos")
        let full = buildPresets(manifest, target).first { $0.id == "full" }!
        let plan = try PreparationPlan.make(
            manifest: manifest, selectedIds: full.members, target: target,
            english: true, subfolderName: "Otzaria setup for macOS"
        )
        XCTAssertEqual(plan.outputSubfolder, "Otzaria setup for macOS")
        XCTAssertTrue(plan.downloads.allSatisfy { !$0.caption.contains("אוצריא") }, "\(plan.downloads.map { $0.caption })")
        let hebrew = try PreparationPlan.make(manifest: manifest, selectedIds: full.members, target: target)
        XCTAssertEqual(hebrew.outputSubfolder, outputSubfolderName("macos"))
    }

    func testFailureTitleDropsTheFinalPeriod() throws {
        let model = try model(.english)
        model.error = AssistantError(AssistantError.cannotReadList, technical: "x")
        model.failure = .load
        XCTAssertEqual(model.failureTitle, "Can't read the list of Otzaria files")
        model.failure = .offline
        XCTAssertEqual(model.failureTitle, "No internet connection")
    }

    func testBidiKeepsLatinListsInReadingOrder() {
        XCTAssertEqual(bidi("מתאים ל-Windows, Linux"), "\u{200F}מתאים ל-Windows,\u{200F} Linux")
        XCTAssertEqual(bidi("For Windows, Linux"), "For Windows, Linux")
    }
}
