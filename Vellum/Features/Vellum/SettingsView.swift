import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: VellumAppModel

    var body: some View {
        ZStack {
            VellumSheetCard(title: "Settings", onDone: { dismiss() }) {
                settingsContent
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(.hidden, for: .navigationBar)
        .presentationBackground(.clear)
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
                .foregroundStyle(isSelected ? VellumTheme.paper : VellumTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background {
                    VellumPillChrome(
                        fill: isSelected ? VellumTheme.ink : .clear,
                        border: isSelected ? VellumTheme.ink : VellumTheme.ink(0.28),
                        shadow: isSelected ? VellumTheme.ink(0.3) : .clear,
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
    @Environment(\.vellumWobble) private var vellumWobble

    let label: String
    let hint: String
    @Binding var isOn: Bool

    var body: some View {
        let shape = VellumOrganicRectangle(
            topLeading: 20,
            bottomLeading: 8,
            bottomTrailing: 22,
            topTrailing: 8,
            straightRadius: 14,
            isOrganic: vellumWobble
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
