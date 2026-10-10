import AppKit
import AssistantCore
import Foundation

public enum AssistantPage: Equatable {
    case welcome
    case connecting
    case mode
    case other
    case presets
    case custom
    case folder
    case ready
    case working
    case finished
    case failure
}

public enum FailureKind: Equatable {
    /// הרשימה לא נטענה (מניפסט חסר, פגום או שאינו זמין).
    case load
    /// אף בקשה לא הגיעה לשרת.
    case offline
    /// ההורדה, ההרכבה או ההעתקה נכשלו.
    case run
    /// המשתמש עצר — מצב רגוע, לא תקלה.
    case stopped
}

public enum TargetMode: Equatable {
    case thisComputer
    case other
}

public struct DialogButton {
    public enum Style { case filled, text, danger }

    let title: String
    let style: Style
    let isDefault: Bool
    let isCancel: Bool
    let action: () -> Void
}

/// שאלה או הודעה בחלון מעוצב בתוך המסייע (כמו UiAsk/UiTell ב-Windows), לא NSAlert.
public struct DialogItem: Identifiable {
    public let id = UUID()
    let title: String
    let text: String
    /// בסדר הקריאה; האחרון בקצה הנגרר.
    let buttons: [DialogButton]
}

let customPresetId = "custom"

/// מכונת המצבים של המסייע. כל כלל בחירה נמצא ב-AssistantCore; כאן רק הניווט והטקסט.
public final class AssistantModel: ObservableObject {
    public let strings: Strings
    let embeddedTag: String

    @Published public internal(set) var page: AssistantPage = .welcome
    @Published var dialog: DialogItem?
    @Published var failure: FailureKind = .load
    @Published var error: AssistantError?
    @Published var showTechnical = false

    @Published var mode: TargetMode = .thisComputer
    @Published var otherTargets: [AssistantTarget] = []
    @Published var otherIndex: Int?
    @Published var presets: [AssistantPreset] = []
    @Published var presetId = ""
    @Published var customChecked = Set<String>()

    @Published var outputBase: URL
    @Published var outputFellBack = false

    @Published var status: PreparationStatus?
    @Published var result: PreparationResult?
    @Published var revealWhenDone = true

    /// הפתיחה כבר הוצגה (או דולגה) — חזרה למסך הפתיחה אינה מנגנת אותה שוב.
    @Published var heroPlayed = false
    /// צילומי מסך בלבד: רגע קבוע בפתיחה במקום שעון.
    var heroPreviewTime: Double?

    var manifest: ReleaseManifest?
    var history: [AssistantPage] = []
    /// היציאה אושרה (או שאין מה לאשר) — Cmd-Q שבא אחריה אינו שואל שוב.
    private var quitConfirmed = false
    private var loader: ReleaseLoader?
    private var loadGeneration = 0
    private var runner: PreparationRunner?
    private var lastPlan: PreparationPlan?
    private var failedWhileLoading = true

    public init(language: UILanguage, embeddedTag: String, bundleURL: URL = Bundle.main.bundleURL) {
        strings = Strings(language)
        self.embeddedTag = embeddedTag
        let location = OutputLocation.defaultBase(
            bundleURL: bundleURL, fallback: OutputLocation.fallbackBase(english: language.isEnglish)
        )
        outputBase = location.url
        outputFellBack = location.usedFallback
    }

    var english: Bool { strings.english }

    // MARK: - יעד

    var target: AssistantTarget {
        if mode == .thisComputer || otherIndex == nil {
            return AssistantTarget(platform: "macos")
        }
        return otherTargets[otherIndex!]
    }

    var releaseVersionLabel: String {
        guard let version = manifest?.releaseVersion, !version.isEmpty else { return "" }
        return strings(.otzariaVersion, ltrUnit(version, english: english))
    }

    func platformName(_ platform: String) -> String {
        platformDisplayNames[platform] ?? platform
    }

    /// המעבד נזכר רק כשהוא ARM: Intel ו-AMD הם כמעט כל המחשבים.
    func targetTitle(_ target: AssistantTarget) -> String {
        let name = platformName(target.platform)
        return target.architecture == "arm64" ? strings(.targetArm, name) : name
    }

    func targetHint(_ target: AssistantTarget) -> String {
        if !target.packageFormat.isEmpty { return formatName(target.packageFormat) }
        switch (target.platform, target.architecture) {
        case ("macos", _): return strings(.hintMac)
        case ("android", _): return strings(.hintAndroid)
        case (_, "arm64"): return strings(.hintArm)
        case (_, "x64"): return strings(.hintX64)
        default: return ""
        }
    }

