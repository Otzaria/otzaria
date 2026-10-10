import AppKit
import AssistantCore
import SwiftUI

/// התוכן שבתוך החלון: העמוד הנוכחי, ומעליו הדו-שיח כשיש.
public struct AssistantRootView: View {
    @ObservedObject var model: AssistantModel

    public init(model: AssistantModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            Palette.page
            VStack(spacing: 0) {
                // הקו שמתחת לשורת הכותרת, כמו UiBarBorderColor ב-Windows.
                Rectangle().fill(Palette.titleBarBorder).frame(height: 1)
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .disabled(model.dialog != nil)
            .environment(\.underDialog, model.dialog != nil)
            .accessibilityHidden(model.dialog != nil)
            if let dialog = model.dialog {
                DialogView(item: dialog)
            }
        }
        .frame(width: Metrics.windowWidth, height: Metrics.contentHeight)
        .environment(\.layoutDirection, model.strings.english ? .leftToRight : .rightToLeft)
        .environment(\.locale, Locale(identifier: model.strings.english ? "en" : "he"))
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var page: some View {
        switch model.page {
        case .welcome: WelcomePage(model: model)
        case .connecting: ConnectingPage(model: model)
        case .mode: ModePage(model: model)
        case .other: OtherPage(model: model)
        case .presets: PresetsPage(model: model)
        case .custom: CustomPage(model: model)
        case .folder: FolderPage(model: model)
        case .ready: ReadyPage(model: model)
        case .working: WorkingPage(model: model)
        case .finished: FinishPage(model: model)
        case .failure: FailurePage(model: model)
        }
    }
}

// MARK: - מסגרת העמודים

/// רצועת השלבים, הכותרת, התוכן (נגלל כשאינו נכנס) והכותרת התחתונה עם הקו שמעליה.
struct WizardFrame<Content: View, Footer: View>: View {
    @ObservedObject var model: AssistantModel
    let header: PageHeader
    var scrolls = true
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if let step = model.step {
                    StepDots(current: step.current, total: step.total, strings: model.strings)
                        .padding(.top, 12)
                }
            }
            .frame(height: Metrics.stepsHeight, alignment: .top)
            header
                .padding(.top, 6)
            if scrolls {
                ScrollView(.vertical) {
                    content()
                        .frame(width: Metrics.contentWidth)
                        .padding(.top, 16)
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity)
                }
            } else {
                content()
                    .frame(width: Metrics.contentWidth)
                    .padding(.top, 16)
                Spacer(minLength: 0)
            }
            Rectangle().fill(Palette.divider).frame(height: 1)
            HStack(spacing: 12) {
                footer()
            }
            .padding(.horizontal, Metrics.margin)
            .frame(height: Metrics.footerHeight - 1)
        }
    }
}

/// "חזרה" בקצה שבו הקריאה מתחילה, והפעולה הראשית בקצה השני (Return). Esc — חזרה.
struct NavFooter: View {
    @ObservedObject var model: AssistantModel
    var primary: String?

    var body: some View {
        Button(model.strings(.back)) { model.back() }
            .buttonStyle(AssistantButtonStyle(kind: .ghost, width: Metrics.secondaryButtonWidth))
            .ownFocusRing()
            .disabled(!model.canGoBack)
            .opacity(model.canGoBack ? 1 : 0)
            .keyboardShortcut(.cancelAction)
        Spacer(minLength: 0)
        Button(primary ?? model.strings(.next)) { model.next() }
            .buttonStyle(AssistantButtonStyle(kind: .primary, width: Metrics.primaryButtonWidth))
            .ownFocusRing()
            .keyboardShortcut(.defaultAction)
    }
}

/// כפתור טונאלי יחיד בקצה הנגרר (ביטול החיבור, עצירת ההורדה); Esc מפעיל אותו.
struct TrailingFooter: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Spacer(minLength: 0)
        Button(title, action: action)
            .buttonStyle(AssistantButtonStyle(kind: .tonal, width: Metrics.secondaryButtonWidth))
            .ownFocusRing()
            .keyboardShortcut(.cancelAction)
    }
}

/// כרטיסי רדיו: חיצים למעלה ולמטה מעבירים את הבחירה, כמו בקבוצת רדיו של המערכת.
struct RadioCards: View {
    let cards: [CardContent]
    let select: (Int) -> Void

