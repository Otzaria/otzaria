import Foundation
import XCTest
@testable import AssistantCore

final class ManifestTests: XCTestCase {
    private func manifestJSON(schema: Int = 1, repository: String = "Otzaria/otzaria", sha: String? = nil,
                              extra: String = "") -> Data {
        let hash = sha ?? String(repeating: "a", count: 64)
        return """
        {"schemaVersion": \(schema), "releaseTag": "0.10.3+143", "releaseVersion": "0.10.3", \(extra)
         "components": [{"id": "x", "name": "אוצריא", "type": "future-type", "required": false,
           "futureField": {"nested": true},
           "assets": [{"kind": "single", "repository": "\(repository)", "releaseTag": "0.10.3+143",
                       "name": "a.exe", "size": 3, "sha256": "\(hash)"}]}]}
        """.data(using: .utf8)!
    }

    func testAcceptsUnknownFieldsAndTypes() throws {
        let manifest = try ReleaseManifest.parse(manifestJSON(extra: "\"newTopLevel\": 1,"))
        XCTAssertEqual(manifest.components.first?.type, "future-type")
        XCTAssertEqual(manifest.components.first?.platform, "")
    }

    func testRejectsOtherSchemaVersion() {
        XCTAssertThrowsError(try ReleaseManifest.parse(manifestJSON(schema: 2))) { error in
            XCTAssertEqual((error as? AssistantError)?.message, AssistantError.cannotReadList)
        }
    }

    func testRejectsRepositoryOutsideTheOrganization() {
        XCTAssertThrowsError(try ReleaseManifest.parse(manifestJSON(repository: "Evil/otzaria")))
        XCTAssertThrowsError(try ReleaseManifest.parse(manifestJSON(repository: "Otzaria/..")))
    }

    func testRejectsMissingOrMalformedHash() {
        XCTAssertThrowsError(try ReleaseManifest.parse(manifestJSON(sha: "")))
        XCTAssertThrowsError(try ReleaseManifest.parse(manifestJSON(sha: String(repeating: "A", count: 64))))
    }

    func testRejectsSplitWhosePartsDoNotSumToTheWhole() {
        let hash = String(repeating: "b", count: 64)
        let json = """
        {"schemaVersion": 1, "releaseTag": "t", "releaseVersion": "1", "components": [{"id": "x", "name": "n",
          "type": "library", "assets": [{"kind": "split", "repository": "Otzaria/otzaria", "releaseTag": "t",
          "name": "a.tar.zst", "size": 10, "sha256": "\(hash)",
          "parts": [{"name": "a.tar.zst.part-000", "size": 4, "sha256": "\(hash)"}]}]}]}
        """
        XCTAssertThrowsError(try ReleaseManifest.parse(json.data(using: .utf8)!))
    }
}

final class EndpointTests: XCTestCase {
    func testAssetURLKeepsThePlusOfTheTag() {
        XCTAssertEqual(
            Endpoints.assetURL(repository: "Otzaria/SeforimLibrary", tag: "0.10.3+143", name: "a.tar.zst")?.absoluteString,
            "https://github.com/Otzaria/SeforimLibrary/releases/download/0.10.3+143/a.tar.zst"
        )
    }

    func testAssetURLRejectsUnsafeParts() {
        XCTAssertNil(Endpoints.assetURL(repository: "otzaria/otzaria", tag: "1", name: "a"))
        XCTAssertNil(Endpoints.assetURL(repository: "Otzaria/a/b", tag: "1", name: "a"))
        XCTAssertNil(Endpoints.assetURL(repository: "Otzaria/otzaria", tag: "..", name: "a"))
        XCTAssertNil(Endpoints.assetURL(repository: "Otzaria/otzaria", tag: "1", name: "a/b"))
        XCTAssertNil(Endpoints.assetURL(repository: "Otzaria/otzaria", tag: "1", name: "א.exe"))
        XCTAssertNil(Endpoints.assetURL(repository: "Otzaria/otzaria", tag: "1 2", name: "a"))
    }

