//
//  SharePlayCoordinator.swift
//  DemoDICOM
//

import GroupActivities
internal import Combine
import Foundation

// MARK: - ParticipantReadyState

/// Tracks the lobby readiness of a single session participant.
///
/// `id` mirrors `Participant.ID`, which is a `UUID` in the GroupActivities framework.
struct ParticipantReadyState: Identifiable {
    let id: UUID
    let isLocal: Bool
    var isReady: Bool = false
    var sliceCount: Int = 0
    var seriesDescription: String = ""
    var patientName: String = ""
}

// MARK: - SharePlayCoordinator

/// Manages the full SharePlay session lifecycle:
///
/// **Lobby phase** — tracks per-participant readiness via `participantStates`.
/// Once `allParticipantsReady` first becomes `true`, `sessionHasStarted` is
/// latched to `true` and `RootView` transitions to the viewer. Late-joining
/// participants do not push active viewers back to the lobby.
///
/// **Viewer phase** — syncs `currentSliceIndex` and `selectedPreset` in real time
/// via `send(_:)`, guarded by `isApplyingRemoteChange` to prevent echo loops.
@Observable
final class SharePlayCoordinator {

    // MARK: - Observable state

    /// True while this device is inside an active GroupSession.
    private(set) var isInSession: Bool = false

    /// Per-participant lobby state, keyed by `Participant.ID` (UUID).
    private(set) var participantStates: [UUID: ParticipantReadyState] = [:]

    /// True once every participant has reported ready. Stays true for the
    /// remainder of the session so late joiners don't interrupt the viewer.
    private(set) var sessionHasStarted: Bool = false

    /// True when all known participants have loaded their DICOM data.
    var allParticipantsReady: Bool {
        guard !participantStates.isEmpty else { return false }
        return participantStates.values.allSatisfy { $0.isReady }
    }

    /// Number of participants currently in the session (including this device).
    var participantCount: Int { participantStates.count }

    /// True when the device is in an active FaceTime call and SharePlay is
    /// available. When false, the system sheet will offer to start a call first.
    private(set) var isEligibleForGroupSession: Bool = false

    /// Set when activation fails (e.g. SharePlay disabled in Settings).
    /// Views should present this as an alert and then clear it.
    var activationError: String?

    // MARK: - Internal

    /// Back-reference to the store; set immediately after `DICOMStore.init()`.
    weak var store: DICOMStore?

    /// Raised while applying a received slice/preset message so that
    /// `DICOMStore`'s `didSet` observers don't re-broadcast the change.
    private(set) var isApplyingRemoteChange: Bool = false

    private var localParticipantID: UUID?
    private var session: GroupSession<DICOMViewerActivity>?
    private var messenger: GroupSessionMessenger?
    private var sessionTasks: [Task<Void, Never>] = []
    private let groupStateObserver = GroupStateObserver()

    // MARK: - Init

    init() {
        // Bridge GroupStateObserver's Combine publisher into @Observable state.
        let observer = groupStateObserver
        Task { @MainActor [weak self] in
            for await eligible in observer.$isEligibleForGroupSession.values {
                self?.isEligibleForGroupSession = eligible
            }
        }
    }

    // MARK: - Activation

