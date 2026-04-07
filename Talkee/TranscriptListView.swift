//
//  TranscriptListView.swift
//  Talkee
//
//  Created by Claude on 2026/03/21.
//

import SwiftUI

struct TranscriptListView: View {

    @State var transcriptManager = TranscriptManager.shared

    var body: some View {
        NavigationStack {
            Group {
                if transcriptManager.transcripts.isEmpty {
                    ContentUnavailableView(
                        "No Transcripts",
                        systemImage: "doc.text",
                        description: Text("Transcripts will appear here after you record and transcribe speech.")
                    )
                } else {
                    List {
                        ForEach(transcriptManager.transcripts) { transcript in
                            NavigationLink(destination: TranscriptDetailView(transcript: transcript)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(transcript.displayTitle)
                                        .font(.headline)
                                    HStack {
                                        Text(transcript.formattedDate)
                                        Text("\u{00B7}")
                                        Text(transcript.modelName)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    Text(transcript.summary ?? transcript.text)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                transcriptManager.deleteTranscript(transcriptManager.transcripts[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Transcripts")
            .onAppear {
                transcriptManager.loadAllTranscripts()
            }
        }
    }
}