    func testRedirectHosts() {
        let allowed = [
            "https://github.com/Otzaria/otzaria/releases/download/0.10.3+143/a.exe",
            "https://objects.githubusercontent.com/github-production-release-asset/1?x=y",
            "https://release-assets.githubusercontent.com/github-production-release-asset/1/2?sp=r",
            "https://api.github.com/repositories/123/releases/latest",
            "https://GITHUB.com/Otzaria/otzaria/x",
        ]
        for url in allowed {
            XCTAssertTrue(Endpoints.isAllowed(URL(string: url)), url)
        }
        let blocked = [
            "http://github.com/Otzaria/otzaria/releases/download/1/a",
            "https://github.com/evil/otzaria/releases/download/1/a",
            "https://github.com/Otzaria/../evil/x",
            "https://evil.com/Otzaria/otzaria",
            "https://github.com.evil.com/Otzaria/x",
            "https://raw.githubusercontent.com/Otzaria/otzaria/main/x",
            "https://github.com:8443/Otzaria/x",
            "https://user@github.com/Otzaria/x",
            "ftp://github.com/Otzaria/x",
        ]
        for url in blocked {
            XCTAssertFalse(Endpoints.isAllowed(URL(string: url)), url)
        }
        XCTAssertFalse(Endpoints.isAllowed(nil))
    }
}

final class ReleaseTagTests: XCTestCase {
    func testVersionPartIgnoresBuildSuffix() {
        XCTAssertEqual(ReleaseTagChoice.versionPart("0.10.3+143"), "0.10.3")
        XCTAssertEqual(ReleaseTagChoice.versionPart(" v0.11.0 "), "0.11.0")
        XCTAssertEqual(ReleaseTagChoice.compare("0.10.3+143", "0.10.3+999"), 0)
        XCTAssertEqual(ReleaseTagChoice.compare("0.10.10", "0.10.9"), 1)
        XCTAssertEqual(ReleaseTagChoice.compare("0.9.99", "0.10.0"), -1)
        XCTAssertEqual(ReleaseTagChoice.compare("1.0", "1.0.0"), 0)
    }

    func testEmbeddedTagWinsUnlessLatestIsHigher() {
        XCTAssertEqual(ReleaseTagChoice.choose(embedded: "0.10.3+143", latest: "0.10.3"), "0.10.3+143")
        XCTAssertEqual(ReleaseTagChoice.choose(embedded: "0.10.3+143", latest: "0.9.99"), "0.10.3+143")
        XCTAssertEqual(ReleaseTagChoice.choose(embedded: "0.10.3+143", latest: "0.10.4"), "0.10.4")
        XCTAssertEqual(ReleaseTagChoice.choose(embedded: "0.10.3+143", latest: "0.10.4+150"), "0.10.4+150")
        XCTAssertEqual(ReleaseTagChoice.choose(embedded: "0.10.3+143", latest: nil), "0.10.3+143")
        XCTAssertEqual(ReleaseTagChoice.choose(embedded: "0.10.3+143", latest: ""), "0.10.3+143")
    }

    func testLocalBuildFallsBackToLatest() {
        XCTAssertEqual(ReleaseTagChoice.choose(embedded: "", latest: "0.10.3"), "0.10.3")
        XCTAssertNil(ReleaseTagChoice.choose(embedded: "", latest: nil))
    }

    func testUnsafeLatestTagIsIgnored() {
        XCTAssertEqual(ReleaseTagChoice.choose(embedded: "0.10.3", latest: "9.9.9/../x"), "0.10.3")
        XCTAssertNil(ReleaseTagChoice.choose(embedded: "", latest: "a b"))
    }
}

final class ResumeRulesTests: XCTestCase {
    func testRangeHeaderOnlyForAResumablePartial() {
        XCTAssertNil(ResumeRules.rangeHeader(existing: 0, size: 100))
        XCTAssertEqual(ResumeRules.rangeHeader(existing: 40, size: 100), "bytes=40-")
        XCTAssertNil(ResumeRules.rangeHeader(existing: 100, size: 100))
    }

    func testExactContentRangeResumes() {
        XCTAssertEqual(
            ResumeRules.action(requestedOffset: 40, statusCode: 206, contentRange: "bytes 40-99/100", expectedSize: 100),
            .append(from: 40)
        )
    }