    var body: some View {
        VStack(spacing: Metrics.cardGap) {
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                OptionCard(content: card) { select(index) }
            }
        }
        .onMoveCommand { direction in
            guard !cards.isEmpty else { return }
            let current = cards.firstIndex(where: { $0.selected })
            switch direction {
            case .up: select(max(0, (current ?? 0) - 1))
            case .down: select(min(cards.count - 1, (current ?? -1) + 1))
            default: break
            }
        }
    }
}

// MARK: - פתיחה

/// הספר נפתח, עולה, והכותרת נחשפת (assistant_art.isi: AA_BOOK_*, AA_RISE_*, AA_TITLE_*).
/// קליק מדלג לסוף; בלי אנימציות מערכת (Reduce Motion) — המצב הסופי מיד.
struct WelcomePage: View {
    @ObservedObject var model: AssistantModel
    @State private var start = Date()

    static let fadeMs = 250.0
    static let frameMs = 42.0
    static let riseStart = 17 * frameMs
    static let riseMs = 650.0
    static let titleFadeMs = 400.0
    static var titleStart: Double { riseStart + riseMs }
    static var endMs: Double { fadeMs + titleStart + titleFadeMs }

    private var animates: Bool {
        !model.heroPlayed && Art.shared.hasBook
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        Group {
            if let time = model.heroPreviewTime {
                hero(time)
            } else if animates {
                TimelineView(.animation) { context in
                    hero(context.date.timeIntervalSince(start) * 1000)
                }
            } else {
                hero(Self.endMs)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.heroPlayed = true }
        .onAppear {
            start = Date()
            guard animates else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.endMs / 1000) {
                model.heroPlayed = true
            }
        }
    }

    private func hero(_ elapsed: Double) -> some View {
        let t = elapsed - Self.fadeMs
        let frame = Int(max(0, min(Double(Art.bookFrameCount - 1), t / Self.frameMs)))
        let rise = easeInOut((t - Self.riseStart) / Self.riseMs)
        let titleProgress = (t - Self.titleStart) / Self.titleFadeMs
        let done = elapsed >= Self.endMs
        return ZStack(alignment: .top) {
            if let image = Art.shared.bookFrame(done ? Art.bookFrameCount - 1 : frame) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 220, height: 220)
                    .opacity(easeInOut(elapsed / Self.fadeMs))
                    .padding(.top, 204 - 130 * CGFloat(done ? 1 : rise))
                    .accessibilityHidden(true)
            }
            WelcomeTitle(strings: model.strings)
                .opacity(done ? 1 : max(0, min(1, titleProgress)))
                .padding(.top, 325 + 8 * CGFloat(done ? 0 : 1 - easeOut(titleProgress)))
            if done {
                Text(bidi(model.strings(.welcomeNote)))
                    .font(Fonts.heroNote)
                    .foregroundColor(Palette.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: Metrics.contentWidth - 32)
                    .padding(.top, 500)
                Button(model.strings(.startButton)) { model.begin() }
                    .buttonStyle(AssistantButtonStyle(kind: .primary, fill: true, height: Metrics.wideButtonHeight))
                    .ownFocusRing()
                    .keyboardShortcut(.defaultAction)
                    .frame(width: Metrics.contentWidth)
                    .padding(.top, 570)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// הכותרת, הקישוט והשורה שמתחתיה — טקסט אמיתי בגופן המערכת, לא תמונה.
struct WelcomeTitle: View {
    let strings: Strings

    var body: some View {
        VStack(spacing: 0) {
            Text(strings(.appTitle))
                .font(Fonts.heroTitle)
                .foregroundColor(Palette.text)
                .accessibilityAddTraits(.isHeader)
            Ornament()
                .padding(.top, 6)
            Text(strings(.welcomeSubtitle))
                .font(Fonts.heroSubtitle)
                .foregroundColor(Palette.muted)
                .padding(.top, 6)
        }
        .frame(width: Metrics.contentWidth)
    }
}

/// קו, יהלום וקו בזהב — הקישוט שמתחת לכותרת.
struct Ornament: View {
    var body: some View {
        HStack(spacing: 5) {
            LinearGradient(colors: [Palette.ornament.opacity(0), Palette.ornament], startPoint: .leading, endPoint: .trailing)
                .frame(width: 26, height: 1)
            Rectangle()
                .fill(Palette.ornament)
                .frame(width: 5, height: 5)
                .rotationEffect(.degrees(45))
            LinearGradient(colors: [Palette.ornament, Palette.ornament.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 26, height: 1)
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

func easeInOut(_ value: Double) -> Double {
    let p = max(0, min(1, value))
    return p < 0.5 ? 4 * p * p * p : 1 - pow(2 - 2 * p, 3) / 2
}

func easeOut(_ value: Double) -> Double {
    let p = max(0, min(1, value))
    return 1 - pow(1 - p, 3)
}

// MARK: - חיבור

struct ConnectingPage: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        WizardFrame(
            model: model,
            header: PageHeader(title: model.strings(.connectTitle), desc: model.strings(.connectDesc)),
            scrolls: false
        ) {
            ProgressPanel(percent: "", caption: model.strings(.connectingProgress), fraction: nil, speed: "", bytes: "")
        } footer: {
            TrailingFooter(title: model.strings(.cancel)) { model.requestStopConnecting() }
        }
    }
}

// MARK: - לאיזה מחשב

struct ModePage: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        let s = model.strings
        let version = model.releaseVersionLabel
        WizardFrame(
            model: model,
            header: PageHeader(
                title: s(.modeTitle), desc: s(.modeDesc),
                hint: version.isEmpty ? "" : s(.versionToDownload, version)
            )
        ) {
            RadioCards(cards: [
                CardContent(
                    title: s(.modeThis), desc: s(.modeThisDesc), icon: "this_pc",
                    selected: model.mode == .thisComputer
                ),
                CardContent(
                    title: s(.modeOther), desc: s(.modeOtherDesc, model.otherSummary), icon: "other_pc",
                    selected: model.mode == .other
                ),
            ]) { index in
                model.mode = index == 0 ? .thisComputer : .other
            }
        } footer: {
            NavFooter(model: model)
        }
    }
}

struct OtherPage: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        let s = model.strings
        WizardFrame(
            model: model,
            header: PageHeader(title: s(.otherTitle), desc: s(.otherDesc), hint: s(.otherHint))
        ) {
            RadioCards(cards: model.otherTargets.enumerated().map { index, target in
                CardContent(
                    title: model.targetTitle(target), desc: model.targetHint(target),
                    icon: ["deb", "rpm", portablePackageFormat].contains(target.packageFormat)
                        ? "fmt_" + target.packageFormat : target.platform,
                    selected: model.otherIndex == index
                )
            }) { index in
                model.otherIndex = index
            }
        } footer: {
            NavFooter(model: model)
        }
    }
}

