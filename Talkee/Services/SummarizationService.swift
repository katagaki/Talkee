//
//  SummarizationService.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import Foundation
import FoundationModels

enum SummarizationService {

    static func summarize(_ transcription: Transcription, kind: SummaryKind) async throws -> String {
        let prompt = String(localized: kind.promptKey)
        let body = transcription.blocks
            .sorted(by: { $0.index < $1.index })
            .map(\.text)
            .joined(separator: "\n")

        let session = LanguageModelSession(
            instructions: String(localized: "Summary.Instructions")
        )
        let response = try await session.respond(to: "\(prompt)\n\n---\n\(body)")
        return response.content
    }
}