    func testMismatchedContentRangeDiscards() {
        for range in ["bytes 0-99/100", "bytes 40-99/200", "bytes 40-59/100", nil] {
            XCTAssertEqual(
                ResumeRules.action(requestedOffset: 40, statusCode: 206, contentRange: range, expectedSize: 100),
                .discardPartial, range ?? "nil"
            )
        }
    }

    /// ברשת המסוננת Range מתעלם: 200 עם כל הקובץ נכתב מההתחלה, בלי בקשה שנייה.
    func testFullReplyToARangeRequestIsWrittenFromTheStart() {
        XCTAssertEqual(
            ResumeRules.action(requestedOffset: 40, statusCode: 200, contentRange: nil, expectedSize: 100),
            .writeFromStart
        )
        XCTAssertEqual(
            ResumeRules.action(requestedOffset: 0, statusCode: 200, contentRange: nil, expectedSize: 100),
            .writeFromStart
        )
    }

    func testOtherStatuses() {
        XCTAssertEqual(
            ResumeRules.action(requestedOffset: 0, statusCode: 404, contentRange: nil, expectedSize: 100),
            .fail(retryable: false)
        )
        XCTAssertEqual(
            ResumeRules.action(requestedOffset: 40, statusCode: 416, contentRange: nil, expectedSize: 100),
            .discardPartial
        )
        XCTAssertEqual(
            ResumeRules.action(requestedOffset: 40, statusCode: 503, contentRange: nil, expectedSize: 100),
            .fail(retryable: true)
        )
        XCTAssertEqual(
            ResumeRules.action(requestedOffset: 0, statusCode: 206, contentRange: "bytes 0-99/100", expectedSize: 100),
            .fail(retryable: false)
        )
    }

    func testRetryPolicy() {
        XCTAssertEqual(RetryPolicy.delay(forRetry: 0), 2)
        XCTAssertEqual(RetryPolicy.delay(forRetry: 1), 5)
        XCTAssertEqual(RetryPolicy.delay(forRetry: 2), 10)
        XCTAssertNil(RetryPolicy.delay(forRetry: 3))
        XCTAssertTrue(RetryPolicy.isNetworkError(URLError(.networkConnectionLost)))
        XCTAssertFalse(RetryPolicy.isNetworkError(URLError(.serverCertificateUntrusted)))
    }
}

final class CacheStatusTests: XCTestCase {
    private let sha = String(repeating: "c", count: 64)
    private let early = Date(timeIntervalSince1970: 1000)
    private let late = Date(timeIntervalSince1970: 2000)

    func testMarkerFormatIsSha256sum() {
        XCTAssertEqual(CacheMarker.line(sha256: sha, name: "a.exe"), "\(sha)  a.exe\n")
        XCTAssertEqual(CacheMarker.parse("\(sha)  a.exe\n"), sha)
        XCTAssertEqual(CacheMarker.parse(sha.uppercased() + " *a.exe"), sha)
        XCTAssertNil(CacheMarker.parse("nothex  a.exe"))
    }

    func testStatus() {
        let marker = CacheMarker.line(sha256: sha, name: "a")
        XCTAssertEqual(cacheStatus(fileSize: nil, fileModified: nil, markerText: marker, markerModified: late,
                                   expectedSize: 5, expectedSha256: sha), .missing)
        XCTAssertEqual(cacheStatus(fileSize: 4, fileModified: early, markerText: marker, markerModified: late,
                                   expectedSize: 5, expectedSha256: sha), .invalid)
        XCTAssertEqual(cacheStatus(fileSize: 5, fileModified: early, markerText: marker, markerModified: late,
                                   expectedSize: 5, expectedSha256: sha), .ready)
        XCTAssertEqual(cacheStatus(fileSize: 5, fileModified: late, markerText: marker, markerModified: late,
                                   expectedSize: 5, expectedSha256: sha), .ready)
        // קובץ שנכתב אחרי החותם, חותם פגום, או בלי חותם — hash אחד מהדיסק.
        XCTAssertEqual(cacheStatus(fileSize: 5, fileModified: late, markerText: marker, markerModified: early,
                                   expectedSize: 5, expectedSha256: sha), .needsHash)
        XCTAssertEqual(cacheStatus(fileSize: 5, fileModified: early, markerText: "garbage", markerModified: late,
                                   expectedSize: 5, expectedSha256: sha), .needsHash)
        // חותם תקף של hash אחר מוכיח שהתוכן שגוי — נמחק בלי hash.
        XCTAssertEqual(cacheStatus(fileSize: 5, fileModified: early, markerText: marker, markerModified: late,
                                   expectedSize: 5, expectedSha256: String(repeating: "d", count: 64)), .invalid)
        XCTAssertEqual(cacheStatus(fileSize: 5, fileModified: early, markerText: nil, markerModified: nil,
                                   expectedSize: 5, expectedSha256: sha), .needsHash)
    }
}

