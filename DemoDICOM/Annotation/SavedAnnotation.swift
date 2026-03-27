//
//  SavedAnnotation.swift
//  DemoDICOM
//

import Foundation
import SwiftData

/// Persisted record of a single annotated CT slice.
///
/// `imageData` is stored externally (outside the SQLite database) via
/// `.externalStorage` because PNG blobs from medical images can be large.
@Model
final class SavedAnnotation {

    var id: UUID
    var date: Date
    var sliceIndex: Int
    var patientName: String
    var seriesDescription: String

    @Attribute(.externalStorage)
    var imageData: Data

    init(
        sliceIndex: Int,
        patientName: String,
        seriesDescription: String,
        imageData: Data
    ) {
        self.id               = UUID()
        self.date             = Date()
        self.sliceIndex       = sliceIndex
        self.patientName      = patientName
        self.seriesDescription = seriesDescription
        self.imageData        = imageData
    }
}
