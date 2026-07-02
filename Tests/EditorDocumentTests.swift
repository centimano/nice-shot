import Testing
import SwiftUI
@testable import NiceShot

private let runningOnCI = ProcessInfo.processInfo.environment["CI"] != nil

@MainActor
struct EditorDocumentTests {
    private func makeDoc(width: Int = 200, height: Int = 100, scale: CGFloat = 1) -> EditorDocument {
        EditorDocument(capture: makeTestCapture(width: width, height: height, scale: scale))
    }

    private var sampleBox: Annotation {
        .test(.box(CGRect(x: 60, y: 30, width: 40, height: 20)))
    }

    // MARK: Undo / redo

    @Test func addIsUndoable() {
        let doc = makeDoc()
        doc.add(sampleBox)
        #expect(doc.annotations.count == 1)
        #expect(doc.canUndo)
        doc.undo()
        #expect(doc.annotations.count == 0)
        #expect(!doc.canUndo)
    }

    @Test func redoRestoresUndoneWork() {
        let doc = makeDoc()
        doc.add(sampleBox)
        doc.undo()
        #expect(doc.canRedo)
        doc.redo()
        #expect(doc.annotations.count == 1)
        #expect(!doc.canRedo)
    }

    @Test func newActionClearsRedoStack() {
        let doc = makeDoc()
        doc.add(sampleBox)
        doc.undo()
        doc.add(sampleBox)
        #expect(!doc.canRedo, "a fresh action must invalidate the redo history")
    }

    @Test func undoRestoresStepCounter() {
        let doc = makeDoc()
        let pre = doc.snapshot()
        doc.annotations.append(.test(.step(CGPoint(x: 10, y: 10)), number: 1))
        doc.stepCounter = 2
        doc.commit(pre)
        doc.undo()
        #expect(doc.stepCounter == 1)
        #expect(doc.annotations.count == 0)
    }

    // MARK: Selection & deletion

    @Test func deleteSelectedIsUndoable() {
        let doc = makeDoc()
        doc.add(sampleBox)
        doc.selectedID = doc.annotations[0].id
        doc.deleteSelected()
        #expect(doc.annotations.count == 0)
        #expect(doc.selectedID == nil)
        doc.undo()
        #expect(doc.annotations.count == 1)
    }

    @Test func clearAnnotationsIsOneUndoStep() {
        let doc = makeDoc()
        doc.add(sampleBox)
        doc.add(.test(.step(CGPoint(x: 20, y: 20)), number: 1))
        doc.selectedID = doc.annotations[0].id
        doc.clearAnnotations()
        #expect(doc.annotations.isEmpty)
        #expect(doc.selectedID == nil)
        doc.undo()
        #expect(doc.annotations.count == 2, "clearing everything should undo in one step")
    }

    @Test func clearOnEmptyDocumentIsNoOp() {
        let doc = makeDoc()
        doc.clearAnnotations()
        #expect(!doc.canUndo)
    }

    @Test func deleteWithoutSelectionIsNoOp() {
        let doc = makeDoc()
        doc.add(sampleBox)
        doc.deleteSelected()
        #expect(doc.annotations.count == 1)
    }

    @Test func hitTestPrefersTopmostAnnotation() {
        let doc = makeDoc()
        let bottom = Annotation.test(.box(CGRect(x: 10, y: 10, width: 50, height: 50)))
        let top = Annotation.test(.box(CGRect(x: 10, y: 10, width: 50, height: 50)))
        doc.annotations = [bottom, top]
        #expect(doc.hitTest(CGPoint(x: 30, y: 30))?.id == top.id)
    }

    @Test func toolSwitchClearsSelectionAndCrop() {
        let doc = makeDoc()
        doc.add(sampleBox)
        doc.tool = .select
        doc.selectedID = doc.annotations[0].id
        doc.tool = .arrow
        #expect(doc.selectedID == nil)

        doc.tool = .crop
        doc.cropDraft = CGRect(x: 0, y: 0, width: 50, height: 50)
        doc.tool = .select
        #expect(doc.cropDraft == nil)
    }

    // MARK: Crop

    @Test func applyCropAdjustsImageAndAnnotations() {
        let doc = makeDoc(width: 200, height: 100)
        doc.add(sampleBox) // at (60, 30)
        doc.cropDraft = CGRect(x: 50, y: 20, width: 100, height: 60)
        doc.applyCrop()

        #expect(doc.baseImage.width == 100)
        #expect(doc.baseImage.height == 60)
        guard case .box(let rect) = doc.annotations[0].shape else { Issue.record("annotation lost"); return }
        #expect(rect.origin == CGPoint(x: 10, y: 10), "annotations must shift with the crop")
        #expect(doc.cropDraft == nil)
    }

