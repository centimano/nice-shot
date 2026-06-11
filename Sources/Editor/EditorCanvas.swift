import SwiftUI

/// The drawing surface. Renders the base image plus annotations through
/// `Renderer`, and (when interactive) handles all tool gestures and inline
/// text editing.
struct EditorCanvas: View {
    @ObservedObject var doc: EditorDocument
    let fitScale: CGFloat
    var interactive = true

    @State private var gesturePhase: GesturePhase = .idle
    @FocusState private var textFieldFocused: Bool

    private enum GesturePhase {
        case idle
        case drawing
        case cropping
        case moving(id: UUID, last: CGPoint, pre: EditorDocument.Snapshot, moved: Bool)
        case resizing(id: UUID, handle: Annotation.Handle, pre: EditorDocument.Snapshot, changed: Bool)
        case ignore
    }

    var body: some View {
        let canvas = Canvas { context, _ in
            var ctx = context
            ctx.scaleBy(x: fitScale, y: fitScale)
            ctx.draw(
                Image(decorative: doc.baseImage, scale: 1),
                in: CGRect(origin: .zero, size: doc.pixelSize)
            )

            for annotation in doc.annotations where annotation.id != doc.editingID {
                Renderer.draw(
                    annotation,
                    in: &ctx,
                    unit: doc.unit,
                    imageSize: doc.pixelSize,
                    pixelated: needsPixelated(annotation) ? doc.pixelated : nil,
                    selected: interactive && annotation.id == doc.selectedID
                )
            }

            if let draft = doc.draft {
                Renderer.draw(
                    draft,
                    in: &ctx,
                    unit: doc.unit,
                    imageSize: doc.pixelSize,
                    pixelated: needsPixelated(draft) ? doc.pixelated : nil,
                    selected: false
                )
            }

            if interactive, let crop = doc.cropDraft {
                drawCropOverlay(crop, in: &ctx)
            }
        }
        .frame(width: doc.pixelSize.width * fitScale, height: doc.pixelSize.height * fitScale)

        if interactive {
            canvas
                .gesture(dragGesture)
                .simultaneousGesture(doubleTapGesture)
                .overlay(alignment: .topLeading) { textEditorOverlay }
        } else {
            canvas
        }
    }

    private func needsPixelated(_ annotation: Annotation) -> Bool {
        if case .blur = annotation.shape { return true }
        return false
    }

    // MARK: - Crop overlay

    private func drawCropOverlay(_ crop: CGRect, in ctx: inout GraphicsContext) {
        var dim = Path(CGRect(origin: .zero, size: doc.pixelSize))
        dim.addPath(Path(crop))
        ctx.fill(dim, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))
        ctx.stroke(
            Path(crop),
            with: .color(.white),
            style: StrokeStyle(lineWidth: max(1.5, 1.5 * doc.unit), dash: [8 * doc.unit, 5 * doc.unit])
        )
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = pixelPoint(value.location)
                let start = pixelPoint(value.startLocation)

