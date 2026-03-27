//
//  RootView.swift
//  DemoDICOM
//

import SwiftUI
import GroupActivities

/// The single source of truth for the app's state.
///
/// Owns the `DICOMStore` and the SharePlay session listener, and routes between:
/// - `LobbyView`   — when a session is active but not yet started (lobby phase)
/// - `ContentView` — solo mode, or once all participants are ready (viewer phase)
struct RootView: View {

    @State private var store = DICOMStore()

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
        .environment(store)
        .task {
            // Listen for incoming GroupSessions for the lifetime of this scene.
            // This fires when the local user activates SharePlay OR when they
            // accept an invitation from a peer.
            for await session in DICOMViewerActivity.sessions() {
                store.sharePlay.handleIncomingSession(session)
            }
        }
    }
}