    @Test func applyCropClampsToImageBounds() {
        let doc = makeDoc(width: 200, height: 100)
        doc.cropDraft = CGRect(x: -50, y: -50, width: 1000, height: 1000)
        doc.applyCrop()
        #expect(doc.baseImage.width == 200)
        #expect(doc.baseImage.height == 100)
    }

    @Test func cropIsUndoable() {
        let doc = makeDoc(width: 200, height: 100)
        doc.cropDraft = CGRect(x: 0, y: 0, width: 80, height: 40)
        doc.applyCrop()
        #expect(doc.baseImage.width == 80)
        doc.undo()
        #expect(doc.baseImage.width == 200)
        #expect(doc.baseImage.height == 100)
    }

    @Test func tinyCropIsRejected() {
        let doc = makeDoc()
        doc.cropDraft = CGRect(x: 10, y: 10, width: 2, height: 2)
        doc.applyCrop()
        #expect(doc.baseImage.width == 200, "a sub-5px crop should be ignored")
        #expect(!doc.canUndo)
    }

    // MARK: Text editing lifecycle

    @Test func emptyTextAnnotationIsDiscarded() {
        let doc = makeDoc()
        let annotation = Annotation.test(.text(CGPoint(x: 10, y: 10)))
        let pre = doc.snapshot()
        doc.annotations.append(annotation)
        doc.beginTextEditing(annotation.id, pre: pre)
        doc.updateText(annotation.id, "   ")
        doc.endTextEditing()
        #expect(doc.annotations.count == 0)
        #expect(!doc.canUndo, "nothing user-visible happened, so nothing to undo")
    }

    @Test func textCreationIsOneUndoStep() {
        let doc = makeDoc()
        let annotation = Annotation.test(.text(CGPoint(x: 10, y: 10)))
        let pre = doc.snapshot()
        doc.annotations.append(annotation)
        doc.beginTextEditing(annotation.id, pre: pre)
        doc.updateText(annotation.id, "Hello")
        doc.endTextEditing()

        #expect(doc.annotations.first?.text == "Hello")
        doc.undo()
        #expect(doc.annotations.count == 0, "creation + typing should undo together")
    }

    @Test func emptyCalloutIsKept() {
        let doc = makeDoc()
        let annotation = Annotation.test(
            .callout(CGRect(x: 10, y: 10, width: 80, height: 40), tail: CGPoint(x: 5, y: 90))
        )
        let pre = doc.snapshot()
        doc.annotations.append(annotation)
        doc.beginTextEditing(annotation.id, pre: pre)
        doc.endTextEditing()
        #expect(doc.annotations.count == 1, "an empty callout bubble is still visible content")
    }

    @Test func reEditCommitsTextChange() {
        let doc = makeDoc()
        let annotation = Annotation.test(.text(CGPoint(x: 10, y: 10)), text: "old")
        doc.add(annotation)
        doc.beginTextEditing(annotation.id)
        doc.updateText(annotation.id, "new")
        doc.endTextEditing()
        #expect(doc.annotations.first?.text == "new")
        doc.undo()
        #expect(doc.annotations.first?.text == "old")
    }

    // MARK: Handles via document

    @Test func moveHandleThroughDocument() {
        let doc = makeDoc()
        doc.add(sampleBox)
        let id = doc.annotations[0].id
        doc.moveHandle(id, .bottomRight, to: CGPoint(x: 150, y: 90))
        guard case .box(let rect) = doc.annotations[0].shape else { Issue.record("annotation lost"); return }
        #expect(rect == CGRect(x: 60, y: 30, width: 90, height: 60))
    }

    // MARK: Derived images

    @Test func unitNeverBelowOne() {
        #expect(makeDoc(scale: 1).unit == 1)
        #expect(makeDoc(scale: 2).unit == 2)
    }

    @Test func pixelatedCompanionMatchesImageSize() {
        let doc = makeDoc(width: 120, height: 80)
        let pixelated = doc.pixelated
        #expect(pixelated != nil)
        #expect(pixelated?.width == 120)
        #expect(pixelated?.height == 80)
    }

    // MARK: Flattened export (skipped on CI: needs a GUI session)

    @Test(.disabled(if: runningOnCI, "ImageRenderer needs a GUI session"))
    func renderFinalMatchesPixelSize() {
        let doc = makeDoc(width: 200, height: 100)
        doc.add(sampleBox)
        let rendered = doc.renderFinal()
        #expect(rendered?.width == 200)
        #expect(rendered?.height == 100)
    }

    @Test(.disabled(if: runningOnCI, "ImageRenderer needs a GUI session"))
    func renderFinalShadowAddsMargin() {
        let doc = makeDoc(width: 200, height: 100)
        doc.shadowOn = true
        let rendered = doc.renderFinal()
        // 36 px of shadow padding per side at unit scale 1.
        #expect(rendered?.width == 272)
        #expect(rendered?.height == 172)
    }
}