// MARK: - מה להוריד

struct PresetsPage: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        let s = model.strings
        let ids = model.presets.map { $0.id } + [customPresetId]
        WizardFrame(
            model: model,
            header: PageHeader(title: s(.presetTitle), desc: s(.presetDesc), hint: s(.presetHint))
        ) {
            RadioCards(cards: ids.map { id -> CardContent in
                let preset = model.presets.first { $0.id == id }
                return CardContent(
                    title: model.presetTitle(id), desc: model.presetDescription(id),
                    side: preset.map { s(.cardSize, humanSize(model.size(of: $0.members), english: s.english)) } ?? "",
                    icon: id == customPresetId ? "preset_custom" : model.presetIcon(id),
                    selected: model.presetId == id
                )
            }) { index in
                model.presetId = ids[index]
            }
        } footer: {
            NavFooter(model: model)
        }
    }
}

struct CustomPage: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        let s = model.strings
        WizardFrame(
            model: model,
            header: PageHeader(title: s(.presetCustom), desc: s(.customDesc), hint: s(.customHint))
        ) {
            VStack(spacing: Metrics.cardGap) {
                // המתקין והחבילה המלאה — רדיו; מתקין בלי חלופה — נעול ומסומן.
                ForEach(model.customChoices, id: \.component.id) { choice in
                    let component = choice.component
                    let required = choice.locked || (component.required && choice.group.isEmpty)
                    let checked = choice.locked || model.customChecked.contains(component.id)
                    OptionCard(content: CardContent(
                        title: component.displayName(english: s.english) + (required ? " " + s(.requiredTag) : ""),
                        desc: component.displayDescription(english: s.english),
                        side: s(.cardSize, humanSize(model.customChoiceSize(component), english: s.english)),
                        icon: "component",
                        mark: choice.group.isEmpty ? .check : .radio,
                        selected: checked,
                        locked: choice.locked
                    )) {
                        model.setCustom(component.id, choice.group.isEmpty ? !checked : true)
                    }
                }
            }
        } footer: {
            NavFooter(model: model)
        }
    }
}

// MARK: - לאן לשמור

