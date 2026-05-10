//
//  TranscriptionDetailView.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct TranscriptionDetailView: View {

    @Bindable var transcription: Transcription
    @Environment(\.modelContext) private var modelContext

    @State private var showRename = false
    @State private var showSummarize = false
    @State private var renameDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                transcriptSection
                if !transcription.summaries.isEmpty {
                    Divider()
                    summariesSection
                }
            }
            .padding()
        }
        .navigationTitle(transcription.title.isEmpty
                         ? String(localized: "Transcriptions.Untitled")
                         : transcription.title)
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar { toolbarItems }
        .sheet(isPresented: $showSummarize) {
            SummarySheet(transcription: transcription)
        }
        .alert("Detail.Rename", isPresented: $showRename) {
            TextField(String(localized: "Detail.Rename.Placeholder"), text: $renameDraft)
            Button("Summary.Save") {
                let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    transcription.title = trimmed
                    try? modelContext.save()
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(transcription.createdAt, format: .dateTime.year().month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
            if let lang = transcription.languageCode {
                Text(lang.uppercased())
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Markdown.Section.Transcript")
                .font(.headline)
            if hasSpeakers {
                chatTranscript
            } else {
                flatTranscript
            }
        }
    }

    private var sortedBlocks: [TranscriptionBlock] {
        transcription.blocks.sorted(by: { $0.index < $1.index })
    }

    private var hasSpeakers: Bool {
        transcription.blocks.contains { $0.speakerIndex != nil }
    }

    private var flatTranscript: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(sortedBlocks) { block in
                Text(block.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var chatTranscript: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(speakerTurns(from: sortedBlocks), id: \.id) { turn in
                speakerBubble(turn)
            }
        }
    }

    private struct SpeakerTurn: Identifiable {
        let id: UUID = UUID()
        let speakerIndex: Int?
        let text: String
    }

    private func speakerTurns(from blocks: [TranscriptionBlock]) -> [SpeakerTurn] {
        var turns: [SpeakerTurn] = []
        for block in blocks {
            if let last = turns.last, last.speakerIndex == block.speakerIndex {
                turns[turns.count - 1] = SpeakerTurn(
                    speakerIndex: last.speakerIndex,
                    text: last.text + " " + block.text
                )
            } else {
                turns.append(SpeakerTurn(speakerIndex: block.speakerIndex, text: block.text))
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
            Text(speakerLabel(for: turn.speakerIndex))
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

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

    private var summariesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Markdown.Section.Summaries")
                .font(.headline)
            ForEach(transcription.summaries.sorted(by: { $0.createdAt < $1.createdAt })) { summary in
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: summary.kind.titleKey))
                        .font(.subheadline.weight(.semibold))
                    Text(LocalizedStringKey(summary.markdown))
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            ShareLink(
                item: MarkdownRenderer.render(transcription),
                preview: SharePreview(transcription.title.isEmpty
                                      ? String(localized: "Transcriptions.Untitled")
                                      : transcription.title)
            ) {
                Image(systemName: "square.and.arrow.up")
            }
            Button {
                showSummarize = true
            } label: {
                Label("Detail.Summarize", systemImage: "sparkles")
            }
            Menu {
                Button {
                    renameDraft = transcription.title
                    showRename = true
                } label: {
                    Label("Detail.Rename", systemImage: "pencil")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}
