import Foundation

// MARK: - File Overview
// Runs a live audio media session: captures microphone audio, encodes it, sends RTP
// (Real-time Transport Protocol) packets to the remote party, receives their packets,
// decodes them, and plays audio. Also handles DTMF (Dual-Tone Multi-Frequency) tones.

/// Coordinates RTP transport, codec, and optional microphone/speaker I/O for one call leg.
public actor MediaSession {
    private let transport: any RTPTransport
    private let codecEngine: any AudioCodecEngine
    private var rtpSession: RTPSession?
    private var audioIO: AudioIODevice?
    private var direction: MediaDirection = .sendrecv
    private var pumpTask: Task<Void, Never>?
    private var rtcpTask: Task<Void, Never>?
    private var capturePCM: Data?

    /// Creates a media session with the given transport and codec; audio I/O is optional.
    public init(transport: any RTPTransport, codecEngine: any AudioCodecEngine, audioIO: AudioIODevice? = nil) {
        self.transport = transport
        self.codecEngine = codecEngine
        self.audioIO = audioIO
    }

    /// Binds local port, starts RTP send/receive, and optionally begins microphone capture.
    public func start(
        localPort: Int,
        remote: MediaEndpoint,
        direction: MediaDirection = .sendrecv
    ) async throws {
        self.direction = direction
        try await transport.bind(localPort: localPort)
        if let loopback = transport as? LoopbackRTPTransport {
            await loopback.setPeer(host: remote.address, port: remote.port)
        }

        let session = RTPSession(
            transport: transport,
            payloadType: remote.payloadType,
            clockRate: remote.clockRate
        )
        rtpSession = session

        try await session.start(remote: remote) { [weak self] packet in
            guard let self else { return }
            Task { await self.handleReceived(packet) }
        }

        if let audioIO {
            try audioIO.start { [weak self] pcm in
                Task { await self?.setCapturePCM(pcm) }
            }
        }

        if direction == .sendrecv || direction == .sendonly {
            pumpTask = Task { [weak self] in
                guard let self else { return }
                await self.transmitLoop()
            }
        }

        // RTCP (RTP Control Protocol) reports help monitor stream quality.
        rtcpTask = Task { [weak self] in
            guard let self else { return }
            await self.rtcpLoop()
        }
    }

    private func setCapturePCM(_ pcm: Data) {
        capturePCM = pcm
    }

    /// Sends a DTMF tone digit as RTP telephone-event packets.
    public func sendDTMF(_ digit: Character) async throws {
        guard let rtpSession, direction == .sendrecv || direction == .sendonly else { return }
        guard let eventDigit = DTMFEncoder.digitCharacter(digit) else { return }
        let start = DTMFEvent(digit: eventDigit, end: false)
        let end = DTMFEvent(digit: eventDigit, duration: 800, end: true)
        let pt = UInt8(AudioCodec.telephoneEvent.payloadType)
        try await rtpSession.send(payload: DTMFEncoder.rtpPayload(for: start), marker: false, samplesPerFrame: 160)
        try await Task.sleep(for: .milliseconds(80))
        try await rtpSession.send(payload: DTMFEncoder.rtpPayload(for: end), marker: true, samplesPerFrame: 160)
        _ = pt
    }

    /// Changes whether this session sends, receives, both, or neither.
    public func setDirection(_ direction: MediaDirection) async {
        self.direction = direction
        if direction == .sendonly || direction == .inactive {
            pumpTask?.cancel()
            pumpTask = nil
        } else if direction == .sendrecv, pumpTask == nil {
            pumpTask = Task { [weak self] in
                guard let self else { return }
                await self.transmitLoop()
            }
        }
    }

    /// Returns current RTP stream statistics (packets sent/received, loss, jitter).
    public func stats() async -> RTPStreamStats {
        await rtpSession?.currentStats() ?? RTPStreamStats()
    }

    /// Stops capture, transmission, and RTP sessions cleanly.
    public func stop() async {
        pumpTask?.cancel()
        rtcpTask?.cancel()
        pumpTask = nil
        rtcpTask = nil
        audioIO?.stop()
        audioIO = nil
        if let rtpSession {
            await rtpSession.stop()
        }
        rtpSession = nil
        await transport.close()
    }

    /// Repeatedly encodes captured (or placeholder) PCM and sends RTP audio frames.
    private func transmitLoop() async {
        var frameIndex: UInt8 = 0
        while !Task.isCancelled {
            let pcm: Data
            if let capturePCM, capturePCM.count >= codecEngine.samplesPerFrame * 2 {
                pcm = capturePCM
            } else {
                // No microphone data yet — send a deterministic placeholder frame.
                pcm = Data(repeating: frameIndex, count: codecEngine.samplesPerFrame * 2)
            }
            let payload = codecEngine.encodePCM(pcm)
            do {
                try await rtpSession?.send(
                    payload: payload,
                    marker: false,
                    samplesPerFrame: codecEngine.samplesPerFrame
                )
            } catch {
                break
            }
            frameIndex &+= 1
            // ~20 ms frame interval for wideband codecs.
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Sends periodic RTCP sender reports to the remote party.
    private func rtcpLoop() async {
        while !Task.isCancelled {
            try? await rtpSession?.sendRTCPReport()
            try? await Task.sleep(for: .seconds(5))
        }
    }

    /// Decodes an incoming RTP packet and plays the resulting PCM audio.
    private func handleReceived(_ packet: RTPPacket) {
        let pcm = codecEngine.decodeRTPPayload(packet.payload)
        audioIO?.playPCM(pcm)
    }
}
