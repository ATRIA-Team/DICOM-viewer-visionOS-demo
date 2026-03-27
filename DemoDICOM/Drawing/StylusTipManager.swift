//
//  StylusTipManager.swift
//  DemoDICOM
//
//  Adapted from SharedSpaceExample2 by Igor Tarantino.
//

import ARKit
import CoreHaptics
import GameController
import RealityKit
import SwiftUI

// MARK: - StylusTipManager

@MainActor
@Observable
final class StylusTipManager {

    // MARK: - Public state

    var isPrimaryButtonPressed: Bool? = false
    var isSecondaryButtonPressed: Bool? = false

    // MARK: - Internal

    var rootEntity: Entity?
    private var tipSphereEntity: Entity?

    private var anchors: [StylusAnchor: AnchorEntity] = [:]
    private var hapticEngines: [ObjectIdentifier: CHHapticEngine] = [:]
    private var hapticPlayers: [ObjectIdentifier: CHHapticPatternPlayer] = [:]

    private let tipRadius: Float = 0.008

    private enum StylusAnchor: String {
        case aim
        case origin
    }

    // MARK: - Public API

    func getTipPosition() -> SIMD3<Float>? {
        tipSphereEntity?.position(relativeTo: nil)
    }

    // MARK: - Setup

    func handleControllerSetup() async {
        // Handle already-connected styli
        for stylus in GCStylus.styli where stylus.productCategory == GCProductCategorySpatialStylus {
            try? await setupAccessory(stylus: stylus)
        }

        // Observe future connections
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.GCStylusDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let stylus = note.object as? GCStylus,
                  stylus.productCategory == GCProductCategorySpatialStylus else { return }
            Task { @MainActor in
                try? await self.setupAccessory(stylus: stylus)
            }
        }
    }

    private func setupAccessory(stylus: GCStylus) async throws {
        guard let root = rootEntity else { return }

        let source = try await AnchoringComponent.AccessoryAnchoringSource(device: stylus)

        // Aim anchor — tracks the stylus tip in 3D space
        guard let aimLocation = source.locationName(named: StylusAnchor.aim.rawValue) else { return }
        let aimAnchor = AnchorEntity(
            .accessory(from: source, location: aimLocation),
            trackingMode: .continuous,
            physicsSimulation: .none
        )
        root.addChild(aimAnchor)
        anchors[.aim] = aimAnchor

        // Origin anchor — reference point on the stylus body
        if let originLocation = source.locationName(named: StylusAnchor.origin.rawValue) {
            let originAnchor = AnchorEntity(
                .accessory(from: source, location: originLocation),
                trackingMode: .continuous,
                physicsSimulation: .none
            )
            root.addChild(originAnchor)
            anchors[.origin] = originAnchor
        }

        let key = ObjectIdentifier(stylus)
        setupHaptics(for: stylus, key: key)
        setupStylusInputs(stylus: stylus, key: key)
        setupTipSphere()
    }

    private func setupStylusInputs(stylus: GCStylus, key: ObjectIdentifier) {
        guard let input = stylus.input else { return }

        input.buttons[.stylusPrimaryButton]?.pressedInput.pressedDidChangeHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                self?.isPrimaryButtonPressed = pressed
                if pressed { self?.playHaptic(for: key) }
            }
        }

        input.buttons[.stylusSecondaryButton]?.pressedInput.pressedDidChangeHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                self?.isSecondaryButtonPressed = pressed
                if pressed { self?.playHaptic(for: key) }
            }
        }
    }

    // MARK: - Tip sphere

    private func setupTipSphere() {
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: tipRadius),
            materials: [UnlitMaterial(color: .white.withAlphaComponent(0.6))]
        )
        sphere.components.remove(CollisionComponent.self)
        sphere.components.remove(PhysicsBodyComponent.self)

        if let aimAnchor = anchors[.aim] {
            aimAnchor.addChild(sphere)
            tipSphereEntity = sphere
        }
    }

    // MARK: - Haptics

    private func setupHaptics(for stylus: GCStylus, key: ObjectIdentifier) {
        guard let deviceHaptics = stylus.haptics,
              let engine = deviceHaptics.createEngine(withLocality: .default) else { return }

        do {
            try engine.start()
            hapticEngines[key] = engine

            let pattern = try CHHapticPattern(events: [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                    ],
                    relativeTime: 0.0
                )
            ], parameters: [])

            hapticPlayers[key] = try engine.makePlayer(with: pattern)
        } catch {
            print("Haptics setup failed: \(error)")
        }
    }

    private func playHaptic(for key: ObjectIdentifier) {
        try? hapticPlayers[key]?.start(atTime: CHHapticTimeImmediate)
    }
}
