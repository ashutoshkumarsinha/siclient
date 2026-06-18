import Foundation

public actor MediaSession {
    private let transport: any RTPTransport
    private let codecEngine: any AudioCodecEngine
    private var rtpSession: RTPSession?
    private var audioIO: AudioIODevice?
    private var direction: MediaDirection = .sendrecv
    private var pumpTask: Task<Void, Never>?
    private var rtcpTask: Task<Void, Never>?
    private var capturePCM: Data?

    public init(transport: any RTPTransport, codecEngine: any AudioCodecEngine, audioIO: AudioIODevice? = nil) {
        self.transport = transport
        self.codecEngine = codecEngine
        self.audioIO = audioIO
    }

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

        rtcpTask = Task { [weak self] in
            guard let self else { return }
            await self.rtcpLoop()
        }
    }

    private func setCapturePCM(_ pcm: Data) {
        capturePCM = pcm
    }

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

    public func stats() async -> RTPStreamStats {
        await rtpSession?.currentStats() ?? RTPStreamStats()
    }

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

    private func transmitLoop() async {
        var frameIndex: UInt8 = 0
        while !Task.isCancelled {
            let pcm: Data
            if let capturePCM, capturePCM.count >= codecEngine.samplesPerFrame * 2 {
                pcm = capturePCM
            } else {
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
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func rtcpLoop() async {
        while !Task.isCancelled {
            try? await rtpSession?.sendRTCPReport()
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func handleReceived(_ packet: RTPPacket) {
        let pcm = codecEngine.decodeRTPPayload(packet.payload)
        audioIO?.playPCM(pcm)
    }
}
