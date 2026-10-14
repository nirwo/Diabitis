import UIKit
import XCTest
@testable import BariatricHabits

final class PhotoStoreTests: XCTestCase {
    private var store: PhotoStore!

    override func setUp() {
        store = PhotoStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    private func image(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func test_save_downscales_large_image() throws {
        let name = try store.save(image(width: 8000, height: 6000))
        let data = try XCTUnwrap(store.data(for: name))
        let saved = try XCTUnwrap(UIImage(data: data))
        XCTAssertLessThanOrEqual(max(saved.size.width * saved.scale, saved.size.height * saved.scale), PhotoStore.maxDimension)
        XCTAssertLessThan(data.count, 8 * 1024 * 1024)
    }

    func test_small_image_is_not_upscaled() throws {
        let name = try store.save(image(width: 400, height: 300))
        let saved = try XCTUnwrap(store.image(for: name))
        XCTAssertEqual(saved.size.width * saved.scale, 400)
    }

    func test_delete_removes_file() throws {
        let name = try store.save(image(width: 10, height: 10))
        store.delete(name)
        XCTAssertNil(store.data(for: name))
    }

    func test_missing_file_returns_nil() {
        XCTAssertNil(store.data(for: "nope.jpg"))
    }

    func test_thumbnail_is_downscaled_to_max_pixel() throws {
        let name = try store.save(image(width: 800, height: 600))
        let thumb = try XCTUnwrap(store.thumbnail(for: name, maxPixel: 100))
        XCTAssertLessThanOrEqual(max(thumb.size.width * thumb.scale, thumb.size.height * thumb.scale), 100)
    }

    func test_thumbnail_missing_file_returns_nil() {
        XCTAssertNil(store.thumbnail(for: "nope.jpg"))
    }

    func test_thumbnail_returns_nil_after_delete() throws {
        let name = try store.save(image(width: 400, height: 300))
        XCTAssertNotNil(store.thumbnail(for: name))
        store.delete(name)
        XCTAssertNil(store.thumbnail(for: name))
    }
}
