@preconcurrency import AVFoundation
import Foundation
import Speech

/// macOS 26 以降に内蔵の SpeechAnalyzer / SpeechTranscriber で、16kHz モノラルの音声を文字にする。
/// 処理は端末内で行う。日本語のアセットは初回に OS がダウンロードする。
actor SpeechRecognizer {
    static let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    enum Failure: LocalizedError {
        case unsupportedLocale
        case audioFormat

        var errorDescription: String? {
            switch self {
            case .unsupportedLocale: "日本語の文字起こしに対応していない"
            case .audioFormat: "音声の形式を変換できなかった"
            }
        }
    }

    private var locale: Locale?

    func prepare() async throws {
        guard locale == nil else { return }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ja-JP")) else {
            throw Failure.unsupportedLocale
        }
        let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        locale = supported
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await prepare()
        guard let locale else { return "" }

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw Failure.audioFormat
        }
        let buffer = try Self.buffer(from: samples, convertedTo: format)

        let collector = Task {
            var text = ""
            for try await result in transcriber.results {
                text += String(result.text.characters)
            }
            return text
        }
        let (input, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        continuation.yield(AnalyzerInput(buffer: buffer))
        continuation.finish()
        try await analyzer.start(inputSequence: input)
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await collector.value
    }

    static func buffer(from samples: [Float]) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1)))
        else { throw Failure.audioFormat }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }

    private static func buffer(from samples: [Float], convertedTo target: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let source = try buffer(from: samples)
        if target == format { return source }
        guard let converter = AVAudioConverter(from: format, to: target) else { throw Failure.audioFormat }
        let capacity = AVAudioFrameCount(Double(source.frameLength) * target.sampleRate / format.sampleRate) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw Failure.audioFormat
        }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return source
        }
        if let error { throw error }
        return output
    }
}
