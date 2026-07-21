import SwiftUI

struct StudyCalendarView: View {
    let activity: StudyActivitySummary
    @Binding var dailyGoal: Int
    @Binding var isCompact: Bool

    @State private var displayedMonth: Date
    @State private var expandedHeight: CGFloat = 0
    @State private var compactHeight: CGFloat = 0
    @State private var selectedDay: StudyDaySelection?
    private let calendar = Calendar.autoupdatingCurrent

    init(activity: StudyActivitySummary,
         dailyGoal: Binding<Int>,
         isCompact: Binding<Bool>) {
        self.activity = activity
        _dailyGoal = dailyGoal
        _isCompact = isCompact
        let calendar = Calendar.autoupdatingCurrent
        let components = calendar.dateComponents([.year, .month], from: Date())
        _displayedMonth = State(initialValue: calendar.date(from: components) ?? Date())
    }

    var body: some View {
        ZStack(alignment: .top) {
            expandedCalendar
                .opacity(isCompact ? 0 : 1)
                .scaleEffect(isCompact ? 0.985 : 1, anchor: .top)
                .offset(y: isCompact ? -8 : 0)
                .allowsHitTesting(!isCompact)
                .accessibilityHidden(isCompact)

            compactSummary
                .opacity(isCompact ? 1 : 0)
                .scaleEffect(isCompact ? 1 : 0.97, anchor: .topTrailing)
                .allowsHitTesting(isCompact)
                .accessibilityHidden(!isCompact)
        }
        .frame(height: targetHeight, alignment: .top)
        .clipped()
        .background {
            ZStack(alignment: .top) {
                expandedCalendar
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        expandedHeight = height
                    }
                compactSummary
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        compactHeight = height
                    }
            }
            .hidden()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: isCompact)
        .navigationDestination(item: $selectedDay) { selection in
            StudyDayDetailView(
                date: selection.date,
                day: activity.activity(on: selection.date, calendar: calendar)
            )
        }
    }

    private var targetHeight: CGFloat? {
        let measured = isCompact ? compactHeight : expandedHeight
        return measured > 0 ? measured : nil
    }

    private var expandedCalendar: some View {
        VStack(alignment: .leading, spacing: 16) {
            goalHeader
            Divider()
            monthHeader
            weekdayHeader
            calendarGrid
            HStack {
                Spacer()
                sizeToggle
            }
        }
    }

    private var compactSummary: some View {
        HStack(spacing: 12) {
            Image(systemName: todayReviews >= dailyGoal ? "checkmark.circle.fill" : "target")
                .font(.title2)
                .foregroundStyle(todayReviews >= dailyGoal ? .green : .blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Today")
                        .font(.headline)
                    Text("\(todayReviews)/\(dailyGoal)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(Double(todayReviews) / Double(max(dailyGoal, 1)), 1))
                    .tint(todayReviews >= dailyGoal ? .green : .blue)
            }

            Spacer(minLength: 8)

            Label("\(activity.currentStreak)", systemImage: "flame.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(activity.currentStreak > 0 ? .orange : .secondary)
                .accessibilityLabel("\(activity.currentStreak)-day streak")

            sizeToggle
        }
        .frame(minHeight: 44)
    }

    private var goalHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today")
                        .font(.headline)
                    Text(todayMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    ForEach([5, 10, 15, 20, 30, 50], id: \.self) { value in
                        Button {
                            dailyGoal = value
                        } label: {
                            if dailyGoal == value {
                                Label("\(value) reviews", systemImage: "checkmark")
                            } else {
                                Text("\(value) reviews")
                            }
                        }
                    }
                } label: {
                    Label("Goal: \(dailyGoal)", systemImage: "target")
                        .font(.subheadline)
                }
            }

            ProgressView(value: min(Double(todayReviews) / Double(max(dailyGoal, 1)), 1))
                .tint(todayReviews >= dailyGoal ? .green : .blue)

            HStack {
                if activity.currentStreak > 0 {
                    Label("\(activity.currentStreak)-day streak", systemImage: "flame.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var sizeToggle: some View {
        Button {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                isCompact.toggle()
            }
        } label: {
            Image(systemName: "chevron.up")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(.secondary.opacity(0.1), in: Circle())
                .rotationEffect(.degrees(isCompact ? 180 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCompact ? "Expand calendar" : "Compact calendar")
    }

    private var monthHeader: some View {
        HStack {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()
            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.subheadline.weight(.semibold))
            Spacer()

            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .disabled(isShowingCurrentMonth)
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: columns, spacing: 7) {
            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayCell(date)
                } else {
                    Color.clear
                        .frame(height: 38)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let day = activity.activity(on: date, calendar: calendar)
        let reviewCount = day?.reviewCount ?? 0
        let isToday = calendar.isDateInToday(date)

        return Button {
            selectedDay = StudyDaySelection(date: date)
        } label: {
            VStack(spacing: 1) {
                Text(date.formatted(.dateTime.day()))
                    .font(.caption.weight(isToday ? .bold : .regular))
                if reviewCount > 0 {
                    Text(reviewCount.formatted())
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                } else {
                    Text(" ")
                        .font(.system(size: 9))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .foregroundStyle(reviewCount > 0 ? Color.primary : Color.secondary)
            .background(dayColor(reviewCount), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.blue, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(date > Date())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityValue("\(reviewCount) reviews")
    }

    private var todayReviews: Int {
        activity.activity(on: Date(), calendar: calendar)?.reviewCount ?? 0
    }

    private var todayMessage: String {
        if todayReviews >= dailyGoal {
            return "Goal complete — \(todayReviews) reviews"
        }
        return "\(todayReviews) of \(dailyGoal) reviews"
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var monthCells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        let weekday = calendar.component(.weekday, from: displayedMonth)
        let prefixCount = (weekday - calendar.firstWeekday + 7) % 7
        var cells = Array<Date?>(repeating: nil, count: prefixCount)
        cells.append(contentsOf: range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: displayedMonth)
        })
        return cells
    }

    private var isShowingCurrentMonth: Bool {
        calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    private func changeMonth(by amount: Int) {
        guard let next = calendar.date(byAdding: .month, value: amount, to: displayedMonth) else { return }
        displayedMonth = next
    }

    private func dayColor(_ reviewCount: Int) -> Color {
        guard reviewCount > 0 else { return .secondary.opacity(0.08) }
        if reviewCount >= dailyGoal { return .green.opacity(0.3) }
        let fraction = min(Double(reviewCount) / Double(max(dailyGoal, 1)), 1)
        return .blue.opacity(0.12 + 0.25 * fraction)
    }
}

private struct StudyDaySelection: Identifiable, Hashable {
    let date: Date
    var id: Date { date }
}

private struct StudyDayDetailView: View {
    let date: Date
    let day: StudyDay?

    private var newWords: [StudyWordActivity] { day?.words.filter(\.isNew) ?? [] }
    private var repeatedWords: [StudyWordActivity] { day?.words.filter { !$0.isNew } ?? [] }

    var body: some View {
        List {
            Section {
                LabeledContent("Reviews", value: (day?.reviewCount ?? 0).formatted())
                LabeledContent("New words", value: newWords.count.formatted())
                LabeledContent("Repeated words", value: repeatedWords.count.formatted())
            }

            wordSection("New", words: newWords, icon: "sparkles", color: .blue)
            wordSection("Repeated", words: repeatedWords, icon: "repeat", color: .purple)

            if newWords.isEmpty && repeatedWords.isEmpty {
                ContentUnavailableView(
                    "No Reviews",
                    systemImage: "calendar",
                    description: Text("No words were reviewed on this day.")
                )
            }
        }
        .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func wordSection(_ title: String, words: [StudyWordActivity], icon: String, color: Color) -> some View {
        if !words.isEmpty {
            Section {
                ForEach(words) { word in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(word.front).font(.headline)
                            Text(word.back)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(word.deckName)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            if word.failedReviewCount > 0 {
                                Label(
                                    "\(word.failedReviewCount) missed",
                                    systemImage: "exclamationmark.circle.fill"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                            }
                            if word.reviewCount > 1 {
                                Text("×\(word.reviewCount) reviews")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listRowBackground(word.failedReviewCount > 0 ? Color.red.opacity(0.08) : nil)
                }
            } header: {
                Label("\(title) · \(words.count)", systemImage: icon)
                    .foregroundStyle(color)
            }
        }
    }
}
