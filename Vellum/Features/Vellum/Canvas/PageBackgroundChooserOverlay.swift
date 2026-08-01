import SwiftUI
import VellumCore

struct PagePatternPreview: View {
    let kind: PageBackgroundStyle.Kind
    let spacing: Double
    let tint: CodableColor?
    var size: CGSize = CGSize(width: 72, height: 96)

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(
                Path(bounds),
                with: .color(tint?.swiftUIColor ?? VellumTheme.card)
            )

            guard kind != .blank else { return }

            let previewScale: CGFloat = 3
            let style = PageBackgroundStyle(
                kind: kind,
                spacing: spacing,
                paperTint: tint
            )
            let pageRect = CGRect(
                origin: .zero,
                size: CGSize(
                    width: size.width * previewScale,
                    height: size.height * previewScale
                )
            )
            let patternColor: Color
            if let tint {
                patternColor = PageBackgroundStyle.patternInk(
                    forTint: tint,
                    opacity: 0.14
                ).swiftUIColor
            } else {
                patternColor = VellumTheme.ink(0.14)
            }

            let marks = PageBackgroundPattern.marks(
                style: style,
                pageRect: pageRect,
                clippedTo: pageRect
            )
            switch marks {
            case .none:
                break
            case .dots(let xs, let ys):
                var dots = Path()

                for x in xs.values {
                    for y in ys.values {
                        dots.addEllipse(
                            in: CGRect(
                                x: x / previewScale - 0.7,
                                y: y / previewScale - 0.7,
                                width: 1.4,
                                height: 1.4
                            )
                        )
                    }
                }

                context.fill(dots, with: .color(patternColor))
            case .rules(let ys, let columns):
                var lines = Path()

                for y in ys.values {
                    let previewY = y / previewScale
                    lines.move(to: CGPoint(x: 0, y: previewY))
                    lines.addLine(to: CGPoint(x: size.width, y: previewY))
                }

                if let xs = columns {
                    for x in xs.values {
                        let previewX = x / previewScale
                        lines.move(to: CGPoint(x: previewX, y: 0))
                        lines.addLine(to: CGPoint(x: previewX, y: size.height))
                    }
                }

                context.stroke(lines, with: .color(patternColor), lineWidth: 0.75)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(VellumTheme.ink(0.14), lineWidth: 1)
        }
    }
}

struct PageBackgroundChooserOverlay: View {
    let onChoose: (PageBackgroundStyle.Kind) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture {
                    onDismiss()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 18) {
                Text("Choose your paper")
                    .font(.vellumNewsreader(20, weight: .semibold))
                    .foregroundStyle(VellumTheme.ink)

                HStack(spacing: 18) {
                    paperButton(.ruled)
                    paperButton(.grid)
                    paperButton(.dots)
                }

                Button("Keep blank", action: onDismiss)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(VellumTheme.mutedDark)
                    .buttonStyle(.plain)
            }
            .padding(24)
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(VellumTheme.popover)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(VellumTheme.ink(0.12), lineWidth: 1)
            }
            .shadow(color: VellumTheme.ink(0.14), radius: 12, y: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func paperButton(_ kind: PageBackgroundStyle.Kind) -> some View {
        Button {
            onChoose(kind)
        } label: {
            VStack(spacing: 8) {
                PagePatternPreview(
                    kind: kind,
                    spacing: PageBackgroundStyle.defaultSpacing,
                    tint: nil
                )

                Text(kind.rawValue.capitalized)
                    .font(.vellumMono(11, weight: .medium))
                    .foregroundStyle(VellumTheme.bodyMuted)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose \(kind.rawValue) paper")
    }
}
