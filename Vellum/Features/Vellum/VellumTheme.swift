import SwiftUI
import VellumCore
import UIKit

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
        switch cleaned.count {
        case 8:
            red = Double((value >> 24) & 0xff) / 255
            green = Double((value >> 16) & 0xff) / 255
            blue = Double((value >> 8) & 0xff) / 255
            alpha = Double(value & 0xff) / 255
        default:
            red = Double((value >> 16) & 0xff) / 255
            green = Double((value >> 8) & 0xff) / 255
            blue = Double(value & 0xff) / 255
            alpha = 1
        }
        self = Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

enum VellumTheme {
    static let paper = Color(hex: "#F6F2E9")
    static let ink = Color(hex: "#26221B")
    static let accent = Color(hex: "#9A6B35")
    static let accentDark = Color(hex: "#8A5A28")
    static let card = Color(hex: "#FBF8F1")
    static let popover = Color(hex: "#FFFDF8")
    static let libraryBody = Color(hex: "#FDFBF6")
    static let stripeCard = Color(hex: "#F1EDE2")
    static let muted = Color(hex: "#9C927E")
    static let mutedCount = Color(hex: "#A99F8B")
    static let mutedControl = Color(hex: "#8B8272")
    static let mutedDark = Color(hex: "#7A7264")
    static let bodyMuted = Color(hex: "#4A4438")
    static let bodyInk = Color(hex: "#33302A")
    static let waveform = Color(hex: "#B9AE97")
    static let toolbarMarker = Color(hex: "#C9BFA8")
    static let dottedUnderline = Color(hex: "#B98A4E")
    static let studio = Color(hex: "#9A6B35")
    static let thesis = Color(hex: "#4E6E58")
    static let team = Color(hex: "#6E5E7A")
    static let reading = Color(hex: "#8A6E4B")
    static let spaceRed = Color(hex: "#955B52")
    static let spaceTeal = Color(hex: "#4F7470")
    static let spaceBlue = Color(hex: "#586E82")
    static let spacePink = Color(hex: "#936B76")
    static let spaceGray = Color(hex: "#7B776E")

    static func ink(_ opacity: Double) -> Color { ink.opacity(opacity) }
    static func accent(_ opacity: Double) -> Color { accent.opacity(opacity) }
    static func paper(_ opacity: Double) -> Color { paper.opacity(opacity) }

    static func color(for spaceColor: SpaceColor) -> Color {
        switch spaceColor {
        case .red: spaceRed
        case .orange: studio
        case .yellow: reading
        case .green: thesis
        case .teal: spaceTeal
        case .blue: spaceBlue
        case .purple: team
        case .pink: spacePink
        case .gray: spaceGray
        }
    }
}

extension Font {
    static func vellumNewsreader(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        italic: Bool = false
    ) -> Font {
        let candidates = italic
            ? ["Newsreader", "Newsreader16pt-Italic", "NewsreaderItalic-Regular"]
            : ["Newsreader", "Newsreader16pt-Regular", "Newsreader-Regular"]
        if candidates.contains(where: { UIFont(name: $0, size: size) != nil }) {
            let font = Font.custom(
                candidates.first(where: { UIFont(name: $0, size: size) != nil })!,
                fixedSize: size
            ).weight(weight)
            return italic ? font.italic() : font
        }
        let fallback = Font.system(size: size, weight: weight, design: .serif)
        return italic ? fallback.italic() : fallback
    }

    static func vellumCaveat(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let candidates = ["Caveat", "Caveat-Regular"]
        if let name = candidates.first(where: { UIFont(name: $0, size: size) != nil }) {
            return .custom(name, fixedSize: size).weight(weight)
        }
        return .system(size: size, weight: weight)
    }

    static func vellumMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

struct VellumDotGrid: View {
    let spacing: CGFloat
    let dotColor: Color
    let background: Color

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background))
            var path = Path()
            for x in stride(from: CGFloat.zero, through: size.width, by: spacing) {
                for y in stride(from: CGFloat.zero, through: size.height, by: spacing) {
                    path.addEllipse(in: CGRect(x: x, y: y, width: 2, height: 2))
                }
            }
            context.fill(path, with: .color(dotColor))
        }
    }
}

struct VellumDiagonalStripes: View {
    let background: Color
    let stripe: Color
    let spacing: CGFloat

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background))
            var path = Path()
            for x in stride(from: -size.height, through: size.width, by: spacing) {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
            }
            context.stroke(path, with: .color(stripe), lineWidth: spacing / 2)
        }
    }
}

struct VellumFlowLayout: Layout {
    var spacing: CGFloat = 3
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
