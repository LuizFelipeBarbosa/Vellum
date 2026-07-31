import SwiftUI
import UIKit
import VellumCore

struct PageBackgroundOptionsView: View {
    @Binding var style: PageBackgroundStyle
    var pageOrientation: PageOrientation = .portrait
    var isPageOrientationAvailable: Bool = false
    var onSetPageOrientation: ((PageOrientation) -> Void)? = nil
    var orientationWouldPushContentOffPage: ((PageOrientation) -> Bool)? = nil

    @State private var pendingOrientation: PageOrientation?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Paper")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(VellumTheme.ink)

            if isPageOrientationAvailable {
                OptionsSectionCaption("Orientation")

                Picker("Orientation", selection: orientationBinding) {
                    ForEach(PageOrientation.allCases, id: \.rawValue) { orientation in
                        Text(orientation == .portrait ? "Portrait" : "Landscape")
                            .tag(orientation)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Page orientation")
            } else {
                Text("Page size follows the imported PDF.")
                    .font(.system(size: 12))
                    .foregroundStyle(VellumTheme.mutedDark)
            }

            OptionsDivider()

            OptionsSectionCaption("Style")

            Picker("Style", selection: $style.kind) {
                ForEach(PageBackgroundStyle.Kind.allCases, id: \.rawValue) { kind in
                    Text(kind.rawValue.capitalized)
                        .tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Paper style")

            HStack {
                Spacer()
                PagePatternPreview(
                    kind: style.kind,
                    spacing: style.spacing,
                    tint: style.paperTint,
                    size: pageOrientation == .landscape
                        ? CGSize(width: 96, height: 72)
                        : CGSize(width: 72, height: 96)
                )
                Spacer()
            }

            OptionsDivider()

            if style.kind != .blank {
                OptionsSectionCaption("Spacing")

                HStack(spacing: 12) {
                    Slider(
                        value: $style.spacing,
                        in: PageBackgroundStyle.spacingRange,
                        step: 1
                    )
                    .accessibilityLabel("Paper pattern spacing")
                    .accessibilityValue("\(Int(style.spacing.rounded())) points")

                    Text("\(Int(style.spacing.rounded())) pt")
                        .font(.vellumMono(11))
                        .foregroundStyle(VellumTheme.mutedDark)
                        .frame(width: 48, alignment: .trailing)
                        .accessibilityHidden(true)
                }

                OptionsDivider()
            }

            OptionsSectionCaption("Paper Color")

            HStack(spacing: 10) {
                paperColorButton(nil)

                ForEach(
                    Array(PageBackgroundStyle.presetTints.enumerated()),
                    id: \.offset
                ) { _, tint in
                    paperColorButton(tint)
                }
            }

            ColorPicker(
                "Custom",
                selection: paperColorBinding,
                supportsOpacity: false
            )
            .accessibilityLabel("Custom paper color")
        }
        .padding(18)
        .frame(width: 300, alignment: .leading)
        .background(VellumTheme.popover)
        .confirmationDialog(
            "Flip to \(pendingOrientation == .landscape ? "Landscape" : "Portrait")?",
            isPresented: Binding(
                get: { pendingOrientation != nil },
                set: { if !$0 { pendingOrientation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Rotate") {
                if let pendingOrientation {
                    onSetPageOrientation?(pendingOrientation)
                }
                pendingOrientation = nil
            }
            Button("Cancel", role: .cancel) {
                pendingOrientation = nil
            }
        } message: {
            Text(
                "Some content is wider than a portrait page and won't be shown. "
                    + "Flip back to landscape to see it again."
            )
        }
    }

    private var orientationBinding: Binding<PageOrientation> {
        Binding(
            get: { pageOrientation },
            set: { requestOrientation($0) }
        )
    }

    private func requestOrientation(_ newOrientation: PageOrientation) {
        guard newOrientation != pageOrientation else { return }
        if orientationWouldPushContentOffPage?(newOrientation) == true {
            pendingOrientation = newOrientation
        } else {
            onSetPageOrientation?(newOrientation)
        }
    }

    private var paperColorBinding: Binding<Color> {
        Binding(
            get: {
                style.paperTint?.swiftUIColor ?? VellumTheme.card
            },
            set: { color in
                style.paperTint = CodableColor(UIColor(color))
            }
        )
    }

    private func paperColorButton(_ tint: CodableColor?) -> some View {
        Button {
            style.paperTint = tint
        } label: {
            Circle()
                .fill(tint?.swiftUIColor ?? VellumTheme.card)
                .frame(width: 24, height: 24)
                .overlay {
                    if tint == nil {
                        Circle()
                            .stroke(VellumTheme.ink(0.18), lineWidth: 1)
                    }
                }
                .overlay {
                    Circle()
                        .stroke(
                            style.paperTint == tint ? VellumTheme.accent : .clear,
                            lineWidth: 2
                        )
                        .padding(-4)
                }
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(paperColorAccessibilityLabel(for: tint))
    }

    private func paperColorAccessibilityLabel(for tint: CodableColor?) -> String {
        if let tint {
            return "Paper color \(tint.hexString)"
        }
        return "Default paper color"
    }
}
