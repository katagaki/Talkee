//
//  TranscriptionsListView.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import SwiftData
import SwiftUI

struct TranscriptionsListView: View {

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transcription.createdAt, order: .reverse) private var transcriptions: [Transcription]

    var body: some View {
        NavigationStack {
            Group {
                if transcriptions.isEmpty {
                    ContentUnavailableView(
                        String(localized: "Transcriptions.Empty"),
                        systemImage: "list.bullet.rectangle"
                    )
                } else {
                    List {
                        ForEach(transcriptions) { transcription in
                            NavigationLink {
                                TranscriptionDetailView(transcription: transcription)
                            } label: {
                                row(for: transcription)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Tab.Transcriptions")
            .toolbarTitleDisplayMode(.inlineLarge)
        }
    }

    private func row(for transcription: Transcription) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(transcription.title.isEmpty
                 ? String(localized: "Transcriptions.Untitled")
                 : transcription.title)
                .font(.headline)
            HStack(spacing: 8) {
                Text(transcription.createdAt, style: .relative)
                Text("•")
                Text("Transcriptions.BlockCount \(transcription.blocks.count)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(transcriptions[index])
        }
        try? modelContext.save()
    }
}
