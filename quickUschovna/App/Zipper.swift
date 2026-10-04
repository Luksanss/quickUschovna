import Foundation
import os
import zlib

/// Zips a dropped folder into one archive before upload, the way Finder's Compress would, but
/// without compression: what people send through Úschovna is mostly video and photos, which don't
/// shrink, and storing keeps zipping as fast as the disk.
///
/// It writes the archive itself rather than calling `/usr/bin/zip` or `ditto`: Apple's `zip` can't
/// mark names as UTF-8, so a Czech name like "Natáčení" arrives garbled on Windows, and `ditto`
/// with compression level 0 still deflates and writes archives over 4 GB that `zipinfo` reports
/// as damaged (both checked on 2026-10-04). Here every name is NFC with the UTF-8 flag, sizes and
/// offsets over 4 GB use ZIP64, and the progress is exact.
enum Zipper {
    struct Archive {
        let url: URL
        let size: Int64
    }

    nonisolated enum ZipError: Error {
        case cannotCreate(URL)
    }

    private static let logger = Logger(subsystem: "com.luksanss.quickUschovna", category: "zip")

    /// Where a package's archives go until it's sent or cancelled.
    nonisolated static func directory(for packageID: UUID) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "quickUschovna", directoryHint: .isDirectory)
            .appending(path: packageID.uuidString, directoryHint: .isDirectory)
    }

    static func removeArchives(for packageID: UUID) {
        try? FileManager.default.removeItem(at: directory(for: packageID))
    }

    /// Zips `folder` as "<name>.zip" with the folder itself at the top of the archive. `progress`
    /// gets the bytes of file content written so far, a few times a second.
    static func zip(folder: URL, packageID: UUID,
                    progress: @escaping @MainActor (Int64) -> Void) async throws -> Archive {
        let directory = directory(for: packageID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: folder.lastPathComponent + ".zip")
        let size = try await write(folder: folder, to: destination, progress: progress)
        logger.info("Zipped a folder into \(size, privacy: .public) bytes")
        return Archive(url: destination, size: size)
    }

    @concurrent
    private nonisolated static func write(folder: URL, to destination: URL,
                                          progress: @escaping @MainActor (Int64) -> Void) async throws -> Int64 {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let output = try? FileHandle(forWritingTo: destination) else { throw ZipError.cannotCreate(destination) }
        defer { try? output.close() }
        var writer = ZipWriter(output: output)
        var reporter = ProgressReporter(progress: progress)
        let root = folder.lastPathComponent
        for entry in entries(in: folder) {
            try Task.checkCancellation()
            let path = entry.relativePath.isEmpty ? root : root + "/" + entry.relativePath
            switch entry.kind {
            case .directory:
                try writer.addDirectory(path: path, modified: entry.modified)
            case .symlink(let target):
                try writer.addSymlink(path: path, target: target, modified: entry.modified)
            case .file:
                try writer.addFile(path: path, from: entry.url, modified: entry.modified, permissions: entry.permissions) { written in
                    reporter.add(written)
                }
            }
        }
        try writer.finish()
        reporter.flush()
        return Int64(try output.offset())
    }

    private nonisolated struct Entry {
        enum Kind { case directory, file, symlink(String) }
        let url: URL
        let relativePath: String
        let kind: Kind
        let modified: Date
        let permissions: UInt16
    }

    /// The folder and everything in it, parents before children, without `.DS_Store` files.
    private nonisolated static func entries(in folder: URL) -> [Entry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        var result = [entry(for: folder, relativePath: "", keys: keys)].compactMap { $0 }
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else {
            return result
        }
        let base = folder.standardizedFileURL.path.count + 1
        for case let url as URL in enumerator where !FileMeasure.isIgnored(url) {
            let relative = String(url.standardizedFileURL.path.dropFirst(base))
            if let entry = entry(for: url, relativePath: relative, keys: keys) { result.append(entry) }
        }
        return result
    }

    private nonisolated static func entry(for url: URL, relativePath: String, keys: [URLResourceKey]) -> Entry? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        let modified = values.contentModificationDate ?? .now
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = UInt16((attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0o644) & 0o7777
        if values.isSymbolicLink == true {
            guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else { return nil }
            return Entry(url: url, relativePath: relativePath, kind: .symlink(target), modified: modified, permissions: 0o755)
        }
        let kind: Entry.Kind = values.isDirectory == true ? .directory : .file
        return Entry(url: url, relativePath: relativePath, kind: kind, modified: modified, permissions: permissions)
    }

    /// Hands the running total to the main actor at most ten times a second.
    private nonisolated struct ProgressReporter {
        let progress: @MainActor (Int64) -> Void
        var total: Int64 = 0
        var lastReport = Date.distantPast

        mutating func add(_ bytes: Int) {
            total += Int64(bytes)
            if Date.now.timeIntervalSince(lastReport) >= 0.1 { flush() }
        }

        mutating func flush() {
            lastReport = .now
            let total = total, progress = progress
            Task { @MainActor in progress(total) }
        }
    }
}

