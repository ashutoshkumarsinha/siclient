import Foundation
@preconcurrency import AVFAudio

// MARK: - File Overview
// Captures microphone audio and plays received PCM (Pulse-Code Modulation) audio
// using macOS AVAudioEngine. Converts captured samples to 16 kHz mono for VoLTE codecs.

/// Bridges the system microphone and speaker to the media session as raw PCM data.
public final class AudioIODevice: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var captureCallback: (@Sendable (Data) -> Void)?
    private let lock = NSLock()

    /// Creates an audio I/O device backed by AVAudioEngine.
    public init() {}

    /// True while the audio engine is running.
    public var isRunning: Bool { engine.isRunning }

    /// Starts microphone capture and playback; calls the handler with PCM frames at 16 kHz.
    public func start(captureHandler: @escaping @Sendable (Data) -> Void) throws {
        lock.lock()
        captureCallback = captureHandler
        lock.unlock()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // VoLTE wideband codecs expect 16 kHz, 16-bit, mono PCM.
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: targetFormat)

        input.installTap(onBus: 0, bufferSize: 320, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            guard let converter = AVAudioConverter(from: format, to: targetFormat) else { return }
            let capacity = AVAudioFrameCount(targetFormat.sampleRate / 50)
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            guard error == nil, let channel = converted.int16ChannelData?.pointee else { return }
            let byteCount = Int(converted.frameLength) * MemoryLayout<Int16>.size
            let data = Data(bytes: channel, count: byteCount)
            self.lock.lock()
            let handler = self.captureCallback
            self.lock.unlock()
            handler?(data)
        }

        try engine.start()
        playerNode.play()
    }

    /// Queues PCM audio for playback through the speaker.
    public func playPCM(_ pcm: Data) {
        guard engine.isRunning else { return }
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
        let frameCount = AVAudioFrameCount(pcm.count / MemoryLayout<Int16>.size)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        pcm.withUnsafeBytes { raw in
            guard let src = raw.baseAddress, let dst = buffer.int16ChannelData?.pointee else { return }
            memcpy(dst, src, pcm.count)
        }
        playerNode.scheduleBuffer(buffer)
    }

    /// Stops capture, playback, and tears down the audio engine.
    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        engine.stop()
        lock.lock()
        captureCallback = nil
        lock.unlock()
    }
}