final class WildcardTests: XCTestCase {
    private let linuxDebX64 = AssistantTarget(platform: "linux", architecture: "x64", packageFormat: "deb")

    func testAnyMatchesEveryTarget() {
        let any = ManifestComponent(id: "a", type: "library", platform: "any", architecture: "any", packageFormat: "any")
        XCTAssertTrue(componentFitsTarget(any, linuxDebX64))
        XCTAssertTrue(componentFitsTarget(any, AssistantTarget(platform: "macos")))
        XCTAssertTrue(componentFitsTarget(ManifestComponent(id: "b", type: "library"), linuxDebX64))
        XCTAssertFalse(componentFitsTarget(
            ManifestComponent(id: "c", type: "application", platform: "linux", packageFormat: "rpm"), linuxDebX64
        ))
    }

    func testAnyIsNeverAChoice() {
        let manifest = ReleaseManifest(components: [
            ManifestComponent(id: "deb", type: "application", platform: "linux", architecture: "x64", packageFormat: "deb"),
            ManifestComponent(id: "lib", type: "library", platform: "linux", architecture: "any", packageFormat: "any"),
            ManifestComponent(id: "arm", type: "application", platform: "linux", architecture: "arm64", packageFormat: "deb"),
        ])
        XCTAssertEqual(architectureChoices(manifest, "linux"), ["x64", "arm64"])
        XCTAssertEqual(packageFormatChoices(manifest, "linux", "x64"), ["deb"])
    }
}

final class ManifestSourceTests: XCTestCase {
    /// ה-API במגבלת קצב (403/429): התג המוטבע מספיק, והמניפסט יורד מהכתובת הישירה.
    func testNoApiAnswerFallsBackToTheDirectAsset() {
        let expected = "https://github.com/Otzaria/otzaria/releases/download/0.10.3%2B143/otzaria-release-manifest.json"
        XCTAssertEqual(ManifestSource.decide(tag: "0.10.3+143", release: nil), .url(URL(string: expected)!))
        if case .url(let url) = ManifestSource.decide(tag: "0.10.3+143", release: nil) {
            XCTAssertTrue(Endpoints.isAllowed(url))
        }
        XCTAssertEqual(ManifestSource.decide(tag: "a/b", release: nil), .missing)
    }

    func testApiAssetListWins() {
        let release: [String: Any] = ["assets": [["name": "x.exe"], ["name": "otzaria-release-manifest.json"]]]
        let expected = "https://github.com/Otzaria/otzaria/releases/download/0.10.3/otzaria-release-manifest.json"
        XCTAssertEqual(ManifestSource.decide(tag: "0.10.3", release: release), .url(URL(string: expected)!))
        XCTAssertEqual(ManifestSource.decide(tag: "0.10.3", release: ["assets": [["name": "x.exe"]]]), .missing)
    }
}

final class StaleHashGateTests: XCTestCase {
    private final class Owner {}

    /// hash מהדיסק שהסתיים אחרי שהמשימה נסגרה אינו פותח את הקובץ שוב.
    func testOnlyTheCurrentOwnerContinues() {
        let transfer = Owner()
        let retry = Owner()
        XCTAssertTrue(ResumeRules.mayContinueAfterPrefixHash(engineEnded: false, currentOwner: transfer, transfer: transfer))
        XCTAssertFalse(ResumeRules.mayContinueAfterPrefixHash(engineEnded: false, currentOwner: nil, transfer: transfer))
        XCTAssertFalse(ResumeRules.mayContinueAfterPrefixHash(engineEnded: false, currentOwner: retry, transfer: transfer))
        XCTAssertFalse(ResumeRules.mayContinueAfterPrefixHash(engineEnded: true, currentOwner: transfer, transfer: transfer))
    }
}

