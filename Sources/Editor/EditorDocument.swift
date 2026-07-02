import AppKit
import CoreImage
import SwiftUI

/// State for one editor window: the base image, annotations, tool settings,
/// snapshot-based undo, and final flattened rendering.
@MainActor
final class EditorDocument: ObservableObject {
    @Published private(set) var baseImage: CGImage {
        didSet { pixelatedCache = nil }
    }
    /// Backing scale the capture was taken at (2.0 on HiDPI displays). Stroke
    /// widths and font sizes are specified in points and multiplied by this.
    let scale: CGFloat

    @Published var annotations: [Annotation] = []
    @Published var draft: Annotation?
    @Published var selectedID: UUID?
    @Published var editingID: UUID?
    @Published var cropDraft: CGRect?

    @Published var tool: Tool = .arrow {
        didSet {
            if tool != .select { selectedID = nil }
            if tool != .crop { cropDraft = nil }
            endTextEditing()
        }
    }
    @Published var color: Color = Color(red: 0.93, green: 0.25, blue: 0.18)
    @Published var strokeWidth: CGFloat = 4
    @Published var fontSize: CGFloat = 22
    @Published var stepCounter = 1

    // Effects
    @Published var borderOn = false
    @Published var borderColor: Color = .black
    @Published var borderWidth: CGFloat = 3
    @Published var shadowOn = false
    @Published var cornerRadius: CGFloat = 0

    var unit: CGFloat { max(1, scale) }
    var pixelSize: CGSize { CGSize(width: baseImage.width, height: baseImage.height) }

    init(capture: Capture) {
        self.baseImage = capture.image
        self.scale = capture.scale
    }

    // MARK: - Undo (snapshot-based; annotations are value types)

    struct Snapshot {
        var image: CGImage
        var annotations: [Annotation]
        var stepCounter: Int
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var editingPreSnapshot: Snapshot?

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func snapshot() -> Snapshot {
        Snapshot(image: baseImage, annotations: annotations, stepCounter: stepCounter)
    }

    /// Record `pre` (taken before a mutation) as an undoable step.
    func commit(_ pre: Snapshot) {
        undoStack.append(pre)
        redoStack.removeAll()
    }

    func undo() {
        endTextEditing()
        guard let snap = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        restore(snap)
    }

    func redo() {
        endTextEditing()
        guard let snap = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        restore(snap)
    }

    private func restore(_ snap: Snapshot) {
        baseImage = snap.image
        annotations = snap.annotations
        stepCounter = snap.stepCounter
        selectedID = nil
        editingID = nil
        cropDraft = nil
        draft = nil
    }

    // MARK: - Annotation mutations

    func annotation(_ id: UUID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    func add(_ annotation: Annotation) {
        let pre = snapshot()
        annotations.append(annotation)
        commit(pre)
    }

    func updateText(_ id: UUID, _ text: String) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[idx].text = text
    }

    func translateAnnotation(_ id: UUID, by delta: CGSize) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[idx].translate(by: delta)
    }

    func moveHandle(_ id: UUID, _ handle: Annotation.Handle, to point: CGPoint) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[idx].moveHandle(handle, to: point)
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        let pre = snapshot()
        annotations.removeAll { $0.id == id }
        selectedID = nil
        commit(pre)
    }

    func hitTest(_ point: CGPoint) -> Annotation? {
        annotations.reversed().first { $0.hitTest(point, unit: unit) }
    }

    /// Remove every annotation as a single undoable step.
    func clearAnnotations() {
        endTextEditing()
        guard !annotations.isEmpty else { return }
        let pre = snapshot()
        annotations.removeAll()
        selectedID = nil
        commit(pre)
    }

    // MARK: - Text editing

    /// Pass `pre` when the annotation was just created so its creation and the
    /// typed text collapse into a single undo step.
    func beginTextEditing(_ id: UUID, pre: Snapshot? = nil) {
        editingPreSnapshot = pre ?? snapshot()
        editingID = id
        selectedID = nil
    }

    func endTextEditing() {
        guard let id = editingID else { return }
        editingID = nil
        let pre = editingPreSnapshot
        editingPreSnapshot = nil
        guard let annotation = annotation(id) else { return }

        let isEmptyTextAnnotation: Bool = {
            guard case .text = annotation.shape else { return false }
            return annotation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }()
        if isEmptyTextAnnotation {
            // A plain text annotation with nothing typed is invisible — drop it.
            // Callouts keep their bubble even when empty.
            annotations.removeAll { $0.id == id }
        } else if let pre {
            commit(pre)
        }
    }

    // MARK: - Crop

    func applyCrop() {
        guard let rect = cropDraft else { return }
        let imageRect = CGRect(origin: .zero, size: pixelSize)
        let target = rect.integral.intersection(imageRect)
        guard target.width > 4, target.height > 4,
              let cropped = baseImage.cropping(to: target) else {
            cropDraft = nil
            return
        }
        let pre = snapshot()
        baseImage = cropped
        let delta = CGSize(width: -target.minX, height: -target.minY)
        for idx in annotations.indices {
            annotations[idx].translate(by: delta)
        }
        commit(pre)
        cropDraft = nil
        tool = .select
    }

    func cancelCrop() {
        cropDraft = nil
    }

    // MARK: - Pixelated companion image (for blur regions)

    private var pixelatedCache: CGImage?

    var pixelated: CGImage? {
        if let pixelatedCache { return pixelatedCache }
        let input = CIImage(cgImage: baseImage)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(max(10, min(pixelSize.width, pixelSize.height) / 45), forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)
        guard let output = filter.outputImage else { return nil }
        let context = CIContext()
        pixelatedCache = context.createCGImage(output.cropped(to: input.extent), from: input.extent)
        return pixelatedCache
    }

    // MARK: - Final render

    /// Flatten the image + annotations + effects at full pixel resolution.
    func renderFinal() -> CGImage? {
        endTextEditing()
        selectedID = nil
        cropDraft = nil

        let renderer = ImageRenderer(content: ExportRenderView(doc: self))
        renderer.scale = 1
        renderer.isOpaque = false
        guard let nsImage = renderer.nsImage else { return nil }
        var rect = CGRect(origin: .zero, size: nsImage.size)
        return nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    func saveFlattened() {
        guard let image = renderFinal() else { return }
        Exporter.save(image: image, scale: scale)
    }

    func copyFlattened() {
        guard let image = renderFinal() else { return }
        Exporter.copyToClipboard(image: image, scale: scale)
    }
}
