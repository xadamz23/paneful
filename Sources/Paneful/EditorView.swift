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
                ForEach(Presets.all, id: \.name) { preset in
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
        if model.dragging == nil {
            // Grab the divider under the press, if there is one.
            let start = displayPoint(value.startLocation, scale: scale)
            model.dragging = model.draft.layout.root.dividerHandle(at: start, in: frame, gap: gap, tolerance: Self.handleReach / scale)
        }
        guard let (zone, edge) = model.dragging else { return }
        let point = displayPoint(value.location, scale: scale)
        // Keep the gap centred on the cursor: the zone's edge sits half a gap before it.
        let position = (edge == .right ? point.x : point.y) - gap / 2
        model.draft.moveDivider(edge, of: zone, to: position, in: frame, gap: gap, minSize: TilingController.minZoneSize)
    }

    private func endDrag(_ value: DragGesture.Value, scale: CGFloat, rects: [ZoneID: CGRect]) {
        defer { model.dragging = nil }
        guard model.dragging == nil else { return }
        // A press that grabbed no divider is a click: select the zone under it, or nothing.
        let point = displayPoint(value.location, scale: scale)
        model.draft.selected = rects.first { $0.value.contains(point) }?.key
    }
}