final class FormattingTests: XCTestCase {
    func testHumanSizeMatchesTheWindowsAssistant() {
        XCTAssertEqual(humanSize(500, english: true), "1\u{00A0}KB")
        XCTAssertEqual(humanSize(5 * 1_048_576, english: true), "5\u{00A0}MB")
        XCTAssertEqual(humanSize(2_012_390_081, english: true), "1.8\u{00A0}GB")
        // בעברית אותו ערך, עטוף כדי שלא יתהפך בתוך משפט.
        XCTAssertEqual(humanSize(5 * 1_048_576), "\u{202A}5\u{00A0}MB\u{202C}")
        XCTAssertEqual(humanSpeed(1_500_000, english: true), "1.4 MB/s")
        XCTAssertEqual(humanSpeed(10_240, english: true), "10 KB/s")
    }

    func testSpeedIsAMovingAverage() {
        var meter = SpeedMeter(window: 5)
        XCTAssertNil(meter.bytesPerSecond)
        for second in 0...10 {
            meter.record(time: TimeInterval(second), bytes: Int64(second) * 1_000_000)
        }
        XCTAssertEqual(meter.bytesPerSecond ?? 0, 1_000_000, accuracy: 1)
        XCTAssertEqual(meter.secondsRemaining(30_000_000) ?? 0, 30, accuracy: 0.01)
        // אחרי עצירה הממוצע יורד תוך חלון אחד, ולא נשאר על המהירות הישנה.
        for second in 11...16 {
            meter.record(time: TimeInterval(second), bytes: 10_000_000)
        }
        XCTAssertEqual(meter.bytesPerSecond ?? -1, 0, accuracy: 1)
    }

    func testRemainingText() {
        XCTAssertEqual(humanRemaining(30), "פחות מדקה")
        XCTAssertEqual(humanRemaining(61), "דקה")
        XCTAssertEqual(humanRemaining(44 * 60 + 10), "44 דקות")
        XCTAssertEqual(humanRemaining(3600), "שעה")
        XCTAssertEqual(humanRemaining(2 * 3600 + 300), "שעתיים ו-5 דקות")
        XCTAssertEqual(humanRemaining(3 * 3600 + 3590), "4 שעות")
        XCTAssertEqual(humanRemaining(30, english: true), "less than a minute")
        XCTAssertEqual(humanRemaining(2 * 3600 + 300, english: true), "2 hours 5 minutes")
    }
}

final class LocationTests: XCTestCase {
    func testTranslocatedAppFallsBackToDocuments() {
        let fallback = URL(fileURLWithPath: "/Users/u/Documents/אוצריא-להתקנה")
        let translocated = URL(fileURLWithPath:
            "/private/var/folders/x/T/AppTranslocation/ABC/d/Otzaria-Download-Assistant.app")
        let result = OutputLocation.defaultBase(bundleURL: translocated, fallback: fallback, isWritable: { _ in true })
        XCTAssertEqual(result.url, fallback)
        XCTAssertTrue(result.usedFallback)
    }

    func testDefaultIsTheFolderContainingTheApp() {
        let app = URL(fileURLWithPath: "/Users/u/Downloads/Otzaria-Download-Assistant.app")
        let result = OutputLocation.defaultBase(
            bundleURL: app, fallback: URL(fileURLWithPath: "/tmp/f"), isWritable: { _ in true }
        )
        XCTAssertEqual(result.url.path, "/Users/u/Downloads")
        XCTAssertFalse(result.usedFallback)
        let readOnly = OutputLocation.defaultBase(
            bundleURL: app, fallback: URL(fileURLWithPath: "/tmp/f"), isWritable: { _ in false }
        )
        XCTAssertTrue(readOnly.usedFallback)
    }

    func testSubfolderNames() {
        XCTAssertEqual(outputSubfolderName("linux"), "אוצריא להתקנה ל-Linux")
        XCTAssertEqual(joinCommand(assetName: "a.tar.zst"), "cat 'a.tar.zst'.part-* > 'a.tar.zst'")
    }
}
