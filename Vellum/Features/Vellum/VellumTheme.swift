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
    static let paper = dynamic(light: "#F2EADB", dark: "#211C17")
    static let card = dynamic(light: "#FCF7EC", dark: "#2A241C")
    static let popover = dynamic(light: "#FDF8EE", dark: "#2E281F")
    static let libraryBody = dynamic(light: "#F2EADB", dark: "#211C17")
    static let stripeCard = dynamic(light: "#EDE3CF", dark: "#221E18")
    static let sidebar = dynamic(light: "#EBE0CB", dark: "#1B1712")
    static let field = dynamic(light: "#F7F1E4", dark: "#262019")
    static let canvasBackdrop = dynamic(light: "#E7DCC6", dark: "#191510")
    static let graphBackdrop = dynamic(light: "#EFE6D3", dark: "#241F18")
    static let danger = dynamic(light: "#82291B", dark: "#C24B38")
    static let highlight = dynamic(light: "#D89B36", dark: "#E0AC55")
    static let ink = dynamic(light: "#2A2622", dark: "#EDE5D3")
    static let bodyInk = dynamic(light: "#332F28", dark: "#DDD6C6")
    static let bodyMuted = dynamic(light: "#4A4338", dark: "#C9C0AE")
    static let mutedDark = dynamic(light: "#5C554A", dark: "#B5AB97")
    static let mutedControl = dynamic(light: "#8B8271", dark: "#9C9384")
    static let muted = dynamic(light: "#968C79", dark: "#8A8071")
    static let mutedCount = dynamic(light: "#A2988A", dark: "#7E7566")
    static let waveform = dynamic(light: "#B9AE97", dark: "#6F6754")
    static let toolbarMarker = dynamic(light: "#C9BFA8", dark: "#5A5344")
    static let accent = dynamic(light: "#A6392C", dark: "#C05A48")
    static let accentDark = dynamic(light: "#93301F", dark: "#CE6B58")
    static let spaceRed = dynamic(light: "#A6392C", dark: "#C86B5B")
    static let spaceOrange = dynamic(light: "#B4622D", dark: "#CE8046")
    static let spaceYellow = dynamic(light: "#D89B36", dark: "#E0AC55")
    static let spaceGreen = dynamic(light: "#5E6B23", dark: "#94A34E")
    static let spaceTeal = dynamic(light: "#57705E", dark: "#84A18C")
    static let spaceBlue = dynamic(light: "#4A6272", dark: "#7B9AAB")
    static let spacePurple = dynamic(light: "#7E4155", dark: "#AA7186")
    static let spacePink = dynamic(light: "#A05262", dark: "#C27E8D")
    static let spaceGray = dynamic(light: "#7A7264", dark: "#9C9384")

    static func ink(_ opacity: Double) -> Color { ink.opacity(opacity) }
    static func accent(_ opacity: Double) -> Color { accent.opacity(opacity) }
    static func paper(_ opacity: Double) -> Color { paper.opacity(opacity) }

    static func color(for spaceColor: SpaceColor) -> Color {
        switch spaceColor {
        case .red: spaceRed
        case .orange: spaceOrange
        case .yellow: spaceYellow
        case .green: spaceGreen
        case .teal: spaceTeal
        case .blue: spaceBlue
        case .purple: spacePurple
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
    static func vellumSans(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        italic: Bool = false
    ) -> Font {
        let candidates = italic
            ? ["Karla-Italic", "Karla"]
            : ["Karla", "Karla-Regular"]
        if let name = candidates.first(where: { UIFont(name: $0, size: size) != nil }) {
            let font = Font.custom(name, fixedSize: size).weight(weight)
            return italic ? font.italic() : font
        }
        let fallback = Font.system(size: size, weight: weight)
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
        let name: String
        if [.semibold, .bold, .heavy, .black].contains(weight) {
            name = "IBMPlexMono-SemiBold"
        } else if weight == .medium {
            name = "IBMPlexMono-Medium"
        } else {
            name = "IBMPlexMono-Regular"
        }
        guard UIFont(name: name, size: size) != nil else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return .custom(name, fixedSize: size)
    }
}

extension EnvironmentValues {
    @Entry public var vellumWobble: Bool = true
    @Entry public var vellumGrain: Bool = true
    @Entry public var vellumHandwritingPreviews: Bool = true
}

struct OrganicPillShape: InsettableShape {
    let variant: Int
    let smallRadius: CGFloat
    let isOrganic: Bool
    private var insetAmount: CGFloat = 0

    init(variant: Int = 0, smallRadius: CGFloat = 20, isOrganic: Bool = true) {
        self.variant = variant
        self.smallRadius = smallRadius
        self.isOrganic = isOrganic
    }

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard bounds.width > 0, bounds.height > 0 else { return Path() }

        if isOrganic {
            let small = max(
                0,
                [smallRadius - insetAmount, bounds.width / 2, bounds.height / 2].min() ?? 0
            )
            // Cap the organic corners so tall narrow pills (the vertical
            // toolbar) don't grow ~130pt sweeps that swallow their end items.
            // Wide short pills (chips, strips, the horizontal toolbar at
            // ~121pt tall) stay below the cap and are unaffected.
            let cap: CGFloat = 64
            let firstLarge = CGSize(
                width: min(bounds.height * 0.52, cap),
                height: min(bounds.height * 0.44, cap)
            )
            let secondLarge = CGSize(
                width: min(bounds.height * 0.48, cap),
                height: min(bounds.height * 0.50, cap)
            )
            let smallCorner = CGSize(width: small, height: small)

            let corners: (CGSize, CGSize, CGSize, CGSize)
            switch ((variant % 4) + 4) % 4 {
            case 0:
                corners = (firstLarge, smallCorner, secondLarge, smallCorner)
            case 1:
                corners = (smallCorner, firstLarge, smallCorner, secondLarge)
            case 2:
                corners = (secondLarge, smallCorner, firstLarge, smallCorner)
            default:
                corners = (smallCorner, secondLarge, smallCorner, firstLarge)
            }

            return vellumRoundedPath(
                in: bounds,
                topLeft: corners.0,
                topRight: corners.1,
                bottomRight: corners.2,
                bottomLeft: corners.3
            )
        } else {
            let r = min(smallRadius, bounds.height / 2, bounds.width / 2)
            return RoundedRectangle(cornerRadius: r, style: .continuous)
                .path(in: bounds)
        }
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

struct VellumOrganicRectangle: InsettableShape {
    let topLeading: CGFloat
    let bottomLeading: CGFloat
    let bottomTrailing: CGFloat
    let topTrailing: CGFloat
    let straightRadius: CGFloat
    let isOrganic: Bool
    private var insetAmount: CGFloat = 0

    init(
        topLeading: CGFloat,
        bottomLeading: CGFloat,
        bottomTrailing: CGFloat,
        topTrailing: CGFloat,
        straightRadius: CGFloat,
        isOrganic: Bool
    ) {
        self.topLeading = topLeading
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
        self.topTrailing = topTrailing
        self.straightRadius = straightRadius
        self.isOrganic = isOrganic
    }

    func path(in rect: CGRect) -> Path {
        if isOrganic {
            return UnevenRoundedRectangle(
                topLeadingRadius: topLeading,
                bottomLeadingRadius: bottomLeading,
                bottomTrailingRadius: bottomTrailing,
                topTrailingRadius: topTrailing,
                style: .continuous
            )
            .inset(by: insetAmount)
            .path(in: rect)
        }
        return RoundedRectangle(cornerRadius: straightRadius, style: .continuous)
            .inset(by: insetAmount)
            .path(in: rect)
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

struct VellumDashedRule: Shape {
    var axis: Axis = .horizontal

    func path(in rect: CGRect) -> Path {
        Path { path in
            switch axis {
            case .horizontal:
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            case .vertical:
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            }
        }
    }
}

struct VellumPillChrome: View {
    @Environment(\.vellumWobble) private var vellumWobble

    let fill: Color
    let border: Color
    let shadow: Color
    let shadowOffset: CGSize
    let variant: Int

    init(
        fill: Color,
        border: Color,
        shadow: Color = .clear,
        shadowOffset: CGSize = .zero,
        variant: Int = 0
    ) {
        self.fill = fill
        self.border = border
        self.shadow = shadow
        self.shadowOffset = shadowOffset
        self.variant = variant
    }

    @ViewBuilder
    var body: some View {
        if vellumWobble {
            layers(for: OrganicPillShape(variant: variant))
        } else {
            layers(for: Capsule())
        }
    }

    private func layers<S: InsettableShape>(for shape: S) -> some View {
        ZStack {
            shape
                .fill(shadow)
                .offset(x: shadowOffset.width, y: shadowOffset.height)
            shape.fill(fill)
            shape.strokeBorder(border, lineWidth: 1.5)
        }
    }
}

struct VellumSheetCard<Content: View>: View {
    @Environment(\.vellumWobble) private var vellumWobble

    let title: String
    let onDone: () -> Void
    let content: Content

    init(title: String, onDone: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.onDone = onDone
        self.content = content()
    }

    var body: some View {
        let shape = VellumOrganicRectangle(
            topLeading: 30,
            bottomLeading: 12,
            bottomTrailing: 32,
            topTrailing: 12,
            straightRadius: 22,
            isOrganic: vellumWobble
        )

        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text(title)
                    .font(.vellumSans(28, weight: .semibold))

                Spacer(minLength: 14)

                Button(action: onDone) {
                    Text("done")
                        .font(.vellumSans(16.5, weight: .semibold))
                        .foregroundStyle(VellumTheme.paper)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 46)
                        .background {
                            VellumPillChrome(
                                fill: VellumTheme.ink,
                                border: VellumTheme.ink
                            )
                        }
                        .contentShape(OrganicPillShape(variant: 0, isOrganic: vellumWobble))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)

            VellumDashedRule()
                .stroke(
                    VellumTheme.ink(0.2),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])
                )
                .frame(height: 1.5)

            content
        }
        .frame(maxWidth: 560, maxHeight: 660)
        .background(VellumTheme.card, in: shape)
        .background {
            shape
                .fill(VellumTheme.ink(0.28))
                .offset(x: 8, y: 10)
        }
        .overlay {
            shape.strokeBorder(VellumTheme.ink(0.4), lineWidth: 1.5)
        }
    }
}