    func formatName(_ format: String) -> String {
        switch format {
        case "deb": return strings(.formatDeb)
        case "rpm": return strings(.formatRpm)
        case portablePackageFormat: return strings(.formatPortable)
        default: return format
        }
    }

    /// "Windows, Linux או Android" — מתוך הרשימה עצמה.
    var otherSummary: String {
        var names: [String] = []
        for target in otherTargets where !names.contains(platformName(target.platform)) {
            names.append(platformName(target.platform))
        }
        guard let last = names.popLast() else { return "" }
        return names.isEmpty ? last : strings(.listOr, names.joined(separator: ", "), last)
    }

    /// כל יעד שהמניפסט מציע בו משהו, חוץ מהמחשב הזה, בסדר החוזה (FillOtherPage ב-Windows).
    static func computeOtherTargets(_ manifest: ReleaseManifest) -> [AssistantTarget] {
        var targets: [AssistantTarget] = []
        for platform in platformChoices(manifest) where platform != "macos" {
            let architectures = architectureChoices(manifest, platform)
            for architecture in architectures.isEmpty ? [""] : architectures {
                let formats = packageFormatChoices(manifest, platform, architecture)
                for format in formats.isEmpty ? [""] : formats {
                    let target = AssistantTarget(platform: platform, architecture: architecture, packageFormat: format)
                    if manifest.components.contains(where: { componentIsOffered(manifest, $0, target) }) {
                        targets.append(target)
                    }
                }
            }
        }
        return targets
    }

    // MARK: - שלבים

    /// (שלב, מתוך) כמו UiStepOf ב-Windows; nil בעמודים שאין בהם נקודות.
    var step: (current: Int, total: Int)? {
        let total = mode == .other ? 6 : 5
        switch page {
        case .mode: return (1, total)
        case .other: return (2, total)
        case .presets, .custom: return (mode == .other ? 3 : 2, total)
        case .folder: return (total - 2, total)
        case .ready: return (total - 1, total)
        case .working: return (total, total)
        default: return nil
        }
    }

    var canGoBack: Bool {
        !history.isEmpty && [.mode, .other, .presets, .custom, .folder, .ready].contains(page)
    }

    // MARK: - טעינה

    /// "בואו נתחיל". התג ננעל אחרי טעינה שהצליחה, ולכן אין טעינה שנייה.
    func begin() {
        heroPlayed = true
        if manifest != nil {
            history = [.welcome]
            page = .mode
            return
        }
        load()
    }

    private func load() {
        loadGeneration += 1
        let generation = loadGeneration
        page = .connecting
        let loader = ReleaseLoader()
        self.loader = loader
        loader.load(embeddedTag: embeddedTag) { [weak self] result in
            guard let self = self, generation == self.loadGeneration else { return }
            self.loader = nil
            switch result {
            case .failure(let error):
                self.failedWhileLoading = true
                self.showFailure(error.offline ? .offline : .load, error)
            case .success(let release):
                self.loaded(release.manifest)
            }
        }
    }

    func loaded(_ manifest: ReleaseManifest) {
        self.manifest = manifest
        otherTargets = Self.computeOtherTargets(manifest)
        history = [.welcome]
        page = .mode
    }

    /// ביטול החיבור מחזיר למסך הפתיחה; תשובה מאוחרת של הטעינה נזרקת.
    func requestStopConnecting() {
        ask(
            title: strings(.connectStopTitle), text: strings(.connectStopText),
            confirm: strings(.connectStopYes), keep: strings(.connectStopNo), destructive: false
        ) { [weak self] in
            guard let self = self, self.page == .connecting else { return }
            self.loadGeneration += 1
            self.loader = nil
            self.page = .welcome
        }
    }

    // MARK: - ניווט

    func next() {
        guard let manifest = manifest else { return }
        switch page {
        case .mode:
            if mode == .thisComputer {
                goToPresets(manifest)
            } else {
                go(.other)
            }
        case .other:
            guard otherIndex != nil else {
                tell(title: strings(.noTargetTitle), text: strings(.noTargetText))
                return
            }
            goToPresets(manifest)
        case .presets:
            if presetId == customPresetId {
                if customChecked.isEmpty { customChecked = defaultCustomChecked() }
                go(.custom)
            } else {
                go(.folder)
            }
        case .custom:
            let choices = customChoices
            customChecked.formIntersection(Set(choices.map { $0.component.id }))
            customChecked.formUnion(choices.filter { $0.locked }.map { $0.component.id })
            guard !customChecked.isEmpty else {
                tell(title: strings(.nothingTitle), text: strings(.nothingText))
                return
            }
            go(.folder)
        case .folder:
            confirmFolder()
        case .ready:
            prepareAndStart()
        default:
            break
        }
    }

