import DingerCore
import SwiftUI

struct QuizRootView: View {
    let env: AppEnvironment
    @State private var vm: QuizStartViewModel
    @State private var activeConfig: ActiveConfig?

    struct ActiveConfig: Identifiable, Hashable {
        let id = UUID()
        let decks: [Deck]
        let config: QuizConfig
    }

    init(env: AppEnvironment) {
        self.env = env
        _vm = State(wrappedValue: QuizStartViewModel(service: env.cardService))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Deck") {
                    if vm.decks.isEmpty {
                        Text("No decks yet. Add a card from the dictionary first.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Deck", selection: Binding(
                            get: { vm.selectedDeckId ?? -1 },
                            set: { newId in vm.selectedDeckId = newId == -1 ? nil : newId }
                        )) {
                            Label("All Decks", systemImage: "rectangle.stack.fill")
                                .tag(Int64(-1))
                            ForEach(vm.decks) { deck in
                                Text(deck.name).tag(deck.id ?? -1)
                            }
                        }
                    }
                }
                Section {
                    Picker("Mode", selection: $vm.mode) {
                        ForEach(QuizMode.allCases, id: \.self) { m in
                            Text(m.displayLabel).tag(m)
                        }
                    }
                    Stepper("Questions: \(vm.maxQuestions)", value: $vm.maxQuestions, in: 5...50, step: 5)
                    Toggle("Include new cards", isOn: $vm.includeNew)
                        .disabled(vm.practiceMode)
                    Toggle("Show examples during question", isOn: $vm.showExamplesDuringQuestion)
                    Toggle("Practice (ignore due dates)", isOn: $vm.practiceMode)
                } header: {
                    Text("Mode")
                } footer: {
                    Text(vm.practiceMode
                         ? "All non-suspended cards will be drawn in shuffled order. Your answers still update the SRS schedule."
                         : "Only cards whose SRS interval has elapsed will be drawn. Enable Practice to override and review anything at any time.")
                }
                Section("Direction") {
                    Picker("Prompt side", selection: $vm.direction) {
                        ForEach(QuizDirectionMode.allCases, id: \.self) { d in
                            Text(directionLabel(for: d)).tag(d)
                        }
                    }
                }
                Section {
                    Button {
                        guard !vm.selectedDecks.isEmpty else { return }
                        activeConfig = ActiveConfig(decks: vm.selectedDecks, config: vm.makeConfig())
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .disabled(vm.selectedDecks.isEmpty)
                } footer: {
                    Text("""
                    Open-source resources:
                    TU Chemnitz / BEOLINGUS German-English dictionary (GPL v2 or later)
                    Tatoeba German-English sentence pairs (CC BY 2.0 FR)
                    Version \(appVersion)
                    Made by ryseek
                    """)
                }
                if let err = vm.error {
                    Section { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Quiz")
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .sheet(item: $activeConfig) { ac in
                QuizPlayView(env: env, decks: ac.decks, config: ac.config)
            }
        }
    }

    private func directionLabel(for mode: QuizDirectionMode) -> String {
        if vm.selectedDeckId == nil {
            switch mode {
            case .native: return "Card default"
            case .sourceToTarget: return "Source → Target"
            case .targetToSource: return "Target → Source"
            case .mixed: return "Both (random)"
            }
        }
        let pair = LanguagePair(source: vm.selectedDeck?.sourceLang ?? env.defaultPair.source,
                                target: vm.selectedDeck?.targetLang ?? env.defaultPair.target)
        return mode.displayLabel(for: pair)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (version?, build?) where !build.isEmpty:
            return "\(version) (\(build))"
        case let (version?, _):
            return version
        default:
            return "1.0"
        }
    }
}
