import CryptoKit
import Foundation

/// מוסיף חלק לסוף הקובץ המורכב ובודק שנוסף בדיוק גודל החלק.
public func appendPart(
    _ part: URL, expectedSize: Int64, to output: FileHandle,
    progress: ((Int64) -> Void)? = nil, isCancelled: () -> Bool = { false }
) throws {
    let input = try FileHandle(forReadingFrom: part)
    defer { try? input.close() }
    let start = try output.seekToEnd()
    var copied: Int64 = 0
    while true {
        if isCancelled() { throw OperationCancelled() }
        guard let chunk = try input.read(upToCount: ioChunkSize), !chunk.isEmpty else { break }
        try output.write(contentsOf: chunk)
        copied += Int64(chunk.count)
        progress?(copied)
    }
    let end = try output.offset()
    guard copied == expectedSize, Int64(end - start) == expectedSize else {
        throw AssistantError(
            AssistantError.writeJoinedFailed,
            technical: "\(part.lastPathComponent): appended \(copied) of \(expectedSize) bytes"
        )
    }
}

/// מחבר את `parts` לקובץ `destination`, ממשיך הרכבה שנקטעה, ומוחק כל חלק מיד אחרי שנוסף.
/// `partURL` מחזיר את מיקום החלק במטמון; `removePart` מוחק אותו ואת החותם שלו.
public func assembleSplitAsset(
    name: String, size: Int64, sha256: String, parts: [DownloadItem],
    destination: URL, partURL: (DownloadItem) -> URL, removePart: (DownloadItem) -> Void,
    progress: ((Int64) -> Void)? = nil,
    verificationProgress: ((Int64) -> Void)? = nil,
    isCancelled: () -> Bool = { false }
) throws {
    let fileManager = FileManager.default
    let working = destination.deletingLastPathComponent()
        .appendingPathComponent(assemblyPartialName(name: name, sha256: sha256))
    if !fileManager.fileExists(atPath: working.path) {
        guard fileManager.createFile(atPath: working.path, contents: nil) else {
            throw AssistantError(
                AssistantError.copyFailed,
                technical: "cannot create \(working.path)"
            )
        }
    }
    let resume = assemblyResumePoint(partialSize: fileSize(working) ?? 0, partSizes: parts.map { $0.size })
    let output = try FileHandle(forWritingTo: working)
    defer { try? output.close() }
    // חלק שנוסף רק בחלקו נחתך, ומתחילים אותו מחדש.
    try output.truncate(atOffset: UInt64(resume.keepBytes))

    var done = resume.keepBytes
    progress?(done)
    for part in parts.dropFirst(resume.parts) {
        let base = done
        try appendPart(
            partURL(part), expectedSize: part.size, to: output,
            progress: { progress?(base + $0) }, isCancelled: isCancelled
        )
        done += part.size
        removePart(part)
    }
    try output.close()

    guard fileSize(working) == size else {
        throw AssistantError(
            AssistantError.joinedDamaged,
            technical: "\(name): assembled \(fileSize(working) ?? -1) bytes, expected \(size)"
        )
    }
    verificationProgress?(0)
    if hexString(try hashFilePrefix(
        working, length: size, progress: verificationProgress, isCancelled: isCancelled
    ).finalize()) != sha256 {
        try? fileManager.removeItem(at: working)
        throw AssistantError(
            AssistantError.joinedDamaged,
            technical: "\(name): assembled sha256 mismatch"
        )
    }
    if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
    }
    try fileManager.moveItem(at: working, to: destination)
}

/// קישור קשיח מהמטמון (מיידי, בלי מקום נוסף), ובכישלון (כונן אחר) — העתקה בנתחים,
/// כדי שתדווח התקדמות ותיעצר בביטול. עותק חלקי נמחק.
public func placeFile(
    from source: URL, to destination: URL,
    progress: ((Int64) -> Void)? = nil, isCancelled: () -> Bool = { false }
) throws {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
    }
    if (try? fileManager.linkItem(at: source, to: destination)) != nil {
        return
    }
    guard fileManager.createFile(atPath: destination.path, contents: nil) else {
        throw AssistantError(
            AssistantError.copyFailed, technical: "cannot create \(destination.path)"
        )
    }
    do {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var copied: Int64 = 0
        while true {
            if isCancelled() { throw OperationCancelled() }
            guard let chunk = try input.read(upToCount: ioChunkSize), !chunk.isEmpty else { break }
            try output.write(contentsOf: chunk)
            copied += Int64(chunk.count)
            progress?(copied)
        }
        try output.close()
    } catch {
        try? fileManager.removeItem(at: destination)
        throw error
    }
}
