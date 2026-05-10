//
//  TranscriptionSummary.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import Foundation
import SwiftData

@Model
final class TranscriptionSummary {
    var id: UUID = UUID()
    var kindRaw: String = SummaryKind.outline.rawValue
    var markdown: String = ""
    var createdAt: Date = Date.now
    var parent: Transcription?

    var kind: SummaryKind {
        get { SummaryKind(rawValue: kindRaw) ?? .outline }
        set { kindRaw = newValue.rawValue }
    }

    init(
        kind: SummaryKind,
        markdown: String,
        createdAt: Date = .now,
        parent: Transcription? = nil
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.markdown = markdown
        self.createdAt = createdAt
        self.parent = parent
    }
}
