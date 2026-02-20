import UIKit

@MainActor
final class ImageCacheService {

    // MARK: - Memory Caches

    private let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        return cache
    }()

    private let fullSizeCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 20
        return cache
    }()

    // MARK: - Disk Cache

    private let cacheDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("ImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let maxDiskBytes: Int = 200 * 1024 * 1024 // 200 MB
    private static let evictionTarget: Double = 0.75

    // MARK: - Download Deduplication

    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]

    // MARK: - LRU Debounce

    private var lastEvictionCheck: Date = .distantPast

    // MARK: - Disk I/O Queue

    private let diskQueue = DispatchQueue(label: "com.grandmawantspics.imagecache.disk")

    // MARK: - Public API

    func loadImage(for photo: Photo, thumbnail: Bool, using store: FamilyStore) async -> UIImage? {
        let cacheKey = photo.id as NSString
        let memoryCache = thumbnail ? thumbnailCache : fullSizeCache

        // 1. Memory cache hit
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }

        // 2. Disk cache hit
        let cachedPath = diskPath(for: photo.id, thumbnail: thumbnail)
        if let diskImage = await loadFromDisk(path: cachedPath) {
            memoryCache.setObject(diskImage, forKey: cacheKey)
            touchFile(at: cachedPath) // update modification date for LRU
            return diskImage
        }

        // 3. If requesting thumbnail and we have a full-size on disk, generate thumbnail from it
        if thumbnail {
            let fullPath = diskPath(for: photo.id, thumbnail: false)
            if let fullImage = await loadFromDisk(path: fullPath) {
                let thumb = fullImage.resizedThumbnail(maxDimension: 300)
                memoryCache.setObject(thumb, forKey: cacheKey)
                await saveToDisk(thumb, path: cachedPath, quality: 0.7)
                // Also promote full-size to memory
                fullSizeCache.setObject(fullImage, forKey: cacheKey)
                touchFile(at: fullPath)
                return thumb
            }
        }

        // 4. Download from network (deduplicated)
        return await downloadAndCache(photo: photo, thumbnail: thumbnail, using: store)
    }

    func evict(photoId: String) {
        let key = photoId as NSString
        thumbnailCache.removeObject(forKey: key)
        fullSizeCache.removeObject(forKey: key)

        let thumbPath = diskPath(for: photoId, thumbnail: true)
        let fullPath = diskPath(for: photoId, thumbnail: false)
        diskQueue.async {
            try? FileManager.default.removeItem(at: thumbPath)
            try? FileManager.default.removeItem(at: fullPath)
        }
    }

    func evictExpired(photos: [Photo]) {
        let validIds = Set(photos.map(\.id))
        diskQueue.async { [cacheDirectory] in
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else { return }
            for file in files {
                let name = file.deletingPathExtension().lastPathComponent
                // Filenames are {id}_thumb or {id}_full
                let photoId = name.replacingOccurrences(of: "_thumb", with: "")
                    .replacingOccurrences(of: "_full", with: "")
                if !validIds.contains(photoId) {
                    try? fm.removeItem(at: file)
                }
            }
        }
    }

    func clearAll() {
        thumbnailCache.removeAllObjects()
        fullSizeCache.removeAllObjects()
        inFlightTasks.values.forEach { $0.cancel() }
        inFlightTasks.removeAll()

        diskQueue.async { [cacheDirectory] in
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else { return }
            for file in files {
                try? fm.removeItem(at: file)
            }
        }
    }

    // MARK: - Private

    private func downloadAndCache(photo: Photo, thumbnail: Bool, using store: FamilyStore) async -> UIImage? {
        let taskKey = photo.id

        // Deduplicate: if a download is already in-flight, await it
        if let existing = inFlightTasks[taskKey] {
            let fullImage = await existing.value
            if thumbnail, let fullImage {
                return thumbnailFromFull(fullImage, photoId: photo.id)
            }
            return fullImage
        }

        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            guard let data = try? await store.loadImageData(for: photo),
                  let image = UIImage(data: data) else {
                return nil
            }

            let cacheKey = photo.id as NSString

            // Save full-size to memory + disk
            self.fullSizeCache.setObject(image, forKey: cacheKey)
            let fullPath = self.diskPath(for: photo.id, thumbnail: false)
            await self.saveToDisk(image, path: fullPath, quality: 0.95)

            // Generate and save thumbnail
            let thumb = image.resizedThumbnail(maxDimension: 300)
            self.thumbnailCache.setObject(thumb, forKey: cacheKey)
            let thumbPath = self.diskPath(for: photo.id, thumbnail: true)
            await self.saveToDisk(thumb, path: thumbPath, quality: 0.7)

            // LRU eviction check (debounced)
            await self.evictDiskIfNeeded()

            return image
        }

        inFlightTasks[taskKey] = task
        let fullImage = await task.value
        inFlightTasks[taskKey] = nil

        if thumbnail, let fullImage {
            return thumbnailFromFull(fullImage, photoId: photo.id)
        }
        return fullImage
    }

    private func thumbnailFromFull(_ fullImage: UIImage, photoId: String) -> UIImage {
        let key = photoId as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        let thumb = fullImage.resizedThumbnail(maxDimension: 300)
        thumbnailCache.setObject(thumb, forKey: key)
        return thumb
    }

    // MARK: - Disk Helpers

    private func diskPath(for photoId: String, thumbnail: Bool) -> URL {
        let suffix = thumbnail ? "_thumb" : "_full"
        return cacheDirectory.appendingPathComponent("\(photoId)\(suffix).jpg")
    }

    private func loadFromDisk(path: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            diskQueue.async {
                if let data = try? Data(contentsOf: path),
                   let image = UIImage(data: data) {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func saveToDisk(_ image: UIImage, path: URL, quality: CGFloat) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            diskQueue.async {
                if let data = image.jpegData(compressionQuality: quality) {
                    try? data.write(to: path, options: .atomic)
                }
                continuation.resume()
            }
        }
    }

    private func touchFile(at url: URL) {
        diskQueue.async {
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: url.path
            )
        }
    }

    private func evictDiskIfNeeded() async {
        let now = Date()
        guard now.timeIntervalSince(lastEvictionCheck) > 30 else { return }
        lastEvictionCheck = now

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            diskQueue.async { [cacheDirectory] in
                let fm = FileManager.default
                guard let files = try? fm.contentsOfDirectory(
                    at: cacheDirectory,
                    includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
                ) else {
                    continuation.resume()
                    return
                }

                var totalSize = 0
                var fileInfos: [(url: URL, date: Date, size: Int)] = []

                for file in files {
                    guard let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                          let date = attrs.contentModificationDate,
                          let size = attrs.fileSize else { continue }
                    totalSize += size
                    fileInfos.append((url: file, date: date, size: size))
                }

                guard totalSize > Self.maxDiskBytes else {
                    continuation.resume()
                    return
                }

                // Sort oldest first
                fileInfos.sort { $0.date < $1.date }
                let target = Int(Double(Self.maxDiskBytes) * Self.evictionTarget)

                while totalSize > target, let oldest = fileInfos.first {
                    fileInfos.removeFirst()
                    try? fm.removeItem(at: oldest.url)
                    totalSize -= oldest.size
                }

                continuation.resume()
            }
        }
    }
}

// MARK: - UIImage Thumbnail Extension

private extension UIImage {
    func resizedThumbnail(maxDimension: CGFloat) -> UIImage {
        let currentMax = max(size.width, size.height)
        guard currentMax > maxDimension else { return self }

        let scale = maxDimension / currentMax
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
