//
//  ContentView.swift
//  DemoDICOM
//
//  Created by Michele Coppola on 25/03/2026.
//

import SwiftUI
import DicomCore
import UniformTypeIdentifiers

// MARK: - Window interaction disabler

/// Invisible UIView that finds its parent UIWindow and toggles
/// `isUserInteractionEnabled` so visionOS stops routing stylus
/// button presses as indirect-pointer clicks into this window.
private struct WindowInteractionToggle: UIViewRepresentable {
    var enabled: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isHidden = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            uiView.window?.isUserInteractionEnabled = enabled
        }
    }
}

struct ContentView: View {

    /// The store is owned by `DemoDICOMApp` and shared via the environment.
    @Environment(DICOMStore.self) private var store

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        // `@Bindable` lets us derive SwiftUI bindings from the @Observable store
        // for modifiers that require them (fileImporter, etc.).
        @Bindable var store = store

        NavigationStack {
            Group {
                if store.sliceImages.isEmpty && !store.isLoading {
                    emptyStateView
                } else {
                    sliceViewerView
                }
            }
            .navigationTitle("DICOM Viewer")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    sharePlayButton
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    drawingToggleButton
                    Button {
                        store.isShowingFolderPicker = true
                    } label: {
                        Label("Import CT Scan", systemImage: "folder.badge.plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $store.isShowingFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { store.importFolder(url: url) }
                case .failure(let error):
                    store.errorMessage = "File picker error: \(error.localizedDescription)"
                }
            }
            .overlay {
                if store.isLoading { loadingOverlay }
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { store.errorMessage != nil },
                    set: { if !$0 { store.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
        // Disable window interaction while drawing so the stylus button
        // isn't intercepted as a pointer click by visionOS.
        .background {
            WindowInteractionToggle(enabled: !store.isDrawingActive)
        }
    }

    // MARK: - Subviews

    /// Shows SharePlay session status, or an invitation button when not in session.
    private var sharePlayButton: some View {
        Group {
            if store.sharePlay.isInSession {
                Label(
                    "\(store.sharePlay.participantCount) in session",
                    systemImage: "shareplay"
                )
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
            } else {
                Button {
                    Task { await store.sharePlay.activate() }
                } label: {
                    Label(
                        store.sharePlay.isEligibleForGroupSession
                            ? "Invite to SharePlay"
                            : "SharePlay",
                        systemImage: "shareplay"
                    )
                }
            }
        }
        .alert(
            "SharePlay Unavailable",
            isPresented: Binding(
                get: { store.sharePlay.activationError != nil },
                set: { if !$0 { store.sharePlay.activationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.sharePlay.activationError ?? "")
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)

            Text("No CT Scan Loaded")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Import a folder containing DICOM (.dcm) files\nto view CT scan slices.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                store.isShowingFolderPicker = true
            } label: {
                Label("Import CT Scan", systemImage: "folder.badge.plus")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var sliceViewerView: some View {
        HStack(alignment: .top, spacing: 0) {
            mainSliceContent
                .frame(maxWidth: .infinity)

            if store.isAnnotationPanelVisible {
                annotationPanel
                    .frame(width: 300)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4), value: store.isAnnotationPanelVisible)
    }

    private var mainSliceContent: some View {
        VStack(spacing: 16) {
            metadataHeader

            if let cgImage = store.currentSliceImage {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 4)
                    .frame(maxHeight: .infinity)
                    .onLongPressGesture(minimumDuration: 0.5) {
                        store.isAnnotationWindowOpen = true
                        openWindow(id: "annotation")
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Label("Hold to annotate", systemImage: "pencil.and.outline")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(6)
                    }
            }

            sliceControls
            presetPicker
        }
        .padding()
    }

    private var annotationPanel: some View {
        VStack(spacing: 0) {
            // Header — tap the expand button to open a full local viewer window
            HStack {
                Label("Live Annotation", systemImage: "pencil.and.outline")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    openWindow(id: "annotation")
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .imageScale(.small)
                }
                .buttonStyle(.borderless)
                .help("Open annotation window to draw")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            // Slice + live strokes
            if let cgImage = store.currentSliceImage {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        AnnotationStrokesView(strokes: Array(store.annotationPanelStrokes.values))
                    }
                    .padding(12)
            } else {
                ContentUnavailableView(
                    "No slice",
                    systemImage: "doc.viewfinder"
                )
            }

            Spacer(minLength: 0)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.vertical, 8)
        .padding(.trailing, 8)
    }

    private var metadataHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if !store.patientName.isEmpty {
                    Label(store.patientName, systemImage: "person.fill")
                        .font(.headline)
                }
                if !store.studyDescription.isEmpty || !store.seriesDescription.isEmpty {
                    Text([store.studyDescription, store.seriesDescription]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !store.modality.isEmpty {
                Text(store.modality)
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.15), in: Capsule())
            }
        }
    }

    private var sliceControls: some View {
        VStack(spacing: 8) {
            if store.sliceCount > 1 {
                Slider(
                    value: Binding(
                        get: { Double(store.currentSliceIndex) },
                        set: { store.currentSliceIndex = Int($0) }
                    ),
                    in: 0...Double(max(store.sliceCount - 1, 1)),
                    step: 1
                )
            }

            Text("Slice \(store.currentSliceIndex + 1) / \(store.sliceCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var presetPicker: some View {
        HStack {
            Text("Window Preset")
                .font(.subheadline)

            Spacer()

            // Manual Binding because @Environment doesn't expose $store in
            // computed properties — only inside body where @Bindable is declared.
            Picker("Preset", selection: Binding(
                get: { store.selectedPreset },
                set: { store.selectedPreset = $0 }
            )) {
                ForEach(DCMWindowingProcessor.ctPresets, id: \.self) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Toolbar button that opens / closes the mixed-immersion drawing space.
    private var drawingToggleButton: some View {
        Button {
            Task {
                if store.isDrawingActive {
                    await dismissImmersiveSpace()
                    store.isDrawingActive = false
                } else {
                    let result = await openImmersiveSpace(id: "DrawingSpace")
                    if case .opened = result {
                        store.isDrawingActive = true
                    }
                }
            }
        } label: {
            Label(
                store.isDrawingActive ? "Stop Drawing" : "Draw",
                systemImage: store.isDrawingActive ? "pencil.slash" : "pencil.and.outline"
            )
        }
        .tint(store.isDrawingActive ? .orange : .primary)
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Loading DICOM slices…")
                    .font(.headline)
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

// MARK: - AnnotationStrokesView

/// Renders normalized annotation strokes scaled to the view's actual size.
/// Used in the shared live-annotation panel so all participants see drawings in real time.
struct AnnotationStrokesView: View {
    let strokes: [AnnotationPanelStroke]

    var body: some View {
        Canvas { context, size in
            for stroke in strokes {
                guard stroke.points.count >= 2 else { continue }
                var path = Path()
                let first = stroke.points[0]
                path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
                for pt in stroke.points.dropFirst() {
                    path.addLine(to: CGPoint(x: pt.x * size.width, y: pt.y * size.height))
                }
                context.stroke(
                    path,
                    with: .color(stroke.color),
                    style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(DICOMStore())
}
