//
//  DICOMSyncMessage.swift
//  DemoDICOM
//

import Foundation

/// A lightweight message exchanged between SharePlay participants.
///
/// Only control signals cross the wire — no DICOM pixel data is ever transmitted.
/// Pixel data always stays on each device's local storage.
struct DICOMSyncMessage: Codable {

    enum Kind: Codable {
        // MARK: - Viewing state (sent during active session)

        /// A participant scrolled to a new slice.
        case sliceChanged(index: Int)
        /// A participant changed the window/level preset.
        /// Uses the raw `Int` value of `MedicalPreset` for Codable compatibility.
        case presetChanged(rawValue: Int)

        // MARK: - Lobby readiness (sent during lobby phase)

        /// A participant has finished loading their local DICOM folder.
        case participantReady(sliceCount: Int, seriesDescription: String, patientName: String)
        /// A participant cleared their data or started a fresh import.
        case participantNotReady
        /// A participant (local or remote) cleared all 3D immersive drawings.
        case clearDrawings
        /// A participant removed a specific set of their own 2D annotation strokes.
        /// Only the strokes whose IDs are listed are removed; others are preserved.
        case removeAnnotationStrokes(strokeIDs: [UUID])

        // MARK: - Annotation Panel

        /// A participant started annotating — show the shared live panel to everyone.
        case annotationPanelOpened
        /// A participant finished annotating — hide the shared panel for everyone.
        case annotationPanelClosed

        // MARK: - Drawing Space

        /// A participant opened the immersive drawing space.
        case drawingSpaceOpened
        /// A participant closed the immersive drawing space.
        case drawingSpaceClosed
    }

    let kind: Kind
}