                switch gesturePhase {
                case .idle:
                    begin(at: start, current: point)
                case .drawing:
                    updateDraft(start: start, current: point)
                case .cropping:
                    doc.cropDraft = CGRect(points: start, point).clamped(to: doc.pixelSize)
                case .moving(let id, let last, let pre, _):
                    let delta = CGSize(width: point.x - last.x, height: point.y - last.y)
                    doc.translateAnnotation(id, by: delta)
                    gesturePhase = .moving(id: id, last: point, pre: pre, moved: true)
                case .resizing(let id, let handle, let pre, _):
                    doc.moveHandle(id, handle, to: point)
                    gesturePhase = .resizing(id: id, handle: handle, pre: pre, changed: true)
                case .ignore:
                    break
                }
            }
            .onEnded { value in
                let point = pixelPoint(value.location)
                let start = pixelPoint(value.startLocation)
                end(start: start, point: point)
                gesturePhase = .idle
            }
    }

    private var doubleTapGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                let point = pixelPoint(value.location)
                if let hit = doc.hitTest(point), hit.isTextual {
                    doc.tool = .select
                    doc.beginTextEditing(hit.id)
                }
            }
    }

    private func begin(at start: CGPoint, current: CGPoint) {
        doc.endTextEditing()

        switch doc.tool {
        case .select:
            // A handle on the current selection wins over body hits, so small
            // annotations can still be resized.
            if let selectedID = doc.selectedID,
               let selected = doc.annotation(selectedID),
               let (handle, _) = selected.handlePositions(unit: doc.unit).first(where: { _, pos in
                   hypot(pos.x - start.x, pos.y - start.y) <= 14 * doc.unit
               }) {
                gesturePhase = .resizing(id: selectedID, handle: handle, pre: doc.snapshot(), changed: false)
            } else if let hit = doc.hitTest(start) {
                doc.selectedID = hit.id
                gesturePhase = .moving(id: hit.id, last: current, pre: doc.snapshot(), moved: false)
            } else {
                doc.selectedID = nil
                gesturePhase = .ignore
            }
        case .crop:
            doc.cropDraft = CGRect(points: start, current).clamped(to: doc.pixelSize)
            gesturePhase = .cropping
        case .text, .step:
            gesturePhase = .ignore // placed on mouse-up
        default:
            doc.draft = makeDraft(start: start, current: current)
            gesturePhase = .drawing
        }
    }

    private func updateDraft(start: CGPoint, current: CGPoint) {
        guard var draft = doc.draft else { return }
        switch draft.shape {
        case .arrow: draft.shape = .arrow(start: start, end: current)
        case .line: draft.shape = .line(start: start, end: current)
        case .box: draft.shape = .box(CGRect(points: start, current))
        case .ellipse: draft.shape = .ellipse(CGRect(points: start, current))
        case .pen(var pts):
            pts.append(current)
            draft.shape = .pen(pts)
        case .highlighter(var pts):
            pts.append(current)
            draft.shape = .highlighter(pts)
        case .callout:
            let rect = CGRect(points: start, current)
            draft.shape = .callout(rect, tail: defaultTail(for: rect))
        case .blur: draft.shape = .blur(CGRect(points: start, current))
        case .redact: draft.shape = .redact(CGRect(points: start, current))
        case .text, .step: break
        }
        doc.draft = draft
    }

    private func end(start: CGPoint, point: CGPoint) {
        switch gesturePhase {
        case .moving(_, _, let pre, let moved):
            if moved { doc.commit(pre) }

        case .resizing(_, _, let pre, let changed):
            if changed { doc.commit(pre) }

        case .cropping:
            if let crop = doc.cropDraft, crop.width < 5 || crop.height < 5 {
                doc.cropDraft = nil
            }

        case .drawing:
            defer { doc.draft = nil }
            guard let draft = doc.draft, draftIsMeaningful(draft) else { break }
            if case .callout = draft.shape {
                // Creation + typed text become one undo step.
                let pre = doc.snapshot()
                doc.annotations.append(draft)
                doc.tool = .select
                doc.beginTextEditing(draft.id, pre: pre)
                textFieldFocused = true
            } else {
                doc.add(draft)
            }

        case .ignore where doc.tool == .text:
            var annotation = baseAnnotation()
            annotation.shape = .text(start)
            let pre = doc.snapshot()
            doc.annotations.append(annotation)
            doc.beginTextEditing(annotation.id, pre: pre)
            textFieldFocused = true

        case .ignore where doc.tool == .step:
            var annotation = baseAnnotation()
            annotation.shape = .step(start)
            annotation.number = doc.stepCounter
            let pre = doc.snapshot()
            doc.annotations.append(annotation)
            doc.stepCounter += 1
            doc.commit(pre)

        default:
            break
        }
    }

    private func makeDraft(start: CGPoint, current: CGPoint) -> Annotation {
        var annotation = baseAnnotation()
        switch doc.tool {
        case .arrow: annotation.shape = .arrow(start: start, end: current)
        case .line: annotation.shape = .line(start: start, end: current)
        case .box: annotation.shape = .box(CGRect(points: start, current))
        case .ellipse: annotation.shape = .ellipse(CGRect(points: start, current))
        case .pen: annotation.shape = .pen([start, current])
        case .highlighter: annotation.shape = .highlighter([start, current])
        case .callout:
            let rect = CGRect(points: start, current)
            annotation.shape = .callout(rect, tail: defaultTail(for: rect))
        case .blur: annotation.shape = .blur(CGRect(points: start, current))
        case .redact: annotation.shape = .redact(CGRect(points: start, current))
        default: annotation.shape = .line(start: start, end: current)
        }
        return annotation
    }

    private func baseAnnotation() -> Annotation {
        Annotation(
            shape: .line(start: .zero, end: .zero),
            color: doc.color,
            strokeWidth: doc.strokeWidth,
            fontSize: doc.fontSize
        )
    }

    private func defaultTail(for rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * 0.25, y: rect.maxY + max(30 * doc.unit, rect.height * 0.6))
    }

    private func draftIsMeaningful(_ draft: Annotation) -> Bool {
        switch draft.shape {
        case .arrow(let a, let b), .line(let a, let b):
            return hypot(b.x - a.x, b.y - a.y) > 4 * doc.unit
        case .box(let r), .ellipse(let r), .blur(let r), .redact(let r):
            return r.width > 4 * doc.unit && r.height > 4 * doc.unit
        case .callout(let r, _):
            return r.width > 20 * doc.unit && r.height > 16 * doc.unit
        case .pen(let pts), .highlighter(let pts):
            return pts.count > 2
        case .text, .step:
            return true
        }
    }

    private func pixelPoint(_ viewPoint: CGPoint) -> CGPoint {
        CGPoint(x: viewPoint.x / fitScale, y: viewPoint.y / fitScale)
    }

    // MARK: - Inline text editing

    @ViewBuilder
    private var textEditorOverlay: some View {
        if let id = doc.editingID, let annotation = doc.annotation(id) {
            let origin = annotation.textEditingOrigin
            let isCallout: Bool = {
                if case .callout = annotation.shape { return true }
                return false
            }()
            let width: CGFloat = {
                if case .callout(let rect, _) = annotation.shape {
                    return max(80, rect.width * fitScale)
                }
                return 280
            }()

            TextField(
                "Text",
                text: Binding(
                    get: { doc.annotation(id)?.text ?? "" },
                    set: { doc.updateText(id, $0) }
                ),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: annotation.fontSize * doc.unit * fitScale, weight: .semibold))
            .foregroundStyle(isCallout ? Color.white : annotation.color)
            .padding(4)
            .frame(width: width)
            .background(.black.opacity(isCallout ? 0 : 0.06))
            .overlay(Rectangle().strokeBorder(Color.blue.opacity(0.7), lineWidth: 1))
            .focused($textFieldFocused)
            .onSubmit { doc.endTextEditing() }
            .onAppear { textFieldFocused = true }
            .offset(
                x: origin.x * fitScale + (isCallout ? 6 : 0),
                y: origin.y * fitScale + (isCallout ? 4 : 0)
            )
        }
    }
}

/// Full-resolution flatten target used by `ImageRenderer` at export time.
struct ExportRenderView: View {
    let doc: EditorDocument

    var body: some View {
        let unit = doc.unit
        let pad: CGFloat = doc.shadowOn ? 36 * unit : 0
        EditorCanvas(doc: doc, fitScale: 1, interactive: false)
            .clipShape(RoundedRectangle(cornerRadius: doc.cornerRadius * unit))
            .overlay {
                if doc.borderOn {
                    RoundedRectangle(cornerRadius: doc.cornerRadius * unit)
                        .strokeBorder(doc.borderColor, lineWidth: doc.borderWidth * unit)
                }
            }
            .shadow(
                color: doc.shadowOn ? .black.opacity(0.4) : .clear,
                radius: doc.shadowOn ? 12 * unit : 0,
                y: doc.shadowOn ? 5 * unit : 0
            )
            .padding(pad)
    }
}

extension CGRect {
    func clamped(to size: CGSize) -> CGRect {
        intersection(CGRect(origin: .zero, size: size))
    }
}
