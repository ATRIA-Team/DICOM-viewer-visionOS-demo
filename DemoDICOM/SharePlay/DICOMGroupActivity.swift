//
//  DICOMGroupActivity.swift
//  DemoDICOM
//

import GroupActivities

/// The SharePlay activity that lets participants collaboratively review
/// the same DICOM series together in real time.
///
/// Each participant loads their own local copy of the DICOM folder; this
/// activity only synchronises the *viewing state* (current slice and
/// windowing preset) — it does not transmit pixel data.
struct DICOMViewerActivity: GroupActivity {

    static let activityIdentifier = "michele.coppola.DemoDICOM.viewDICOM"

    var metadata: GroupActivityMetadata {
        var m = GroupActivityMetadata()
        m.title = "DICOM Viewer"
        m.subtitle = "Collaborative scan review"
        m.type = .generic
        return m
    }
}