/// A store-only ZIP writer with ZIP64 and UTF-8 names. Each file's CRC is computed while its bytes
/// are copied, then patched into its local header, so no data descriptors are needed and every
/// unzip tool can read the result.
private nonisolated struct ZipWriter {
    private struct CentralEntry {
        let name: Data
        let crc: UInt32
        let size: UInt64
        let offset: UInt64
        let dosTime: UInt16
        let dosDate: UInt16
        let externalAttributes: UInt32
    }

    private let output: FileHandle
    private var entries: [CentralEntry] = []
    private static let chunkSize = 8 << 20
    private static let utf8Flag: UInt16 = 1 << 11
    private static let unixHost: UInt16 = 3 << 8
    private static let zip64Version: UInt16 = 45
    private static let baseVersion: UInt16 = 20
    private static let max32 = UInt64(UInt32.max)

    init(output: FileHandle) {
        self.output = output
    }

    mutating func addDirectory(path: String, modified: Date) throws {
        try add(name: path + "/", modified: modified, mode: 0o040755, dosAttributes: 0x10, size: 0) { _ in 0 }
    }

    mutating func addSymlink(path: String, target: String, modified: Date) throws {
        let data = Data(target.utf8)
        try add(name: path, modified: modified, mode: 0o120755, dosAttributes: 0, size: UInt64(data.count)) { output in
            try output.write(contentsOf: data)
            return UInt32(data.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count)) })
        }
    }

    mutating func addFile(path: String, from url: URL, modified: Date, permissions: UInt16,
                          written: (Int) -> Void) throws {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        let size = try input.seekToEnd()
        try input.seek(toOffset: 0)
        try add(name: path, modified: modified, mode: 0o100000 | UInt32(permissions), dosAttributes: 0, size: size) { output in
            var crc = crc32(0, nil, 0)
            var copied: UInt64 = 0
            while copied < size {
                try Task.checkCancellation()
                guard let data = try input.read(upToCount: Self.chunkSize), !data.isEmpty else { break }
                crc = data.withUnsafeBytes { crc32(crc, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count)) }
                try output.write(contentsOf: data)
                copied += UInt64(data.count)
                written(data.count)
            }
            // A file that shrank while it was read would leave the header's size wrong.
            guard copied == size else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url]) }
            return UInt32(crc)
        }
    }

    /// Writes one entry: the local header with the CRC left at zero, the content, then the CRC.
    private mutating func add(name: String, modified: Date, mode: UInt32, dosAttributes: UInt32, size: UInt64,
                              content: (FileHandle) throws -> UInt32) throws {
        let nameData = Data(name.precomposedStringWithCanonicalMapping.utf8)
        let offset = try output.offset()
        let (dosTime, dosDate) = Self.dosDateTime(modified)
        let needsZip64 = size >= Self.max32
        var header = Data()
        header.append(le: UInt32(0x04034b50))
        header.append(le: needsZip64 ? Self.zip64Version : Self.baseVersion)
        header.append(le: Self.utf8Flag)
        header.append(le: UInt16(0)) // stored
        header.append(le: dosTime)
        header.append(le: dosDate)
        header.append(le: UInt32(0)) // CRC, patched below
        header.append(le: needsZip64 ? UInt32.max : UInt32(size))
        header.append(le: needsZip64 ? UInt32.max : UInt32(size))
        header.append(le: UInt16(nameData.count))
        header.append(le: UInt16(needsZip64 ? 20 : 0))
        header.append(nameData)
        if needsZip64 {
            header.append(le: UInt16(0x0001))
            header.append(le: UInt16(16))
            header.append(le: size)
            header.append(le: size)
        }
        try output.write(contentsOf: header)
        let crc = try content(output)
        let end = try output.offset()
        try output.seek(toOffset: offset + 14)
        var crcData = Data()
        crcData.append(le: crc)
        try output.write(contentsOf: crcData)
        try output.seek(toOffset: end)
        entries.append(CentralEntry(name: nameData, crc: crc, size: size, offset: offset, dosTime: dosTime,
                                    dosDate: dosDate, externalAttributes: (mode << 16) | dosAttributes))
    }

    func finish() throws {
        let directoryOffset = try output.offset()
        var directory = Data()
        for entry in entries {
            let sizeOverflows = entry.size >= Self.max32
            let offsetOverflows = entry.offset >= Self.max32
            var extra = Data()
            if sizeOverflows {
                extra.append(le: entry.size)
                extra.append(le: entry.size)
            }
            if offsetOverflows { extra.append(le: entry.offset) }
            if !extra.isEmpty {
                var field = Data()
                field.append(le: UInt16(0x0001))
                field.append(le: UInt16(extra.count))
                extra = field + extra
            }
            let version = extra.isEmpty ? Self.baseVersion : Self.zip64Version
            directory.append(le: UInt32(0x02014b50))
            directory.append(le: Self.unixHost | Self.zip64Version)
            directory.append(le: version)
            directory.append(le: Self.utf8Flag)
            directory.append(le: UInt16(0))
            directory.append(le: entry.dosTime)
            directory.append(le: entry.dosDate)
            directory.append(le: entry.crc)
            directory.append(le: sizeOverflows ? UInt32.max : UInt32(entry.size))
            directory.append(le: sizeOverflows ? UInt32.max : UInt32(entry.size))
            directory.append(le: UInt16(entry.name.count))
            directory.append(le: UInt16(extra.count))
            directory.append(le: UInt16(0)) // comment
            directory.append(le: UInt16(0)) // disk
            directory.append(le: UInt16(0)) // internal attributes
            directory.append(le: entry.externalAttributes)
            directory.append(le: offsetOverflows ? UInt32.max : UInt32(entry.offset))
            directory.append(entry.name)
            directory.append(extra)
        }
        try output.write(contentsOf: directory)
        let directorySize = UInt64(directory.count)
        let count = UInt64(entries.count)
        var end = Data()
        let needsZip64 = count >= 0xFFFF || directoryOffset >= Self.max32 || directorySize >= Self.max32
        if needsZip64 {
            let zip64EndOffset = directoryOffset + directorySize
            end.append(le: UInt32(0x06064b50))
            end.append(le: UInt64(44))
            end.append(le: Self.unixHost | Self.zip64Version)
            end.append(le: Self.zip64Version)
            end.append(le: UInt32(0))
            end.append(le: UInt32(0))
            end.append(le: count)
            end.append(le: count)
            end.append(le: directorySize)
            end.append(le: directoryOffset)
            end.append(le: UInt32(0x07064b50))
            end.append(le: UInt32(0))
            end.append(le: zip64EndOffset)
            end.append(le: UInt32(1))
        }
        end.append(le: UInt32(0x06054b50))
        end.append(le: UInt16(0))
        end.append(le: UInt16(0))
        end.append(le: needsZip64 ? UInt16.max : UInt16(count))
        end.append(le: needsZip64 ? UInt16.max : UInt16(count))
        end.append(le: needsZip64 ? UInt32.max : UInt32(directorySize))
        end.append(le: needsZip64 ? UInt32.max : UInt32(directoryOffset))
        end.append(le: UInt16(0))
        try output.write(contentsOf: end)
    }

    /// MS-DOS time and date in local time, which is what unzip tools show. Clamped to 1980, the
    /// earliest the format can hold.
    private static func dosDateTime(_ date: Date) -> (time: UInt16, date: UInt16) {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, parts.year ?? 1980)
        let time = UInt16((parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2)
        let day = UInt16((year - 1980) << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1))
        return (time, day)
    }
}

private nonisolated extension Data {
    mutating func append<T: FixedWidthInteger>(le value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
