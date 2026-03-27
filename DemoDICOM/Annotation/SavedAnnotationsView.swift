//
//  SavedAnnotationsView.swift
//  DemoDICOM
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - SavedAnnotationsView

/// Tab that shows a grid of all saved annotated slices.
/// Tap a thumbnail to view it full-screen. Long-press (or use the context menu)
/// to delete an entry.
struct SavedAnnotationsView: View {

    @Query(sort: \SavedAnnotation.date, order: .reverse)
    private var annotations: [SavedAnnotation]

    @Environment(\.modelContext) private var modelContext

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if annotations.isEmpty {
                    ContentUnavailableView(
                        "No Saved Annotations",
                        systemImage: "doc.richtext.image",
                        description: Text(
                            "Open a CT slice, draw on it, then tap Save to store your annotation here."
                        )
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(annotations) { annotation in
                                NavigationLink {
                                    AnnotationDetailView(annotation: annotation)
                                } label: {
                                    AnnotationThumbnail(annotation: annotation)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        modelContext.delete(annotation)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Saved Annotations")
        }
    }
}

// MARK: - AnnotationThumbnail

private struct AnnotationThumbnail: View {

    let annotation: SavedAnnotation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let uiImage = UIImage(data: annotation.imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.secondary.opacity(0.2))
                    .frame(height: 160)
            }

            VStack(alignment: .leading, spacing: 2) {
                if !annotation.patientName.isEmpty {
                    Text(annotation.patientName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                if !annotation.seriesDescription.isEmpty {
                    Text(annotation.seriesDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack {
                    Text("Slice \(annotation.sliceIndex + 1)")
                    Text("·")
                    Text(annotation.date.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - AnnotationDetailView

struct AnnotationDetailView: View {

    let annotation: SavedAnnotation

    var body: some View {
        Group {
            if let uiImage = UIImage(data: annotation.imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .padding()
            } else {
                ContentUnavailableView("Image unavailable", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle(
            annotation.patientName.isEmpty
                ? "Annotation – Slice \(annotation.sliceIndex + 1)"
                : annotation.patientName
        )
        .navigationBarTitleDisplayMode(.inline)
    }
}
