//
//  Transcription.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import Foundation
import SwiftData

@Model
final class Transcription {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date.now
    var languageCode: String?

    @Relationship(deleteRule: .cascade, inverse: \TranscriptionBlock.parent)
    var blocks: [TranscriptionBlock] = []

    @Relationship(deleteRule: .cascade, inverse: \TranscriptionSummary.parent)
    var summaries: [TranscriptionSummary] = []

    init(title: String, createdAt: Date = .now, languageCode: String? = nil) {
        self.id = UUID()
        self.title = title
        self.createdAt = createdAt
        self.languageCode = languageCode
    }
}
