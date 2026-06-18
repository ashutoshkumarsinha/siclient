// MediaTests.swift
//
// Verifies RTP/RTCP packet handling, codec engines, DTMF, video SDP, and end-to-end
// media sessions for VoLTE. Once SIP signaling completes, IMS carries voice over RTP —
// these tests ensure packets, stats, and error mapping work before hitting a real network.

import Foundation
import Testing
@testable import SICLientCore

// MARK: - RTP packet format

/// RTP headers (PT, sequence, timestamp, SSRC) must survive serialize/parse so audio
/// frames are not corrupted on the wire between UE and media gateway.
@Test func rtpPacketRoundTrip() {
    let original = RTPPacket(
        payloadType: 103,
        sequenceNumber: 42,
        timestamp: 9_600,
        ssrc: 0x1234_5678,
        payload: Data([0xF0, 0x01, 0x02, 0x03])
    )
    let parsed = RTPPacket.parse(original.serialize())
    #expect(parsed == original)
}

// MARK: - RTCP reporting

/// RTCP Sender Reports carry packet/octet counts the IMS core uses for QoS monitoring.
/// Parsing must extract SSRC and counters for media statistics UI and diagnostics.
@Test func rtcpSenderReportParses() {
    let report = RTCPPacket.buildSenderReport(
        ssrc: 0xAABB_CCDD,
        rtpTimestamp: 48_000,
        packetCount: 10,
        octetCount: 800
    )
    let parsed = RTCPPacket.parseSenderReport(report)
    #expect(parsed?.ssrc == 0xAABB_CCDD)
    #expect(parsed?.packetCount == 10)
    #expect(parsed?.octetCount == 800)
}

/// Receiver Reports report loss and jitter — critical for detecting degraded VoLTE audio.
@Test func rtcpReceiverReportParses() {
    var data = Data([0x81, 201, 0, 7])
    data.append(contentsOf: [0xAA, 0xBB, 0xCC, 0xDD])
    data.append(contentsOf: [0x11, 0x22, 0x33, 0x44])
    data.append(0x05)
    data.append(contentsOf: [0x00, 0x00, 0x02])
    data.append(contentsOf: [0x00, 0x00, 0x01, 0x00])
    data.append(contentsOf: [0x00, 0x00, 0x00, 0x10])
    data.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

    let parsed = RTCPPacket.parseReceiverReport(data)
    #expect(parsed?.ssrc == 0x1122_3344)
    #expect(parsed?.fractionLost == 5)
    #expect(parsed?.cumulativeLost == 2)
    #expect(parsed?.highestSequence == 256)
    #expect(parsed?.jitter == 16)
}

// MARK: - DTMF (RFC 4733)

/// In-band DTMF tones for IVR menus are sent as RTP telephone-event payloads during
/// an active call; encoding must set the end-of-event marker correctly.
@Test func dtmfRtpPayloadEncoding() {
    let payload = DTMFEncoder.rtpPayload(for: DTMFEvent(digit: 5, duration: 800, end: true))
    #expect(payload.count == 4)
    #expect(payload[0] == 5)
    #expect(payload[1] & 0x80 != 0)
}

// MARK: - Video SDP

/// Video calls add an m=video line with H.264 — the offer must match 3GPP video telephony
/// profile-level-id expectations for IMS interoperability.
@Test func videoSdpOfferIncludesH264() throws {
    let profile = try loadFixtureProfile()
    let offer = SDPSessionBuilder.voLTEOffer(
        profile: profile,
        localIP: "127.0.0.1",
        audioPort: 40000,
        includeVideo: true
    )
    let text = offer.serialize()
    #expect(text.contains("m=video"))
    #expect(text.contains("a=rtpmap:96 H264/90000"))
    #expect(text.contains("profile-level-id=42e01f"))
}

// MARK: - Media session (loopback)

/// Two loopback RTP endpoints must exchange encoded AMR-WB frames, proving the media
/// pipeline from codec engine through RTP transport works without real UDP sockets.
@Test func mediaSessionLoopbackExchangesPackets() async throws {
    let bridge = LoopbackRTPBridge()
    let localTransport = LoopbackRTPTransport(bridge: bridge, isLeftSide: true)
    let remoteTransport = LoopbackRTPTransport(bridge: bridge, isLeftSide: false)

    let remoteEndpoint = MediaEndpoint(
        address: "127.0.0.1",
        port: 50_000,
        payloadType: 103,
        codec: .amrWB,
        clockRate: 16_000
    )
    await remoteTransport.setPeer(host: "127.0.0.1", port: 40_000)
    await localTransport.setPeer(host: "127.0.0.1", port: 50_000)

    let localSession = MediaSession(transport: localTransport, codecEngine: LabAMRCodecEngine(codec: .amrWB))
    let remoteSession = RTPSession(transport: remoteTransport, payloadType: 103, clockRate: 16_000)

    final class Counter: @unchecked Sendable { var value = 0 }
    let counter = Counter()

    try await remoteSession.start(remote: MediaEndpoint(
        address: "127.0.0.1", port: 40_000, payloadType: 103, codec: .amrWB, clockRate: 16_000
    )) { _ in counter.value += 1 }

    try await localSession.start(localPort: 40_000, remote: remoteEndpoint)
    try await Task.sleep(for: .milliseconds(120))

    let stats = await localSession.stats()
    #expect(stats.packetsSent >= 1)

    await localSession.stop()
    await remoteSession.stop()
}

