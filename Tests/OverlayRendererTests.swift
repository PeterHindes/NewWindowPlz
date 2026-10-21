import Metal
import XCTest
@testable import NewWindowPlz

final class OverlayRendererTests: XCTestCase {
    func testRendererBuildsPipelineAndTextTextures() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable on this machine")
        }
        let renderer = try OverlayRenderer(device: device)
        XCTAssertFalse(renderer.rendererDescription.isEmpty)
    }

    func testOverlayPreviewRenders() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable on this machine")
        }
        let renderer = try OverlayRenderer(device: device)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewWindowPlz-overlay-preview.png")
        try renderer.writePreview(
            to: url,
            pointSize: CGSize(width: 640, height: 420),
            scale: 1
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertGreaterThan((attributes[.size] as? NSNumber)?.intValue ?? 0, 1_000)
    }
}
