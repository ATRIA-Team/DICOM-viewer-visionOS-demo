//
//  AnnotationView.swift
//  DemoDICOM
//

import SwiftUI
import SwiftData

/// A dedicated 2-D annotation window opened from the slice viewer.
///
/// The user opens this window by pinching and holding on the CT scan image.
/// Drawing is done with Apple Pencil Pro directly on the window surface.
/// Tapping "Save" composites the slice and strokes into a PNG and persists it
/// via SwiftData so it appears in the Annotations tab.
struct AnnotationView: View {

    @Environment(DICOMStore.self) private var store
    @Environment(\.modelContext) private var modelContext

    @State private var canvasState = PencilCanvasState()
    @State private var brushColor: Color   = .red
    @State private var brushSize:  CGFloat = 3.0
    @State private var showSavedConfirmation = false

    var body: some View {
        NavigationStack {
            contentArea
                .navigationTitle(
                    "Annotate — Slice \(store.currentSliceIndex + 1) / \(store.sliceCount)"
                )
                .toolbar { toolbarContent }
                .overlay(alignment: .top) {
                    if showSavedConfirmation {
                        savedBanner
                    }
                }
        }
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        if let cgImage = store.currentSliceImage {
            Image(decorative: cgImage, scale: 1.0)
                .resizable()
                .scaledToFit()
                .overlay {
                    PencilCanvas(
                        state:      canvasState,
                        brushColor: brushColor,
                        brushSize:  brushSize
                    )
                }
                .overlay(alignment: .bottom) {
                    if canvasState.strokeCount == 0 {
                        Text("Draw with Apple Pencil Pro")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 12)
                    }
                }
                .padding()
        } else {
            ContentUnavailableView(
                "No slice loaded",
                systemImage: "doc.viewfinder",
                description: Text("Import a DICOM folder in the main viewer first.")
            )
        }
    }

    // MARK: - Save

    private func saveAnnotation() {
        guard let cgImage = store.currentSliceImage,
              let composite = canvasState.snapshot(backgroundCGImage: cgImage),
              let pngData   = composite.pngData() else { return }

        let annotation = SavedAnnotation(
            sliceIndex:         store.currentSliceIndex,
            patientName:        store.patientName,
            seriesDescription:  store.seriesDescription,
            imageData:          pngData
        )
        modelContext.insert(annotation)

        withAnimation {
            showSavedConfirmation = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                showSavedConfirmation = false
            }
        }
    }

    // MARK: - Saved banner

    private var savedBanner: some View {
        Label("Saved to Annotations", systemImage: "checkmark.circle.fill")
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.green.gradient, in: Capsule())
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {

        ToolbarItemGroup(placement: .topBarLeading) {
            ColorPicker("Color", selection: $brushColor, supportsOpacity: false)
                .labelsHidden()

            HStack(spacing: 8) {
                Image(systemName: "pencil.tip")
                    .foregroundStyle(.secondary)
                Slider(value: $brushSize, in: 1...20, step: 1)
                    .frame(width: 120)
                Text("\(Int(brushSize)) pt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            // Save composite image to the Annotations tab
            Button {
                saveAnnotation()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .disabled(canvasState.strokeCount == 0)

            // Undo last stroke
            Button {
                canvasState.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(canvasState.strokeCount == 0)

            // Clear all strokes
            Button(role: .destructive) {
                canvasState.clear()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(canvasState.strokeCount == 0)
        }
    }
}
