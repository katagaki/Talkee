//
//  ProgressDonut.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import SwiftUI

struct ProgressDonut: View {

    let progress: Double
    var lineWidth: CGFloat = 14

    private var clamped: Double {
        max(0, min(1, progress))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.25), value: clamped)

            Text(percent)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Download progress"))
        .accessibilityValue(Text(percent))
    }

    private var percent: String {
        let value = Int((clamped * 100).rounded())
        return "\(value)%"
    }
}
