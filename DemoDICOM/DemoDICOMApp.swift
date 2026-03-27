//
//  DemoDICOMApp.swift
//  DemoDICOM
//
//  Created by Michele Coppola on 25/03/2026.
//

import SwiftUI
import GroupActivities

@main
struct DemoDICOMApp: App {

    /// Single source of truth — lives for the entire app lifetime.
    @State private var store = DICOMStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }

        // Mixed-immersion drawing space.
        // Opened/dismissed from ContentView via openImmersiveSpace / dismissImmersiveSpace.
        ImmersiveSpace(id: "DrawingSpace") {
            ImmersiveDrawingView()
                .environment(store)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
