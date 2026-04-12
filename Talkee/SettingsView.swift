//
//  SettingsView.swift
//  Talkee
//

import Speech
import SwiftUI

struct SettingsView: View {

    @State var speechManager = SpeechAnalyzerManager.shared
    @State var installedLocales: [Locale] = []
    @State var supportedLocales: [Locale] = []
    @State var downloadingLocale: TranscriptionLocale?

    var body: some View {
        NavigationStack {
            List {
                Section("Current Language") {
                    Picker("Language", selection: Binding(
                        get: { speechManager.selectedLocale },
                        set: { newValue in
                            Task {
                                await speechManager.switchLocale(to: newValue)
                                await refreshInventory()
                            }
                        }
                    )) {
                        ForEach(TranscriptionLocale.allCases) { locale in
                            Text("\(locale.flag) \(locale.displayName)")
                                .tag(locale)
                        }
                    }

                    LabeledContent("Status", value: statusText)
                }

                Section("Installed Languages") {
                    let installed = installedTranscriptionLocales
                    if installed.isEmpty {
                        Text("No languages installed")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(installed) { locale in
                            HStack {
                                Text("\(locale.flag) \(locale.displayName)")
                                Spacer()
                                if locale == speechManager.selectedLocale {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Button("Use") {
                                        Task {
                                            await speechManager.switchLocale(to: locale)
                                            await refreshInventory()
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }

                Section("Available Languages") {
                    let available = availableTranscriptionLocales
                    if available.isEmpty {
                        Text("All languages installed")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(available) { locale in
                            HStack {
                                Text("\(locale.flag) \(locale.displayName)")
                                Spacer()
                                if downloadingLocale == locale,
                                   case .downloading(let progress) = speechManager.state {
                                    ProgressView(value: progress)
                                        .frame(width: 80)
                                } else {
                                    Button("Download") {
                                        Task {
                                            downloadingLocale = locale
                                            await speechManager.switchLocale(to: locale)
                                            await speechManager.downloadModel()
                                            downloadingLocale = nil
                                            await refreshInventory()
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("Speech Engine", value: "Apple SpeechAnalyzer")
                }
            }
            .navigationTitle("Settings")
            .task {
                await refreshInventory()
            }
        }
    }

    // MARK: - Derived state

    private var statusText: String {
        switch speechManager.state {
        case .idle: return "Idle"
        case .checkingModel: return "Checking\u{2026}"
        case .modelMissing: return "Not Installed"
        case .downloading(let progress): return "Downloading \(Int(progress * 100))%"
        case .ready: return "Ready"
        case .error: return "Error"
        }
    }

    private var installedTranscriptionLocales: [TranscriptionLocale] {
        let installedIdentifiers = Set(installedLocales.map { $0.identifier(.bcp47) })
        return TranscriptionLocale.allCases.filter { installedIdentifiers.contains($0.locale.identifier(.bcp47)) }
    }

    private var availableTranscriptionLocales: [TranscriptionLocale] {
        let installedIdentifiers = Set(installedLocales.map { $0.identifier(.bcp47) })
        let supportedIdentifiers = Set(supportedLocales.map { $0.identifier(.bcp47) })
        return TranscriptionLocale.allCases.filter {
            let bcp47 = $0.locale.identifier(.bcp47)
            return supportedIdentifiers.contains(bcp47) && !installedIdentifiers.contains(bcp47)
        }
    }

    // MARK: - Inventory

    private func refreshInventory() async {
        supportedLocales = await SpeechTranscriber.supportedLocales
        installedLocales = await SpeechTranscriber.installedLocales
    }
}
