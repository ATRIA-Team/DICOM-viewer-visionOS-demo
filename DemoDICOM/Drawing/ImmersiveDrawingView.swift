//
//  ImmersiveDrawingView.swift
//  DemoDICOM
//
//  Adapted from SharedSpaceExample2 by Igor Tarantino.
//

import SwiftUI
import RealityKit
import ARKit

/// Mixed-immersion RealityKit space that:
/// - Tracks the spatial stylus via `StylusTipManager`
/// - Draws 3D tube strokes when the primary button is held
/// - Broadcasts each stroke point to SharePlay peers in real time
/// - Receives peer stroke points and clears via `NotificationCenter`
struct ImmersiveDrawingView: View {

    @Environment(DICOMStore.self) private var store
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var drawingRoot  = Entity()
    @State private var stylusManager = StylusTipManager()

    @State private var activeStrokes: [UUID: StrokeEntity] = [:]
    @State private var currentLocalStrokeID: UUID?
    @State private var lastTipPosition: SIMD3<Float>?

    // MARK: - Body

    var body: some View {
        RealityView { content in
            // Drawing strokes live here
            content.add(drawingRoot)

            // Stylus anchors need a root entity in the RealityKit scene
            let stylusRoot = Entity()
            content.add(stylusRoot)
            stylusManager.rootEntity = stylusRoot
            await stylusManager.handleControllerSetup()
        }
        // Open the floating brush-controls window when the immersive space starts
        .onAppear {
            openWindow(id: "drawingTools")
        }
        // Close it when the immersive space ends (e.g. dismissed from elsewhere)
        .onDisappear {
            dismissWindow(id: "drawingTools")
        }
        // Receive remote draw points from peers
        .onReceive(
            NotificationCenter.default.publisher(for: .remoteDrawPoint)
        ) { notification in
            guard let message = notification.object as? DrawPointMessage else { return }
            let color = UIColor(
                red:   CGFloat(message.color.x),
                green: CGFloat(message.color.y),
                blue:  CGFloat(message.color.z),
                alpha: CGFloat(message.color.w)
            )
            addPoint(
                strokeID:  message.strokeID,
                point:     message.point,
                thickness: message.thickness,
                color:     color,
                isLocal:   false
            )
        }
        // Receive clear-drawings command (local or remote)
        .onReceive(
            NotificationCenter.default.publisher(for: .clearAllDrawings)
        ) { _ in
            drawingRoot.children.removeAll()
            activeStrokes.removeAll()
        }
        // Main drawing loop — runs for the lifetime of this immersive space
        .task { await runDrawingLoop() }
    }

    // MARK: - Drawing loop

    /// Polls the stylus tip position every 10 ms and emits stroke points
    /// while the primary button is held. Points closer than 5 mm to the
    /// previous point are skipped to keep the mesh density reasonable.
    private func runDrawingLoop() async {
        let configuration = SpatialTrackingSession.Configuration(tracking: [.accessory])
        let session = SpatialTrackingSession()
        await session.run(configuration)

        while !Task.isCancelled {
            if stylusManager.isPrimaryButtonPressed == true,
               let currentPos = stylusManager.getTipPosition() {

                let strokeID = currentLocalStrokeID ?? UUID()
                currentLocalStrokeID = strokeID

                let farEnough: Bool
                if let last = lastTipPosition {
                    farEnough = simd_distance(currentPos, last) > 0.005
                } else {
                    farEnough = true
                }

                if farEnough {
                    let color = UIColor(store.drawing.brushColor)
                    addPoint(
                        strokeID:  strokeID,
                        point:     currentPos,
                        thickness: store.drawing.brushSize,
                        color:     color,
                        isLocal:   true
                    )
                    lastTipPosition = currentPos
                }
            } else {
                currentLocalStrokeID = nil
                lastTipPosition = nil
            }

            try? await Task.sleep(nanoseconds: 10_000_000)   // ~10 ms
        }
    }

    // MARK: - Stroke management

    private func addPoint(
        strokeID: UUID,
        point: SIMD3<Float>,
        thickness: Float,
        color: UIColor,
        isLocal: Bool
    ) {
        // Create stroke entity on first point
        if activeStrokes[strokeID] == nil {
            let stroke = StrokeEntity(thickness: thickness, color: color)
            drawingRoot.addChild(stroke)
            activeStrokes[strokeID] = stroke
        }
        activeStrokes[strokeID]?.addPoint(point)

        // Broadcast to peers only for locally drawn points
        if isLocal {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            store.sharePlay.sendDrawPoint(
                strokeID:  strokeID,
                point:     point,
                thickness: thickness,
                color:     SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))
            )
        }
    }
}

// MARK: - DrawingToolsPanel

/// Floating brush-controls window opened automatically alongside the DrawingSpace.
/// Declared as a separate WindowGroup so visionOS makes it draggable.
struct DrawingToolsPanel: View {

    @Environment(DICOMStore.self) private var store
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 14) {
            HStack {
                Text("Drawing Tools")
                    .font(.headline)
                Spacer()
                Button {
                    Task {
                        dismissWindow(id: "drawingTools")
                        await dismissImmersiveSpace()
                        store.isDrawingActive = false
                    }
                } label: {
                    Label("Stop Drawing", systemImage: "pencil.slash")
                }
                .tint(.orange)
            }

            Divider()

            HStack {
                Text("Color")
                Spacer()
                ColorPicker("Brush Color", selection: $store.drawing.brushColor, supportsOpacity: false)
                    .labelsHidden()
            }

            HStack {
                Text("Size")
                Slider(value: $store.drawing.brushSize, in: 0.001...0.02, step: 0.001)
                Text(String(format: "%.0f mm", store.drawing.brushSize * 1000))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }

            Button(role: .destructive) {
                store.drawing.receiveClearDrawings()
                store.sharePlay.sendClearDrawings()
            } label: {
                Label("Clear All", systemImage: "trash")
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
