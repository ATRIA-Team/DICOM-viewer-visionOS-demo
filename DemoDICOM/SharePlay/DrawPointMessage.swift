//
//  DrawPointMessage.swift
//  DemoDICOM
//

import RealityKit
import Foundation

/// Sent via the **unreliable** GroupSessionMessenger for real-time 3D drawing sync.
///
/// Draw points are emitted every ~10 ms while the stylus primary button is held,
/// so we accept occasional drops in exchange for low latency.
/// The `strokeID` ties individual points to the same continuous stroke.
struct DrawPointMessage: Codable {
    let strokeID: UUID
    let point: SIMD3<Float>
    let thickness: Float
    let color: SIMD4<Float>   // RGBA, each component in [0, 1]
}

/// Sent via the **unreliable** GroupSessionMessenger for real-time 2D annotation sync.
///
/// Points are emitted for every Apple Pencil move in the annotation window.
/// `isStart` marks the beginning of a new stroke; `isEnd` marks its completion.
/// Coordinates are normalized to [0, 1] so the shared panel can scale them to any size.
struct Annotation2DPointMessage: Codable {
    let strokeID: UUID
    let x: Float        // normalized [0, 1] within the canvas bounds
    let y: Float        // normalized [0, 1] within the canvas bounds
    let isStart: Bool
    let isEnd: Bool
    let colorR: Float   // RGB, each component in [0, 1]
    let colorG: Float
    let colorB: Float
    let lineWidth: Float
}