    func back() {
        guard canGoBack, let previous = history.popLast() else { return }
        page = previous
    }

    private func go(_ next: AssistantPage) {
        history.append(page)
        page = next
    }

    private func goToPresets(_ manifest: ReleaseManifest) {
        let target = self.target
        let built = buildPresets(manifest, target)
        if built != presets { customChecked.removeAll() }
        presets = built
        if presetId != customPresetId && !presets.contains(where: { $0.id == presetId }) {
            presetId = defaultPresetIdFor(presets) ?? customPresetId
        }
        go(.presets)
    }

    // MARK: - הצעות ובחירה אישית

    func presetTitle(_ id: String) -> String {
        switch id {
        case "full-indexed": return strings(.presetFullIndexed)
        case "full": return strings(.presetFull)
        case "basic": return strings(.presetBasic)
        case "update": return strings(.presetUpdate)
        default: return strings(.presetCustom)
        }
    }

    func presetDescription(_ id: String) -> String {
        switch id {
        case "full-indexed": return strings(.presetFullIndexedDesc)
        case "full": return strings(.presetFullDesc)
        case "basic": return strings(.presetBasicDesc)
        case "update": return strings(.presetUpdateDesc)
        default: return strings(.presetCustomDesc)
        }
    }

    /// `ico_preset_<מזהה>` עם קו תחתון במקום מקף, כמו UiOptionIcon.
    func presetIcon(_ id: String) -> String {
        "preset_" + id.replacingOccurrences(of: "-", with: "_")
    }

    var customChoices: [CustomChoice] {
        guard let manifest = manifest else { return [] }
        return AssistantCore.customChoices(manifest, target)
    }

    func customChoiceSize(_ component: ManifestComponent) -> Int64 {
        guard let manifest = manifest else { return component.downloadSize }
        return AssistantCore.customChoiceSize(manifest, component, target)
    }

    /// הנעולים, הנדרשים, ובקבוצת הרדיו — מה שסומן בהצעה שקדמה, ובלעדיה המתקין.
    func defaultCustomChecked() -> Set<String> {
        let choices = customChoices
        var checked = Set(choices.filter { $0.locked || ($0.group.isEmpty && $0.component.required) }
            .map { $0.component.id })
        let radio = choices.filter { !$0.group.isEmpty }
        let previous = Set(presets.first { $0.id == defaultPresetIdFor(presets) }?.members ?? [])
        if let pick = radio.first(where: { previous.contains($0.component.id) })
            ?? radio.first(where: { $0.component.type == "application" }) ?? radio.first {
            checked.insert(pick.component.id)
        }
        return checked
    }

    /// רדיו מבטל את חברי קבוצתו; סימון גורר את התלויות (אינדקס←ספרייה), וביטול
    /// מבטל את מי שתלוי בשורה.
    func setCustom(_ id: String, _ checked: Bool) {
        let choices = customChoices
        guard let choice = choices.first(where: { $0.component.id == id }), !choice.locked else { return }
        if checked {
            if !choice.group.isEmpty {
                for other in choices where other.group == choice.group {
                    customChecked.remove(other.component.id)
                }
            }
            customChecked.insert(id)
            for dependency in choice.component.dependsOn
            where choices.contains(where: { $0.component.id == dependency && $0.group.isEmpty }) {
                customChecked.insert(dependency)
            }
        } else if choice.group.isEmpty {
            customChecked.remove(id)
            for other in choices where other.component.dependsOn.contains(id) {
                customChecked.remove(other.component.id)
            }
        }
    }

    var selectedMembers: [String] {
        guard let manifest = manifest else { return [] }
        if let preset = presets.first(where: { $0.id == presetId }) {
            return preset.members
        }
        let ordered = manifest.components.map { $0.id }.filter { customChecked.contains($0) }
        return withDependencies(manifest, ordered, target)
    }

    func size(of members: [String]) -> Int64 {
        let set = Set(members)
        return manifest?.components.filter { set.contains($0.id) }.reduce(0) { $0 + $1.downloadSize } ?? 0
    }

