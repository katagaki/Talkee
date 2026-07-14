//
//  LanguageOption.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import Foundation

struct LanguageOption: Identifiable {
    let code: String
    let name: String
    var id: String { code }

    /// Optional hints for the auto-detecting multilingual model. An empty code
    /// (and any code the model doesn't recognize) falls back to auto-detection.
    static let all: [LanguageOption] = [
        LanguageOption(code: "", name: "Auto"),
        LanguageOption(code: "ja", name: "日本語"),
        LanguageOption(code: "zh", name: "中文"),
        LanguageOption(code: "en", name: "English"),
        LanguageOption(code: "es", name: "Español"),
        LanguageOption(code: "fr", name: "Français"),
        LanguageOption(code: "de", name: "Deutsch"),
        LanguageOption(code: "it", name: "Italiano"),
        LanguageOption(code: "pt", name: "Português"),
        LanguageOption(code: "ro", name: "Română"),
        LanguageOption(code: "pl", name: "Polski"),
        LanguageOption(code: "cs", name: "Čeština"),
        LanguageOption(code: "sk", name: "Slovenčina"),
        LanguageOption(code: "sl", name: "Slovenščina"),
        LanguageOption(code: "hr", name: "Hrvatski"),
        LanguageOption(code: "ru", name: "Русский"),
        LanguageOption(code: "uk", name: "Українська"),
        LanguageOption(code: "bg", name: "Български"),
        LanguageOption(code: "ko", name: "한국어"),
        LanguageOption(code: "nl", name: "Nederlands"),
        LanguageOption(code: "hi", name: "हिन्दी"),
        LanguageOption(code: "vi", name: "Tiếng Việt"),
        LanguageOption(code: "ar", name: "العربية")
    ]
}
