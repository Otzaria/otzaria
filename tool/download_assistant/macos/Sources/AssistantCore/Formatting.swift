import Foundation

/// אותן יחידות כמו במסייע ל-Windows ובתוכנה עצמה: GB, MB, KB, עם רווח קשיח.
/// בעברית הערך עטוף ב-LRE…PDF, אחרת "37 MB" בתוך משפט עברי מוצג הפוך.
public func humanSize(_ bytes: Int64, english: Bool = false) -> String {
    let text: String
    if bytes >= 1_073_741_824 {
        let tenths = bytes * 10 / 1_073_741_824
        text = "\(tenths / 10).\(tenths % 10)\u{00A0}GB"
    } else if bytes >= 1_048_576 {
        text = "\(bytes / 1_048_576)\u{00A0}MB"
    } else {
        text = "\((bytes + 1023) / 1024)\u{00A0}KB"
    }
    return ltrUnit(text, english: english)
}

public func humanSpeed(_ bytesPerSecond: Double, english: Bool = false) -> String {
    let perSecond = Int64(max(0, bytesPerSecond))
    let text: String
    if perSecond >= 1_048_576 {
        let tenths = perSecond * 10 / 1_048_576
        text = "\(tenths / 10).\(tenths % 10) MB/s"
    } else {
        text = "\(perSecond / 1024) KB/s"
    }
    return ltrUnit(text, english: english)
}

/// כמו HumanDuration של Windows: שעות שלמות ודקות מעוגלות.
public func humanRemaining(_ seconds: TimeInterval, english: Bool = false) -> String {
    if seconds < 60 { return english ? "less than a minute" : "פחות מדקה" }
    let whole = Int64(seconds)
    var hours = whole / 3600
    var minutes = (whole % 3600 + 30) / 60
    if minutes == 60 {
        hours += 1
        minutes = 0
    }
    var text = ""
    if hours == 1 {
        text = english ? "1 hour" : "שעה"
    } else if hours == 2 {
        text = english ? "2 hours" : "שעתיים"
    } else if hours > 2 {
        text = english ? "\(hours) hours" : "\(hours) שעות"
    }
    if minutes == 0 { return text }
    let minutesText = minutes == 1
        ? (english ? "1 minute" : "דקה")
        : (english ? "\(minutes) minutes" : "\(minutes) דקות")
    if text.isEmpty { return minutesText }
    return english ? "\(text) \(minutesText)" : "\(text) ו-\(minutesText)"
}

/// ערך משמאל לימין (גודל, נתיב, גרסה) בתוך משפט עברי.
public func ltrUnit(_ text: String, english: Bool) -> String {
    english ? text : "\u{202A}" + text + "\u{202C}"
}

/// מהירות כממוצע נע על ~5 שניות, וזמן משוער לסיום.
public struct SpeedMeter {
    public let window: TimeInterval
    private var samples: [(time: TimeInterval, bytes: Int64)] = []

    public init(window: TimeInterval = 5) {
        self.window = window
    }

    /// `bytes` הוא מונה מצטבר של בתים שירדו בריצה הזאת.
    public mutating func record(time: TimeInterval, bytes: Int64) {
        samples.append((time, bytes))
        while let first = samples.first, time - first.time > window, samples.count > 2 {
            samples.removeFirst()
        }
    }

    /// nil עד שנצבר מספיק זמן למדידה.
    public var bytesPerSecond: Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let span = last.time - first.time
        guard span >= 0.5 else { return nil }
        return Double(last.bytes - first.bytes) / span
    }

    public func secondsRemaining(_ remainingBytes: Int64) -> TimeInterval? {
        guard let speed = bytesPerSecond, speed > 0 else { return nil }
        return Double(max(0, remainingBytes)) / speed
    }
}