private struct VellumBlobShape: Shape {
    let isOrganic: Bool

    func path(in rect: CGRect) -> Path {
        guard isOrganic else { return Path(ellipseIn: rect) }
        return vellumRoundedPath(
            in: rect,
            topLeft: CGSize(width: rect.width * 0.60, height: rect.height * 0.45),
            topRight: CGSize(width: rect.width * 0.40, height: rect.height * 0.60),
            bottomRight: CGSize(width: rect.width * 0.55, height: rect.height * 0.40),
            bottomLeft: CGSize(width: rect.width * 0.45, height: rect.height * 0.55)
        )
    }
}

struct VellumBlobDot: View {
    @Environment(\.vellumWobble) private var vellumWobble

    let color: Color
    let size: CGFloat

    var body: some View {
        VellumBlobShape(isOrganic: vellumWobble)
            .fill(color)
            .frame(width: size, height: size)
    }
}

struct VellumGrainOverlay: View {
    @Environment(\.vellumGrain) private var vellumGrain

    @ViewBuilder
    var body: some View {
        if vellumGrain {
            Canvas { context, size in
                var fineDots = Path()
                for x in stride(from: CGFloat(1), through: size.width, by: 7) {
                    for y in stride(from: CGFloat(1), through: size.height, by: 7) {
                        fineDots.addEllipse(
                            in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)
                        )
                    }
                }
                context.fill(
                    fineDots,
                    with: .color(Color(hex: "#5A4A34").opacity(0.10))
                )

                var broadDots = Path()
                for x in stride(from: CGFloat(3), through: size.width, by: 11) {
                    for y in stride(from: CGFloat(5), through: size.height, by: 13) {
                        broadDots.addEllipse(
                            in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)
                        )
                    }
                }
                context.fill(
                    broadDots,
                    with: .color(Color(hex: "#5A4A34").opacity(0.07))
                )
            }
            .opacity(0.5)
            .blendMode(.multiply)
            .allowsHitTesting(false)
            .ignoresSafeArea()
        } else {
            EmptyView()
        }
    }
}

