import Foundation

/// Sizes of dropped items, folders included. Runs off the main actor: a big folder takes a while.
enum FileMeasure {
    nonisolated static func isDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }

    /// Finder's own litter, which isn't measured or zipped.
    nonisolated static func isIgnored(_ url: URL) -> Bool {
        url.lastPathComponent == ".DS_Store"
    }

    /// The bytes an upload of these items would send: file sizes, folders summed recursively.
    @concurrent
    nonisolated static func totalSize(of urls: [URL]) async -> Int64 {
        urls.reduce(0) { $0 + size(of: $1) }
    }

    private nonisolated static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        guard isDirectory(url) else {
            return Int64((try? url.resourceValues(forKeys: keys))?.fileSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else {
            return 0
        }
        var total: Int64 = 0
        for case let item as URL in enumerator where !isIgnored(item) {
            guard let values = try? item.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
