import PanefulCore
import SwiftUI

// No @State / @Observable / #Preview here: those are macros, and their plugin ships only with Xcode.

struct EditorView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Display", selection: Binding(get: { model.displayID }, set: { model.select(displayID: $0) })) {
                ForEach(model.displays, id: \.id) { display in
                    Text(display.name).tag(display.id)
                }
            }
            .frame(maxWidth: 360)

            HStack {
                Text("Presets")
                // Computed for this display at the draft gap, so size-exact presets stay exact when saved.
                ForEach(model.display.map { Presets.available(for: $0.visibleFrame, gap: CGFloat(model.gap)) } ?? Presets.all, id: \.name) { preset in
                    Button(preset.name) { model.draft.apply(preset) }
                }
            }

            if let display = model.display {
                LayoutCanvas(model: model, frame: display.visibleFrame)
            }

            HStack {
                Text("Selected zone")
                Button("Split side by side") { model.draft.splitSelected(along: .vertical) }
                Button("Split top / bottom") { model.draft.splitSelected(along: .horizontal) }
                Button("Remove") { model.draft.removeSelected() }
                    .disabled(!model.draft.canRemove)
            }
            .disabled(model.draft.selected == nil)

            HStack {
                Text("Gap")
                Slider(value: $model.gap, in: 0...40, step: 1)
                    .frame(maxWidth: 240)
                Text("\(Int(model.gap)) px")
                    .monospacedDigit()
            }

            HStack {
                Spacer()
                Button("Revert") { model.revert() }
                    .disabled(!model.hasChanges)
                Button("Save") { model.save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.hasChanges)
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 540)
    }
}

/// The draft layout drawn in its display's shape, with the draft gap. Click a zone to select it;
/// drag the gap between zones to move that divider.
struct LayoutCanvas: View {
    @ObservedObject var model: EditorModel
    /// The display's usable area, in Accessibility coordinates (top-left origin, like SwiftUI).
    let frame: CGRect

    /// How close, in canvas points, a press must be to a divider to grab it.
    private static let handleReach: CGFloat = 6
    /// How far, in canvas points, the cursor must travel before a grabbed divider starts moving.
    private static let dragThreshold: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / frame.width, proxy.size.height / frame.height)
            let gap = CGFloat(model.gap)
            let rects = Geometry.zoneRects(model.draft.layout.root, in: frame, gap: gap)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.black.opacity(0.25))
                    .frame(width: frame.width * scale, height: frame.height * scale)
                ForEach(rects.keys.sorted(), id: \.self) { zone in
                    let rect = canvasRect(rects[zone]!, scale: scale)
                    let isSelected = zone == model.draft.selected
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(isSelected ? 0.45 : 0.18))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: isSelected ? 2 : 1))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in drag(value, scale: scale, gap: gap) }
                .onEnded { value in endDrag(value, scale: scale, rects: rects) })
        }
        .aspectRatio(frame.width / frame.height, contentMode: .fit)
    }

    private func canvasRect(_ rect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: (rect.minX - frame.minX) * scale, y: (rect.minY - frame.minY) * scale,
               width: rect.width * scale, height: rect.height * scale)
    }

    private func displayPoint(_ point: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: frame.minX + point.x / scale, y: frame.minY + point.y / scale)
    }

    private func drag(_ value: DragGesture.Value, scale: CGFloat, gap: CGFloat) {
        let start = displayPoint(value.startLocation, scale: scale)
        if model.dragging?.start != start {
            // A new press: grab the divider under it, if there is one.
            model.dragging = model.draft.layout.root.dividerHandle(at: start, in: frame, gap: gap, tolerance: Self.handleReach / scale)
                .map { handle in
                    let rect = Geometry.zoneRects(model.draft.layout.root, in: frame, gap: gap)[handle.zone]!
                    return DividerDrag(zone: handle.zone, edge: handle.edge, grabbedAt: handle.edge.coordinate(of: rect), start: start)
                }
        }
        // Only a real drag moves the divider; a click near one stays a click.
        guard let drag = model.dragging,
              let position = model.dragging?.position(for: displayPoint(value.location, scale: scale), threshold: Self.dragThreshold / scale) else { return }
        model.draft.moveDivider(drag.edge, of: drag.zone, to: position, in: frame, gap: gap, minSize: TilingController.minZoneSize)
    }

    private func endDrag(_ value: DragGesture.Value, scale: CGFloat, rects: [ZoneID: CGRect]) {
        defer { model.dragging = nil }
        guard model.dragging?.hasMoved != true else { return }
        // A press that didn't drag a divider is a click: select the zone it started on, or nothing.
        let point = displayPoint(value.startLocation, scale: scale)
        model.draft.selected = rects.first { $0.value.contains(point) }?.key
    }
}
