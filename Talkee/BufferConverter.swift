//
//  BufferConverter.swift
//  Talkee
//
//  Converts AVAudioPCMBuffer between formats, used to match the
//  SpeechAnalyzer's required audio format.
//

@preconcurrency import AVFoundation
import Foundation
import os

final class BufferConverter {
    enum ConversionError: Swift.Error {
        case failedToCreateConverter
        case failedToCreateConversionBuffer
        case conversionFailed(NSError?)
    }

    private var converter: AVAudioConverter?

    func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != format else {
            return buffer
        }

        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            converter?.primeMethod = .none
        }

        guard let converter else {
            throw ConversionError.failedToCreateConverter
        }

        let sampleRateRatio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let scaledFrameLength = Double(buffer.frameLength) * sampleRateRatio
        let frameCapacity = AVAudioFrameCount(scaledFrameLength.rounded(.up))

        guard let conversionBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat,
                                                       frameCapacity: frameCapacity) else {
            throw ConversionError.failedToCreateConversionBuffer
        }

        var nsError: NSError?
        let bufferProcessedLock = OSAllocatedUnfairLock(initialState: false)

        let status = converter.convert(to: conversionBuffer, error: &nsError) { _, inputStatusPointer in
            let wasProcessed = bufferProcessedLock.withLock { bufferProcessed in
                let wasProcessed = bufferProcessed
                bufferProcessed = true
                return wasProcessed
            }
            inputStatusPointer.pointee = wasProcessed ? .noDataNow : .haveData
            return wasProcessed ? nil : buffer
        }

        guard status != .error else {
            throw ConversionError.conversionFailed(nsError)
        }

        return conversionBuffer
    }
}
