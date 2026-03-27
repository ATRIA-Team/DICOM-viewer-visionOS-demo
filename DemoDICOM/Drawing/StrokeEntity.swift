//
//  StrokeEntity.swift
//  DemoDICOM
//
//  Adapted from SharedSpaceExample2 by Igor Tarantino.
//  Mesh update strategy (replace vs. recreate) adapted from ShareDraw / StrokeHelpers.swift.
//

import RealityKit
import UIKit

/// A RealityKit `Entity` that renders a 3D tube stroke from a sequence of points.
///
/// Points are added incrementally via `addPoint(_:)`. Each call regenerates the
/// mesh using a Frenet-Serret frame algorithm that keeps the cross-section
/// perpendicular to the stroke direction, producing a smooth tube.
///
/// After the first point pair the mesh is updated via `MeshResource.replace(with:)`
/// rather than allocating a new `MeshResource` each frame, which avoids repeated
/// GPU buffer allocations while drawing.
class StrokeEntity: Entity {

    // MARK: - Private

    private var points: [SIMD3<Float>] = []
    private let thickness: Float
    private let color: UIColor
    private let model = ModelEntity()
    private let sides = 8      // octagonal cross-section — good quality / low cost

    // MARK: - Init

    init(thickness: Float, color: UIColor) {
        self.thickness = thickness
        self.color = color
        super.init()
        addChild(model)
    }

    required init() {
        self.thickness = 0.005
        self.color = .red
        super.init()
        addChild(model)
    }

    // MARK: - Public API

    func addPoint(_ point: SIMD3<Float>) {
        points.append(point)
        updateMesh()
    }

    // MARK: - Mesh generation

    private func updateMesh() {
        guard points.count > 1 else { return }

        let (positions, normals, indices) = buildMeshData()

        var contents = MeshResource.Contents()
        contents.instances = [MeshResource.Instance(id: "inst", model: "main")]

        var part = MeshResource.Part(id: "stroke", materialIndex: 0)
        part.positions = MeshBuffer(positions)
        part.normals = MeshBuffer(normals)
        part.triangleIndices = MeshBuffer(indices)

        contents.models = [MeshResource.Model(id: "main", parts: [part])]

        // Reuse the existing mesh buffer when possible (avoids per-frame GPU allocation).
        if let existingMesh = model.model?.mesh {
            try? existingMesh.replace(with: contents)
        } else {
            if let mesh = try? MeshResource.generate(from: contents) {
                model.model = ModelComponent(
                    mesh: mesh,
                    materials: [SimpleMaterial(color: color, roughness: 1.0, isMetallic: false)]
                )
            }
        }
    }

    private func buildMeshData() -> ([SIMD3<Float>], [SIMD3<Float>], [UInt32]) {
        var positions: [SIMD3<Float>] = []
        var normals:   [SIMD3<Float>] = []
        var indices:   [UInt32] = []
        var lastNormal = SIMD3<Float>(0, 1, 0)

        for i in 0..<points.count {
            let current = points[i]
            let next = (i < points.count - 1) ? points[i + 1] : current
            let prev = (i > 0) ? points[i - 1] : current

            // Tangent direction along the stroke
            let tangent = simd_normalize(next - prev)

            // Keep the Frenet normal from becoming parallel to the tangent
            if abs(simd_dot(tangent, lastNormal)) > 0.99 {
                lastNormal = (abs(tangent.z) > 0.9)
                    ? SIMD3<Float>(1, 0, 0)
                    : SIMD3<Float>(0, 0, 1)
            }

            let right = simd_normalize(simd_cross(tangent, lastNormal))
            lastNormal = simd_cross(right, tangent)
            let up = lastNormal

            // Build the ring of vertices at this point
            for j in 0..<sides {
                let angle  = Float(j) / Float(sides) * 2.0 * .pi
                let normal = cos(angle) * right + sin(angle) * up   // unit outward normal
                positions.append(current + normal * thickness)
                normals.append(normal)
            }

            // Connect this ring to the previous one with quad-pairs (two triangles each)
            if i > 0 {
                let currRing = UInt32(i * sides)
                let prevRing = UInt32((i - 1) * sides)
                for j in 0..<sides {
                    let nextJ = UInt32((j + 1) % sides)
                    indices.append(contentsOf: [
                        prevRing + UInt32(j), currRing + UInt32(j), currRing + nextJ,
                        prevRing + UInt32(j), currRing + nextJ,     prevRing + nextJ
                    ])
                }
            }
        }

        return (positions, normals, indices)
    }
}
