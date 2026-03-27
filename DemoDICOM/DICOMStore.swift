//
//  DICOMStore.swift
//  DemoDICOM
//
//  Created on 25/03/2026.
//

import SwiftUI
import CoreGraphics
import DicomCore
import UniformTypeIdentifiers

// MARK: - DICOMStore

/// Observable state manager for loading and browsing CT DICOM slices.
///
/// Workflow:
/// 1. User calls `importFolder()` which triggers a folder picker.
/// 2. The store scans the folder for `.dcm` files, sorts them by Instance Number,
///    decodes each with `DCMDecoder`, and applies window/level to produce `CGImage` slices.
/// 3. The user scrubs through slices with a slider bound to `currentSliceIndex`.
/// 4. Changing `selectedPreset` re-applies windowing across all slices.
@Observable
final class DICOMStore {

    // MARK: - SharePlay

    /// Coordinator that manages the SharePlay session for this store.
    let sharePlay = SharePlayCoordinator()

    // MARK: - Drawing

    /// Owns brush settings and routes incoming drawing messages.
    var drawing = DrawingManager()

    // MARK: - Init

    init() {
        sharePlay.store = self
    }

    // MARK: - Public State

    /// The decoded, windowed slice images for the current series.
    private(set) var sliceImages: [CGImage] = []

    /// Index of the currently displayed slice.
    var currentSliceIndex: Int = 0 {
        didSet {
            guard currentSliceIndex != oldValue else { return }
            sharePlay.send(DICOMSyncMessage(kind: .sliceChanged(index: currentSliceIndex)))
        }
    }

    /// The active window/level preset.
    var selectedPreset: MedicalPreset = .softTissue {
        didSet {
            guard selectedPreset != oldValue else { return }
            sharePlay.send(DICOMSyncMessage(kind: .presetChanged(rawValue: selectedPreset.rawValue)))
            reapplyWindowing()
        }
    }
    
    /// Patient metadata from the first slice.
    private(set) var patientName: String = ""
    
    /// Study description from the first slice.
    private(set) var studyDescription: String = ""
    
    /// Series description from the first slice.
    private(set) var seriesDescription: String = ""
    
    /// Modality (e.g. "CT").
    private(set) var modality: String = ""
    
    /// Loading state for the UI.
    private(set) var isLoading: Bool = false
    
    /// User-visible error message.
    var errorMessage: String?
    
    /// Whether a folder picker should be presented.
    var isShowingFolderPicker: Bool = false
    
    /// Total number of slices.
    var sliceCount: Int { sliceImages.count }
    
    /// The currently displayed slice image.
    var currentSliceImage: CGImage? {
        guard !sliceImages.isEmpty,
              currentSliceIndex >= 0,
              currentSliceIndex < sliceImages.count else { return nil }
        return sliceImages[currentSliceIndex]
    }
    
    // MARK: - Internal storage
    
    /// Raw 16-bit pixel buffers for each slice (kept for re-windowing on preset change).
    /// Stored as (pixels, width, height).
    private var rawPixelBuffers16: [([UInt16], Int, Int)] = []
    
    // MARK: - SharePlay API

    /// Applies a received SharePlay message to local state.
    /// Called by `SharePlayCoordinator` with `isApplyingRemoteChange` set to
    /// prevent the resulting `didSet` observers from re-broadcasting.
    @MainActor
    func applySharePlayMessage(_ message: DICOMSyncMessage) {
        switch message.kind {
        case .sliceChanged(let index):
            guard index >= 0, index < sliceCount else { return }
            currentSliceIndex = index
        case .presetChanged(let rawValue):
            guard let preset = MedicalPreset(rawValue: rawValue) else { return }
            selectedPreset = preset
        case .participantReady, .participantNotReady, .clearDrawings:
            // Lobby and drawing messages are handled elsewhere, not by the store.
            break
        }
    }

    // MARK: - Public API

    /// Import DICOM slices from a folder URL obtained via the file picker.
    @MainActor
    func importFolder(url: URL) {
        isLoading = true
        errorMessage = nil
        sliceImages = []
        rawPixelBuffers16 = []
        currentSliceIndex = 0
        // Signal to peers that we are re-loading and not yet ready to view.
        sharePlay.broadcastNotReady()

        Task.detached { [weak self] in
            guard let self else { return }
            await self.performImport(url: url)
        }
    }
    
    // MARK: - Private
    
