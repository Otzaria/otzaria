import AssistantCore
import SwiftUI

// MARK: - כפתורים

enum ButtonKind {
    case primary
    case tonal
    case ghost
    case danger
}

/// כפתורי העיצוב: מלא, טונאלי וטקסט, ברדיוס 8, עם ריחוף, לחיצה וטבעת מוקד מצוירת.
struct AssistantButtonStyle: ButtonStyle {
    let kind: ButtonKind
    /// nil — לפי הטקסט; fill — כל רוחב התוכן.
    var width: CGFloat?
    var fill = false
    var height: CGFloat = Metrics.buttonHeight

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, kind: kind, width: width, fill: fill, height: height)
    }
}

private struct StyledButton: View {
    let configuration: ButtonStyleConfiguration
    let kind: ButtonKind
    let width: CGFloat?
    let fill: Bool
    let height: CGFloat
    @Environment(\.isEnabled) private var environmentEnabled
    @Environment(\.underDialog) private var underDialog
    @Environment(\.isFocused) private var isFocused
    @State private var hover = false

    /// מתחת לדו-שיח הכפתורים מושבתים אבל נראים כרגיל, מוצללים בלבד — כמו ב-Windows.
    private var isEnabled: Bool { environmentEnabled || underDialog }

    var body: some View {
        configuration.label
            .font(Fonts.button)
            .lineLimit(1)
            .foregroundColor(foreground)
            .padding(.horizontal, 16)
            .frame(minWidth: width, minHeight: height, maxHeight: height)
            .frame(maxWidth: fill ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous).fill(background)
            )
            .overlay(FocusRing(visible: isFocused, radius: Metrics.radius))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }

    private var pressed: Bool { configuration.isPressed }

    private var foreground: Color {
        guard isEnabled else { return Palette.disabledText }
        switch kind {
        case .primary: return Palette.onPrimary
        case .tonal: return Palette.onTonal
        case .ghost: return Palette.primary
        case .danger: return Palette.error
        }
    }

    private var background: Color {
        switch kind {
        case .primary:
            guard isEnabled else { return Palette.disabled }
            return pressed ? Palette.primaryPressed : (hover ? Palette.primary.opacity(0.92) : Palette.primary)
        case .tonal:
            guard isEnabled else { return Palette.disabled }
            return pressed ? Palette.tonalPressed : (hover ? Palette.tonal.opacity(0.85) : Palette.tonal)
        case .ghost, .danger:
            return pressed ? Palette.primary.opacity(0.12) : (hover ? Palette.primary.opacity(0.07) : .clear)
        }
    }
}

/// טבעת מוקד בצבע הראשי, מחוץ לגבולות הפקד — כמו UiDrawFocusRect, בלי לשנות את גודלו.
struct FocusRing: View {
    let visible: Bool
    let radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
            .strokeBorder(Palette.primary, lineWidth: 2)
            .padding(-3)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(false)
    }
}

extension View {
    /// בלי הטבעת של המערכת מעל הטבעת המצוירת (macOS 14 ומעלה; לפני כן אין טבעת כפולה בכפתור מעוצב).
    @ViewBuilder
    func ownFocusRing() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            self
        }
    }

    /// שורה ששמה LTR (נתיב, שם קובץ, פקודה) בתוך ממשק עברי.
    func pathText() -> some View {
        self.font(Fonts.mono).foregroundColor(Palette.text)
    }
}

struct UnderDialogKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var underDialog: Bool {
        get { self[UnderDialogKey.self] }
        set { self[UnderDialogKey.self] = newValue }
    }
}

// MARK: - נקודות השלבים

struct StepDots: View {
    let current: Int
    let total: Int
    let strings: Strings

