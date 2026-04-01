//
//  DemoDICOMApp.swift
//  DemoDICOM
//
//  Created by Michele Coppola on 25/03/2026.
//

import SwiftUI
import SwiftData
import GroupActivities

@main
struct DemoDICOMApp: App {

    /// Single source of truth — lives for the entire app lifetime.
    @State private var store = DICOMStore()

    /// Single shared container so the main window and the annotation window
    /// read/write the same SwiftData store. Without this, the annotation window
    /// gets an empty default context that does not persist to disk.
    private let annotationContainer: ModelContainer = {
        try! ModelContainer(for: SavedAnnotation.self)
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
        .modelContainer(annotationContainer)

        // 2-D annotation window (local — only the annotating user sees this).
        // Opened from ContentView when the user long-presses on the CT slice.
        WindowGroup(id: "annotation") {
            AnnotationView()
                .environment(store)
        }
        .defaultSize(width: 720, height: 780)
        .modelContainer(annotationContainer)  // same instance → same store

        // Mixed-immersion drawing space.
        // Opened/dismissed from ContentView via openImmersiveSpace / dismissImmersiveSpace.
        ImmersiveSpace(id: "DrawingSpace") {
            ImmersiveDrawingView()
                .environment(store)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
