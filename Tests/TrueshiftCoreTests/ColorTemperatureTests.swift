import XCTest
@testable import TrueshiftCore

final class ColorTemperatureTests: XCTestCase {

    // MARK: - fromKelvin Tests

    /// At 1000K (firelight), blue should be zero and red should be full
    func testFromKelvin1000() {
        let rgb = GammaRGB.fromKelvin(1000)

        XCTAssertEqual(rgb.red, 1.0, accuracy: 0.01, "Red should be at max for 1000K")
        XCTAssertLessThan(rgb.green, 0.5, "Green should be low for 1000K")
        XCTAssertEqual(rgb.blue, 0.0, accuracy: 0.01, "Blue should be zero for 1000K")
    }

    /// At 2700K (incandescent), warm orange-ish
    func testFromKelvin2700() {
        let rgb = GammaRGB.fromKelvin(2700)

        XCTAssertEqual(rgb.red, 1.0, accuracy: 0.01, "Red should be at max for 2700K")
        XCTAssertGreaterThan(rgb.green, 0.5, "Green should be moderate for 2700K")
        XCTAssertGreaterThan(rgb.blue, 0.3, "Blue should exist but be low for 2700K")
        XCTAssertLessThan(rgb.blue, rgb.green, "Blue should be less than green for 2700K")
    }

    /// At 4000K (neutral white)
    func testFromKelvin4000() {
        let rgb = GammaRGB.fromKelvin(4000)

        XCTAssertEqual(rgb.red, 1.0, accuracy: 0.01, "Red should be at max for 4000K")
        XCTAssertGreaterThan(rgb.green, 0.8, "Green should be high for 4000K")
        XCTAssertGreaterThan(rgb.blue, 0.5, "Blue should be moderate for 4000K")
    }

    /// At 6500K (daylight), all channels should be close to 1.0
    func testFromKelvin6500() {
        let rgb = GammaRGB.fromKelvin(6500)

        XCTAssertGreaterThan(rgb.red, 0.9, "Red should be near max for 6500K")
        XCTAssertGreaterThan(rgb.green, 0.9, "Green should be near max for 6500K")
        XCTAssertGreaterThan(rgb.blue, 0.9, "Blue should be near max for 6500K")
    }

    /// Kelvin values are clamped to valid range
    func testFromKelvinClamping() {
        let tooLow = GammaRGB.fromKelvin(500)
        let atMin = GammaRGB.fromKelvin(1000)

        XCTAssertEqual(tooLow.red, atMin.red, accuracy: 0.01, "Values below 1000K should be clamped")
        XCTAssertEqual(tooLow.green, atMin.green, accuracy: 0.01)
        XCTAssertEqual(tooLow.blue, atMin.blue, accuracy: 0.01)

        let tooHigh = GammaRGB.fromKelvin(50000)
        let atMax = GammaRGB.fromKelvin(40000)

        XCTAssertEqual(tooHigh.red, atMax.red, accuracy: 0.01, "Values above 40000K should be clamped")
        XCTAssertEqual(tooHigh.green, atMax.green, accuracy: 0.01)
        XCTAssertEqual(tooHigh.blue, atMax.blue, accuracy: 0.01)
    }

    // MARK: - Brightness Adjustment Tests

    func testWithBrightnessHalf() {
        let full = GammaRGB.fromKelvin(6500)
        let half = full.withBrightness(0.5)

        XCTAssertEqual(half.red, full.red * 0.5, accuracy: 0.01)
        XCTAssertEqual(half.green, full.green * 0.5, accuracy: 0.01)
        XCTAssertEqual(half.blue, full.blue * 0.5, accuracy: 0.01)
    }

    func testWithBrightnessZero() {
        let full = GammaRGB.fromKelvin(2700)
        let zero = full.withBrightness(0.0)

        XCTAssertEqual(zero.red, 0.0, accuracy: 0.001)
        XCTAssertEqual(zero.green, 0.0, accuracy: 0.001)
        XCTAssertEqual(zero.blue, 0.0, accuracy: 0.001)
    }

