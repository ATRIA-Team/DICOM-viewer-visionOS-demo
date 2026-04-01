//
//  PencilCanvas.swift
//  DemoDICOM
//

import SwiftUI
import UIKit

// MARK: - PencilCanvasState

/// Observable object that bridges UIKit stroke state to SwiftUI.
/// `AnnotationView` holds one as `@State` and uses it to drive
/// the undo / clear toolbar buttons and to check whether strokes exist.
@Observable
final class PencilCanvasState {

    /// Number of completed strokes — drives toolbar button enabled states.
    private(set) var strokeCount: Int = 0

    /// Weak reference to the underlying UIView, set by the representable.
    fileprivate weak var canvasView: PencilCanvasUIView? {
        didSet { syncCount() }
    }

    func undo() {
        canvasView?.undo()
        syncCount()
    }

    func clear() {
        canvasView?.clear()
        syncCount()
    }

    /// Removes only the strokes whose IDs are in `ids`, leaving all others intact.
    func removeStrokes(ids: Set<UUID>) {
        canvasView?.removeStrokes(ids: ids)
        syncCount()
    }

    /// Composites the DICOM image and all drawn strokes into a single `UIImage`.
    /// Returns `nil` if the canvas view is not yet attached or has zero size.
    func snapshot(backgroundCGImage: CGImage) -> UIImage? {
        canvasView?.snapshot(backgroundCGImage: backgroundCGImage)
    }

    private func syncCount() {
        strokeCount = canvasView?.strokeCount ?? 0
    }

    /// Called by the UIView whenever a stroke is completed.
    fileprivate func strokeCompleted() {
        strokeCount = canvasView?.strokeCount ?? 0
    }
}

// MARK: - PencilCanvasUIView

/// UIView that captures Apple Pencil Pro touches and renders strokes
/// as `CAShapeLayer`s — one per completed stroke, for easy undo.
final class PencilCanvasUIView: UIView {

    // MARK: Public settings (updated by the representable on SwiftUI re-render)

    var brushColor: UIColor = .red   { didSet { /* affects next stroke only */ } }
    var brushSize:  CGFloat = 3.0

    /// How many completed strokes are stored (used by `PencilCanvasState`).
    private(set) var strokeCount: Int = 0

    // MARK: Callbacks

    var onStrokeCompleted: (() -> Void)?

    /// Called for every stylus point — including start and end of each stroke.
    /// Parameters: strokeID, normalizedPoint (0-1), isStart, isEnd, colorR, colorG, colorB, lineWidth.
    var onAnnotationPoint: ((UUID, CGPoint, Bool, Bool, Float, Float, Float, Float) -> Void)?

    // MARK: Private state

    /// Completed strokes, each paired with the UUID used for SharePlay sync.
    private var strokeLayers:   [(id: UUID, layer: CAShapeLayer)] = []
    private var currentPath:    UIBezierPath?
    private var currentLayer:   CAShapeLayer?
    private var currentStrokeID = UUID()

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Public API

