import SwiftUI

struct QuizPlayView: View {
    let env: AppEnvironment
    let decks: [Deck]
    let config: QuizConfig

    @State private var vm: QuizPlayViewModel
    @State private var revealOffset: CGFloat = 0
    @State private var revealOpacity: Double = 1
    @State private var isDismissingReveal = false
    @State private var cardToFix: Question?
    @Environment(\.dismiss) private var dismiss

    init(env: AppEnvironment, decks: [Deck], config: QuizConfig) {
        self.env = env
        self.decks = decks
        self.config = config
        let session = QuizSession(
            decks: decks,
            config: config,
            cardService: env.cardService,
            reader: env.database.dbWriter
        )
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
            .navigationTitle(decks.count == 1 ? (decks.first?.name ?? "Quiz") : "All Decks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await vm.start() }
            .sheet(item: $cardToFix) { question in
                FixQuizCardSheet(env: env, question: question) { hit, sourceTermId, targetTermId in
                    await vm.replaceCurrentCard(
                        with: hit,
                        selectedSourceTermId: sourceTermId,
                        selectedTargetTermId: targetTermId
                    )
                }
            }
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
            if config.showExamplesDuringQuestion, let frontExample = q.frontExample {
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
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(Array(q.choices.enumerated()), id: \.offset) { idx, choice in
                        Button {
                            Task { await vm.submitChoice(idx) }
                        } label: {
                            Text(choice)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .minimumScaleFactor(0.85)
                                .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
                                .padding(.horizontal, 10)
                                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Choice \(idx + 1): \(choice)")
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private func revealView(_ q: Question, inferredGrade: Grade?) -> some View {
        let gotItDisabled = inferredGrade == .again
        VStack(spacing: 14) {
            ZStack {
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
                }
                .frame(maxWidth: .infinity, minHeight: 260)
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(swipeColor(gotItDisabled: gotItDisabled).opacity(swipeStrength), lineWidth: 3)
                }
                .shadow(color: .black.opacity(0.12), radius: 16, y: 8)

                VStack {
                    HStack {
                        Spacer()
                        Menu {
                            Button {
                                cardToFix = q
                            } label: {
                                Label("Fix card", systemImage: "wrench.and.screwdriver")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.headline)
                                .frame(width: 36, height: 36)
                                .background(.thinMaterial, in: Circle())
                        }
                        .accessibilityLabel("Card actions")
                    }
                    Spacer()
                }
                .padding(14)

                swipeFeedback(gotItDisabled: gotItDisabled)
            }
            .offset(x: revealOffset)
            .rotationEffect(.degrees(Double(revealOffset / 28)))
            .opacity(revealOpacity)
            .gesture(reviewDragGesture(gotItDisabled: gotItDisabled))

            Text("Swipe or tap a side")
                .font(.caption)
                .foregroundStyle(.secondary)

            binaryReviewControls(gotItDisabled: gotItDisabled)
        }
        .padding(.top)
    }

    private func swipeFeedback(gotItDisabled: Bool) -> some View {
        HStack {
            if revealOffset < 0 {
                feedbackBadge("Again", icon: "arrow.left", color: .red)
            }
            Spacer()
            if revealOffset > 0, !gotItDisabled {
                feedbackBadge("Got it", icon: "arrow.right", color: .green)
            }
        }
        .padding(24)
        .opacity(swipeStrength)
    }

    private func feedbackBadge(_ title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func binaryReviewControls(gotItDisabled: Bool) -> some View {
        HStack(spacing: 12) {
            reviewButton("Again", icon: "arrow.left", color: .red, grade: .again, direction: -1, disabled: false)
            reviewButton("Got it", icon: "arrow.right", color: .green, grade: .good, direction: 1, disabled: gotItDisabled)
        }
    }

    private func reviewButton(_ title: String,
                              icon: String,
                              color: Color,
                              grade: Grade,
                              direction: CGFloat,
                              disabled: Bool) -> some View {
        Button {
            Task { await dismissReveal(grade: grade, direction: direction) }
        } label: {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(color)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.32 : 1)
        .disabled(isDismissingReveal || disabled)
    }

    private func reviewDragGesture(gotItDisabled: Bool) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isDismissingReveal else { return }
                let translation = value.translation.width
                revealOffset = gotItDisabled && translation > 0 ? translation * 0.18 : translation
            }
            .onEnded { value in
                guard !isDismissingReveal else { return }
                if value.translation.width <= -70 {
                    Task { await dismissReveal(grade: .again, direction: -1) }
                } else if value.translation.width >= 70, !gotItDisabled {
                    Task { await dismissReveal(grade: .good, direction: 1) }
                } else {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                        revealOffset = 0
                    }
                }
            }
    }

    private var swipeStrength: Double {
        min(1, Double(abs(revealOffset)) / 90)
    }

    private func swipeColor(gotItDisabled: Bool) -> Color {
        if revealOffset < 0 { return .red }
        return gotItDisabled ? .secondary : .green
    }

    private func dismissReveal(grade: Grade, direction: CGFloat) async {
        guard !isDismissingReveal else { return }
        isDismissingReveal = true
        withAnimation(.easeIn(duration: 0.15)) {
            revealOffset = direction * 1_000
            revealOpacity = 0
        }
        try? await Task.sleep(nanoseconds: 150_000_000)
        await vm.submitGrade(grade)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            revealOffset = 0
            revealOpacity = 1
        }
        isDismissingReveal = false
    }