    func testWithBrightnessClamping() {
        let full = GammaRGB.fromKelvin(4000)
        let overMax = full.withBrightness(1.5)
        let underMin = full.withBrightness(-0.5)

        // Over max should clamp to 1.0
        XCTAssertEqual(overMax.red, full.red, accuracy: 0.01)
        XCTAssertEqual(overMax.green, full.green, accuracy: 0.01)

        // Under min should clamp to 0.0
        XCTAssertEqual(underMin.red, 0.0, accuracy: 0.01)
        XCTAssertEqual(underMin.green, 0.0, accuracy: 0.01)
    }

    // MARK: - Kelvin Estimation Tests

    func testEstimateKelvinDefault() {
        let rgb = GammaRGB(red: 1.0, green: 1.0, blue: 1.0)
        let kelvin = rgb.estimateKelvin()

        XCTAssertEqual(kelvin, 6500, "All 1.0 should estimate as 6500K (default)")
    }

    func testEstimateKelvinWarm() {
        let rgb = GammaRGB.fromKelvin(2700)
        let estimated = rgb.estimateKelvin()

        XCTAssertNotNil(estimated)
        // Allow some tolerance for reverse calculation
        XCTAssertTrue(abs(estimated! - 2700) <= 200, "Should estimate close to 2700K, got \(estimated!)")
    }

    func testEstimateKelvinCold() {
        let rgb = GammaRGB.fromKelvin(5500)
        let estimated = rgb.estimateKelvin()

        XCTAssertNotNil(estimated)
        XCTAssertTrue(abs(estimated! - 5500) <= 200, "Should estimate close to 5500K, got \(estimated!)")
    }

    func testEstimateKelvinVeryDim() {
        let rgb = GammaRGB(red: 0.001, green: 0.001, blue: 0.001)
        let kelvin = rgb.estimateKelvin()

        XCTAssertNil(kelvin, "Very dim display should return nil")
    }

    // MARK: - Brightness Estimation Tests

    func testEstimateBrightnessFull() {
        let rgb = GammaRGB.fromKelvin(6500)
        let brightness = rgb.estimateBrightness()

        XCTAssertGreaterThanOrEqual(brightness, 95, "Full brightness should be ~100%")
        XCTAssertLessThanOrEqual(brightness, 100)
    }

    func testEstimateBrightnessHalf() {
        let rgb = GammaRGB.fromKelvin(6500).withBrightness(0.5)
        let brightness = rgb.estimateBrightness()

        XCTAssertTrue(abs(brightness - 50) <= 5, "Should estimate ~50% brightness, got \(brightness)")
    }

    // MARK: - Preset Tests

    func testPresetsExist() {
        // Verify presets are valid
        XCTAssertGreaterThan(GammaRGB.daylight.red, 0)
        XCTAssertGreaterThan(GammaRGB.incandescent.red, 0)
        XCTAssertGreaterThan(GammaRGB.evening.red, 0)
        XCTAssertGreaterThan(GammaRGB.night.red, 0)
        XCTAssertGreaterThan(GammaRGB.aggressive.red, 0)
    }

    func testPresetsOrdered() {
        // Daylight should have most blue, aggressive should have least
        XCTAssertGreaterThan(GammaRGB.daylight.blue, GammaRGB.incandescent.blue)
        XCTAssertGreaterThan(GammaRGB.incandescent.blue, GammaRGB.evening.blue)
        XCTAssertGreaterThanOrEqual(GammaRGB.evening.blue, GammaRGB.night.blue)
    }

    // MARK: - Edge Cases

    func testColorTemperatureAtThreshold() {
        // 6600K is right at the algorithm's branching threshold (66 * 100)
        let at66 = GammaRGB.fromKelvin(6600)
        let above66 = GammaRGB.fromKelvin(6700)

        // Both should produce valid colors
        XCTAssertGreaterThan(at66.red, 0)
        XCTAssertGreaterThan(at66.green, 0)
        XCTAssertGreaterThan(at66.blue, 0)

        XCTAssertGreaterThan(above66.red, 0)
        XCTAssertGreaterThan(above66.green, 0)
        XCTAssertGreaterThan(above66.blue, 0)
    }

    func testBlueThreshold() {
        // Blue is 0 at temp <= 19 (1900K)
        let at1900 = GammaRGB.fromKelvin(1900)
        let at2000 = GammaRGB.fromKelvin(2000)

        XCTAssertEqual(at1900.blue, 0.0, accuracy: 0.01, "Blue should be 0 at 1900K")
        XCTAssertGreaterThan(at2000.blue, 0, "Blue should exist at 2000K")
    }
}