    private func performImport(url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        
        do {
            // 1. Scan for DICOM files
            let fileManager = FileManager.default
            let contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            
            // Accept .dcm files, .dicom, .ima, and also extensionless files (common for DICOM)
            let dicomFiles = contents.filter { u in
                let isReg = (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? true
                guard isReg else { return false }
                let ext = u.pathExtension.lowercased()
                return ext == "dcm" || ext == "dicom" || ext == "ima" || ext.isEmpty
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            guard !dicomFiles.isEmpty else {
                await updateError("No DICOM files found in the selected folder. Make sure you selected the right folder.")
                return
            }
            
            // 2. Decode each file
            struct SliceEntry {
                let instanceNumber: Int
                let pixels16: [UInt16]
                let width: Int
                let height: Int
            }
            
            var sliceEntries: [SliceEntry] = []
            var firstDecoder: DCMDecoder?
            var compressedCount = 0
            var totalCount = dicomFiles.count
            
            for fileURL in dicomFiles {
                let decoder = DCMDecoder()
                decoder.setDicomFilename(fileURL.path)
                
                guard decoder.dicomFileReadSuccess else { continue }
                
                // Track compressed images for better user messaging
                if decoder.compressedImage {
                    compressedCount += 1
                }
                
                // Try to get pixel data — attempt 16-bit first, then 8-bit (upcast to UInt16)
                let pixels16: [UInt16]?
                
                if let p16 = decoder.getPixels16() {
                    pixels16 = p16
                } else if let p8 = decoder.getPixels8() {
                    // Upcast 8-bit to 16-bit (scale 0-255 → 0-65535)
                    pixels16 = p8.map { UInt16($0) << 8 }
                } else {
                    // Could not decode pixels — skip this slice
                    continue
                }
                
                guard let pixels = pixels16 else { continue }
                
                if firstDecoder == nil {
                    firstDecoder = decoder
                }
                
                // Instance Number (0x00200013) for anatomical ordering
                let instanceNumber = decoder.intValue(for: 0x00200013) ?? sliceEntries.count
                sliceEntries.append(SliceEntry(
                    instanceNumber: instanceNumber,
                    pixels16: pixels,
                    width: decoder.width,
                    height: decoder.height
                ))
            }
            
            // 3. Handle empty result — give specific feedback on why
            if sliceEntries.isEmpty {
                if compressedCount == totalCount {
                    await updateError(
                        "All \(compressedCount) files use a compressed transfer syntax (e.g. JPEG2000) " +
                        "that could not be decoded on this platform.\n\n" +
                        "You can convert them to uncompressed DICOM using dcmtk:\n" +
                        "  dcmconv --write-xfer-little input.dcm output.dcm"
                    )
                } else if compressedCount > 0 {
                    await updateError(
                        "\(compressedCount) of \(totalCount) files used unsupported compression and were skipped. " +
                        "No decodable slices remained."
                    )
                } else {
                    await updateError("Could not decode any DICOM slices from this folder.")
                }
                return
            }
            
            // 4. Sort by Instance Number for correct anatomical order
            sliceEntries.sort { $0.instanceNumber < $1.instanceNumber }
            
            // 5. Extract metadata from first successfully decoded slice
            let patientInfo = firstDecoder?.getPatientInfo() ?? [:]
            let studyInfo = firstDecoder?.getStudyInfo() ?? [:]
            let seriesInfo = firstDecoder?.getSeriesInfo() ?? [:]
            let modalityStr = firstDecoder?.info(for: 0x00080060) ?? ""
            
            // 6. Determine window/level to use
            // Priority: DICOM header values → auto-calculated → preset
            let presetSnap = await MainActor.run { self.selectedPreset }
            let windowCenter: Double
            let windowWidth: Double
            
            // Try DICOM header window first
            let headerCenter = firstDecoder?.windowCenter ?? 0
            let headerWidth  = firstDecoder?.windowWidth  ?? 0
            
            if headerWidth > 0 {
                windowCenter = headerCenter
                windowWidth  = headerWidth
            } else if let optimal = firstDecoder?.calculateOptimalWindow() {
                windowCenter = optimal.center
                windowWidth  = optimal.width
            } else {
                let preset = DCMWindowingProcessor.getPresetValues(preset: presetSnap)
                windowCenter = preset.center
                windowWidth  = preset.width
            }
            
            // 7. Apply windowing and build CGImages
            var images: [CGImage] = []
            var rawBuffers: [([UInt16], Int, Int)] = []
            
            for entry in sliceEntries {
                rawBuffers.append((entry.pixels16, entry.width, entry.height))
                
                if let windowedData = DCMWindowingProcessor.applyWindowLevel(
                    pixels16: entry.pixels16,
                    center: windowCenter,
                    width: windowWidth
                ),
                   let cgImage = CGImage.fromDICOMWindowedData(
                    windowedData,
                    width: entry.width,
                    height: entry.height
                   ) {
                    images.append(cgImage)
                }
            }
            
            // 8. Commit to main actor
            await MainActor.run {
                self.rawPixelBuffers16 = rawBuffers
                self.sliceImages = images
                self.currentSliceIndex = images.count / 2   // Start in the middle
                self.patientName = patientInfo["Name"] ?? ""
                self.studyDescription = studyInfo["StudyDescription"] ?? ""
                self.seriesDescription = seriesInfo["SeriesDescription"] ?? ""
                self.modality = modalityStr
                self.isLoading = false
                // Notify peers that this participant has finished loading and is ready.
                self.sharePlay.broadcastReady(
                    sliceCount: images.count,
                    seriesDescription: seriesInfo["SeriesDescription"] ?? "",
                    patientName: patientInfo["Name"] ?? ""
                )
            }
            
        } catch {
            await updateError("Import failed: \(error.localizedDescription)")
        }
    }
    
    /// Re-applies windowing with the current preset to all raw 16-bit buffers.
    private func reapplyWindowing() {
        guard !rawPixelBuffers16.isEmpty else { return }
        
        isLoading = true
        let preset = selectedPreset
        let buffers = rawPixelBuffers16
        
        Task.detached {
            let presetValues = DCMWindowingProcessor.getPresetValues(preset: preset)
            
            var images: [CGImage] = []
            for (pixels, width, height) in buffers {
                if let windowedData = DCMWindowingProcessor.applyWindowLevel(
                    pixels16: pixels,
                    center: presetValues.center,
                    width: presetValues.width
                ),
                   let cgImage = CGImage.fromDICOMWindowedData(
                    windowedData,
                    width: width,
                    height: height
                   ) {
                    images.append(cgImage)
                }
            }
            
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.sliceImages = images
                if self.currentSliceIndex >= images.count {
                    self.currentSliceIndex = max(0, images.count - 1)
                }
                self.isLoading = false
            }
        }
    }
    
    @MainActor
    private func updateError(_ message: String) {
        self.errorMessage = message
        self.isLoading = false
    }
}
