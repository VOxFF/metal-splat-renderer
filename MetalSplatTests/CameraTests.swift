import XCTest
@testable import MetalSplat

final class CameraTests: XCTestCase {

    // MARK: - Orbit

    func testOrbitChangesAzimuthAndElevation() {
        let cam = Camera()
        let az0 = cam.azimuth
        let el0 = cam.elevation
        cam.orbit(dx: 100, dy: 50)
        XCTAssertNotEqual(cam.azimuth, az0)
        XCTAssertNotEqual(cam.elevation, el0)
    }

    func testElevationClampNearPlusPiOver2() {
        let cam = Camera()
        cam.orbit(dx: 0, dy: -100_000)  // large upward drag
        XCTAssertLessThan(cam.elevation, .pi / 2)
    }

    func testElevationClampNearMinusPiOver2() {
        let cam = Camera()
        cam.orbit(dx: 0, dy: 100_000)   // large downward drag
        XCTAssertGreaterThan(cam.elevation, -.pi / 2)
    }

    // MARK: - Dolly

    func testDollyDecreasesRadius() {
        let cam = Camera()
        let r0 = cam.radius
        cam.dolly(delta: 5)
        XCTAssertLessThan(cam.radius, r0)
    }

    func testDollyRespectsMinRadius() {
        let cam = Camera()
        cam.dolly(delta: 1_000_000)
        XCTAssertGreaterThanOrEqual(cam.radius, cam.minRadius)
    }

    // MARK: - Pan

    func testPanMovesTarget() {
        let cam = Camera()
        let t0 = cam.target
        cam.pan(dx: 50, dy: 50)
        XCTAssertNotEqual(cam.target.x, t0.x)
    }

    // MARK: - View matrix

    func testViewMatrixLastColumnIsOneW() {
        let cam = Camera()
        let m = cam.viewMatrix
        // Last column w component must be 1 for an affine view matrix
        XCTAssertEqual(m.columns.3.w, 1.0, accuracy: 1e-5)
    }

    func testPositionDerivedFromAzimuthElevationRadius() {
        let cam = Camera()
        cam.azimuth   = 0
        cam.elevation = 0
        cam.radius    = 10
        cam.target    = .zero
        // elevation=0, azimuth=0 → camera sits on +Z axis
        let pos = cam.position
        XCTAssertEqual(pos.x, 0,  accuracy: 1e-5)
        XCTAssertEqual(pos.y, 0,  accuracy: 1e-5)
        XCTAssertEqual(pos.z, 10, accuracy: 1e-5)
    }
}
