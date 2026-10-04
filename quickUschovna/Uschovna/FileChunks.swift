import Foundation

/// Reads the files being sent, off the main actor: a chunk is up to 10 MiB, and a slow disk or a
/// network volume mustn't stall the menu bar while it's read.
nonisolated enum FileChunks {
    /// `length` bytes from `offset`, or fewer if the file ends sooner.
    @concurrent static func read(_ url: URL, offset: Int64, length: Int) async throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        return try handle.read(upToCount: length) ?? Data()
    }

    /// Each file's size now, or nil where it can't be read.
    @concurrent static func sizes(of urls: [URL]) async -> [Int64?] {
        urls.map { url in
            (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? NSNumber)?
                .int64Value
        }
    }
}