    var body: some View {
        VStack(spacing: 6) {
            // ב-RTL ה-HStack מתהפך: השלב הראשון בקצה הימני, כמו בכיוון הקריאה.
            HStack(spacing: 6) {
                ForEach(1...max(1, total), id: \.self) { index in
                    Capsule()
                        .fill(index == current ? Palette.primary : (index < current ? Palette.dotDone : Palette.divider))
                        .frame(width: index == current ? 20 : 6, height: 6)
                }
            }
            Text(strings(.stepOf, "\(current)", "\(total)"))
                .font(Fonts.step)
                .foregroundColor(Palette.faint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(strings(.stepOf, "\(current)", "\(total)"))
    }
}

// MARK: - כותרת העמוד

struct PageHeader: View {
    let title: String
    var desc: String = ""
    var hint: String = ""

    var body: some View {
        VStack(spacing: 0) {
            Text(bidi(title))
                .font(Fonts.pageTitle)
                .foregroundColor(Palette.text)
                .accessibilityAddTraits(.isHeader)
            if !desc.isEmpty {
                Text(bidi(desc))
                    .font(Fonts.pageDesc)
                    .foregroundColor(Palette.muted)
                    .padding(.top, 8)
            }
            if !hint.isEmpty {
                Text(bidi(hint))
                    .font(Fonts.pageHint)
                    .foregroundColor(Palette.muted)
                    .padding(.top, 6)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: Metrics.contentWidth)
    }
}

// MARK: - כרטיס בחירה

enum CardMark {
    case radio
    case check
    case none
}

struct CardContent {
    var title: String
    var desc: String = ""
    var side: String = ""
    var icon: String?
    var mark: CardMark = .radio
    var selected = false
    var locked = false
}

/// כרטיס אחד: סימון בקצה שבו הטקסט מתחיל, אריח הסמל, ואז הכותרת, התיאור והגודל (UiLayoutCard).
struct OptionCard: View {
    let content: CardContent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if content.mark != .none {
                    SelectionMark(mark: content.mark, on: content.selected)
                }
                if let icon = content.icon {
                    IconTile(name: icon)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(bidi(content.title))
                        .font(Fonts.cardTitle)
                        .foregroundColor(Palette.text)
                    if !content.desc.isEmpty {
                        Text(bidi(content.desc))
                            .font(Fonts.cardDesc)
                            .foregroundColor(Palette.muted)
                            .padding(.top, 3)
                    }
                    if !content.side.isEmpty {
                        Text(content.side)
                            .font(Fonts.cardSide)
                            .foregroundColor(Palette.faint)
                            .padding(.top, 4)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .frame(minHeight: 68)
        }
        .buttonStyle(CardButtonStyle(selected: content.selected, locked: content.locked))
        .ownFocusRing()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(content.selected ? [.isButton, .isSelected] : .isButton)
    }
}

struct CardButtonStyle: ButtonStyle {
    let selected: Bool
    var locked = false

    func makeBody(configuration: Configuration) -> some View {
        CardBody(configuration: configuration, selected: selected, locked: locked)
    }
}

private struct CardBody: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    let locked: Bool
    @Environment(\.isFocused) private var isFocused
    @State private var hover = false

    var body: some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous).fill(fill)
            )
            .overlay(FocusRing(visible: isFocused, radius: Metrics.radius))
            .contentShape(Rectangle())
            .onHover { hover = $0 && !locked }
    }

    private var fill: Color {
        if selected { return hover ? Palette.cardSelected.opacity(0.85) : Palette.cardSelected }
        return hover || configuration.isPressed ? Palette.cardHover : Palette.card
    }
}

/// רדיו ותיבת סימון בגודל 20, מצוירים (radio_on/check_on של העיצוב).
struct SelectionMark: View {
    let mark: CardMark
    let on: Bool

    var body: some View {
        Group {
            if mark == .check {
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(on ? Palette.primary : Color.clear)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(on ? Palette.primary : Palette.muted, lineWidth: 2)
                    if on {
                        CheckGlyph()
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .frame(width: 11, height: 8)
                    }
                }
            } else {
                ZStack {
                    Circle().strokeBorder(on ? Palette.primary : Palette.muted, lineWidth: 2)
                    if on {
                        Circle().fill(Palette.primary).frame(width: 10, height: 10)
                    }
                }
            }
        }
        .frame(width: Metrics.toggle, height: Metrics.toggle)
        .accessibilityHidden(true)
    }
}

struct CheckGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

// MARK: - פס התקדמות

/// פס בגובה 8 בצבע הטונאלי; בלי ערך — מקטע נע מראה שהעבודה נמשכת.
struct ProgressBar: View {
    let fraction: Double?
    var animationTime: Double?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.tonal)
                if let fraction = fraction {
                    Capsule().fill(Palette.primary)
                        .frame(width: max(8, width * CGFloat(min(1, max(0, fraction)))))
                } else {
                    IndeterminateSegment(width: width, time: animationTime)
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityValue(fraction.map { "\(Int($0 * 100))%" } ?? "")
    }
}