struct VellumPillButtonStyle: ButtonStyle {
    enum Variant: Equatable {
        case primary
        case outline
        case quiet
    }

    @Environment(\.vellumWobble) private var vellumWobble

    let variant: Variant

    init(_ variant: Variant = .primary) {
        self.variant = variant
    }

    func makeBody(configuration: Configuration) -> some View {
        let shape = VellumFloatingChromeShape(
            kind: .pill(variant: 0),
            usesOrganicShape: vellumWobble
        )
        let fillColor: Color = variant == .primary ? VellumTheme.accent : .clear
        let foregroundColor: Color = variant == .primary
            ? Color(hex: "#FDF8EE")
            : VellumTheme.ink
        let borderColor: Color = variant == .quiet && !configuration.isPressed
            ? .clear
            : VellumTheme.ink.opacity(variant == .primary ? 1 : 0.3)
        let shadowColor: Color = variant == .quiet && !configuration.isPressed
            ? .clear
            : VellumTheme.ink.opacity(0.13)
        let shadowOffset: CGFloat = configuration.isPressed ? 1 : 3
        let shadowDrop: CGFloat = configuration.isPressed ? 1 : 4

        return configuration.label
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(fillColor, in: shape)
            .background {
                shape
                    .fill(shadowColor)
                    .offset(x: shadowOffset, y: shadowDrop)
            }
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: 1.5)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

enum VellumChromeKind {
    case pill(variant: Int = 0)
    case panel
}

extension View {
    func vellumFloatingChrome(
        _ kind: VellumChromeKind,
        strokeColor: Color? = nil
    ) -> some View {
        modifier(VellumFloatingChromeModifier(kind: kind, strokeColor: strokeColor))
    }
}

private struct VellumFloatingChromeModifier: ViewModifier {
    @Environment(\.vellumWobble) private var vellumWobble

    let kind: VellumChromeKind
    let strokeColor: Color?

