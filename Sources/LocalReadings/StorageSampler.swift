import Foundation

/// A volume's capacity, with available space as Finder counts it.
public struct StorageSampler: Sampler {
    public var path: String

    /// `path` empty measures the startup volume.
    public init(path: String = "") { self.path = path }

    public mutating func sample(at date: Date) -> StorageReading? {
        let p = path.isEmpty ? "/" : path
        let url = URL(fileURLWithPath: p, isDirectory: true)
        guard let v = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedNameKey,
        ]), let total = v.volumeTotalCapacity, total > 0, let available = v.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return Self.reading(name: v.volumeLocalizedName ?? p, path: p, total: Int64(total), available: available)
    }

    static func reading(name: String, path: String, total: Int64, available: Int64) -> StorageReading {
        let free = max(0, min(total, available))
        let used = total - free
        return StorageReading(volumeName: name, path: path, totalBytes: total, availableBytes: free, usedBytes: used,
                              usedPercent: total > 0 ? Double(used) / Double(total) * 100 : 0)
    }

    /// Mounted local volumes a user would pick from.
    static func volumes() -> [(name: String, path: String)] {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeIsLocalKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.volumeIsLocal == true,
                  v.volumeIsBrowsable != false
            else { return nil }
            return (v.volumeLocalizedName ?? url.lastPathComponent, url.path)
        }
    }
}
