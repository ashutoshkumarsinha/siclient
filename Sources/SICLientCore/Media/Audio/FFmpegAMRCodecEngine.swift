import Foundation

/// AMR-WB encode/decode via ffmpeg when installed (`brew install ffmpeg`).
public struct FFmpegAMRCodecEngine: AudioCodecEngine {
    public let codec: AudioCodec
    public let samplesPerFrame: Int

    public static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ffmpeg")
            || FileManager.default.fileExists(atPath: "/usr/local/bin/ffmpeg")
    }

    private static var ffmpegPath: String {
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ffmpeg") {
            return "/opt/homebrew/bin/ffmpeg"
        }
        return "/usr/local/bin/ffmpeg"
    }

    public init(codec: AudioCodec) {
        self.codec = codec
        self.samplesPerFrame = codec == .amrWB ? 320 : 160
    }

    public func encodePCM(_ pcm: Data) -> Data {
        guard codec == .amrWB else {
            return LabAMRCodecEngine(codec: codec).encodePCM(pcm)
        }
        let format = "amrwb"
        let args = [
            "-hide_banner", "-loglevel", "error",
            "-f", "s16le", "-ar", "16000", "-ac", "1", "-i", "pipe:0",
            "-f", format, "pipe:1",
        ]
        guard let output = runFFmpeg(args: args, input: pcm), !output.isEmpty else {
            return LabAMRCodecEngine(codec: codec).encodePCM(pcm)
        }
        var payload = Data([0xF0])
        payload.append(output)
        return payload
    }

    public func decodeRTPPayload(_ payload: Data) -> Data {
        guard codec == .amrWB else {
            return LabAMRCodecEngine(codec: codec).decodeRTPPayload(payload)
        }
        let frame = payload.first == 0xF0 ? payload.dropFirst() : payload[...]
        let args = [
            "-hide_banner", "-loglevel", "error",
            "-f", "amrwb", "-i", "pipe:0",
            "-f", "s16le", "-ar", "16000", "-ac", "1", "pipe:1",
        ]
        guard let pcm = runFFmpeg(args: args, input: Data(frame)) else {
            return LabAMRCodecEngine(codec: codec).decodeRTPPayload(payload)
        }
        return pcm
    }

    private func runFFmpeg(args: [String], input: Data) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.ffmpegPath)
        process.arguments = args

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            inputPipe.fileHandleForWriting.write(input)
            try inputPipe.fileHandleForWriting.close()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return outputPipe.fileHandleForReading.readDataToEndOfFile()
        } catch {
            return nil
        }
    }
}
