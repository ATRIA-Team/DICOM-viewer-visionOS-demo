//
//  DrawPointMessage.swift
//  DemoDICOM
//

import RealityKit
import Foundation

/// Sent via the **unreliable** GroupSessionMessenger for real-time drawing sync.
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