    // MARK: - תיקייה

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = strings(.chooseFolderPrompt)
        panel.message = strings(.folderTitle)
        panel.directoryURL = outputBase
        if panel.runModal() == .OK, let url = panel.url {
            outputBase = url
            outputFellBack = false
        }
    }

    private func confirmFolder() {
        if OutputLocation.isWritable(outputBase) {
            go(.ready)
            return
        }
        let fallback = OutputLocation.fallbackBase(english: english)
        if outputBase != fallback && OutputLocation.isWritable(fallback) {
            outputBase = fallback
            tell(title: strings(.folderBadTitle), text: strings(.folderBadFallback, fallback.path))
        } else {
            tell(title: strings(.folderBadTitle), text: strings(.folderBadText))
        }
    }

    // MARK: - הורדה

    private var subfolderName: String? {
        english ? "Otzaria setup for \(platformName(target.platform))" : nil
    }

    private func prepareAndStart() {
        guard let manifest = manifest else { return }
        let plan: PreparationPlan
        do {
            plan = try PreparationPlan.make(
                manifest: manifest, selectedIds: selectedMembers, target: target,
                english: english, subfolderName: subfolderName
            )
        } catch let failure as AssistantError {
            failedWhileLoading = false
            showFailure(.run, failure)
            return
        } catch {
            failedWhileLoading = false
            showFailure(.run, AssistantError(AssistantError.cannotPrepare, technical: "\(error)"))
            return
        }
        if let shortfall = missingSpace(for: plan) {
            ask(
                title: strings(.spaceTitle), text: strings(.spaceText, humanSize(shortfall, english: english)),
                confirm: strings(.spaceYes), keep: strings(.cancel), destructive: false
            ) { [weak self] in self?.start(plan) }
            return
        }
        start(plan)
    }

    /// כמה מקום דרוש בכרך שחסר בו, או nil כשיש מספיק (או כשאי אפשר למדוד).
    private func missingSpace(for plan: PreparationPlan) -> Int64? {
        let cache = CacheStore(directory: CacheStore.defaultDirectory())
        try? cache.prepare()
        let cacheVolume = volumeIdentifier(cache.directory)
        let outputVolume = volumeIdentifier(outputBase)
        let sameVolume = cacheVolume != nil && outputVolume != nil && cacheVolume!.isEqual(outputVolume!)
        let need = spaceNeeded(
            plan: plan,
            isCached: { item in
                let status = cache.status(name: item.name, size: item.size, sha256: item.sha256)
                return status == .ready || status == .needsHash
            },
            sameVolume: sameVolume
        )
        if sameVolume {
            let total = need.cacheBytes + need.outputBytes
            if let free = freeSpace(at: outputBase), free < total { return total }
            return nil
        }
        if let free = freeSpace(at: cache.directory), free < need.cacheBytes { return need.cacheBytes }
        if let free = freeSpace(at: outputBase), free < need.outputBytes { return need.outputBytes }
        return nil
    }

    private func volumeIdentifier(_ url: URL) -> NSObject? {
        (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
    }

    /// ל"שימוש חשוב" עשוי להחזיר nil או 0 בכרכים שאינם APFS — אז הקיבולת הרגילה.
    private func freeSpace(at url: URL) -> Int64? {
        let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        )
        if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 {
            return important
        }
        return values?.volumeAvailableCapacity.map { Int64($0) }
    }

    private func start(_ plan: PreparationPlan) {
        lastPlan = plan
        failedWhileLoading = false
        history.removeAll()
        page = .working
        status = nil
        error = nil
        let runner = PreparationRunner(plan: plan, outputBase: outputBase)
        self.runner = runner
        runner.start(update: { [weak self] status in
            self?.status = status
        }, completion: { [weak self] outcome in
            guard let self = self else { return }
            self.runner = nil
            switch outcome {
            case .success(let result):
                self.result = result
                self.page = .finished
            case .failure(is OperationCancelled):
                self.showFailure(.stopped, nil)
            case .failure(let error as AssistantError):
                self.showFailure(.run, error)
            case .failure(let error):
                self.showFailure(.run, AssistantError(AssistantError.cannotPrepare, technical: "\(error)"))
            }
        })
    }

    private func showFailure(_ kind: FailureKind, _ error: AssistantError?) {
        if let error = error { NSLog("DownloadAssistant: %@", error.technical) }
        dialog = nil
        self.error = error
        failure = kind
        showTechnical = false
        page = .failure
    }

    /// עצירה של המשתמש: מה שכבר ירד נשאר במטמון, ו"המשך" ממשיך ממנו.
    func requestStop() {
        ask(
            title: strings(.stopTitle), text: strings(.stopText),
            confirm: strings(.stopYes), keep: strings(.stopNo), destructive: false
        ) { [weak self] in self?.runner?.cancel() }
    }

    /// "נסה שוב" / "המשך": בטעינה — טעינה חוזרת; אחרת אותו תג ננעל, אותה תוכנית ואותו מטמון.
    func retry() {
        if failedWhileLoading || manifest == nil {
            load()
        } else if let plan = lastPlan {
            start(plan)
        } else {
            page = .ready
        }
    }

    var failureTitle: String {
        switch failure {
        case .offline: return strings(.offlineTitle)
        case .stopped: return strings(.stoppedTitle)
        case .load, .run:
            let message = error?.message(english: english) ?? strings(.offlineTitle)
            return message.hasSuffix(".") ? String(message.dropLast()) : message
        }
    }

    var failureBody: String {
        switch failure {
        case .offline: return strings(.offlineBody)
        case .load: return strings(.loadFailedBody)
        case .run: return strings(.runFailedBody)
        case .stopped: return strings(.stoppedBody)
        }
    }

    // MARK: - יציאה וסיום

    /// הרמזור האדום או Cmd-Q. בזמן עבודה — שאלה; אחרת יציאה מיד.
    public func requestClose() -> Bool {
        guard !quitConfirmed, page == .working || page == .connecting else { return true }
        ask(
            title: strings(.exitTitle), text: strings(.exitMessage),
            confirm: strings(.exitYes), keep: strings(.exitNo), destructive: true
        ) { [weak self] in
            self?.runner?.cancel()
            self?.quit()
        }
        return false
    }

    func quit() {
        quitConfirmed = true
        NSApplication.shared.terminate(nil)
    }

    func openDownloadsPage() {
        NSWorkspace.shared.open(Endpoints.releasesPage)
    }

    /// קובץ DMG יחיד במחשב הזה: "התקן עכשיו" פותח אותו (macOS מציג את חלון הגרירה ליישומים).
    var installableFile: URL? {
        guard mode == .thisComputer, let files = result?.producedFiles, files.count == 1,
              files[0].pathExtension.lowercased() == "dmg" else { return nil }
        return files[0]
    }

    func installNow() {
        guard let file = installableFile else { return }
        if !NSWorkspace.shared.open(file) {
            tell(
                title: strings(.installFailedTitle),
                text: strings(.installFailedText, file.deletingLastPathComponent().path)
            )
        }
    }

    /// פתיחת Finder היא נוחות בלבד: כישלון שקט, התוצאה כבר מוכנה.
    func openOutput() {
        if let target = result?.revealTarget {
            NSWorkspace.shared.activateFileViewerSelecting([target])
        }
    }

    func finish() {
        if mode == .other && revealWhenDone { openOutput() }
        quit()
    }

    // MARK: - דו-שיח

    func tell(title: String, text: String) {
        dialog = DialogItem(title: title, text: text, buttons: [
            DialogButton(title: strings(.ok), style: .filled, isDefault: true, isCancel: true) { [weak self] in
                self?.dialog = nil
            },
        ])
    }

    /// "keep" ממלא (ברירת המחדל ו-Esc) כשהפעולה הורסת; אחרת "confirm" ממלא, כמו ב-Windows.
    func ask(
        title: String, text: String, confirm: String, keep: String, destructive: Bool,
        onConfirm: @escaping () -> Void
    ) {
        let dismiss: () -> Void = { [weak self] in self?.dialog = nil }
        let run: () -> Void = { [weak self] in
            self?.dialog = nil
            onConfirm()
        }
        let buttons: [DialogButton]
        if destructive {
            buttons = [
                DialogButton(title: keep, style: .filled, isDefault: true, isCancel: true, action: dismiss),
                DialogButton(title: confirm, style: .danger, isDefault: false, isCancel: false, action: run),
            ]
        } else {
            buttons = [
                DialogButton(title: keep, style: .text, isDefault: false, isCancel: true, action: dismiss),
                DialogButton(title: confirm, style: .filled, isDefault: true, isCancel: false, action: run),
            ]
        }
        dialog = DialogItem(title: title, text: text, buttons: buttons)
    }
}
