//
//  ContentView.swift
//  DemoDICOM
//
//  Created by Michele Coppola on 25/03/2026.
//

import SwiftUI
import DicomCore
import UniformTypeIdentifiers

struct ContentView: View {
    
    @State private var store = DICOMStore()
    
    var body: some View {
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
                ToolbarItem(placement: .topBarTrailing) {
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
                    if let url = urls.first {
                        store.importFolder(url: url)
                    }
                case .failure(let error):
                    store.errorMessage = "File picker error: \(error.localizedDescription)"
                }
            }
            .overlay {
                if store.isLoading {
                    loadingOverlay
                }
            }
            .alert(
                "Error",
                isPresented: .init(
                    get: { store.errorMessage != nil },
                    set: { if !$0 { store.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }
    
    // MARK: - Subviews
    
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
        VStack(spacing: 16) {
            // Metadata header
            metadataHeader
            
            // Slice image
            if let cgImage = store.currentSliceImage {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 4)
                    .frame(maxHeight: .infinity)
            }
            
            // Slice navigation controls
            sliceControls
            
            // Preset picker
            presetPicker
        }
        .padding()
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
            
            Picker("Preset", selection: $store.selectedPreset) {
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

#Preview(windowStyle: .automatic) {
    ContentView()
}