    /// Renders the DICOM image + all strokes into a single `UIImage`.
    /// The CGImage is drawn scaled to fill the view bounds; stroke layers are
    /// composited on top in the same coordinate space.
    func snapshot(backgroundCGImage: CGImage) -> UIImage {
        let size = bounds.size.width > 0 ? bounds.size : CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext
            // CGImage origin is bottom-left; UIKit is top-left — flip to draw upright
            cgCtx.saveGState()
            cgCtx.translateBy(x: 0, y: size.height)
            cgCtx.scaleBy(x: 1, y: -1)
            cgCtx.draw(backgroundCGImage, in: CGRect(origin: .zero, size: size))
            cgCtx.restoreGState()
            // Render all stroke CAShapeLayers on top
            layer.render(in: cgCtx)
        }
    }

    func undo() {
        guard let last = strokeLayers.popLast() else { return }
        last.layer.removeFromSuperlayer()
        strokeCount = strokeLayers.count
    }

    func clear() {
        strokeLayers.forEach { $0.layer.removeFromSuperlayer() }
        strokeLayers = []
        currentLayer?.removeFromSuperlayer()
        currentLayer = nil
        currentPath  = nil
        strokeCount  = 0
    }

    /// Removes only the strokes matching `ids`, leaving all others visible.
    func removeStrokes(ids: Set<UUID>) {
        strokeLayers = strokeLayers.filter { entry in
            guard ids.contains(entry.id) else { return true }
            entry.layer.removeFromSuperlayer()
            return false
        }
        strokeCount = strokeLayers.count
    }

    // MARK: Touch handling — Apple Pencil Pro only

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch.type == .pencil else { return }

        let point = touch.location(in: self)
        let path  = UIBezierPath()
        path.move(to: point)
        currentPath = path
        currentStrokeID = UUID()

        let shapeLayer = makeShapeLayer()
        layer.addSublayer(shapeLayer)
        currentLayer = shapeLayer

        emitPoint(point, isStart: true, isEnd: false)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch.type == .pencil,
              let path = currentPath else { return }

        // Coalesced touches give higher-resolution input with lower latency
        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        for sample in samples {
            let pt = sample.location(in: self)
            path.addLine(to: pt)
            emitPoint(pt, isStart: false, isEnd: false)
        }
        currentLayer?.path = path.cgPath
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch.type == .pencil else { return }
        emitPoint(touch.location(in: self), isStart: false, isEnd: true)
        finaliseStroke()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Discard the in-progress stroke on cancellation
        currentLayer?.removeFromSuperlayer()
        currentLayer = nil
        currentPath  = nil
    }

    // MARK: Private helpers

    private func normalizedPoint(_ point: CGPoint) -> CGPoint {
        let w = bounds.width  > 0 ? bounds.width  : 1
        let h = bounds.height > 0 ? bounds.height : 1
        return CGPoint(x: point.x / w, y: point.y / h)
    }

    private func emitPoint(_ point: CGPoint, isStart: Bool, isEnd: Bool) {
        guard let onAnnotationPoint else { return }
        var r: CGFloat = 1, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        brushColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let n = normalizedPoint(point)
        onAnnotationPoint(currentStrokeID, n, isStart, isEnd, Float(r), Float(g), Float(b), Float(brushSize))
    }

    private func makeShapeLayer() -> CAShapeLayer {
        let sl = CAShapeLayer()
        sl.strokeColor = brushColor.cgColor
        sl.lineWidth   = brushSize
        sl.lineCap     = .round
        sl.lineJoin    = .round
        sl.fillColor   = UIColor.clear.cgColor
        return sl
    }

    private func finaliseStroke() {
        guard let layer = currentLayer else { return }
        strokeLayers.append((id: currentStrokeID, layer: layer))
        strokeCount = strokeLayers.count
        currentLayer = nil
        currentPath  = nil
        onStrokeCompleted?()
    }
}

// MARK: - PencilCanvas (UIViewRepresentable)

/// SwiftUI wrapper around `PencilCanvasUIView`.
///
/// - `state` is an `@Observable` object owned by `AnnotationView`.
///   The representable wires the UIView into it so that SwiftUI can
///   call `state.undo()` / `state.clear()` from toolbar buttons.
/// - `onAnnotationPoint` is forwarded to the UIView so callers can stream
///   normalized stroke points for real-time SharePlay sync.
struct PencilCanvas: UIViewRepresentable {

    /// Shared state object — owned by `AnnotationView`.
    let state: PencilCanvasState

    /// Current brush settings, passed down on every SwiftUI re-render.
    let brushColor: Color
    let brushSize:  CGFloat

    /// Optional callback for every stylus point (start, move, end of each stroke).
    /// Parameters: strokeID, normalizedPoint (0-1), isStart, isEnd, colorR, colorG, colorB, lineWidth.
    var onAnnotationPoint: ((UUID, CGPoint, Bool, Bool, Float, Float, Float, Float) -> Void)?

    func makeUIView(context: Context) -> PencilCanvasUIView {
        let view = PencilCanvasUIView()
        // Wire the UIView back into the observable state object
        state.canvasView = view
        view.onStrokeCompleted = { [weak state] in
            state?.strokeCompleted()
        }
        view.onAnnotationPoint = onAnnotationPoint
        return view
    }

    func updateUIView(_ uiView: PencilCanvasUIView, context: Context) {
        uiView.brushColor = UIColor(brushColor)
        uiView.brushSize  = brushSize
        uiView.onAnnotationPoint = onAnnotationPoint
    }
}
