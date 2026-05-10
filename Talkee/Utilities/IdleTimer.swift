//
//  IdleTimer.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import UIKit

@MainActor
enum IdleTimer {
    private static var holders = 0

    static func acquire() {
        holders += 1
        UIApplication.shared.isIdleTimerDisabled = true
    }

    static func release() {
        holders = max(0, holders - 1)
        if holders == 0 {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}
