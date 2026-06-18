import Foundation

// MARK: - File Overview
//
// SessionFSM (Finite State Machine) drives the full VoLTE call lifecycle: outgoing
// INVITE (MO), incoming INVITE (MT), media setup via SDP, QoS preconditions, hold/resume,
// and BYE teardown. It coordinates SIP signaling with RTP media and dedicated bearers.

/// State machine for VoLTE call setup, media, hold, and teardown.
public actor SessionFSM {
    private let profile: OperatorProfile
    private let platform: PlatformContext
    private let transport: any SIPTransport
    private let logger: Logger
    private let mediaTransportFactory: (@Sendable () -> any RTPTransport)?

    private var activeSession: SessionContext?
    private var heldSession: SessionContext?
    private var pendingInvite: SIPRequest?
    private var activeMedia: MediaSession?
    private var heldMedia: MediaSession?
    private var activeVideo: VideoRTPSession?
    private var heldVideo: VideoRTPSession?
    private var audioIODevice: AudioIODevice?

    /// Creates a session FSM bound to profile, platform adapters, and SIP transport.
    public init(
        profile: OperatorProfile,
        platform: PlatformContext,
        transport: any SIPTransport,
        logger: Logger,
        mediaTransportFactory: (@Sendable () -> any RTPTransport)? = nil
    ) {
        self.profile = profile
        self.platform = platform
        self.transport = transport
        self.logger = logger
        self.mediaTransportFactory = mediaTransportFactory
    }

    /// Returns the active call session context, if a call is in progress or connected.
    public func activeSessionContext() -> SessionContext? { activeSession }
    /// Returns a held call session while a second call is active.
    public func heldSessionContext() -> SessionContext? { heldSession }

    /// Test helper to inject active/held dialogs without full INVITE flow.
    public func injectSessionsForTesting(active: SessionContext?, held: SessionContext?) {
        activeSession = active
        heldSession = held
    }

    /// Tears down all active and held calls plus media when registration is lost.
    public func terminateAllCalls(registration: RegistrationContext) async {
        if var session = activeSession {
            try? await terminate(session: &session, registration: registration)
            activeSession = nil
        }
        if var session = heldSession {
            try? await terminate(session: &session, registration: registration)
            heldSession = nil
        }
        if let media = activeMedia {
            await media.stop()
            activeMedia = nil
        }
        if let media = heldMedia {
            await media.stop()
            heldMedia = nil
        }
        if let video = activeVideo {
            await video.stop()
            activeVideo = nil
        }
        if let video = heldVideo {
            await video.stop()
            heldVideo = nil
        }
        audioIODevice?.stop()
        audioIODevice = nil
        pendingInvite = nil
    }

    /// Returns live RTP statistics for the active media session.
    public func mediaStats() async -> RTPStreamStats {
        await activeMedia?.stats() ?? RTPStreamStats()
    }

    /// Sends CANCEL to abort an outgoing INVITE that has not yet been answered.
    public func cancelPendingInvite(registration: RegistrationContext) async throws {
        guard let invite = pendingInvite else { throw SessionError.noPendingInvite }
        let pani = try platform.accessInfo.currentAccessInfo().paniHeaderValue
        let localIP = try platform.network.localIPAddress()
        let cancel = SessionRequestBuilder.makeCANCEL(
            invite: invite,
            pani: pani,
            localIP: localIP,
            localPort: 5060,
            securityAssociation: registration.securityAssociation
        )
        try await transport.send(SIPSerializer.serialize(.request(cancel)))

        let deadline = ContinuousClock.now + .seconds(4)
        while ContinuousClock.now < deadline {
            if let data = try await transport.receive(timeout: .milliseconds(200)) {
                if case .response(let response) = try? SIPParser.parse(data),
                   response.headers["Call-ID"] == invite.headers["Call-ID"],
                   response.statusCode == 200,
                   response.headers["CSeq"]?.localizedCaseInsensitiveContains("CANCEL") == true {
                    break
                }
                if let loopback = transport as? LoopbackSIPTransport {
                    await loopback.requeue(data)
                }
            }
        }

        if var session = activeSession {
            await cleanupSession(&session)
            activeSession = nil
        }
        pendingInvite = nil
        throw SessionError.inviteCancelled
    }

    /// Starts an outgoing (MO) VoLTE call: INVITE → PRACK/UPDATE → ACK → RTP media.
    public func originateCall(
        to destinationURI: String,
        registration: RegistrationContext,
        emergency: Bool = false
    ) async throws -> SessionContext {
        guard registration.serviceRoute != nil || registration.defaultIMPU != nil else {
            throw SessionError.notRegistered
        }
        guard destinationURI.hasPrefix("sip:") || destinationURI.hasPrefix("tel:") else {
            throw SessionError.invalidDestination
        }

        // Only one active + one held call allowed at a time.
        if heldSession != nil, activeSession != nil {
            throw SessionError.concurrentCallLimit
        }

        // Auto-hold the current call before placing a second one.
        if var existing = activeSession, existing.state == .established, heldSession == nil {
            try await renegotiateMedia(
                direction: .sendonly,
                registration: registration,
                session: &existing,
                media: activeMedia
            )
            heldSession = existing
            heldMedia = activeMedia
            heldVideo = activeVideo
            activeSession = nil
            activeMedia = nil
            activeVideo = nil
        }

        let impus = try platform.sim.getIMPUList()
        guard let impu = registration.defaultIMPU ?? impus.first else {
            throw SessionError.notRegistered
        }

        let pani = try platform.accessInfo.currentAccessInfo().paniHeaderValue
        let localIP = try platform.network.localIPAddress()
        // Request a dedicated QoS bearer for voice before sending INVITE.
        let bearer = try platform.bearer.requestDedicatedBearer(qci: .voice)

        var preconditionState = PreconditionState()
        if profile.preconditions.enabled {
            preconditionState.local = .none
        }

        var dialog = DialogContext()
        dialog.localCSeq = 1
        let audioPort = heldSession != nil ? profile.media.localRTPPort + 2 : profile.media.localRTPPort
        var session = SessionContext(
            dialog: dialog,
            state: .inviting,
            remoteURI: destinationURI,
            localURI: impu,
            preconditionState: preconditionState,
            bearerHandle: bearer,
            localAudioPort: audioPort
        )
        activeSession = session

        let offer = SDPSessionBuilder.voLTEOffer(
            profile: profile,
            localIP: localIP,
            audioPort: audioPort,
            preconditionState: preconditionState,
            includeVideo: profile.media.enableVideo
        )

        let invite: SIPRequest
        if emergency {
            invite = EmergencyRequestBuilder.makeEmergencyInvite(
                profile: profile,
                impu: impu,
                pani: pani,
                localIP: localIP,
                localPort: 5060,
                destinationURI: destinationURI,
                dialog: dialog,
                registration: registration,
                sdp: offer,
                securityAssociation: registration.securityAssociation
            )
        } else {
            invite = SessionRequestBuilder.makeInvite(
                profile: profile,
                impu: impu,
                pani: pani,
                localIP: localIP,
                localPort: 5060,
                destinationURI: destinationURI,
                dialog: dialog,
                registration: registration,
                sdp: offer,
                securityAssociation: registration.securityAssociation
            )
        }
        var signedInvite = invite
        STIRSHAKPolicy.attachIdentity(to: &signedInvite.headers, profile: profile)
        pendingInvite = signedInvite

        // INVITE transaction handles 1xx provisionals, PRACK, and final 2xx.
        let transaction = InviteClientTransaction(transport: transport, logger: logger)
        let inviteDialog = dialog
        let result = try await transaction.sendInvite(signedInvite) { [profile] provisional in
            guard let rseq = provisional.headers["RSeq"],
                  let cseq = provisional.headers["CSeq"] else { return nil }
            var prackDialog = inviteDialog
            prackDialog.remoteTag = provisional.headers["To"]?.components(separatedBy: "tag=").last?
                .trimmingCharacters(in: CharacterSet(charactersIn: ">; "))
            prackDialog.remoteTarget = destinationURI
            prackDialog.localCSeq = 2
            return SessionRequestBuilder.makePRACK(
                profile: profile,
                impu: impu,
                pani: pani,
                localIP: localIP,
                localPort: 5060,
                dialog: prackDialog,
                rseq: rseq,
                cseq: cseq,
                securityAssociation: registration.securityAssociation
            )
        }

        pendingInvite = nil
        dialog.localCSeq = 2
        session.dialog = dialog
        session.state = .proceeding
        for provisional in result.provisionals where provisional.body != nil {
            let answer = SDPParser.parse(String(decoding: provisional.body!, as: UTF8.self))
            session.preconditionState.remote = answer.preconditionState.remote
            session.negotiatedCodec = SDPParser.offeredAudioCodecs(answer).first(where: { $0 != .telephoneEvent })
        }

        guard (200 ... 299).contains(result.final.statusCode) else {
            let action = SIPErrorMapper.action(for: result.final.statusCode, method: SIPMethod.invite.rawValue)
            await cleanupSession(&session)
            activeSession = nil
            logger.warn(
                "MO INVITE failed",
                fields: [
                    "status": String(result.final.statusCode),
                    "action": String(describing: action),
                ]
            )
            throw SessionError.unexpectedResponse(result.final.statusCode)
        }

        if let body = result.final.body {
            let answer = SDPParser.parse(String(decoding: body, as: UTF8.self))
            session.preconditionState = answer.preconditionState
            if session.negotiatedCodec == nil {
                session.negotiatedCodec = SDPParser.offeredAudioCodecs(answer).first(where: { $0 != .telephoneEvent })
            }
        }

        session.dialog.remoteTag = result.final.headers["To"]?.components(separatedBy: "tag=").last?
            .trimmingCharacters(in: CharacterSet(charactersIn: ">; "))
        session.dialog.remoteTarget = destinationURI
        // Record-Route from 200 OK becomes our Route set for in-dialog requests.
        session.dialog.recordRoute = result.final.headers.allValues("Record-Route")
        if !session.dialog.recordRoute.isEmpty {
            session.dialog.routeSet = session.dialog.recordRoute.reversed()
        }

        if profile.preconditions.enabled, !session.preconditionState.allMet {
            try await fulfillPreconditionsMO(
                session: &session,
                impu: impu,
                pani: pani,
                localIP: localIP,
                registration: registration
            )
        }

        session.dialog.localCSeq = 1
        let ack = SessionRequestBuilder.makeACK(
            impu: impu, localIP: localIP, localPort: 5060, dialog: session.dialog
        )
        try await transaction.sendAck(ack)

        session.state = .established
        if let body = result.final.body {
            let answer = SDPParser.parse(String(decoding: body, as: UTF8.self))
            try await startMedia(session: &session, remoteSDP: answer, localIP: localIP)
        }
        activeSession = session
        logger.info(
            "MO call established",
            fields: [
                "destination": destinationURI,
                "codec": session.negotiatedCodec?.rawValue ?? "",
                "preconditions_met": String(session.preconditionState.allMet),
                "media_started": String(session.remoteMedia != nil),
            ]
        )
        return session
    }

    /// Puts the active call on hold by re-INVITE with sendonly SDP.
    public func holdActiveCall(registration: RegistrationContext) async throws {
        try await renegotiateMedia(direction: .sendonly, registration: registration)
    }

    /// Resumes a held call by re-INVITE with sendrecv SDP.
    public func resumeActiveCall(registration: RegistrationContext) async throws {
        try await renegotiateMedia(direction: .sendrecv, registration: registration)
    }

    private func renegotiateMedia(direction: MediaDirection, registration: RegistrationContext) async throws {
        guard var session = activeSession, session.state == .established else {
            throw SessionError.holdNotAllowed
        }
        try await renegotiateMedia(
            direction: direction,
            registration: registration,
            session: &session,
            media: activeMedia
        )
        session.mediaDirection = direction
        activeSession = session
        logger.info("Call media direction updated", fields: ["direction": direction.rawValue])
    }

    private func renegotiateMedia(
        direction: MediaDirection,
        registration: RegistrationContext,
        session: inout SessionContext,
        media: MediaSession?
    ) async throws {
        let impu = session.localURI
        let pani = try platform.accessInfo.currentAccessInfo().paniHeaderValue
        let localIP = try platform.network.localIPAddress()
        let codec = session.negotiatedCodec ?? .amrWB
        let port = session.localAudioPort ?? 40000
        session.dialog.localCSeq = session.dialog.nextCSeq()

        let sdp = SDPSessionBuilder.voLTEMediaSDP(
            profile: profile,
            localIP: localIP,
            audioPort: port,
            codec: codec,
            direction: direction,
            preconditionState: session.preconditionState
        )
        let reinvite = SessionRequestBuilder.makeReInvite(
            profile: profile,
            impu: impu,
            pani: pani,
            localIP: localIP,
            localPort: 5060,
            dialog: session.dialog,
            registration: registration,
            sdp: sdp,
            securityAssociation: registration.securityAssociation
        )

        let transaction = ClientTransaction(transport: transport, logger: logger)
        let response = try await transaction.send(reinvite)
        guard (200 ... 299).contains(response.statusCode) else {
            let action = SIPErrorMapper.action(for: response.statusCode, method: SIPMethod.invite.rawValue)
            logger.warn(
                "Media re-negotiation failed",
                fields: ["status": String(response.statusCode), "action": String(describing: action)]
            )
            throw SessionError.unexpectedResponse(response.statusCode)
        }

        session.mediaDirection = direction
        await media?.setDirection(direction)
    }

    /// Sends an RFC 2833 DTMF tone on the active RTP session.
    public func sendDTMF(_ digit: Character) async throws {
        try await activeMedia?.sendDTMF(digit)
    }

    private func startMedia(session: inout SessionContext, remoteSDP: SDPSessionDescription, localIP: String) async throws {
        guard let factory = mediaTransportFactory else { return }
        guard let remote = SDPMediaParser.audioEndpoint(
            from: remoteSDP,
            preferred: AudioCodec.fromProfile(profile.codecs.audio)
        ) else { return }

        let localPort = session.localAudioPort ?? profile.media.localRTPPort
        let codec = session.negotiatedCodec ?? remote.codec
        let engine = MediaBootstrap.codecEngine(for: codec, profile: profile)
        if profile.media.enableAudioIO, audioIODevice == nil {
            audioIODevice = AudioIODevice()
        }
        let media = MediaSession(
            transport: factory(),
            codecEngine: engine,
            audioIO: profile.media.enableAudioIO ? audioIODevice : nil
        )
        do {
            try await media.start(localPort: localPort, remote: remote, direction: session.mediaDirection)
        } catch {
            throw SessionError.mediaFailed(error.localizedDescription)
        }
        activeMedia = media
        session.remoteMedia = remote

        if profile.media.enableVideo,
           let videoRemote = SDPMediaParser.videoEndpoint(
               from: remoteSDP,
               preferred: VideoCodec.fromProfile(profile.codecs.video)
           ) {
            let video = VideoRTPSession()
            await video.start(remote: videoRemote)
            activeVideo = video
        }
    }

    private func fulfillPreconditionsMO(
        session: inout SessionContext,
        impu: String,
        pani: String,
        localIP: String,
        registration: RegistrationContext
    ) async throws {
        session.state = .preconditionWait
        session.preconditionState.local = .sendrecv
        session.dialog.localCSeq = 3

        let updateSDP = SDPSessionBuilder.voLTEOffer(
            profile: profile,
            localIP: localIP,
            audioPort: profile.media.localRTPPort,
            preconditionState: session.preconditionState
        )
        let update = SessionRequestBuilder.makeUPDATE(
            profile: profile,
            impu: impu,
            pani: pani,
            localIP: localIP,
            localPort: 5060,
            dialog: session.dialog,
            sdp: updateSDP,
            securityAssociation: registration.securityAssociation
        )

        let transaction = ClientTransaction(transport: transport, logger: logger)
        let response = try await transaction.send(update)
        guard (200 ... 299).contains(response.statusCode) else {
            await cleanupSession(&session)
            activeSession = nil
            throw SessionError.unexpectedResponse(response.statusCode)
        }

        if let body = response.body {
            let answer = SDPParser.parse(String(decoding: body, as: UTF8.self))
            session.preconditionState.remote = answer.preconditionState.local
        }

        guard session.preconditionState.allMet else {
            await cleanupSession(&session)
            activeSession = nil
            throw SessionError.preconditionTimeout
        }
    }

    /// Hangs up the active call; automatically resumes a held call afterward.
    public func terminateActiveCall(registration: RegistrationContext) async throws {
        guard var session = activeSession else { throw SessionError.noActiveSession }
        try await terminate(session: &session, registration: registration)
        activeSession = nil
        activeMedia = nil
        activeVideo = nil

        if var held = heldSession {
            try await renegotiateMedia(
                direction: .sendrecv,
                registration: registration,
                session: &held,
                media: heldMedia
            )
            activeSession = held
            activeMedia = heldMedia
            activeVideo = heldVideo
            heldSession = nil
            heldMedia = nil
            heldVideo = nil
        }
    }

    /// Handles an incoming (MT — Mobile Terminated) INVITE: Trying → 183 → PRACK → 200 → ACK.
    public func handleIncomingInvite(
        _ invite: SIPRequest,
        registration: RegistrationContext
    ) async throws -> SessionContext {
        let localIP = try platform.network.localIPAddress()
        let impu = registration.defaultIMPU ?? invite.headers["To"] ?? ""
        let caller = invite.headers["P-Asserted-Identity"] ?? invite.headers["From"] ?? ""

        let bearer = try platform.bearer.requestDedicatedBearer(qci: .voice)
        var preconditionState = PreconditionState(local: .none, remote: .none)

        if let body = invite.body {
            let offer = SDPParser.parse(String(decoding: body, as: UTF8.self))
            preconditionState.remote = offer.preconditionState.local
        }

        let remoteTag = invite.headers["From"]?.components(separatedBy: "tag=").last?
            .trimmingCharacters(in: CharacterSet(charactersIn: ">; "))
        var dialog = DialogContext(
            callID: invite.headers["Call-ID"] ?? UUID().uuidString,
            localTag: String(UUID().uuidString.prefix(8)),
            remoteTag: remoteTag,
            localCSeq: 1,
            remoteCSeq: Int(invite.headers["CSeq"]?.split(separator: " ").first ?? "0"),
            remoteTarget: caller
        )

        var session = SessionContext(
            dialog: dialog,
            state: .proceeding,
            remoteURI: caller,
            localURI: impu,
            preconditionState: preconditionState,
            bearerHandle: bearer
        )
        activeSession = session

        let serverTxn = InviteServerTransaction(transport: transport, logger: logger)
        try await serverTxn.sendResponse(SessionRequestBuilder.makeTrying(for: invite))

        let offered = invite.body.map { SDPParser.parse(String(decoding: $0, as: UTF8.self)) }
            .map { SDPParser.offeredAudioCodecs($0) } ?? []
        let progressSDP = SDPSessionBuilder.voLTEAnswer(
            profile: profile,
            localIP: localIP,
            audioPort: 40002,
            offeredCodecs: offered,
            preconditionState: preconditionState
        )
        let progress = SessionRequestBuilder.makeSessionProgress(
            for: invite,
            sdp: progressSDP,
            require100rel: profile.preconditions.enabled,
            localTag: dialog.localTag
        )
        try await serverTxn.sendResponse(progress)

        if profile.preconditions.enabled {
            let callID = dialog.callID
            let prack = try await serverTxn.waitForRequest(method: SIPMethod.prack.rawValue, callID: callID)
            try await serverTxn.sendResponse(SessionRequestBuilder.makeOK(for: prack))

            preconditionState.local = .sendrecv
            session.preconditionState = preconditionState

            let update = try await serverTxn.waitForRequest(method: SIPMethod.update.rawValue, callID: callID)
            if let body = update.body {
                let remoteSDP = SDPParser.parse(String(decoding: body, as: UTF8.self))
                preconditionState.remote = remoteSDP.preconditionState.local
            }
            session.preconditionState = preconditionState

            let updateAnswer = SDPSessionBuilder.voLTEAnswer(
                profile: profile,
                localIP: localIP,
                audioPort: 40002,
                offeredCodecs: offered,
                preconditionState: preconditionState
            )
            try await serverTxn.sendResponse(SessionRequestBuilder.makeOK(for: update, sdp: updateAnswer))

            guard session.preconditionState.allMet else {
                await cleanupSession(&session)
                activeSession = nil
                throw SessionError.preconditionTimeout
            }
        }

        let finalSDP = SDPSessionBuilder.voLTEAnswer(
            profile: profile,
            localIP: localIP,
            audioPort: 40002,
            offeredCodecs: offered,
            preconditionState: session.preconditionState
        )
        let ok = SessionRequestBuilder.makeOK(for: invite, sdp: finalSDP)
        try await serverTxn.sendResponse(ok)

        dialog.remoteTarget = caller
        session.dialog = dialog
        session.negotiatedCodec = SDPParser.offeredAudioCodecs(finalSDP).first(where: { $0 != .telephoneEvent })

        _ = try await serverTxn.waitForRequest(method: SIPMethod.ack.rawValue, callID: dialog.callID, timeout: .seconds(2))

        session.state = .established
        session.localAudioPort = 40002
        if let offerBody = invite.body {
            let offerSDP = SDPParser.parse(String(decoding: offerBody, as: UTF8.self))
            try await startMedia(session: &session, remoteSDP: offerSDP, localIP: localIP)
        }
        activeSession = session

        logger.info(
            "MT call established",
            fields: [
                "caller": caller,
                "codec": session.negotiatedCodec?.rawValue ?? "",
                "preconditions_met": String(session.preconditionState.allMet),
            ]
        )
        return session
    }

    private func terminate(session: inout SessionContext, registration: RegistrationContext) async throws {
        session.state = .terminating
        let impu = session.localURI
        let pani = try platform.accessInfo.currentAccessInfo().paniHeaderValue
        let localIP = try platform.network.localIPAddress()
        session.dialog.localCSeq = 3

        let bye = SessionRequestBuilder.makeBYE(
            impu: impu,
            pani: pani,
            localIP: localIP,
            localPort: 5060,
            dialog: session.dialog,
            securityAssociation: registration.securityAssociation
        )

        let transaction = InviteClientTransaction(transport: transport, logger: logger)
        let response = try await transaction.sendRequest(bye)
        guard (200 ... 299).contains(response.statusCode) else {
            throw SessionError.unexpectedResponse(response.statusCode)
        }

        await cleanupSession(&session)
        session.state = .terminated
        logger.info("Call terminated", fields: ["call_id": session.dialog.callID])
    }

    private func cleanupSession(_ session: inout SessionContext) async {
        if let media = activeMedia {
            await media.stop()
            activeMedia = nil
        }
        if let video = activeVideo {
            await video.stop()
            activeVideo = nil
        }
        audioIODevice?.stop()
        audioIODevice = nil
        if let bearer = session.bearerHandle {
            try? platform.bearer.releaseBearer(bearer)
            session.bearerHandle = nil
        }
        session.state = .terminated
    }
}
