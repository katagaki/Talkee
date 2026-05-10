//
//  AppleIntelligenceAvailability.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import Foundation
import FoundationModels

enum AppleIntelligenceAvailability {

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return String(localized: "Summary.Unavailable.DeviceNotEligible")
        case .unavailable(.appleIntelligenceNotEnabled):
            return String(localized: "Summary.Unavailable.NotEnabled")
        case .unavailable(.modelNotReady):
            return String(localized: "Summary.Unavailable.ModelNotReady")
        case .unavailable:
            return String(localized: "Summary.Unavailable")
        }
    }
}
