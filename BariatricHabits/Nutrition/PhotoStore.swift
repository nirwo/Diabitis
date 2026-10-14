import UIKit

enum PhotoStoreError: Error {
    case encodingFailed
}

/// Meal photos as JPEG files in Application Support/photos (never inside state.json).
struct PhotoStore {
    static let maxDimension: CGFloat = 1600
    private static let jpegQuality: CGFloat = 0.7

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

    func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
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
