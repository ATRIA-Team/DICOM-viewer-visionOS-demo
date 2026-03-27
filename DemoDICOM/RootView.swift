//
//  RootView.swift
//  DemoDICOM
//

import SwiftUI
import GroupActivities

/// Routes between `LobbyView` and `ContentView` based on SharePlay session state.
///
/// The `DICOMStore` is owned by `DemoDICOMApp` and injected via `.environment`.
/// This view listens for incoming `GroupSession`s for the lifetime of the window.
struct RootView: View {

    @Environment(DICOMStore.self) private var store

    var body: some View {
        Group {
            // Show the lobby only while a session exists AND the session hasn't
            // officially started. Once `sessionHasStarted` latches to true, all
            // participants stay in the viewer even if a late joiner connects.
            if store.sharePlay.isInSession && !store.sharePlay.sessionHasStarted {
                LobbyView()
            } else {
                ContentView()
            }
        }
        .task {
            // Listen for incoming GroupSessions for the lifetime of this scene.
            for await session in DICOMViewerActivity.sessions() {
                store.sharePlay.handleIncomingSession(session)
            }
        }
    }
}
