import ImageIO
import UIKit

enum PhotoStoreError: Error {
    case encodingFailed
}

/// Meal photos as JPEG files in Application Support/photos (never inside state.json).
struct PhotoStore {
    static let maxDimension: CGFloat = 1600
    private static let jpegQuality: CGFloat = 0.7

    /// ~44pt row thumbnail at 3x.
    static let rowThumbnailPixels: CGFloat = 132
    private static let thumbnailCache = NSCache<NSString, UIImage>()

    let directory: URL

    init(directory: URL = PhotoStore.defaultDirectory()) {
        self.directory = directory
    }

    static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("photos", isDirectory: true)
    }

    func save(_ image: UIImage) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = Self.resized(image).jpegData(compressionQuality: Self.jpegQuality) else {
            throw PhotoStoreError.encodingFailed
        }
        let fileName = "\(UUID().uuidString).jpg"
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        return fileName
    }

    func data(for fileName: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(fileName))
    }

    func image(for fileName: String) -> UIImage? {
        data(for: fileName).flatMap(UIImage.init(data:))
    }

    /// Downscaled copy for lists; decoded once per file and size, then served from memory.
    func thumbnail(for fileName: String, maxPixel: CGFloat = PhotoStore.rowThumbnailPixels) -> UIImage? {
        let url = directory.appendingPathComponent(fileName)
        let key = Self.cacheKey(url, maxPixel: maxPixel)
        if let cached = Self.thumbnailCache.object(forKey: key) {
            // A deleted file must not linger in the cache.
            return FileManager.default.fileExists(atPath: url.path) ? cached : nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let thumbnail = UIImage(cgImage: cgImage)
        Self.thumbnailCache.setObject(thumbnail, forKey: key)
        return thumbnail
    }

    func delete(_ fileName: String) {
        let url = directory.appendingPathComponent(fileName)
        Self.thumbnailCache.removeObject(forKey: Self.cacheKey(url, maxPixel: Self.rowThumbnailPixels))
        try? FileManager.default.removeItem(at: url)
    }

    private static func cacheKey(_ url: URL, maxPixel: CGFloat) -> NSString {
        "\(url.path)#\(Int(maxPixel))" as NSString
    }

    /// Redraws at scale 1, which also bakes in the EXIF orientation.
    private static func resized(_ image: UIImage) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let ratio = min(1, maxDimension / max(pixelWidth, pixelHeight))
        let target = CGSize(width: (pixelWidth * ratio).rounded(), height: (pixelHeight * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