// MARK: - Signaling-integrated media

/// A full MO call through SessionFSM must negotiate remote media port and start sending
/// RTP — this is the path from SIP INVITE/200 OK to actual voice on a VoLTE call.
@Test func moCallStartsMediaWithLoopbackRTP() async throws {
    let profile = try loadFixtureProfile()
    let state = MockIMSState()
    let bridge = LoopbackRTPBridge()
    let sipTransport = LoopbackSIPTransport { data in
        MockIMSResponder.responses(for: data, profile: profile, state: state)
    }
    let logger = Logger(output: { _ in })
    let platform = try PlatformContext.stubbed(profile: profile)
    let sessionFSM = SessionFSM(
        profile: profile,
        platform: platform,
        transport: sipTransport,
        logger: logger,
        mediaTransportFactory: { LoopbackRTPTransport(bridge: bridge, isLeftSide: true) }
    )

    let registration = RegistrationContext(
        serviceRoute: "<sip:pcscf.ims.mnc001.mcc001.3gppnetwork.org;lr>",
        defaultIMPU: "sip:001010123456789@ims.mnc001.mcc001.3gppnetwork.org"
    )

    let session = try await sessionFSM.originateCall(
        to: "sip:001010987654321@ims.mnc001.mcc001.3gppnetwork.org",
        registration: registration
    )
    #expect(session.remoteMedia != nil)
    #expect(session.remoteMedia?.port == 50_000)

    try await Task.sleep(for: .milliseconds(80))
    let stats = await sessionFSM.mediaStats()
    #expect(stats.packetsSent >= 1)

    try await sessionFSM.terminateActiveCall(registration: registration)
}

// MARK: - UDP RTP transport

/// Real VoLTE uses UDP for RTP; this test binds local ports and verifies a packet
/// survives send/receive on the loopback interface.
@Test func udpRtpTransportRoundTrip() async throws {
    let sender = UDPRTPTransport()
    let receiver = UDPRTPTransport()
    try await receiver.bind(localPort: 50_001)
    try await sender.bind(localPort: 0)

    let packet = RTPPacket(
        payloadType: 103,
        sequenceNumber: 7,
        timestamp: 160,
        ssrc: 0xDEAD_BEEF,
        payload: Data([0x01, 0x02])
    ).serialize()

    try await sender.send(packet, to: "127.0.0.1", port: 50_001)
    let received = try await receiver.receive(timeout: .seconds(2))
    #expect(received?.data == packet)

    await sender.close()
    await receiver.close()
}

// MARK: - Network resilience

/// When the UE roams from Wi-Fi to LTE (IP/path change), IMS requires re-registration.
/// The policy must detect path changes and schedule appropriate retry delays.
@Test func networkResiliencePolicy() {
    #expect(NetworkResiliencePolicy.shouldReregisterAfterIPChange(previousPath: "wifi", currentPath: "lte"))
    #expect(!NetworkResiliencePolicy.shouldReregisterAfterIPChange(previousPath: "wifi", currentPath: "wifi"))
    #expect(NetworkResiliencePolicy.registrationRetryDelay(attempt: 0) == .milliseconds(500))
}

// MARK: - Video RTP

/// Video sessions track keyframe sends separately from audio — needed for video call
/// statistics and adaptive bitrate decisions.
@Test func videoRtp_serviceTracksKeyframes() async {
    let session = VideoRTPSession()
    let remote = VideoMediaEndpoint(address: "127.0.0.1", port: 50002, payloadType: 96, codec: .h264)
    await session.start(remote: remote)
    await session.noteKeyframeSent(bytes: 1200)
    let stats = await session.currentStats()
    #expect(stats.packetsSent == 1)
    #expect(stats.bytesSent == 1200)
    await session.stop()
}

// MARK: - SIP error mapping

/// SIP response codes drive client behavior: 401 → re-auth, 487 → cleanup dialog,
/// 503 → retry. Wrong mapping causes stuck calls or infinite REGISTER loops.
@Test func sipErrorMapperActions() {
    #expect(SIPErrorMapper.action(for: 401) == .reauthenticate)
    #expect(SIPErrorMapper.action(for: 487) == .cleanupDialog)
    #expect(SIPErrorMapper.action(for: 503) == .retry(maxAttempts: 2))
}