    private func resultsView(_ p: QuizProgress) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(.green)
            Text("Session complete").font(.title2)
            LabeledContent("Answered", value: "\(p.answered)")
            LabeledContent("Correct", value: "\(p.correct)")
            Divider()
            LabeledContent("Again", value: "\(p.again)")
            LabeledContent("Got it", value: "\(p.good)")
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top)
        }
        .padding()
    }
}

private struct FixQuizCardSheet: View {
    let env: AppEnvironment
    let question: Question
    let onSelect: (SenseHit, Int64, Int64) async -> Void

    @State private var query: String
    @State private var results: [SenseHit] = []
    @State private var isSearching = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(env: AppEnvironment,
         question: Question,
         onSelect: @escaping (SenseHit, Int64, Int64) async -> Void) {
        self.env = env
        self.question = question
        self.onSelect = onSelect
        _query = State(initialValue: Self.searchText(from: question.displayFronts.first ?? question.front))
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSearching && results.isEmpty {
                    ProgressView("Finding meanings…")
                } else if let error, results.isEmpty {
                    ContentUnavailableView("Search failed", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results) { hit in
                        NavigationLink {
                            FixQuizCardTermPicker(hit: hit) { sourceTermId, targetTermId in
                                await onSelect(hit, sourceTermId, targetTermId)
                                dismiss()
                            }
                        } label: {
                            SenseRowView(hit: hit)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Fix card")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search dictionary")
            .onChange(of: query) { _, _ in search() }
            .task { search() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            results = []
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, text == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                let options = DictionarySearchService.SearchOptions(limit: 80, direction: .auto, pair: env.defaultPair)
                results = try await env.searchService.search(text, options: options)
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private static func searchText(from surface: String) -> String {
        surface
            .replacingOccurrences(of: #"\s*\{[^}]+\}"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct FixQuizCardTermPicker: View {
    let hit: SenseHit
    let onApply: (Int64, Int64) async -> Void

    @State private var selectedSourceTermId: Int64
    @State private var selectedTargetTermId: Int64
    @State private var isApplying = false

    init(hit: SenseHit, onApply: @escaping (Int64, Int64) async -> Void) {
        self.hit = hit
        self.onApply = onApply
        let matchedSource = hit.sourceTerms.first { $0.termId == hit.matchedTermId }?.termId
        let matchedTarget = hit.targetTerms.first { $0.termId == hit.matchedTermId }?.termId
        _selectedSourceTermId = State(initialValue: matchedSource ?? hit.sourceTerms.first?.termId ?? 0)
        _selectedTargetTermId = State(initialValue: matchedTarget ?? hit.targetTerms.first?.termId ?? 0)
    }

    var body: some View {
        Form {
            termSection("German", terms: hit.sourceTerms, selection: $selectedSourceTermId)
            termSection("English translation", terms: hit.targetTerms, selection: $selectedTargetTermId)

            Section {
                Button {
                    isApplying = true
                    Task {
                        await onApply(selectedSourceTermId, selectedTargetTermId)
                        isApplying = false
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isApplying { ProgressView() }
                        Text("Replace meaning")
                        Spacer()
                    }
                }
                .disabled(isApplying || selectedSourceTermId == 0 || selectedTargetTermId == 0)
            }
        }
        .navigationTitle("Choose translation")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func termSection(_ title: String,
                             terms: [TermDisplay],
                             selection: Binding<Int64>) -> some View {
        Section(title) {
            ForEach(terms, id: \.termId) { term in
                Button {
                    selection.wrappedValue = term.termId
                } label: {
                    HStack {
                        Text(term.surface)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection.wrappedValue == term.termId {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