    /// Presents the system SharePlay / FaceTime invitation sheet.
    ///
    /// - Already in FaceTime call → shows SharePlay invite directly.
    /// - Not in a call → system shows FaceTime picker first.
    /// - SharePlay disabled → sets `activationError` for the UI to display.
    @MainActor
    func activate() async {
        let activity = DICOMViewerActivity()
        switch await activity.prepareForActivation() {
        case .activationPreferred:
            _ = try? await activity.activate()
        case .activationDisabled:
            activationError = "SharePlay is not available on this device, or it has been disabled in Settings › FaceTime › SharePlay. Note: SharePlay requires a real device and cannot be tested in the simulator."
        case .cancelled:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Session entry

    /// Called by `RootView` each time a `GroupSession` arrives
    /// (user started one, or accepted a peer's invitation).
    @MainActor
    func handleIncomingSession(_ session: GroupSession<DICOMViewerActivity>) {
        // Cancel any prior session work
        sessionTasks.forEach { $0.cancel() }
        sessionTasks = []

        self.session = session
        let messenger = GroupSessionMessenger(session: session)
        self.messenger = messenger

        let localID = session.localParticipant.id
        localParticipantID = localID

        session.join()
        isInSession = true
        sessionHasStarted = false

        // Seed the local participant as not-ready
        participantStates = [localID: ParticipantReadyState(id: localID, isLocal: true)]

        // If the store already has data (user imported before starting SharePlay),
        // immediately declare ourselves ready so joining peers learn our state.
        if let store, store.sliceCount > 0 {
            broadcastReady(
                sliceCount: store.sliceCount,
                seriesDescription: store.seriesDescription,
                patientName: store.patientName
            )
        }

        // Reconcile participant list as peers join and leave
        sessionTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            for await participants in session.$activeParticipants.values {
                self.reconcileParticipants(participants, localParticipant: session.localParticipant)
            }
        })

        // Tear down gracefully when the session ends
        sessionTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            for await state in session.$state.values {
                if case .invalidated = state {
                    self.tearDown()
                    break
                }
            }
        })

        // Receive and route messages from peers
        sessionTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            for await (message, context) in messenger.messages(of: DICOMSyncMessage.self) {
                self.apply(message, from: context.source)
            }
        })
    }

    // MARK: - Lobby broadcasting

    /// Marks the local participant ready and notifies all peers.
    /// Called by `DICOMStore` after a successful import.
    @MainActor
    func broadcastReady(sliceCount: Int, seriesDescription: String, patientName: String) {
        guard isInSession, let localID = localParticipantID else { return }
        participantStates[localID] = ParticipantReadyState(
            id: localID,
            isLocal: true,
            isReady: true,
            sliceCount: sliceCount,
            seriesDescription: seriesDescription,
            patientName: patientName
        )
        checkSessionStart()
        send(DICOMSyncMessage(kind: .participantReady(
            sliceCount: sliceCount,
            seriesDescription: seriesDescription,
            patientName: patientName
        )))
    }

    /// Marks the local participant not-ready and notifies peers.
    /// Called by `DICOMStore` when a fresh import begins.
    @MainActor
    func broadcastNotReady() {
        guard isInSession, let localID = localParticipantID else { return }
        participantStates[localID]?.isReady = false
        participantStates[localID]?.sliceCount = 0
        participantStates[localID]?.seriesDescription = ""
        participantStates[localID]?.patientName = ""
        send(DICOMSyncMessage(kind: .participantNotReady))
    }

    // MARK: - Viewer state sending

    /// Broadcasts a slice/preset message to all other participants.
    /// No-ops when not in session or while applying a remote change.
    func send(_ message: DICOMSyncMessage) {
        guard isInSession, !isApplyingRemoteChange, let messenger else { return }
        Task {
            try? await messenger.send(message)
        }
    }

    // MARK: - Private

    /// Keeps `participantStates` in sync with the GroupSession's live participant set.
    @MainActor
    private func reconcileParticipants(
        _ participants: Set<Participant>,
        localParticipant: Participant
    ) {
        let incomingIDs = Set(participants.map { $0.id })
        let existingIDs = Set(participantStates.keys)

        // Remove participants who left
        for id in existingIDs.subtracting(incomingIDs) {
            participantStates.removeValue(forKey: id)
        }

        // Add newcomers as not-ready
        let newArrivals = incomingIDs.subtracting(existingIDs)
        for participant in participants where newArrivals.contains(participant.id) {
            participantStates[participant.id] = ParticipantReadyState(
                id: participant.id,
                isLocal: participant.id == localParticipant.id
            )
        }

        // Re-broadcast our own ready state whenever new remote peers arrive,
        // so they learn we're already ready without needing another import.
        let newRemoteArrivals = newArrivals.subtracting([localParticipant.id])
        if !newRemoteArrivals.isEmpty,
           participantStates[localParticipant.id]?.isReady == true,
           let store {
            broadcastReady(
                sliceCount: store.sliceCount,
                seriesDescription: store.seriesDescription,
                patientName: store.patientName
            )
        }
    }

    /// Routes an incoming message to either lobby state or viewer state handling.
    @MainActor
    private func apply(_ message: DICOMSyncMessage, from participant: Participant) {
        switch message.kind {

        case .participantReady(let sliceCount, let seriesDescription, let patientName):
            participantStates[participant.id] = ParticipantReadyState(
                id: participant.id,
                isLocal: participant.id == localParticipantID,
                isReady: true,
                sliceCount: sliceCount,
                seriesDescription: seriesDescription,
                patientName: patientName
            )
            checkSessionStart()

        case .participantNotReady:
            participantStates[participant.id]?.isReady = false
            participantStates[participant.id]?.sliceCount = 0
            participantStates[participant.id]?.seriesDescription = ""
            participantStates[participant.id]?.patientName = ""

        case .sliceChanged, .presetChanged:
            // Guard against echo: the didSet observers on DICOMStore check
            // isApplyingRemoteChange and skip re-broadcasting when it is raised.
            isApplyingRemoteChange = true
            defer { isApplyingRemoteChange = false }
            store?.applySharePlayMessage(message)
        }
    }

    /// Latches `sessionHasStarted` the first time all participants are ready.
    @MainActor
    private func checkSessionStart() {
        if !sessionHasStarted && allParticipantsReady {
            sessionHasStarted = true
        }
    }

    @MainActor
    private func tearDown() {
        isInSession = false
        sessionHasStarted = false
        participantStates = [:]
        localParticipantID = nil
        session = nil
        messenger = nil
        sessionTasks.forEach { $0.cancel() }
        sessionTasks = []
    }
}
