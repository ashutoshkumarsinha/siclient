// SDPTests.swift
//
// Verifies Session Description Protocol (SDP) offer/answer generation and parsing for
// VoLTE media negotiation. SDP carries codec choices, RTP ports, and QoS preconditions
// exchanged in SIP INVITE/183/200 OK — getting this wrong means no audio on the call.

import Foundation
import Testing
@testable import SICLientCore

// MARK: - Offer generation

/// VoLTE INVITEs include SDP with AMR-WB and mandatory QoS preconditions (curr/des/conf
/// attributes). Carriers require these before they will open the media bearer.
@Test func sdpOfferIncludesPreconditions() throws {
    let profile = try loadFixtureProfile()
    let offer = SDPSessionBuilder.voLTEOffer(
        profile: profile,
        localIP: "127.0.0.1",
        audioPort: 40000,
        preconditionState: PreconditionState(local: .none, remote: .none)
    )
    let text = offer.serialize()
    #expect(text.contains("m=audio 40000 RTP/AVP"))
    #expect(text.contains("a=rtpmap:103 AMR-WB/16000"))
    #expect(text.contains("a=curr:qos local none"))
    #expect(text.contains("a=des:qos mandatory local sendrecv"))
    #expect(text.contains("a=conf:qos remote sendrecv"))
}

// MARK: - Round-trip parsing

/// Parsing an SDP answer must preserve codec list and precondition state so the
/// session FSM knows when both sides have met QoS requirements for media start.
@Test func sdpRoundTripPreservesPreconditionState() throws {
    let profile = try loadFixtureProfile()
    let original = SDPSessionBuilder.voLTEAnswer(
        profile: profile,
        localIP: "10.0.0.2",
        audioPort: 50000,
        offeredCodecs: [.amrWB, .telephoneEvent],
        preconditionState: PreconditionState(local: .sendrecv, remote: .sendrecv)
    )
    let parsed = SDPParser.parse(original.serialize())
    #expect(parsed.preconditionState.allMet)
    #expect(SDPParser.offeredAudioCodecs(parsed).contains(.amrWB))
}

// MARK: - Precondition state machine

/// QoS preconditions progress from "none" to "sendrecv" as UPDATE/re-INVITE exchanges
/// complete. The parser must detect when local vs remote sides are satisfied.
@Test func preconditionStateParsing() {
    let attrs = [
        "a=curr:qos local sendrecv",
        "a=curr:qos remote none",
        "a=des:qos mandatory local sendrecv",
    ]
    let state = PreconditionState.parse(from: attrs)
    #expect(state.local.isMet)
    #expect(!state.remote.isMet)
    #expect(!state.allMet)
}
