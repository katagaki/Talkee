//
//  TalkNowView.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import SwiftData
import SwiftUI
import UIKit

struct TalkNowView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(ModelDownloadCoordinator.self) private var downloads
    @Query(sort: \Transcription.createdAt, order: .reverse) private var transcriptions: [Transcription]
    @State private var service = ASRService()
    @State private var showRecordingContent = false
    @State private var showManageModels = false
    @State private var showAttributions = false
    @State private var navigateToTranscription: Transcription?
    @Namespace private var glassNamespace
    @AppStorage("selectedLanguageCode") private var selectedLanguageCode: String = ""

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                if isIdle {
                    idleTranscriptionsContent
                } else {
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
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if !service.isRecording {
                        languageSelector
                            .transition(.opacity)
                    }
                    recordingSection
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
                .animation(.smooth.speed(2.0), value: service.isRecording)
            }
            .onChange(of: service.isRecording) { _, isRecording in
                if isRecording {
                    Task {
                        try? await Task.sleep(for: .seconds(0.35))
                        withAnimation(.smooth.speed(2.0)) {
                            showRecordingContent = true
                        }
                    }
                } else {
                    withAnimation(.smooth.speed(2.0)) {
                        showRecordingContent = false
                    }
                }
            }
            .navigationTitle("Tab.TalkNow")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !service.isRecording {
                    Menu {
                        Button {
                            showManageModels = true
                        } label: {
                            Label("Manage Models...", systemImage: "cpu")
                        }
                        Divider()
                        Button {
                            openURL(URL(string: "https://github.com/katagaki/Talkee")!)
                        } label: {
                            Label("More.SourceCode", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                        Button("More.Attributions") {
                            showAttributions = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    }
                }
            }
            .navigationDestination(isPresented: $showAttributions) {
                MoreAttributionsView()
            }
            .navigationDestination(item: $navigateToTranscription) {
                TranscriptionDetailView(transcription: $0)
            }
            .sheet(isPresented: $showManageModels) {
                ManageModelsView()
                    .environment(downloads)
            }
            .alert(
                "TalkNow.Error.Title",
                isPresented: Binding(
                    get: { service.lastErrorMessage != nil },
                    set: { if !$0 { service.lastErrorMessage = nil } }
                ),
                actions: {
                    if service.lastErrorNeedsSettings,
                       let url = URL(string: UIApplication.openSettingsURLString) {
                        Button("TalkNow.Error.OpenSettings") {
                            openURL(url)
                        }
                    }
                    Button("OK", role: .cancel) { }
                },
                message: {
                    Text(service.lastErrorMessage ?? "")
                }
            )
        }
    }

    private var isIdle: Bool {
        !service.isRecording && service.liveBlocks.isEmpty
    }

    private struct LanguageOption {
        let code: String
        let name: String
    }

    private let languages = [
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
        LanguageOption(code: "bs", name: "Bosanski"),
        LanguageOption(code: "ru", name: "Русский"),
        LanguageOption(code: "uk", name: "Українська"),
        LanguageOption(code: "be", name: "Беларуская"),
        LanguageOption(code: "bg", name: "Български"),
        LanguageOption(code: "sr", name: "Српски"),
    ]

    private var currentLanguageName: String {
        languages.first(where: { $0.code == selectedLanguageCode })?.name ?? "Auto"
    }

    @ViewBuilder
    private var languageSelector: some View {
        Menu {
            ForEach(languages, id: \.code) { lang in
                Button {
                    selectedLanguageCode = lang.code
                } label: {
                    if selectedLanguageCode == lang.code {
                        Label(lang.name, systemImage: "checkmark")
                    } else {
                        Text(lang.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                Text(currentLanguageName)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var idleTranscriptionsContent: some View {
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
                        transcriptionRow(for: transcription)
                    }
                }
                .onDelete(perform: deleteTranscriptions)
            }
            .listStyle(.insetGrouped)
        }
    }

    private var recordingSection: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if service.isRecording {
                    Group {
                        if showRecordingContent {
                            WaveformView(samples: service.waveformLevels, isActive: true)
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 84)
                    .padding(.horizontal, 12)
                    .glassEffect(.regular.tint(.black), in: Capsule())
                    .glassEffectID("panel", in: glassNamespace)
                    .glassEffectTransition(.matchedGeometry)
                }
                micStopButton(in: glassNamespace)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.smooth.speed(2.0), value: service.isRecording)
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

    private func micStopButton(in namespace: Namespace.ID) -> some View {
        let buttonGlass: Glass = showRecordingContent
            ? Glass.regular.tint(.red).interactive()
            : Glass.regular.tint(.accentColor).interactive()

        return Button {
            Task { await togglePressed() }
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .labelsHidden()
                        .tint(.white)
                        .transition(.opacity)
                } else {
                    Image(systemName: showRecordingContent ? "stop.fill" : "mic.fill")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(Color.white)
                        .contentTransition(.symbolEffect(.replace))
                        .transition(.opacity)
                }
            }
            .frame(width: 84, height: 84)
            .animation(.smooth.speed(2.0), value: isLoading)
            .accessibilityLabel(isLoading ? "TalkNow.Loading" : (service.isRecording ? "TalkNow.Stop" : "TalkNow.Start"))
        }
        .buttonStyle(.plain)
        .glassEffect(buttonGlass, in: Circle())
        .glassEffectID("button", in: namespace)
        .contentShape(Circle())
        .disabled(isLoading)
    }

    private var isLoading: Bool {
        !downloadIsReady || service.state == .starting || service.state == .stopping
    }

    private var downloadIsReady: Bool {
        if case .ready = downloads.phase { return true }
        return false
    }

    private func togglePressed() async {
        if service.isRecording {
            let savedID = await service.stop()
            if let id = savedID,
               let transcription = modelContext.model(for: id) as? Transcription {
                navigateToTranscription = transcription
            }
        } else if let models = downloads.models {
            let diarizer = await downloads.ensureDiarizer()
            let langCode = selectedLanguageCode.isEmpty ? nil : selectedLanguageCode
            await service.start(in: modelContext, models: models, diarizerModels: diarizer, languageCode: langCode)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = service.liveBlocks.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func transcriptionRow(for transcription: Transcription) -> some View {
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

    private func deleteTranscriptions(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(transcriptions[index])
        }
        try? modelContext.save()
    }
}
