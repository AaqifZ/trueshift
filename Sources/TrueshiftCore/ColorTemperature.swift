// ColorTemperature.swift
// Converts color temperature (Kelvin) to RGB gamma values

import Foundation

/// Represents RGB values for gamma correction (0.0 - 1.0 range)
public struct GammaRGB {
    public let red: Float
    public let green: Float
    public let blue: Float

    public init(red: Float, green: Float, blue: Float) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Creates gamma values from color temperature in Kelvin
    /// Algorithm based on Tanner Helland's work, adapted for gamma tables
    /// Reference: https://tannerhelland.com/2012/09/18/convert-temperature-rgb-algorithm-code.html
    public static func fromKelvin(_ kelvin: Int) -> GammaRGB {
        let temp = Double(max(1000, min(40000, kelvin))) / 100.0

        var red: Double
        var green: Double
        var blue: Double

        // Calculate Red
        if temp <= 66 {
            red = 255
        } else {
            red = temp - 60
            red = 329.698727446 * pow(red, -0.1332047592)
            red = max(0, min(255, red))
        }

        // Calculate Green
        if temp <= 66 {
            green = temp
            green = 99.4708025861 * log(green) - 161.1195681661
            green = max(0, min(255, green))
        } else {
            green = temp - 60
            green = 288.1221695283 * pow(green, -0.0755148492)
            green = max(0, min(255, green))
        }

        // Calculate Blue
        if temp >= 66 {
            blue = 255
        } else if temp <= 19 {
            blue = 0
        } else {
            blue = temp - 10
            blue = 138.5177312231 * log(blue) - 305.0447927307
            blue = max(0, min(255, blue))
        }

        // Normalize to 0.0 - 1.0 range for gamma tables
        return GammaRGB(
            red: Float(red / 255.0),
            green: Float(green / 255.0),
            blue: Float(blue / 255.0)
        )
    }

    /// Apply brightness adjustment (0.0 - 1.0)
    public func withBrightness(_ brightness: Float) -> GammaRGB {
        let b = max(0.0, min(1.0, brightness))
        return GammaRGB(
            red: red * b,
            green: green * b,
            blue: blue * b
        )
    }

    /// Estimate color temperature from gamma values
    /// Returns approximate Kelvin value, or nil if gamma is at default (1,1,1)
    public func estimateKelvin() -> Int? {
        // If all channels are at 1.0, display is at default (no gamma applied)
        if red >= 0.99 && green >= 0.99 && blue >= 0.99 {
            return 6500 // Default/neutral
        }

        // Estimate brightness from the max channel
        let brightness = max(red, max(green, blue))
        if brightness < 0.01 {
            return nil // Display is essentially off
        }

        // Normalize to remove brightness factor
        let normRed = red / brightness
        let normGreen = green / brightness
        let normBlue = blue / brightness

        // Search for closest matching temperature
        var bestKelvin = 6500
        var bestDistance: Float = Float.infinity

        for kelvin in stride(from: 1000, through: 6500, by: 100) {
            let ref = GammaRGB.fromKelvin(kelvin)
            let distance = pow(normRed - ref.red, 2) +
                          pow(normGreen - ref.green, 2) +
                          pow(normBlue - ref.blue, 2)
            if distance < bestDistance {
                bestDistance = distance
                bestKelvin = kelvin
            }
        }

        return bestKelvin
    }

    /// Estimate brightness percentage from gamma values
    public func estimateBrightness() -> Int {
        let brightness = max(red, max(green, blue))
        return Int(brightness * 100)
    }
}

// MARK: - Temperature Presets

extension GammaRGB {
    /// Standard presets based on Jack Kruse recommendations
    public static let daylight = fromKelvin(5500)      // Natural daylight
    public static let incandescent = fromKelvin(2700)  // Warm bulb
    public static let evening = fromKelvin(1200)       // Post-sunset
    public static let night = fromKelvin(1000)         // Firelight
    public static let aggressive = fromKelvin(100)     // Unusable red (power-down)
}