struct FolderPage: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        let s = model.strings
        WizardFrame(
            model: model,
            header: PageHeader(
                title: s(.folderTitle), desc: s(.folderDesc),
                hint: s(.folderHint) + (model.outputFellBack ? "\n\n" + s(.folderFallbackNote) : "")
            ),
            scrolls: false
        ) {
            VStack(alignment: .trailing, spacing: 12) {
                Button { model.chooseFolder() } label: {
                    Text(ltrUnit(model.outputBase.path, english: false))
                        .font(.system(size: 14))
                        .foregroundColor(Palette.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous).fill(Palette.field))
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                                .strokeBorder(Palette.outline, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainFocusStyle())
                .ownFocusRing()
                .accessibilityLabel(s(.rowSavedIn))
                .accessibilityValue(model.outputBase.path)
                Button(s(.browse)) { model.chooseFolder() }
                    .buttonStyle(AssistantButtonStyle(kind: .tonal, width: Metrics.secondaryButtonWidth))
                    .ownFocusRing()
            }
        } footer: {
            NavFooter(model: model)
        }
    }
}

struct PlainFocusStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PlainFocusBody(configuration: configuration)
    }
}

private struct PlainFocusBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .overlay(FocusRing(visible: isFocused, radius: Metrics.radius))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - מוכנים להתחיל

struct ReadyPage: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        let s = model.strings
        WizardFrame(
            model: model,
            header: PageHeader(title: s(.readyTitle), desc: s(.readyDesc), hint: s(.readyHint))
        ) {
            SummaryCard(rows: rows)
        } footer: {
            NavFooter(model: model, primary: s(.start))
        }
    }

    private var rows: [SummaryRow] {
        let s = model.strings
        var rows: [SummaryRow] = []
        if !model.releaseVersionLabel.isEmpty {
            rows.append(SummaryRow(icon: "preset_update", label: s(.rowVersion), value: model.releaseVersionLabel))
        }
        let isCustom = !model.presets.contains { $0.id == model.presetId }
        let what = model.presetTitle(isCustom ? customPresetId : model.presetId)
            + " · " + humanSize(model.size(of: model.selectedMembers), english: s.english)
        rows.append(SummaryRow(
            icon: isCustom ? "preset_custom" : model.presetIcon(model.presetId), label: s(.rowWhat), value: what
        ))
        let target = model.target
        var forText = model.mode == .thisComputer ? s(.modeThis) : model.targetTitle(target)
        if !target.packageFormat.isEmpty { forText += " · " + model.formatName(target.packageFormat) }
        rows.append(SummaryRow(
            icon: model.mode == .thisComputer ? "this_pc" : target.platform, label: s(.rowFor), value: forText
        ))
        rows.append(SummaryRow(icon: "folder", label: s(.rowSavedIn), value: model.outputBase.path, isPath: true))
        return rows
    }
}

// MARK: - הורדה

struct ProgressPanel: View {
    let percent: String
    let caption: String
    let fraction: Double?
    let speed: String
    let bytes: String
    var barTime: Double?

    var body: some View {
        VStack(spacing: 0) {
            Text(percent.isEmpty ? " " : percent)
                .font(Fonts.percent)
                .foregroundColor(Palette.primary)
            Text(bidi(caption))
                .font(Fonts.progressCaption)
                .foregroundColor(Palette.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
                .padding(.top, 4)
            ProgressBar(fraction: fraction, animationTime: barTime)
                .padding(.top, 16)
            Text(speed.isEmpty ? " " : speed)
                .font(Fonts.progressDetail)
                .foregroundColor(Palette.muted)
                .padding(.top, 16)
            Text(bytes.isEmpty ? " " : bytes)
                .font(Fonts.progressDetail)
                .foregroundColor(Palette.faint)
                .padding(.top, 4)
        }
        .padding(.top, 28)
        .accessibilityElement(children: .combine)
    }
}

struct WorkingPage: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        let s = model.strings
        let status = model.status
        let downloading = status == nil || status?.phase == .downloading
        let version = model.releaseVersionLabel
        WizardFrame(
            model: model,
            header: downloading
                ? PageHeader(
                    title: version.isEmpty ? s(.workTitle) : s(.downloadingVersion, version),
                    desc: s(.downloadDesc)
                )
                : PageHeader(title: s(.workTitle), desc: s(.workDesc)),
            scrolls: false
        ) {
            ProgressPanel(
                percent: status.map { "\(Int($0.fraction * 100))%" } ?? "0%",
                caption: caption(status),
                fraction: status?.fraction ?? 0,
                speed: speed(status),
                bytes: bytes(status)
            )
        } footer: {
            TrailingFooter(title: s(.stopDownload)) { model.requestStop() }
        }
    }

    private func caption(_ status: PreparationStatus?) -> String {
        let s = model.strings
        guard let status = status else { return s(.preparing) }
        let title = status.title(english: s.english)
        if status.phase == .downloading && status.title == PreparationStatus.downloadingTitle {
            return status.detail.isEmpty ? title : s(.downloadingItem, status.detail)
        }
        return status.detail.isEmpty ? title : title + ": " + status.detail
    }

    private func speed(_ status: PreparationStatus?) -> String {
        let s = model.strings
        guard let status = status, status.phase == .downloading, let rate = status.bytesPerSecond else { return "" }
        var text = humanSpeed(rate, english: s.english)
        if let remaining = status.secondsRemaining {
            text += " · " + s(.timeLeft, humanRemaining(remaining, english: s.english))
        }
        return text
    }

    private func bytes(_ status: PreparationStatus?) -> String {
        let s = model.strings
        guard let status = status, status.totalBytes > 0 else { return "" }
        let done = humanSize(status.doneBytes, english: s.english)
        let total = humanSize(status.totalBytes, english: s.english)
        return status.phase == .downloading ? s(.downloadedOf, done, total) : s(.sizeOf, done, total)
    }
}

