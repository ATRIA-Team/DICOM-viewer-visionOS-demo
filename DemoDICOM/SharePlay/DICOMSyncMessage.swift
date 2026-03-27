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
        /// A participant (local or remote) cleared all drawings.
        case clearDrawings
    }

    let kind: Kind
}
