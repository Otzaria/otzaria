import Foundation
import XCTest
@testable import AssistantCore

/// מחברי זמננו מול expected-zmanenu.json, שמימוש הייחוס ב-Dart מפיק.
final class ZmanenuTests: XCTestCase {
    private static let fixturesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // AssistantCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // macos
        .deletingLastPathComponent() // download_assistant
        .appendingPathComponent("fixtures", isDirectory: true)

    private func data(_ name: String) throws -> Data {
        try Data(contentsOf: Self.fixturesDirectory.appendingPathComponent(name))
    }

    private func json(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data(name)) as? [String: Any])
    }

    private func release(_ name: String) throws -> [String: Any]? {
        name.isEmpty ? nil : try json(name)
    }

    private func target(_ value: Any?) throws -> AssistantTarget {
        let fields = try XCTUnwrap(value as? [String: String])
        return AssistantTarget(
            platform: fields["platform"] ?? "", architecture: fields["architecture"] ?? "",
            packageFormat: fields["packageFormat"] ?? ""
        )
    }

    private func offer(_ entry: [String: Any]) throws -> ZmanenuOffer? {
        let manifestName = try XCTUnwrap(entry["partsManifest"] as? String)
        return Zmanenu.offer(
            release: try release(try XCTUnwrap(entry["release"] as? String)),
            partsManifest: manifestName.isEmpty ? nil : try data(manifestName)
        )
    }

    func testNamesMatchTheContract() throws {
        let expected = try json("expected-zmanenu.json")
        XCTAssertEqual(expected["archive"] as? String, Zmanenu.archiveName)
        XCTAssertEqual(expected["partsManifestName"] as? String, Zmanenu.partsManifestName)
        XCTAssertEqual(expected["dropFolder"] as? String, Zmanenu.dropFolder)
    }

    func testOfferedTargets() throws {
        let expected = try json("expected-zmanenu.json")
        for entry in try XCTUnwrap(expected["offeredTargets"] as? [[String: Any]]) {
            let target = try target(entry["target"])
            XCTAssertEqual(Zmanenu.isOffered(target), entry["offered"] as? Bool, "\(target)")
        }
    }

    func testCases() throws {
        let expected = try json("expected-zmanenu.json")
        for entry in try XCTUnwrap(expected["cases"] as? [[String: Any]]) {
            let id = entry["id"] as? String ?? ""
            let releaseName = try XCTUnwrap(entry["release"] as? String)
            XCTAssertEqual(
                Zmanenu.partsManifestURL(release: try release(releaseName))?.absoluteString,
                entry["partsManifestUrl"] as? String, id
            )
            let actual = try offer(entry)
            guard let want = entry["offer"] as? [String: Any] else {
                XCTAssertNil(actual, id)
                continue
            }
            let got = try XCTUnwrap(actual, id)
            XCTAssertEqual(got.tag, want["tag"] as? String, id)
            XCTAssertEqual(got.split, want["split"] as? Bool, id)
            XCTAssertEqual(got.downloadSize, (want["downloadSize"] as? NSNumber)?.int64Value, id)
            XCTAssertEqual(got.outputFiles, want["outputFiles"] as? [String], id)
            let downloads = try XCTUnwrap(want["downloads"] as? [[String: Any]])
            XCTAssertEqual(got.downloads.count, downloads.count, id)
            for (item, file) in zip(got.downloads, downloads) {
                XCTAssertEqual(item.name, file["name"] as? String, id)
                XCTAssertEqual(item.size, (file["size"] as? NSNumber)?.int64Value, id)
                XCTAssertEqual(item.sha256, file["sha256"] as? String, id)
                XCTAssertEqual(item.url.absoluteString, file["url"] as? String, id)
                XCTAssertTrue(Endpoints.isAllowed(item.url), id)
            }
        }
    }

    /// למחשב אחר הקבצים נכתבים לצד הבחירה, וכלל תת-התיקייה חל על כולם.
    func testOtherComputerOutput() throws {
        let manifest = try ReleaseManifest.parse(data("release-manifest.json"))
        let expected = try json("expected-zmanenu.json")
        let cases = try XCTUnwrap(expected["cases"] as? [[String: Any]])
        for entry in try XCTUnwrap(expected["otherComputer"] as? [[String: Any]]) {
            let caseEntry = try XCTUnwrap(cases.first { $0["id"] as? String == entry["case"] as? String })
            let target = try target(entry["target"])
            let preset = try XCTUnwrap(buildPresets(manifest, target).first { $0.id == entry["preset"] as? String })
            let plan = try PreparationPlan.make(
                manifest: manifest, selectedIds: preset.members, target: target, zmanenu: try offer(caseEntry)
            )
            XCTAssertEqual(plan.outputFiles, entry["outputFiles"] as? [String], "\(entry)")
            XCTAssertEqual(plan.outputSubfolder, entry["outputSubfolder"] as? String, "\(entry)")
        }
    }

    /// למחשב הזה הקבצים הולכים לתיקיית האיסוף ואינם משנים את תיקיית הפלט.
    func testThisComputerKeepsTheOutputFolder() throws {
        let manifest = try ReleaseManifest.parse(data("release-manifest.json"))
        let target = AssistantTarget(platform: "macos")
        let preset = try XCTUnwrap(buildPresets(manifest, target).first { $0.id == defaultPresetId })
        let offer = try XCTUnwrap(Zmanenu.offer(release: try json("zmanenu-release-whole.json"), partsManifest: nil))
        let drop = Zmanenu.dropDirectory(home: URL(fileURLWithPath: "/Users/test"))
        let plan = try PreparationPlan.make(
            manifest: manifest, selectedIds: preset.members, target: target,
            zmanenu: offer, zmanenuDirectory: drop
        )
        XCTAssertEqual(plan.outputFiles, plannedOutputFiles(manifest, preset.members, target))
        XCTAssertTrue(plan.downloads.contains(offer.downloads[0]))
        XCTAssertEqual(drop.path, "/Users/test/Library/Application Support/otzaria/מסדים אישיים/להתקנה")
    }

    /// קובץ בלי sha256 לעולם אינו נלקח מהמטמון, וגודל 0 (לא ידוע) מקבל כל אורך.
    func testUnverifiedFileIsNeverCachedAndAcceptsAnyLength() throws {
        XCTAssertEqual(cacheStatus(
            fileSize: 10, fileModified: Date(timeIntervalSince1970: 1), markerText: "  \(Zmanenu.archiveName)\n",
            markerModified: Date(timeIntervalSince1970: 2), expectedSize: 10, expectedSha256: ""
        ), .invalid)
        XCTAssertEqual(cacheStatus(
            fileSize: nil, fileModified: nil, markerText: nil, markerModified: nil,
            expectedSize: 0, expectedSha256: ""
        ), .missing)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zmanenu-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let sink = TransferSink(url: url, expectedSize: 0, expectedSha256: "")
        try sink.begin(.writeFromStart)
        try sink.write(Data(count: 5))
        XCTAssertTrue(sink.finishAndVerify())
        XCTAssertEqual(sink.written, 5)

        let known = TransferSink(url: url, expectedSize: 4, expectedSha256: "")
        try known.begin(.writeFromStart)
        XCTAssertThrowsError(try known.write(Data(count: 5)))
        known.close()
    }

    func testPlacementWritesTheManifestLastWithoutLeftovers() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zmanenu-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        let drop = root.appendingPathComponent("drop", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let manifestData = try data("zmanenu-parts-manifest.json")
        let offer = try XCTUnwrap(Zmanenu.offer(release: nil, partsManifest: manifestData))
        for item in offer.downloads {
            try Data(count: Int(item.size)).write(to: cache.appendingPathComponent(item.name))
        }
        let placed = try placeZmanenu(offer, in: drop, sourceURL: { cache.appendingPathComponent($0.name) })
        XCTAssertEqual(placed.map { $0.lastPathComponent }, offer.outputFiles)
        XCTAssertEqual(placed.last?.lastPathComponent, Zmanenu.partsManifestName)
        XCTAssertEqual(try Data(contentsOf: drop.appendingPathComponent(Zmanenu.partsManifestName)), manifestData)
        let names = try FileManager.default.contentsOfDirectory(atPath: drop.path).sorted()
        XCTAssertEqual(names, offer.outputFiles.sorted())
    }
}
