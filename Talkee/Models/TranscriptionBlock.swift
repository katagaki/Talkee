//
//  TranscriptionBlock.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import Foundation
import SwiftData

@Model
final class TranscriptionBlock {
    var id: UUID = UUID()
    var index: Int = 0
    var text: String = ""
    var confidence: Float = 0
    var timestamp: Date = Date.now
    var speakerIndex: Int?
    var parent: Transcription?

    init(
        index: Int,
        text: String,
        confidence: Float,
        timestamp: Date,
        speakerIndex: Int? = nil,
        parent: Transcription? = nil
    ) {
        self.id = UUID()
        self.index = index
        self.text = text
        self.confidence = confidence
        self.timestamp = timestamp
        self.speakerIndex = speakerIndex
        self.parent = parent
    }
}