private struct IndeterminateSegment: View {
    let width: CGFloat
    let time: Double?

    var body: some View {
        if let time = time {
            segment(at: time)
        } else {
            TimelineView(.animation) { context in
                segment(at: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func segment(at time: Double) -> some View {
        let segment = width * 0.3
        let phase = time.truncatingRemainder(dividingBy: 1.6) / 1.6
        return Capsule().fill(Palette.primary)
            .frame(width: segment)
            .offset(x: -segment + (width + segment) * CGFloat(phase))
    }
}

// MARK: - כרטיס סיכום

struct SummaryRow: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String
    var isPath = false
}

/// כרטיס אחד לכל השורות, ורצועה בצבע העמוד ביניהן (UiPlaceSummary).
struct SummaryCard: View {
    let rows: [SummaryRow]

    var body: some View {
        VStack(spacing: 2) {
            ForEach(rows) { row in
                HStack(spacing: 14) {
                    IconTile(name: row.icon)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bidi(row.label))
                            .font(Fonts.rowLabel)
                            .foregroundColor(Palette.faint)
                        if row.isPath {
                            Text(ltrUnit(row.value, english: false))
                                .font(Fonts.rowValue)
                                .foregroundColor(Palette.text)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        } else {
                            Text(bidi(row.value))
                                .font(Fonts.rowValue)
                                .foregroundColor(Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Palette.card)
                .accessibilityElement(children: .combine)
            }
        }
        .background(Palette.page)
        .padding(.vertical, 4)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
    }
}

// MARK: - פרטים טכניים

struct TechnicalDetails: View {
    let text: String
    let strings: Strings
    @Binding var expanded: Bool

    var body: some View {
        VStack(spacing: 10) {
            Button(strings(.techDetails)) { expanded.toggle() }
                .buttonStyle(LinkStyle())
                .ownFocusRing()
                .accessibilityValue(expanded ? "1" : "0")
            if expanded {
                ScrollView {
                    Text(text)
                        .pathText()
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .environment(\.layoutDirection, .leftToRight)
                .background(Palette.card)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
    }
}

struct LinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LinkBody(configuration: configuration)
    }
}

private struct LinkBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(configuration.isPressed ? Palette.primaryPressed : Palette.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(FocusRing(visible: isFocused, radius: 4))
            .contentShape(Rectangle())
    }
}

// MARK: - דו-שיח

/// שכבת הצללה וכרטיס בגוון שורת הכותרת, כמו UiAsk. Return ו-Esc לפי הכפתורים.
struct DialogView: View {
    let item: DialogItem

    var body: some View {
        ZStack {
            Palette.shade
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
            VStack(alignment: .leading, spacing: 0) {
                Text(bidi(item.title))
                    .font(Fonts.dialogTitle)
                    .foregroundColor(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                Text(bidi(item.text))
                    .font(Fonts.dialogText)
                    .foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    ForEach(Array(item.buttons.enumerated()), id: \.offset) { _, button in
                        dialogButton(button)
                    }
                }
                .padding(.top, 24)
            }
            .multilineTextAlignment(.leading)
            .padding(24)
            .frame(width: 336, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.dialog)
                    .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 6)
            )
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    @ViewBuilder
    private func dialogButton(_ button: DialogButton) -> some View {
        let kind: ButtonKind = button.style == .filled ? .primary : (button.style == .danger ? .danger : .ghost)
        let base = Button(button.title, action: button.action)
            .buttonStyle(AssistantButtonStyle(kind: kind, width: nil))
            .ownFocusRing()
        if button.isDefault && button.isCancel {
            // כפתור יחיד ("אישור"): Return ו-Esc סוגרים אותו שניהם.
            base.keyboardShortcut(.defaultAction)
                .background(
                    Button("", action: button.action)
                        .keyboardShortcut(.cancelAction)
                        .opacity(0)
                        .accessibilityHidden(true)
                )
        } else if button.isDefault {
            base.keyboardShortcut(.defaultAction)
        } else if button.isCancel {
            base.keyboardShortcut(.cancelAction)
        } else {
            base
        }
    }
}
