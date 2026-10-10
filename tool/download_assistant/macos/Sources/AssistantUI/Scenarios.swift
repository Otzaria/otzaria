import AssistantCore
import Foundation

/// מצב אחד של המסייע לצילום מסך (AssistantSnapshots), בלי רשת ובלי הורדה.
public struct SnapshotScenario {
    public let name: String
    public let model: AssistantModel
}

/// כל מסך שהמסייע מציג, בנוי דרך הניווט האמיתי של המודל על מניפסט קבוע.
public enum SnapshotScenarios {
    public static func all(
        language: UILanguage, manifest: ReleaseManifest, outputBase: URL
    ) -> [SnapshotScenario] {
        var list: [SnapshotScenario] = []
        func add(_ name: String, _ build: (AssistantModel) -> Void) {
            let model = AssistantModel(language: language, embeddedTag: "", bundleURL: outputBase.appendingPathComponent("A.app"))
            model.outputBase = outputBase
            model.outputFellBack = false
            build(model)
            list.append(SnapshotScenario(name: name, model: model))
        }
        let s = Strings(language)
        let windows = AssistantTarget(platform: "windows", architecture: "x64")

        add("welcome") { $0.heroPlayed = true }
        add("connecting") { $0.page = .connecting }
        add("mode") { $0.loaded(manifest) }
        add("other") { model in
            model.loaded(manifest)
            model.mode = .other
            model.next()
        }
        add("presets") { model in
            model.loaded(manifest)
            model.next()
        }
        add("presets_windows") { model in
            toOther(model, manifest, windows)
            model.next()
        }
        add("custom") { model in
            model.loaded(manifest)
            model.next()
            model.presetId = customPresetId
            model.next()
        }
        add("custom_windows") { model in
            toOther(model, manifest, windows)
            model.next()
            model.presetId = customPresetId
            model.next()
        }
        add("folder") { model in
            model.loaded(manifest)
            model.next()
            model.next()
        }
        add("folder_fallback") { model in
            model.loaded(manifest)
            model.next()
            model.next()
            model.outputFellBack = true
        }
        add("ready") { model in
            model.loaded(manifest)
            model.next()
            model.next()
            model.next()
        }
        add("downloading") { model in
            model.loaded(manifest)
            model.page = .working
            let name = manifest.component(withId: "otzaria-macos-full")?.displayName(english: s.english) ?? ""
            model.status = PreparationStatus(
                phase: .downloading, title: PreparationStatus.downloadingTitle, detail: name,
                doneBytes: 1_288_490_188, totalBytes: 3_758_096_384,
                bytesPerSecond: 7_654_604, secondsRemaining: 44 * 60
            )
        }
        add("joining") { model in
            model.loaded(manifest)
            model.page = .working
            let name = manifest.component(withId: "otzaria-macos-full")?.displayName(english: s.english) ?? ""
            model.status = PreparationStatus(
                phase: .assembling, title: PreparationStatus.assemblingTitle, detail: name,
                doneBytes: 1_073_741_824, totalBytes: 1_986_422_374
            )
        }
        add("finished_this") { model in
            model.loaded(manifest)
            model.page = .finished
            model.result = PreparationResult(
                outputDirectory: outputBase,
                producedFiles: [outputBase.appendingPathComponent("otzaria-macos.dmg")],
                revealTarget: outputBase.appendingPathComponent("otzaria-macos.dmg"),
                keptSplitAssets: []
            )
        }
        add("finished_other") { model in
            toOther(model, manifest, windows)
            model.page = .finished
            let folder = outputBase.appendingPathComponent(
                s.english ? "Otzaria setup for Windows" : outputSubfolderName("windows")
            )
            let names = ["otzaria-0.10.3-windows.exe", "otzaria-0.10.3-library.tar.zst.part-000",
                         "otzaria-0.10.3-library.tar.zst.part-001"]
            let notes = plannedOutputNotes(manifest, ["library-full"], english: s.english)
            model.result = PreparationResult(
                outputDirectory: folder,
                producedFiles: names.map { folder.appendingPathComponent($0) },
                revealTarget: folder,
                keptSplitAssets: [],
                outputNotes: notes
            )
        }
        add("finished_linux_parts") { model in
            toOther(model, manifest, AssistantTarget(platform: "linux", architecture: "x64", packageFormat: "deb"))
            model.page = .finished
            let folder = outputBase.appendingPathComponent(
                s.english ? "Otzaria setup for Linux" : outputSubfolderName("linux")
            )
            let names = ["otzaria-linux-full.tar.zst.part-000", "otzaria-linux-full.tar.zst.part-001"]
            model.result = PreparationResult(
                outputDirectory: folder,
                producedFiles: names.map { folder.appendingPathComponent($0) },
                revealTarget: folder,
                keptSplitAssets: ["otzaria-linux-full.tar.zst"]
            )
        }
        add("error_offline") { model in
            model.page = .failure
            model.failure = .offline
            model.error = AssistantError(
                AssistantError.cannotConnect,
                technical: "https://api.github.com/repos/Otzaria/otzaria/releases/latest: The Internet connection appears to be offline.",
                offline: true
            )
        }
        add("error_list") { model in
            model.page = .failure
            model.failure = .load
            model.error = AssistantError(AssistantError.cannotReadList, technical: "unsupported schemaVersion 2")
        }
        add("error_file") { model in
            model.loaded(manifest)
            model.page = .failure
            model.failure = .run
            model.error = AssistantError(
                AssistantError.fileUnavailable,
                technical: "otzaria-macos-full.tar.zst: HTTP 404 Not Found"
            )
            model.showTechnical = true
        }
        add("stopped") { model in
            model.loaded(manifest)
            model.page = .failure
            model.failure = .stopped
        }
        add("dialog_stop") { model in
            model.loaded(manifest)
            model.page = .working
            model.status = PreparationStatus(
                phase: .downloading, title: PreparationStatus.downloadingTitle,
                detail: manifest.component(withId: "otzaria-macos")?.displayName(english: s.english) ?? "",
                doneBytes: 40_000_000, totalBytes: 90_177_536, bytesPerSecond: 5_000_000, secondsRemaining: 10
            )
            model.requestStop()
        }
        add("dialog_exit") { model in
            model.loaded(manifest)
            model.page = .working
            model.status = PreparationStatus(
                phase: .downloading, title: PreparationStatus.downloadingTitle,
                detail: manifest.component(withId: "otzaria-macos")?.displayName(english: s.english) ?? "",
                doneBytes: 40_000_000, totalBytes: 90_177_536, bytesPerSecond: 5_000_000, secondsRemaining: 10
            )
            _ = model.requestClose()
        }
        add("dialog_no_target") { model in
            model.loaded(manifest)
            model.mode = .other
            model.next()
            model.next()
        }
        add("dialog_space") { model in
            model.loaded(manifest)
            model.next()
            model.next()
            model.next()
            model.ask(
                title: s(.spaceTitle), text: s(.spaceText, humanSize(128_849_018_880, english: s.english)),
                confirm: s(.spaceYes), keep: s(.cancel), destructive: false
            ) {}
        }
        return list
    }

    /// "סוג מחשב אחר" ושורת היעד שנבחרה, עד עמוד ההצעות.
    private static func toOther(_ model: AssistantModel, _ manifest: ReleaseManifest, _ target: AssistantTarget) {
        model.loaded(manifest)
        model.mode = .other
        model.next()
        model.otherIndex = model.otherTargets.firstIndex(of: target)
    }

    /// רגעים בפתיחה (מילישניות) לצילום רצף שממנו מרכיבים GIF.
    public static func heroTimes() -> [Double] {
        stride(from: 0.0, through: WelcomePage.endMs, by: 42).map { $0 } + [WelcomePage.endMs]
    }

    public static func hero(language: UILanguage, time: Double) -> AssistantModel {
        let model = AssistantModel(language: language, embeddedTag: "", bundleURL: URL(fileURLWithPath: "/tmp/A.app"))
        model.heroPreviewTime = time
        return model
    }
}
