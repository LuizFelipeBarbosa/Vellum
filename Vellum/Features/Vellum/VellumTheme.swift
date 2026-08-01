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
    static let paper = dynamic(light: "#F6F2E9", dark: "#1C1914")
    static let ink = dynamic(light: "#26221B", dark: "#E9E3D6")
    static let accent = dynamic(light: "#9A6B35", dark: "#C99A5F")
    static let accentDark = dynamic(light: "#8A5A28", dark: "#B98A4E")
    static let card = dynamic(light: "#FBF8F1", dark: "#242019")
    static let popover = dynamic(light: "#FFFDF8", dark: "#2A2620")
    static let libraryBody = dynamic(light: "#FDFBF6", dark: "#211D17")
    static let stripeCard = dynamic(light: "#F1EDE2", dark: "#221E18")
    static let muted = dynamic(light: "#9C927E", dark: "#8A8171")
    static let mutedCount = dynamic(light: "#A99F8B", dark: "#A69C89")
    static let mutedControl = dynamic(light: "#8B8272", dark: "#9C9384")
    static let mutedDark = dynamic(light: "#7A7264", dark: "#B0A794")
    static let bodyMuted = dynamic(light: "#4A4438", dark: "#C9C0AE")
    static let bodyInk = dynamic(light: "#33302A", dark: "#DDD6C6")
    static let waveform = dynamic(light: "#B9AE97", dark: "#8F866F")
    static let toolbarMarker = dynamic(light: "#C9BFA8", dark: "#5A5344")
    static let studio = dynamic(light: "#9A6B35", dark: "#C99A5F")
    static let thesis = dynamic(light: "#4E6E58", dark: "#7FA98C")
    static let team = dynamic(light: "#6E5E7A", dark: "#A896B5")
    static let reading = dynamic(light: "#8A6E4B", dark: "#C2A379")
    static let spaceRed = dynamic(light: "#955B52", dark: "#C99189")
    static let spaceTeal = dynamic(light: "#4F7470", dark: "#82ACA7")
    static let spaceBlue = dynamic(light: "#586E82", dark: "#8FA8BC")
    static let spacePink = dynamic(light: "#936B76", dark: "#C8A0AB")
    static let spaceGray = dynamic(light: "#7B776E", dark: "#A9A59B")

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

    private static func dynamic(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
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
