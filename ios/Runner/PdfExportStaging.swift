import Darwin
import Foundation

/// An exclusive, closed export file owned by one operation, never the PDF cache.
/// Directory descriptors keep cleanup inside the validated child even if a path
/// alias changes while UIKit is using the file.
final class PdfExportStaging {
  static let rootName = "otzaria-pdf-exports-v1"

  let operationID: String
  let fileName: String
  let sourceURL: URL
  private let cachesURL: URL
  private let rootDescriptor: Int32
  private let directoryDescriptor: Int32
  private let rootIdentity: stat
  private let directoryIdentity: stat
  private let fileIdentity: stat
  private var closed = false

  static func cachesDirectory() throws -> URL {
    guard let path = NSSearchPathForDirectoriesInDomains(
      .cachesDirectory, .userDomainMask, true
    ).first else {
      throw SourceError.invalidPath
    }
    // This is also path_provider_foundation 2.6.0's iOS temporary directory.
    return URL(fileURLWithPath: path, isDirectory: true)
      .standardizedFileURL.resolvingSymlinksInPath()
  }

  static func validate(
    operationID: String, sourcePath: String, fileName: String,
    cachesDirectory: URL
  ) throws -> PdfExportStaging {
    guard operationID.utf8.count == 32,
      operationID.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil,
      !fileName.isEmpty, fileName.utf8.count <= 255,
      fileName.hasSuffix(".pdf"), fileName != ".pdf",
      !fileName.contains("/"), !fileName.contains("\\"),
      !fileName.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f })
    else { throw SourceError.invalidIdentity }
    guard sourcePath.hasPrefix("/"), !sourcePath.contains("\0") else {
      throw SourceError.invalidPath
    }

    let caches = cachesDirectory.standardizedFileURL.resolvingSymlinksInPath()
    let expected = caches.appendingPathComponent(rootName, isDirectory: true)
      .appendingPathComponent(operationID, isDirectory: true)
      .appendingPathComponent(fileName, isDirectory: false)
    let supplied = URL(fileURLWithPath: sourcePath).standardizedFileURL
      .resolvingSymlinksInPath()
    guard supplied == expected else { throw SourceError.invalidPath }

    let cachesFD = open(caches.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard cachesFD >= 0 else { throw SourceError.unreadableSource }
    defer { close(cachesFD) }
    let rootFD = openat(cachesFD, rootName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard rootFD >= 0 else { throw SourceError.invalidPath }
    var retainRoot = false
    defer { if !retainRoot { close(rootFD) } }
    let directoryFD = openat(
      rootFD, operationID, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    )
    guard directoryFD >= 0 else { throw SourceError.invalidPath }
    var retainDirectory = false
    defer { if !retainDirectory { close(directoryFD) } }
    // Reject a FIFO without waiting for a writer on the UIKit thread.
    let fileFD = openat(directoryFD, fileName, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
    guard fileFD >= 0 else { throw SourceError.unreadableSource }
    defer { close(fileFD) }
    var rootInformation = stat()
    var directoryInformation = stat()
    var fileInformation = stat()
    guard fstat(rootFD, &rootInformation) == 0,
      fstat(directoryFD, &directoryInformation) == 0,
      fstat(fileFD, &fileInformation) == 0,
      fileInformation.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
      fileInformation.st_nlink == 1, fileInformation.st_size > 0
    else { throw SourceError.unreadableSource }
    retainRoot = true
    retainDirectory = true
    return PdfExportStaging(
      operationID: operationID, fileName: fileName, sourceURL: expected,
      cachesURL: caches,
      rootDescriptor: rootFD, directoryDescriptor: directoryFD,
      rootIdentity: rootInformation,
      directoryIdentity: directoryInformation, fileIdentity: fileInformation
    )
  }

  private init(
    operationID: String, fileName: String, sourceURL: URL, cachesURL: URL,
    rootDescriptor: Int32, directoryDescriptor: Int32,
    rootIdentity: stat, directoryIdentity: stat, fileIdentity: stat
  ) {
    self.operationID = operationID
    self.fileName = fileName
    self.sourceURL = sourceURL
    self.cachesURL = cachesURL
    self.rootDescriptor = rootDescriptor
    self.directoryDescriptor = directoryDescriptor
    self.rootIdentity = rootIdentity
    self.directoryIdentity = directoryIdentity
    self.fileIdentity = fileIdentity
  }

  /// Called only after the picker is terminal. No recursive/path-based delete.
  /// A competing replacement or an unexpected child is preserved, not swept.
  func cleanup() -> String? {
    guard !closed else { return nil }
    defer { closeDescriptors() }
    // Dart also owns a fallback cleanup by pathname. If the visible root was
    // replaced, report refusal even though our old descriptors remain safe.
    // The shared refusal prefix prevents Dart from deleting the replacement.
    let currentCaches = open(cachesURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard currentCaches >= 0 else { return cleanupFailure("caches_open", errno) }
    defer { close(currentCaches) }
    var currentRoot = stat()
    guard fstatat(currentCaches, Self.rootName, &currentRoot, AT_SYMLINK_NOFOLLOW) == 0 else {
      return cleanupFailure("root_stat", errno)
    }
    guard sameFile(currentRoot, rootIdentity),
      currentRoot.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
    else { return "staging_cleanup_failed: root_replaced" }
    var currentDirectory = stat()
    if fstatat(rootDescriptor, operationID, &currentDirectory, AT_SYMLINK_NOFOLLOW) != 0 {
      return errno == ENOENT ? nil : cleanupFailure("directory_stat", errno)
    }
    guard sameFile(currentDirectory, directoryIdentity),
      currentDirectory.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
    else { return "staging_cleanup_failed: operation_directory_replaced" }
    var currentFile = stat()
    if fstatat(directoryDescriptor, fileName, &currentFile, AT_SYMLINK_NOFOLLOW) == 0 {
      guard sameFile(currentFile, fileIdentity),
        currentFile.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
      else { return "staging_cleanup_failed: source_replaced" }
      if unlinkat(directoryDescriptor, fileName, 0) != 0 && errno != ENOENT {
        return cleanupFailure("source_unlink", errno)
      }
    } else if errno != ENOENT {
      return cleanupFailure("source_stat", errno)
    }
    if unlinkat(rootDescriptor, operationID, AT_REMOVEDIR) != 0 && errno != ENOENT {
      return cleanupFailure("directory_unlink", errno)
    }
    return nil
  }

  private func sameFile(_ left: stat, _ right: stat) -> Bool {
    left.st_dev == right.st_dev && left.st_ino == right.st_ino
  }

  private func cleanupFailure(_ stage: String, _ code: Int32) -> String {
    "staging_cleanup_failed: \(stage) (errno \(code))"
  }

  private func closeDescriptors() {
    guard !closed else { return }
    closed = true
    close(directoryDescriptor)
    close(rootDescriptor)
  }

  deinit { closeDescriptors() }

  enum SourceError: Error {
    case invalidIdentity
    case invalidPath
    case unreadableSource
  }
}
