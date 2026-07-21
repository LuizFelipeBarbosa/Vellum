import Foundation

public struct CodableColor: Codable, Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(hex: String, alpha: Double = 1) {
        let value: String
        if hex.hasPrefix("#") {
            value = String(hex.dropFirst())
        } else {
            value = hex
        }

        guard value.count == 6, let rgb = UInt64(value, radix: 16) else {
            self.init(red: 0, green: 0, blue: 0, alpha: alpha)
            return
        }

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }

    public var hexString: String {
        let redByte = Int((red.clampedToColorComponent * 255).rounded())
        let greenByte = Int((green.clampedToColorComponent * 255).rounded())
        let blueByte = Int((blue.clampedToColorComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", redByte, greenByte, blueByte)
    }
}

private extension Double {
    var clampedToColorComponent: Double {
        min(max(self, 0), 1)
    }
}
