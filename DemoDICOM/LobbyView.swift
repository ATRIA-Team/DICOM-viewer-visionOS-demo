//
//  LobbyView.swift
//  DemoDICOM
//

import SwiftUI
import UniformTypeIdentifiers

/// Pre-session lobby shown while a SharePlay session is active but not all
/// participants have loaded their local DICOM folder yet.
///
/// Each participant imports their own copy of the study. When the last participant
/// marks themselves ready, `SharePlayCoordinator.sessionHasStarted` latches to
/// `true` and `RootView` automatically transitions everyone to the viewer.
struct LobbyView: View {

    @Environment(DICOMStore.self) private var store

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    headerSection
                    participantsSection
                    if hasMismatchWarning { mismatchBanner }
                    importSection
                }
                .padding(24)
            }
            .navigationTitle("Session Lobby")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Label(
                        "\(store.sharePlay.participantCount) connected",
                        systemImage: "shareplay"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .fileImporter(
                isPresented: $store.isShowingFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { store.importFolder(url: url) }
                case .failure(let error):
                    store.errorMessage = "File picker error: \(error.localizedDescription)"
                }
            }
            .overlay {
                if store.isLoading { loadingOverlay }
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { store.errorMessage != nil },
                    set: { if !$0 { store.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)

            Text("Collaborative Session")
                .font(.title2.weight(.semibold))

            Text("Each participant loads their own local copy of the DICOM folder. The session begins automatically once everyone is ready.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Participants

    private var sortedParticipants: [ParticipantReadyState] {
        // Local participant always appears first
        store.sharePlay.participantStates.values
            .sorted { $0.isLocal && !$1.isLocal }
    }

    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Participants", systemImage: "person.2.fill")
                .font(.headline)
                .padding(.bottom, 14)

            if sortedParticipants.isEmpty {
                Text("Waiting for participants to join…")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(sortedParticipants) { state in
                        ParticipantRow(state: state)
                        if state.id != sortedParticipants.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Mismatch warning

    /// Show a warning if two or more ready participants have different slice counts,
    /// which likely means they loaded different series.
    private var hasMismatchWarning: Bool {
        let readyCounts = store.sharePlay.participantStates.values
            .filter { $0.isReady }
            .map { $0.sliceCount }
        guard readyCounts.count >= 2 else { return false }
        return Set(readyCounts).count > 1
    }

    private var mismatchBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("Slice count mismatch")
                    .font(.subheadline.weight(.semibold))
                Text("Participants have loaded different numbers of slices. Verify that everyone is using the same DICOM series before proceeding.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.yellow.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Import section

    private var localState: ParticipantReadyState? {
        store.sharePlay.participantStates.values.first { $0.isLocal }
    }

    private var waitingCount: Int {
        store.sharePlay.participantStates.values.filter { !$0.isReady }.count
    }

    @ViewBuilder
    private var importSection: some View {
        if localState?.isReady == true {
            // Already loaded — show summary and offer re-import
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your files are loaded")
                            .font(.subheadline.weight(.medium))
                        if let local = localState {
                            let desc = local.seriesDescription.isEmpty
                                ? "No series description"
                                : local.seriesDescription
                            Text("\(local.sliceCount) slices · \(desc)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button("Change") {
                        store.isShowingFolderPicker = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
                .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.green.opacity(0.3), lineWidth: 1)
                )

                if waitingCount > 0 {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for \(waitingCount) participant\(waitingCount == 1 ? "" : "s") to load…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        } else {
            // Not yet loaded — show the import prompt
            VStack(spacing: 10) {
                Button {
                    store.isShowingFolderPicker = true
                } label: {
                    Label("Import Your DICOM Folder", systemImage: "folder.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)

                Text("Load the same DICOM folder as your session partners.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Loading overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().scaleEffect(1.5)
                Text("Loading DICOM slices…").font(.headline)
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

// MARK: - ParticipantRow

private struct ParticipantRow: View {
    let state: ParticipantReadyState

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Group {
                if state.isReady {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 28)

            // Name + detail
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(state.isLocal ? "You" : "Participant")
                        .font(.subheadline.weight(.medium))
                    if state.isLocal {
                        Text("· This device")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if state.isReady {
                    let desc = state.seriesDescription.isEmpty
                        ? "No series description"
                        : state.seriesDescription
                    Text("\(state.sliceCount) slices · \(desc)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Waiting to load files…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 10)
    }
}
