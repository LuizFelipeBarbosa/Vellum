import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: VellumAppModel

    var body: some View {
        ZStack {
            sheetCard
                .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(.hidden, for: .navigationBar)
        .presentationBackground(.clear)
    }

    private var sheetCard: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 30,
            bottomLeadingRadius: 12,
            bottomTrailingRadius: 32,
            topTrailingRadius: 12,
            style: .continuous
        )

        return VStack(spacing: 0) {
            header
            SettingsDashedLine(color: VellumTheme.ink(0.2))
                .frame(height: 1.5)
            settingsContent
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

    private var header: some View {
        HStack(spacing: 14) {
            Text("Settings")
                .font(.vellumSans(28, weight: .semibold))

            Spacer(minLength: 14)

            Button {
                dismiss()
            } label: {
                Text("done")
                    .font(.vellumSans(16.5, weight: .semibold))
                    .foregroundStyle(Color(hex: "#FDF8EE"))
                    .padding(.horizontal, 20)
                    .frame(minHeight: 46)
                    .background {
                        SettingsPillChrome(
                            fillColor: VellumTheme.ink,
                            borderColor: VellumTheme.ink,
                            shadowColor: .clear,
                            variant: 0
                        )
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel("APPEARANCE")

                HStack(spacing: 9) {
                    ForEach(AppearanceMode.allCases) { mode in
                        appearanceButton(for: mode)
                    }
                }
                .padding(.top, 11)

                sectionLabel("FEEL")
                    .padding(.top, 26)

                VStack(spacing: 10) {
                    SettingsFeelRow(
                        label: "Paper grain",
                        hint: "the tooth you can almost feel",
                        isOn: $model.feelGrain
                    )
                    SettingsFeelRow(
                        label: "Handwriting previews",
                        hint: "handwritten preview text on cards",
                        isOn: $model.feelHandwriting
                    )
                    SettingsFeelRow(
                        label: "Wobbly edges",
                        hint: "nothing is perfectly straight",
                        isOn: $model.feelWobble
                    )
                }
                .padding(.top, 11)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 26)
        }
        .scrollIndicators(.hidden)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.vellumMono(11))
            .tracking(1.3)
            .foregroundStyle(VellumTheme.muted)
    }

    private func appearanceButton(for mode: AppearanceMode) -> some View {
        let isSelected = model.appearanceMode == mode

        return Button {
            model.appearanceMode = mode
        } label: {
            Text(mode.label)
                .font(.vellumSans(17, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color(hex: "#FDF8EE") : VellumTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background {
                    SettingsPillChrome(
                        fillColor: isSelected ? VellumTheme.ink : .clear,
                        borderColor: isSelected ? VellumTheme.ink : VellumTheme.ink(0.28),
                        shadowColor: isSelected ? VellumTheme.ink(0.3) : .clear,
                        shadowOffset: CGSize(width: 3, height: 4),
                        variant: mode == .light ? 1 : mode == .dark ? 2 : 0
                    )
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsFeelRow: View {
    let label: String
    let hint: String
    @Binding var isOn: Bool

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 20,
            bottomLeadingRadius: 8,
            bottomTrailingRadius: 22,
            topTrailingRadius: 8,
            style: .continuous
        )

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(label)
                        .font(.vellumSans(17.5))
                        .foregroundStyle(VellumTheme.ink)
                    Text(hint)
                        .font(.vellumCaveat(17))
                        .foregroundStyle(VellumTheme.mutedControl)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SettingsOrganicToggle(isOn: isOn)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(VellumTheme.field, in: shape)
            .overlay {
                shape.strokeBorder(VellumTheme.ink(0.26), lineWidth: 1.5)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct SettingsOrganicToggle: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            VellumBlobDot(color: VellumTheme.ink, size: 24)
                .offset(x: isOn ? 13 : -13)
        }
        .frame(width: 58, height: 32)
        .background(
            isOn ? VellumTheme.accent(0.4) : VellumTheme.ink(0.08),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .strokeBorder(VellumTheme.ink, lineWidth: 1.5)
        }
        .animation(.easeInOut(duration: 0.18), value: isOn)
        .accessibilityHidden(true)
    }
}

private struct SettingsPillChrome: View {
    @Environment(\.vellumWobble) private var vellumWobble

    let fillColor: Color
    let borderColor: Color
    let shadowColor: Color
    var shadowOffset: CGSize = .zero
    let variant: Int

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
                .fill(shadowColor)
                .offset(x: shadowOffset.width, y: shadowOffset.height)
            shape.fill(fillColor)
            shape.strokeBorder(borderColor, lineWidth: 1.5)
        }
    }
}

private struct SettingsDashedLine: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let y = geometry.size.height / 2
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: geometry.size.width, y: y))
            }
            .stroke(
                color,
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])
            )
        }
    }
}