// MARK: - סיום

struct FinishPage: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        let s = model.strings
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    StatusBadge(kind: .ok)
                        .padding(.top, 36)
                    Text(s(.finishedTitle))
                        .font(Fonts.pageTitle)
                        .foregroundColor(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 16)
                    if let result = model.result {
                        SummaryCard(rows: rows(result))
                            .padding(.top, 24)
                        guide(result)
                            .padding(.top, 14)
                    }
                }
                .frame(width: Metrics.contentWidth)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
            }
            // מחוץ לגלילה: רשימת קבצים ארוכה אינה מסתירה את הבחירה.
            if model.mode == .other {
                OptionCard(content: CardContent(
                    title: isSingle ? s(.revealFile) : s(.revealFolder),
                    mark: .check, selected: model.revealWhenDone
                )) { model.revealWhenDone.toggle() }
                .frame(width: Metrics.contentWidth)
                .padding(.top, 8)
            }
            actions
                .frame(width: Metrics.contentWidth)
                .padding(.top, 8)
                .padding(.bottom, 18)
        }
    }

    private var isSingle: Bool { model.result?.producedFiles.count == 1 }

    @ViewBuilder
    private var actions: some View {
        let s = model.strings
        VStack(spacing: 8) {
            if model.mode == .other {
                Button(s(.finish)) { model.finish() }
                    .buttonStyle(AssistantButtonStyle(kind: .primary, fill: true))
                    .ownFocusRing()
                    .keyboardShortcut(.defaultAction)
            } else {
                if model.installableFile != nil {
                    Button(s(.installNow)) { model.installNow() }
                        .buttonStyle(AssistantButtonStyle(kind: .primary, fill: true))
                        .ownFocusRing()
                        .keyboardShortcut(.defaultAction)
                    Button(s(.openFolder)) { model.openOutput() }
                        .buttonStyle(AssistantButtonStyle(kind: .tonal, fill: true))
                        .ownFocusRing()
                } else {
                    Button(s(.openFolder)) { model.openOutput() }
                        .buttonStyle(AssistantButtonStyle(kind: .primary, fill: true))
                        .ownFocusRing()
                        .keyboardShortcut(.defaultAction)
                }
                Button(s(.close)) { model.quit() }
                    .buttonStyle(AssistantButtonStyle(kind: .ghost, fill: true))
                    .ownFocusRing()
            }
        }
    }

    private func rows(_ result: PreparationResult) -> [SummaryRow] {
        let s = model.strings
        var rows: [SummaryRow] = []
        if !model.releaseVersionLabel.isEmpty {
            rows.append(SummaryRow(icon: "preset_update", label: s(.rowVersion), value: model.releaseVersionLabel))
        }
        if isSingle {
            rows.append(SummaryRow(
                icon: "component", label: s(.rowFile), value: result.producedFiles[0].lastPathComponent, isPath: true
            ))
        }
        rows.append(SummaryRow(icon: "folder", label: s(.rowFolder), value: result.outputDirectory.path, isPath: true))
        return rows
    }

    /// הניסוח נגזר ממה שנוצר בפועל, ולא מהרכיב שנבחר — כמו PrepareOutput ב-Windows.
    @ViewBuilder
    private func guide(_ result: PreparationResult) -> some View {
        let s = model.strings
        let names = result.producedFiles.map {
            $0.path.replacingOccurrences(of: result.outputDirectory.path + "/", with: "")
        }
        let platform = model.platformName(model.target.platform)
        VStack(spacing: 8) {
            if isSingle {
                paragraph(model.mode == .thisComputer
                    ? s(.guideThisFile)
                    : s(.guideOtherFile, platform) + " " + openHint(names[0]))
            } else {
                if model.mode == .thisComputer {
                    paragraph(s(.guideThisFolder))
                } else {
                    let exe = names.first { $0.lowercased().hasSuffix(".exe") }
                    paragraph(s(.guideOtherFolder, platform)
                        + (model.target.platform == "windows" && exe != nil
                            ? " " + s(.guideRunExe, unbreakable(exe!, english: s.english)) : ""))
                }
                if !result.keptSplitAssets.isEmpty {
                    paragraph(s(.guideJoin))
                    ForEach(result.keptSplitAssets, id: \.self) { asset in
                        CommandBox(text: joinCommand(assetName: asset))
                    }
                }
                paragraph(s(.preparedFiles))
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(names, id: \.self) { name in
                        Text("• " + name)
                            .font(Fonts.pageHint)
                            .foregroundColor(Palette.muted)
                            .textSelection(.enabled)
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(result.outputNotes, id: \.self) { note in
                paragraph(note)
            }
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(bidi(text))
            .font(Fonts.pageHint)
            .foregroundColor(Palette.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    /// מה עושים בקובץ במחשב היעד, לפי הסיומת (OpenHint).
    private func openHint(_ name: String) -> String {
        let s = model.strings
        let lower = name.lowercased()
        if lower.hasSuffix(".exe") { return s(.openHintExe) }
        if lower.hasSuffix(".dmg") { return s(.openHintDmg) }
        if lower.hasSuffix(".deb") || lower.hasSuffix(".rpm") { return s(.openHintPackage) }
        if lower.hasSuffix(".apk") { return s(.openHintApk) }
        return s(.openHintArchive)
    }
}

/// שם קובץ בתוך משפט: מקפים שאינם נשברים, כדי שהשם לא יתפצל בין שורות ויתהפך סביב השבירה.
func unbreakable(_ name: String, english: Bool) -> String {
    ltrUnit(name.replacingOccurrences(of: "-", with: "\u{2011}"), english: english)
}

/// פקודה להעתקה: משמאל לימין, ניתנת לבחירה, בלי תווי כיווניות שהיו נשברים בטרמינל.
struct CommandBox: View {
    let text: String

    var body: some View {
        Text(text)
            .pathText()
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: - שגיאה ועצירה

struct FailurePage: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        let s = model.strings
        let technical = model.failure == .stopped ? "" : (model.error?.technical ?? "")
        VStack(spacing: 0) {
            StatusBadge(kind: badge)
                .padding(.top, 52)
            Text(bidi(model.failureTitle))
                .font(Fonts.pageTitle)
                .foregroundColor(Palette.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 20)
            Text(bidi(model.failureBody))
                .font(Fonts.pageDesc)
                .foregroundColor(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            if !technical.isEmpty {
                TechnicalDetails(text: technical, strings: s, expanded: $model.showTechnical)
                    .padding(.top, 14)
            }
            Spacer(minLength: 12)
            VStack(spacing: 8) {
                Button(model.failure == .stopped ? s(.resume) : s(.retry)) { model.retry() }
                    .buttonStyle(AssistantButtonStyle(kind: .primary, fill: true))
                    .ownFocusRing()
                    .keyboardShortcut(.defaultAction)
                if model.failure != .stopped {
                    Button(s(.openDownloads)) { model.openDownloadsPage() }
                        .buttonStyle(AssistantButtonStyle(kind: .tonal, fill: true))
                        .ownFocusRing()
                }
                Button(s(.close)) { model.quit() }
                    .buttonStyle(AssistantButtonStyle(kind: .ghost, fill: true))
                    .ownFocusRing()
            }
            .padding(.bottom, 18)
        }
        .frame(width: Metrics.contentWidth)
        .frame(maxWidth: .infinity)
    }

    private var badge: BadgeKind {
        switch model.failure {
        case .offline: return .offline
        case .stopped: return .paused
        case .load, .run: return .err
        }
    }
}
