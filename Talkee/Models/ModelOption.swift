//
//  ModelOption.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import FluidAudio
import Foundation

struct ModelOption: Identifiable {
    let id: String
    let version: AsrModelVersion
    let nameKey: String.LocalizationValue
    let descriptionKey: String.LocalizationValue

    static let userVisible: [ModelOption] = [
        ModelOption(
            id: "v3",
            version: .v3,
            nameKey: "Model.V3.Name",
            descriptionKey: "Model.V3.Description"
        ),
        ModelOption(
            id: "tdtJa",
            version: .tdtJa,
            nameKey: "Model.TdtJa.Name",
            descriptionKey: "Model.TdtJa.Description"
        ),
        ModelOption(
            id: "ctcZhCn",
            version: .ctcZhCn,
            nameKey: "Model.CtcZhCn.Name",
            descriptionKey: "Model.CtcZhCn.Description"
        )
    ]

    static func defaultSelection() -> Set<String> {
        var selection: Set<String> = ["v3"]
        switch Locale.current.language.languageCode?.identifier {
        case "ja": selection.insert("tdtJa")
        case "zh": selection.insert("ctcZhCn")
        default: break
        }
        return selection
    }
}
