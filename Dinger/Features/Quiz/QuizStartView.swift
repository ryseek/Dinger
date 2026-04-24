import SwiftUI

struct QuizRootView: View {
    let env: AppEnvironment
    @State private var vm: QuizStartViewModel
    @State private var activeConfig: ActiveConfig?

    struct ActiveConfig: Identifiable, Hashable {
        let id = UUID()
        let deck: Deck
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
                            get: { vm.selectedDeck?.id ?? -1 },
                            set: { newId in vm.selectedDeck = vm.decks.first { $0.id == newId } }
                        )) {
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
                        guard let deck = vm.selectedDeck else { return }
                        activeConfig = ActiveConfig(deck: deck, config: vm.makeConfig())
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .disabled(vm.selectedDeck == nil)
                }
                if let err = vm.error {
                    Section { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Quiz")
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .sheet(item: $activeConfig) { ac in
                QuizPlayView(env: env, deck: ac.deck, config: ac.config)
            }
        }
    }

    private func directionLabel(for mode: QuizDirectionMode) -> String {
        let pair = LanguagePair(source: vm.selectedDeck?.sourceLang ?? env.defaultPair.source,
                                target: vm.selectedDeck?.targetLang ?? env.defaultPair.target)
        return mode.displayLabel(for: pair)
    }
}
