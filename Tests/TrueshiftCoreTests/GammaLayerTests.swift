// GammaLayerTests.swift
// Pure math tests for the residual gamma layer

import XCTest
@testable import TrueshiftCore

final class GammaLayerTests: XCTestCase {

    func testResidualIsIdentityAt2700AndAbove() {
        for kelvin in [2700, 3500, 5500, 6500] {
            let g = GammaLayer.residual(forTarget: kelvin)
            XCTAssertEqual(g.red, 1.0, accuracy: 0.01, "red at \(kelvin)K")
            XCTAssertEqual(g.green, 1.0, accuracy: 0.05, "green at \(kelvin)K")
            XCTAssertEqual(g.blue, 1.0, accuracy: 0.05, "blue at \(kelvin)K")
        }
    }

    func testResidualDeepensBelow2700() {
        let g = GammaLayer.residual(forTarget: 1000)
        // Red channel stays full — deep red, not dimming
        XCTAssertEqual(g.red, 1.0, accuracy: 0.01)
        // Green substantially reduced, blue essentially gone
        XCTAssertLessThan(g.green, 0.6)
        XCTAssertLessThan(g.blue, 0.05)
    }

    func testResidualIsMonotonicInKelvin() {
        // Warmer target → smaller green/blue residual
        var previousGreen: Float = 0
        var previousBlue: Float = 0
        for kelvin in stride(from: 1000, through: 2700, by: 100) {
            let g = GammaLayer.residual(forTarget: kelvin)
            XCTAssertGreaterThanOrEqual(g.green + 0.001, previousGreen, "green fell at \(kelvin)K")
            XCTAssertGreaterThanOrEqual(g.blue + 0.001, previousBlue, "blue fell at \(kelvin)K")
            previousGreen = g.green
            previousBlue = g.blue
        }
    }

    func testResidualClampsInput() {
        let low = GammaLayer.residual(forTarget: 500)
        let ref = GammaLayer.residual(forTarget: 1000)
        XCTAssertEqual(low.green, ref.green, accuracy: 0.001)

        let high = GammaLayer.residual(forTarget: 9000)
        XCTAssertEqual(high.red, 1.0, accuracy: 0.01)
        XCTAssertEqual(high.green, 1.0, accuracy: 0.05)
    }

    func testChannelsNeverExceedOne() {
        for kelvin in stride(from: 1000, through: 6500, by: 250) {
            let g = GammaLayer.residual(forTarget: kelvin)
            XCTAssertLessThanOrEqual(g.red, 1.0)
            XCTAssertLessThanOrEqual(g.green, 1.0)
            XCTAssertLessThanOrEqual(g.blue, 1.0)
        }
    }
}
