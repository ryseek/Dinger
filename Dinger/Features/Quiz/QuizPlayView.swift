import SwiftUI

struct QuizPlayView: View {
    let env: AppEnvironment
    let deck: Deck
    let config: QuizConfig

    @State private var vm: QuizPlayViewModel
    @Environment(\.dismiss) private var dismiss

    init(env: AppEnvironment, deck: Deck, config: QuizConfig) {
        self.env = env
        self.deck = deck
        self.config = config
        let generator = QuestionGenerator(reader: env.database.dbWriter, deck: deck)
        let session = QuizSession(deck: deck, config: config, cardService: env.cardService, generator: generator)
        _vm = State(wrappedValue: QuizPlayViewModel(session: session))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                progressBar
                Spacer(minLength: 8)
                body(for: vm.phase)
                Spacer()
            }
            .padding()
            .navigationTitle(deck.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await vm.start() }
        }
    }

    private var progressBar: some View {
        HStack {
            ProgressView(value: Double(vm.progress.answered),
                         total: Double(max(1, vm.progress.total)))
            Text("\(vm.progress.answered)/\(vm.progress.total)")
                .font(.caption).monospacedDigit()
        }
    }

    @ViewBuilder
    private func body(for phase: QuizPlayViewModel.Phase) -> some View {
        switch phase {
        case .loading:
            ProgressView("Loading…")
        case .empty:
            ContentUnavailableView("No cards due",
                                   systemImage: "checkmark.seal",
                                   description: Text("Add some cards or come back later."))
        case .question(let q):
            questionView(q)
        case .reveal(let q, let inferred):
            revealView(q, inferredGrade: inferred)
        case .done(let p):
            resultsView(p)
        case .error(let msg):
            ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(msg))
        }
    }

    // MARK: - Phases

    @ViewBuilder
    private func questionView(_ q: Question) -> some View {
        VStack(spacing: 20) {
            Text(q.front)
                .font(.largeTitle)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if let frontExample = q.frontExample {
                Text(frontExample)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            switch q.kind {
            case .flashcard:
                Button("Show answer") {
                    vm.flashcardReveal()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            case .typing:
                TextField("Translation", text: $vm.typedAnswer)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal)
                    .onSubmit {
                        Task { await vm.submitTypedAnswer() }
                    }
                Button("Check") {
                    Task { await vm.submitTypedAnswer() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.typedAnswer.trimmingCharacters(in: .whitespaces).isEmpty)

            case .multipleChoice:
                VStack(spacing: 10) {
                    ForEach(Array(q.choices.enumerated()), id: \.offset) { idx, choice in
                        Button {
                            Task { await vm.submitChoice(idx) }
                        } label: {
                            Text(choice)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private func revealView(_ q: Question, inferredGrade: Grade?) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                ForEach(Array(q.displayFronts.enumerated()), id: \.offset) { _, front in
                    Text(front).font(.title2).foregroundStyle(.secondary)
                }
            }
            if let frontExample = q.frontExample {
                Text(frontExample)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Divider()
            ForEach(q.displayAnswers, id: \.self) { answer in
                Text(answer).font(.title3)
            }
            if let backExample = q.backExample {
                Text(backExample)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            if let grade = inferredGrade {
                Text(grade == .again ? "Incorrect" : (grade == .hard ? "Close" : "Correct"))
                    .font(.headline)
                    .foregroundStyle(grade == .again ? .red : (grade == .hard ? .orange : .green))
            }
            Spacer(minLength: 12)
            gradeButtons(for: q, inferred: inferredGrade)
        }
        .padding(.top)
    }

    private func gradeButtons(for q: Question, inferred: Grade?) -> some View {
        HStack(spacing: 8) {
            ForEach(Grade.allCases, id: \.self) { g in
                Button {
                    Task { await vm.submitGrade(g) }
                } label: {
                    VStack(spacing: 2) {
                        Text(g.displayLabel).font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(color(for: g).opacity(inferred == g ? 0.5 : 0.2),
                                in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func color(for g: Grade) -> Color {
        switch g {
        case .again: return .red
        case .hard:  return .orange
        case .good:  return .blue
        case .easy:  return .green
        }
    }

    private func resultsView(_ p: QuizProgress) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(.green)
            Text("Session complete").font(.title2)
            LabeledContent("Answered", value: "\(p.answered)")
            LabeledContent("Correct", value: "\(p.correct)")
            Divider()
            LabeledContent("Again", value: "\(p.again)")
            LabeledContent("Hard", value: "\(p.hard)")
            LabeledContent("Good", value: "\(p.good)")
            LabeledContent("Easy", value: "\(p.easy)")
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top)
        }
        .padding()
    }
}
