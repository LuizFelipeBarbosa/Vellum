import SwiftUI
import VellumCore

@MainActor
struct ColumnDividerView: View {
    let app: VellumAppModel
    let dividerIndex: Int
    let containerWidth: CGFloat

    @State private var gridAtDragStart: SplitGridSnapshot?
    @State private var isDragging = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(VellumTheme.ink(0.09))
                .frame(width: 1)

            RoundedRectangle(cornerRadius: 2)
                .fill(isDragging ? VellumTheme.accent : VellumTheme.ink(0.18))
                .frame(width: 4, height: 36)
        }
        .frame(width: SplitGridPolicy.dividerHitThickness)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named("splitContainer")
            )
            .onChanged { value in
                let startGrid = gridAtDragStart ?? app.split.gridSnapshot
                if gridAtDragStart == nil {
                    gridAtDragStart = startGrid
                    isDragging = true
                }
                let grid = SplitGridPolicy.resizingColumnDivider(
                    startGrid,
                    dividerIndex: dividerIndex,
                    byTranslation: value.translation.width,
                    containerWidth: containerWidth
                )
                app.split.applyGrid(grid)
            }
            .onEnded { _ in
                gridAtDragStart = nil
                isDragging = false
            }
        )
    }
}

@MainActor
struct RowDividerView: View {
    let app: VellumAppModel
    let columnIndex: Int
    let dividerIndex: Int
    let containerHeight: CGFloat

    @State private var gridAtDragStart: SplitGridSnapshot?
    @State private var isDragging = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(VellumTheme.ink(0.09))
                .frame(height: 1)

            RoundedRectangle(cornerRadius: 2)
                .fill(isDragging ? VellumTheme.accent : VellumTheme.ink(0.18))
                .frame(width: 36, height: 4)
        }
        .frame(height: SplitGridPolicy.dividerHitThickness)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named("splitContainer")
            )
            .onChanged { value in
                let startGrid = gridAtDragStart ?? app.split.gridSnapshot
                if gridAtDragStart == nil {
                    gridAtDragStart = startGrid
                    isDragging = true
                }
                let grid = SplitGridPolicy.resizingRowDivider(
                    startGrid,
                    column: columnIndex,
                    dividerIndex: dividerIndex,
                    byTranslation: value.translation.height,
                    containerHeight: containerHeight
                )
                app.split.applyGrid(grid)
            }
            .onEnded { _ in
                gridAtDragStart = nil
                isDragging = false
            }
        )
    }
}