    init(kind: VellumChromeKind, strokeColor: Color? = nil) {
        self.kind = kind
        self.strokeColor = strokeColor
    }

    func body(content: Content) -> some View {
        let shape = VellumFloatingChromeShape(
            kind: kind,
            usesOrganicShape: vellumWobble
        )
        return content
            .background(VellumTheme.popover, in: shape)
            .background {
                shape
                    .fill(VellumTheme.ink.opacity(0.13))
                    .offset(x: 3, y: 4)
            }
            .overlay {
                shape.strokeBorder(
                    strokeColor ?? VellumTheme.ink.opacity(0.3),
                    lineWidth: 1.5
                )
            }
    }
}

private struct VellumFloatingChromeShape: InsettableShape {
    let kind: VellumChromeKind
    let usesOrganicShape: Bool
    private var insetAmount: CGFloat = 0

    init(kind: VellumChromeKind, usesOrganicShape: Bool) {
        self.kind = kind
        self.usesOrganicShape = usesOrganicShape
    }

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .pill(let variant):
            if !usesOrganicShape {
                return Capsule().inset(by: insetAmount).path(in: rect)
            }
            return OrganicPillShape(variant: variant)
                .inset(by: insetAmount)
                .path(in: rect)
        case .panel:
            if !usesOrganicShape {
                return RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .inset(by: insetAmount)
                    .path(in: rect)
            }
            let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
            return vellumRoundedPath(
                in: bounds,
                topLeft: panelCornerRadius(26),
                topRight: panelCornerRadius(10),
                bottomRight: panelCornerRadius(28),
                bottomLeft: panelCornerRadius(10)
            )
        }
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    private func panelCornerRadius(_ radius: CGFloat) -> CGSize {
        let adjusted = max(0, radius - insetAmount)
        return CGSize(width: adjusted, height: adjusted)
    }
}

private func vellumRoundedPath(
    in rect: CGRect,
    topLeft: CGSize,
    topRight: CGSize,
    bottomRight: CGSize,
    bottomLeft: CGSize
) -> Path {
    guard rect.width > 0, rect.height > 0 else { return Path() }

    var topLeft = topLeft
    var topRight = topRight
    var bottomRight = bottomRight
    var bottomLeft = bottomLeft
    let scale = [
        1,
        rect.width / max(topLeft.width + topRight.width, 1),
        rect.width / max(bottomLeft.width + bottomRight.width, 1),
        rect.height / max(topLeft.height + bottomLeft.height, 1),
        rect.height / max(topRight.height + bottomRight.height, 1),
    ].min() ?? 1
    if scale < 1 {
        topLeft = CGSize(width: topLeft.width * scale, height: topLeft.height * scale)
        topRight = CGSize(width: topRight.width * scale, height: topRight.height * scale)
        bottomRight = CGSize(
            width: bottomRight.width * scale,
            height: bottomRight.height * scale
        )
        bottomLeft = CGSize(
            width: bottomLeft.width * scale,
            height: bottomLeft.height * scale
        )
    }

    let curve: CGFloat = 0.552_284_749_8
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + topLeft.width, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - topRight.width, y: rect.minY))
    path.addCurve(
        to: CGPoint(x: rect.maxX, y: rect.minY + topRight.height),
        control1: CGPoint(
            x: rect.maxX - topRight.width + topRight.width * curve,
            y: rect.minY
        ),
        control2: CGPoint(
            x: rect.maxX,
            y: rect.minY + topRight.height - topRight.height * curve
        )
    )
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight.height))
    path.addCurve(
        to: CGPoint(x: rect.maxX - bottomRight.width, y: rect.maxY),
        control1: CGPoint(
            x: rect.maxX,
            y: rect.maxY - bottomRight.height + bottomRight.height * curve
        ),
        control2: CGPoint(
            x: rect.maxX - bottomRight.width + bottomRight.width * curve,
            y: rect.maxY
        )
    )
    path.addLine(to: CGPoint(x: rect.minX + bottomLeft.width, y: rect.maxY))
    path.addCurve(
        to: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft.height),
        control1: CGPoint(
            x: rect.minX + bottomLeft.width - bottomLeft.width * curve,
            y: rect.maxY
        ),
        control2: CGPoint(
            x: rect.minX,
            y: rect.maxY - bottomLeft.height + bottomLeft.height * curve
        )
    )
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft.height))
    path.addCurve(
        to: CGPoint(x: rect.minX + topLeft.width, y: rect.minY),
        control1: CGPoint(
            x: rect.minX,
            y: rect.minY + topLeft.height - topLeft.height * curve
        ),
        control2: CGPoint(
            x: rect.minX + topLeft.width - topLeft.width * curve,
            y: rect.minY
        )
    )
    path.closeSubpath()
    return path
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
