//
//  WaveformView.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import SwiftUI

struct WaveformView: View {

    let samples: [ASRService.LevelSample]
    var isActive: Bool = true
    var barWidth: CGFloat = 3
    var barSpacing: CGFloat = 1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
                draw(into: ctx, size: size, now: context.date)
            }
        }
        .frame(height: 84)
        .opacity(isActive ? 1.0 : 0.35)
        .accessibilityHidden(true)
    }

    private func draw(into ctx: GraphicsContext, size: CGSize, now: Date) {
        guard size.width > 0, size.height > 0, !samples.isEmpty else { return }

        let centerY = size.height / 2
        let maxBarHeight = size.height * 0.95
        let minBarHeight = max(2, size.height * 0.05)
        let halfBar = barWidth / 2
        let slotStride: CGFloat = barWidth + barSpacing

        let visibleSlots = Int(ceil(size.width / slotStride)) + 2
        let recent = Array(samples.suffix(visibleSlots))
        guard let newest = recent.last else { return }

        let interval = estimatedInterval(in: recent) ?? (1.0 / 30.0)
        let newestAge = max(0, now.timeIntervalSince(newest.recordedAt))
        let scrollOffset = min(slotStride, CGFloat(newestAge / interval) * slotStride)

        let fadeWidth: CGFloat = max(slotStride * 6, 32)

        // Bucket bars by opacity (0.125 steps) and combine each bucket into a
        // single Path so we issue ~8 fills per frame instead of one per bar.
        var buckets: [Int: Path] = [:]
        let bucketCount = 8

        for (barIndex, sample) in recent.enumerated() {
            let positionFromRight = recent.count - 1 - barIndex
            let xPos = size.width - halfBar - CGFloat(positionFromRight) * slotStride - scrollOffset

            if xPos + halfBar < 0 { continue }
            if xPos - halfBar > size.width { continue }

            let leftFade = min(1, max(0, xPos / fadeWidth))
            let rightFade = min(1, max(0, (size.width - xPos) / fadeWidth))
            let opacity = Double(leftFade * rightFade)
            guard opacity > 0.01 else { continue }

            let barHeight = max(minBarHeight, CGFloat(sample.value) * maxBarHeight)
            let rect = CGRect(
                x: xPos - halfBar,
                y: centerY - barHeight / 2,
                width: barWidth,
                height: barHeight
            )

            let bucket = min(bucketCount - 1, Int(opacity * Double(bucketCount)))
            buckets[bucket, default: Path()]
                .addRoundedRect(in: rect, cornerSize: CGSize(width: halfBar, height: halfBar))
        }

        let accent = Color.accentColor
        for (bucket, path) in buckets {
            let opacity = Double(bucket) / Double(bucketCount - 1)
            ctx.fill(path, with: .color(accent.opacity(opacity)))
        }
    }

    private func estimatedInterval(in window: [ASRService.LevelSample]) -> TimeInterval? {
        guard window.count >= 2 else { return nil }
        let tail = window.suffix(min(window.count, 9))
        var total: TimeInterval = 0
        var pairs = 0
        var prev: ASRService.LevelSample?
        for sample in tail {
            if let prevSample = prev {
                let delta = sample.recordedAt.timeIntervalSince(prevSample.recordedAt)
                if delta > 0 {
                    total += delta
                    pairs += 1
                }
            }
            prev = sample
        }
        return pairs > 0 ? total / Double(pairs) : nil
    }
}
