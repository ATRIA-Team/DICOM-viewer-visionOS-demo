//
//  DrawingManager.swift
//  DemoDICOM
//

import SwiftUI

// MARK: - Notification names

extension Notification.Name {
    /// Posted when a remote draw point arrives from a peer.
    /// `object` is a `DrawPointMessage`.
    static let remoteDrawPoint = Notification.Name("DICOMRemoteDrawPoint")
    /// Posted when any participant (local or remote) clears all drawings.
    static let clearAllDrawings = Notification.Name("DICOMClearAllDrawings")
}

// MARK: - DrawingManager

/// Owns brush settings and routes incoming drawing messages to the
/// `ImmersiveDrawingView` via `NotificationCenter`.
///
/// Owned by `DICOMStore` so all views can access it through the environment.
@Observable
final class DrawingManager {

    // MARK: - Observable brush settings (drive the UI)

    /// Current brush colour shown in the colour picker.
    var brushColor: Color = .red

    /// Current brush thickness in metres (0.001 … 0.02).
    var brushSize: Float = 0.005

    // MARK: - Routing incoming messages

    /// Called by `SharePlayCoordinator` when a peer sends a draw point.
    /// Routes the message to `ImmersiveDrawingView` via NotificationCenter.
    func receiveRemotePoint(_ message: DrawPointMessage) {
        NotificationCenter.default.post(
            name: .remoteDrawPoint,
            object: message
        )
    }

    /// Called by `SharePlayCoordinator` (or local clear button) to wipe all strokes.
    func receiveClearDrawings() {
        NotificationCenter.default.post(name: .clearAllDrawings, object: nil)
    }
}
