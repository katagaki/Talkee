//
//  TalkNowView.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import SwiftData
import SwiftUI

struct TalkNowView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(ModelDownloadCoordinator.self) private var downloads
    @State private var service = ASRService()

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(speakerTurns(from: service.liveBlocks), id: \.id) { turn in
                            speakerBubble(turn)
                                .id(turn.anchorID)
                        }
                    }
                    .padding(.horizontal)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: service.liveBlocks.count) { _, _ in
                    scrollToBottom(proxy)
                }
            }
            .safeAreaInset(edge: .top) {
                idleHeader
            }
            .safeAreaInset(edge: .bottom) {
                recordingSection
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            }
            .navigationTitle("Tab.TalkNow")
            .toolbarTitleDisplayMode(.inlineLarge)
        }
    }

    @ViewBuilder
    private var idleHeader: some View {
        if !downloadIsReady {
            Label(downloads.phaseTitle, systemImage: "arrow.down.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    private var recordingSection: some View {
        VStack(spacing: 12) {
            if service.isRecording {
                Label("TalkNow.Listening", systemImage: "waveform")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .symbolEffect(.variableColor.iterative.reversing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))

                WaveformView(samples: service.waveformLevels, isActive: true)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            primaryButton
        }
        .padding(service.isRecording ? 16 : 8)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: service.isRecording)
    }

    private struct SpeakerTurn: Identifiable {
        let id: UUID = UUID()
        let speakerIndex: Int?
        let text: String
        let anchorID: UUID
    }

    private func speakerTurns(from blocks: [ASRService.BlockSnapshot]) -> [SpeakerTurn] {
        var turns: [SpeakerTurn] = []
        for block in blocks {
            if let last = turns.last, last.speakerIndex == block.speakerIndex {
                turns[turns.count - 1] = SpeakerTurn(
                    speakerIndex: last.speakerIndex,
                    text: last.text + " " + block.text,
                    anchorID: block.id
                )
            } else {
                turns.append(SpeakerTurn(
                    speakerIndex: block.speakerIndex,
                    text: block.text,
                    anchorID: block.id
                ))
            }
        }
        return turns
    }

    private func speakerBubble(_ turn: SpeakerTurn) -> some View {
        let isFirstSpeaker = turn.speakerIndex == 0
        let bubbleAlignment: HorizontalAlignment = isFirstSpeaker ? .trailing : .leading
        let frameAlignment: Alignment = isFirstSpeaker ? .trailing : .leading
        let tint = speakerColor(for: turn.speakerIndex)

        return VStack(alignment: bubbleAlignment, spacing: 4) {
            if turn.speakerIndex != nil {
                Text(speakerLabel(for: turn.speakerIndex))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }

            Text(turn.text)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    private func speakerLabel(for index: Int?) -> String {
        guard let index else { return String(localized: "Speaker.Unknown") }
        return String(format: String(localized: "Speaker.Numbered"), index + 1)
    }

    private func speakerColor(for index: Int?) -> Color {
        guard let index else { return .secondary }
        let palette: [Color] = [.blue, .pink, .green, .orange, .purple, .teal, .indigo, .red]
        return palette[index % palette.count]
    }

    private var primaryButton: some View {
        Button {
            Task { await togglePressed() }
        } label: {
            Image(systemName: service.isRecording ? "stop.fill" : "mic.fill")
                .font(.title2)
                .frame(width: 56, height: 56)
                .accessibilityLabel(service.isRecording ? "TalkNow.Stop" : "TalkNow.Start")
        }
        .buttonStyle(.borderedProminent)
        .tint(service.isRecording ? .red : .accentColor)
        .controlSize(.extraLarge)
        .buttonBorderShape(.circle)
        .disabled(!downloadIsReady || service.state == .starting || service.state == .stopping)
    }

    private var downloadIsReady: Bool {
        if case .ready = downloads.phase { return true }
        return false
    }

    private func togglePressed() async {
        if service.isRecording {
            await service.stop()
        } else if let models = downloads.models {
            let diarizer = await downloads.ensureDiarizer()
            await service.start(in: modelContext, models: models, diarizerModels: diarizer)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = service.liveBlocks.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}
