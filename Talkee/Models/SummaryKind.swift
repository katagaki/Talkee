//
//  SummaryKind.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import Foundation

enum SummaryKind: String, CaseIterable, Identifiable, Sendable {
    case outline
    case actionTasks
    case timeline
    case keyPoints

    var id: String { rawValue }

    var titleKey: String.LocalizationValue {
        switch self {
        case .outline:     "Summary.Kind.Outline"
        case .actionTasks: "Summary.Kind.ActionTasks"
        case .timeline:    "Summary.Kind.Timeline"
        case .keyPoints:   "Summary.Kind.KeyPoints"
        }
    }

    var promptKey: String.LocalizationValue {
        switch self {
        case .outline:     "Summary.Prompt.Outline"
        case .actionTasks: "Summary.Prompt.ActionTasks"
        case .timeline:    "Summary.Prompt.Timeline"
        case .keyPoints:   "Summary.Prompt.KeyPoints"
        }
    }
}
