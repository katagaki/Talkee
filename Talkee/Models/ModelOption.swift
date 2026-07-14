//
//  ModelOption.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import Foundation

struct ModelOption: Identifiable {
    let id: String
    let nameKey: String.LocalizationValue
    let descriptionKey: String.LocalizationValue

    static let userVisible: [ModelOption] = [
        ModelOption(
            id: ModelDownloadCoordinator.asrKey,
            nameKey: "Model.Multilingual.Name",
            descriptionKey: "Model.Multilingual.Description"
        )
    ]

    static func defaultSelection() -> Set<String> {
        [ModelDownloadCoordinator.asrKey]
    }
}
