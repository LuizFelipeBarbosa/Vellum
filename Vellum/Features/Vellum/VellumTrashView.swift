import SwiftUI

struct VellumTrashView: View {
    @Bindable var model: VellumAppModel

    var body: some View {
        @Bindable var trash = model.trashScreen

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compost")
                        .font(.vellumSans(42, weight: .medium))
                        .foregroundStyle(VellumTheme.ink)
                    Text("\(trash.rows.count) notes · everything here is recoverable until you say otherwise")
                        .font(.vellumCaveat(21))
                        .foregroundStyle(VellumTheme.muted)
                }

                Spacer(minLength: 20)

                Button("empty it out") {
                    trash.isConfirmingEmptyTrash = true
                }
                .buttonStyle(CompostEmptyButtonStyle())
                .disabled(trash.rows.isEmpty)
            }
            .padding(.bottom, 20)

            ScrollView {
                if trash.rows.isEmpty {
                    VStack(spacing: 4) {
                        Text("Compost is empty")
                            .font(.vellumSans(24, italic: true))
                            .foregroundStyle(VellumTheme.bodyMuted)
                        Text("nothing waiting to come back")
                            .font(.vellumCaveat(18))
                            .foregroundStyle(VellumTheme.muted)
                    }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                } else {
                    LazyVStack(spacing: 11) {
                        ForEach(trash.rows) { row in
                            trashRow(row, trash: trash)
                        }

                        Text("nothing is really gone until you say so twice")
                            .font(.vellumCaveat(22))
                            .foregroundStyle(VellumTheme.mutedCount)
                            .rotationEffect(.degrees(-0.8))
                            .padding(.top, 8)
                    }
                    .padding(.bottom, 26)
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 30)
        .padding(.top, 26)
        .background(VellumTheme.paper)
        .confirmationDialog(
            "Empty Trash?",
            isPresented: $trash.isConfirmingEmptyTrash,
            titleVisibility: .visible
        ) {
            Button("Empty Trash", role: .destructive) {
                Task {
                    await trash.emptyTrash()
                    await model.refreshStats()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \(trash.rows.count) notes. This can't be undone.")
        }
        .confirmationDialog(
            "Delete permanently?",
            isPresented: Binding(
                get: { trash.pendingPurgeID != nil },
                set: { isPresented in
                    if !isPresented { trash.cancelPurge() }
                }
            ),
            titleVisibility: .visible,
            presenting: trash.pendingPurgeID
        ) { noteID in
            Button("Delete Forever", role: .destructive) {
                Task {
                    await trash.confirmPurge(noteID)
                    await model.refreshStats()
                    await model.library.refresh()
                }
            }
            Button("Cancel", role: .cancel) {
                trash.cancelPurge()
            }
        } message: { _ in
            Text("This can't be undone.")
        }
        .alert(
            "Vellum",
            isPresented: Binding(
                get: { trash.errorMessage != nil },
                set: { isPresented in
                    if !isPresented { trash.errorMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                trash.errorMessage = nil
            }
        } message: {
            Text(trash.errorMessage ?? "An unknown error occurred.")
        }
        .task { await trash.refresh() }
    }

    private func trashRow(_ row: TrashRow, trash: TrashScreenModel) -> some View {
        let rowShape = CompostRowShape()

        return HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(row.title)
                    .font(.vellumSans(19, weight: .semibold))
                    .foregroundStyle(VellumTheme.mutedDark)
                    .lineLimit(1)
                Text(subtitle(for: row))
                    .font(.vellumMono(11))
                    .foregroundStyle(VellumTheme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button("put it back") {
                Task {
                    await trash.restore(row.id)
                    await model.refreshStats()
                    await model.library.refresh()
                }
            }
            .buttonStyle(CompostRestoreButtonStyle())

            Button("delete forever") {
                trash.requestPurge(row.id)
            }
            .buttonStyle(CompostDeleteButtonStyle())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(VellumTheme.field, in: rowShape)
        .overlay {
            rowShape.strokeBorder(
                VellumTheme.ink(0.3),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
            )
        }
    }

    private func subtitle(for row: TrashRow) -> String {
        var subtitle = "Deleted \(relativeTime(for: row.deletedAt))"
        if let spaceName = row.spaceName {
            subtitle += " · \(spaceName)"
        }
        return subtitle
    }

    private func relativeTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct CompostEmptyButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = OrganicPillShape(variant: 0)

        configuration.label
            .font(.vellumSans(16.5, weight: .semibold))
            .foregroundStyle(VellumTheme.danger)
            .padding(.horizontal, 22)
            .frame(minHeight: 50)
            .background(VellumTheme.danger.opacity(0.07), in: shape)
            .overlay {
                shape.strokeBorder(VellumTheme.danger, lineWidth: 1.5)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct CompostRestoreButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = OrganicPillShape(variant: 1)
        let shadowX: CGFloat = configuration.isPressed ? 1 : 2
        let shadowY: CGFloat = configuration.isPressed ? 1 : 3

        configuration.label
            .font(.vellumSans(16.5, weight: .semibold))
            .foregroundStyle(VellumTheme.ink)
            .padding(.horizontal, 20)
            .frame(minHeight: 48)
            .background(VellumTheme.field, in: shape)
            .background {
                shape
                    .fill(VellumTheme.ink(0.12))
                    .offset(x: shadowX, y: shadowY)
            }
            .overlay {
                shape.strokeBorder(VellumTheme.ink(0.32), lineWidth: 1.5)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct CompostDeleteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = OrganicPillShape(variant: 2)

        configuration.label
            .font(.vellumSans(16.5, weight: .semibold))
            .foregroundStyle(VellumTheme.danger)
            .padding(.horizontal, 20)
            .frame(minHeight: 48)
            .overlay {
                shape.strokeBorder(VellumTheme.danger.opacity(0.55), lineWidth: 1.5)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct CompostRowShape: InsettableShape {
    private var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radii = CompostCornerRadii(
            topLeft: max(0, 22 - insetAmount),
            topRight: max(0, 9 - insetAmount),
            bottomRight: max(0, 24 - insetAmount),
            bottomLeft: max(0, 9 - insetAmount)
        )
        return compostRoundedPath(in: bounds, radii: radii)
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

private struct CompostCornerRadii {
    var topLeft: CGFloat
    var topRight: CGFloat
    var bottomRight: CGFloat
    var bottomLeft: CGFloat
}

private func compostRoundedPath(in rect: CGRect, radii: CompostCornerRadii) -> Path {
    guard rect.width > 0, rect.height > 0 else { return Path() }

    var radii = radii
    let scale = [
        1,
        rect.width / max(radii.topLeft + radii.topRight, 1),
        rect.width / max(radii.bottomLeft + radii.bottomRight, 1),
        rect.height / max(radii.topLeft + radii.bottomLeft, 1),
        rect.height / max(radii.topRight + radii.bottomRight, 1),
    ].min() ?? 1
    if scale < 1 {
        radii.topLeft *= scale
        radii.topRight *= scale
        radii.bottomRight *= scale
        radii.bottomLeft *= scale
    }

    let curve: CGFloat = 0.552_284_749_8
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + radii.topLeft, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - radii.topRight, y: rect.minY))
    path.addCurve(
        to: CGPoint(x: rect.maxX, y: rect.minY + radii.topRight),
        control1: CGPoint(
            x: rect.maxX - radii.topRight + radii.topRight * curve,
            y: rect.minY
        ),
        control2: CGPoint(
            x: rect.maxX,
            y: rect.minY + radii.topRight - radii.topRight * curve
        )
    )
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radii.bottomRight))
    path.addCurve(
        to: CGPoint(x: rect.maxX - radii.bottomRight, y: rect.maxY),
        control1: CGPoint(
            x: rect.maxX,
            y: rect.maxY - radii.bottomRight + radii.bottomRight * curve
        ),
        control2: CGPoint(
            x: rect.maxX - radii.bottomRight + radii.bottomRight * curve,
            y: rect.maxY
        )
    )
    path.addLine(to: CGPoint(x: rect.minX + radii.bottomLeft, y: rect.maxY))
    path.addCurve(
        to: CGPoint(x: rect.minX, y: rect.maxY - radii.bottomLeft),
        control1: CGPoint(
            x: rect.minX + radii.bottomLeft - radii.bottomLeft * curve,
            y: rect.maxY
        ),
        control2: CGPoint(
            x: rect.minX,
            y: rect.maxY - radii.bottomLeft + radii.bottomLeft * curve
        )
    )
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radii.topLeft))
    path.addCurve(
        to: CGPoint(x: rect.minX + radii.topLeft, y: rect.minY),
        control1: CGPoint(
            x: rect.minX,
            y: rect.minY + radii.topLeft - radii.topLeft * curve
        ),
        control2: CGPoint(
            x: rect.minX + radii.topLeft - radii.topLeft * curve,
            y: rect.minY
        )
    )
    path.closeSubpath()
    return path
}
