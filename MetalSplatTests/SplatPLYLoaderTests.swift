import XCTest
@testable import MetalSplat

final class SplatPLYLoaderTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a minimal valid binary_little_endian PLY with one splat.
    private func makePLY(
        x: Float = 1, y: Float = 2, z: Float = 3,
        opacity: Float = 0,         // raw, sigmoid applied → 0.5
        rot0: Float = 1, rot1: Float = 0, rot2: Float = 0, rot3: Float = 0,
        scale0: Float = 0, scale1: Float = 0, scale2: Float = 0,  // exp(0)=1
        fdc0: Float = 0, fdc1: Float = 0, fdc2: Float = 0
    ) -> Data {
        let props = [
            "x", "y", "z", "opacity",
            "rot_0", "rot_1", "rot_2", "rot_3",
            "scale_0", "scale_1", "scale_2",
            "f_dc_0", "f_dc_1", "f_dc_2"
        ]
        var header = "ply\nformat binary_little_endian 1.0\nelement vertex 1\n"
        for p in props { header += "property float \(p)\n" }
        header += "end_header\n"

        var data = Data(header.utf8)
        for v in [x, y, z, opacity, rot0, rot1, rot2, rot3, scale0, scale1, scale2, fdc0, fdc1, fdc2] {
            withUnsafeBytes(of: v) { data.append(contentsOf: $0) }
        }
        return data
    }

    private func load(_ data: Data) throws -> [GaussianSplatData] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ply")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try SplatPLYLoader.load(url: url)
    }

    // MARK: - Position

    func testPositionXZPreserved() throws {
        let splats = try load(makePLY(x: 1, y: 2, z: 3))
        XCTAssertEqual(splats[0].posX,  1, accuracy: 1e-6)
        XCTAssertEqual(splats[0].posZ,  3, accuracy: 1e-6)
    }

    func testPositionYFlipped() throws {
        // Scaniverse Y-down → loader negates Y
        let splats = try load(makePLY(y: 2))
        XCTAssertEqual(splats[0].posY, -2, accuracy: 1e-6)
    }

    // MARK: - Opacity

    func testOpacitySigmoidZero() throws {
        // sigmoid(0) = 0.5
        let splats = try load(makePLY(opacity: 0))
        XCTAssertEqual(splats[0].opacity, 0.5, accuracy: 1e-5)
    }

    func testOpacityLargePositiveNearOne() throws {
        let splats = try load(makePLY(opacity: 20))
        XCTAssertGreaterThan(splats[0].opacity, 0.99)
    }

    // MARK: - Scale filter

    func testBackgroundSplatFiltered() throws {
        // scale_raw=2.0 → exp(2.0)≈7.39 > 2.72 threshold → dropped
        let splats = try load(makePLY(scale0: 2.0, scale1: 2.0, scale2: 2.0))
        XCTAssertTrue(splats.isEmpty)
    }

    func testNormalSplatNotFiltered() throws {
        // scale_raw=0 → exp(0)=1.0 < 2.72 → kept
        let splats = try load(makePLY(scale0: 0, scale1: 0, scale2: 0))
        XCTAssertEqual(splats.count, 1)
    }

    // MARK: - Color

    func testColorDCToLinearRGB() throws {
        // f_dc=0 → 0.5 + SH_C0*0 = 0.5
        let splats = try load(makePLY(fdc0: 0, fdc1: 0, fdc2: 0))
        XCTAssertEqual(splats[0].colorR, 0.5, accuracy: 1e-5)
        XCTAssertEqual(splats[0].colorG, 0.5, accuracy: 1e-5)
        XCTAssertEqual(splats[0].colorB, 0.5, accuracy: 1e-5)
    }

    func testColorClamped() throws {
        // Very large f_dc → clamp to 1
        let splats = try load(makePLY(fdc0: 1000, fdc1: -1000, fdc2: 0))
        XCTAssertEqual(splats[0].colorR, 1.0, accuracy: 1e-5)
        XCTAssertEqual(splats[0].colorG, 0.0, accuracy: 1e-5)
    }

    // MARK: - Error handling

    func testMissingPropertyThrows() {
        // PLY without opacity property
        let header = "ply\nformat binary_little_endian 1.0\nelement vertex 1\nproperty float x\nproperty float y\nproperty float z\nend_header\n"
        var data = Data(header.utf8)
        for _ in 0..<3 { withUnsafeBytes(of: Float(0)) { data.append(contentsOf: $0) } }
        XCTAssertThrowsError(try load(data))
    }

    func testAsciiFormatThrows() {
        let header = "ply\nformat ascii 1.0\nelement vertex 1\nproperty float x\nend_header\n1.0\n"
        XCTAssertThrowsError(try load(Data(header.utf8)))
    }
}
