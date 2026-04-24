import Foundation

/// Minimum-viable SM-2 scheduler. Pure function over (state, grade) → new state,
/// so it's trivially unit-testable and free of side effects.
///
/// This intentionally collapses the traditional quality scale 0..5 into our
/// four user-facing grades (again/hard/good/easy) using ease adjustments of
/// `{-0.2, -0.15, 0, +0.15}` and interval multipliers of `{0 / reset, 1.2, ease, ease*1.3}`.
public nonisolated enum SM2Scheduler {

    public static let minEase: Double = 1.3
    public static let defaultEase: Double = 2.5

    /// Returns the updated SRS state. Does NOT write to the DB — caller does.
    public static func update(srs: CardSRS, grade: Grade, now: Date = Date()) -> CardSRS {
        var next = srs
        let prevInterval = srs.intervalDays
        let prevEase = srs.ease

        switch grade {
        case .again:
            next.repetitions = 0
            next.intervalDays = 1
            next.lapses += 1
            next.ease = max(minEase, prevEase - 0.2)
        case .hard:
            next.repetitions += 1
            next.ease = max(minEase, prevEase - 0.15)
            next.intervalDays = Self.nextInterval(reps: next.repetitions,
                                                  previousInterval: prevInterval,
                                                  ease: next.ease,
                                                  multiplier: 1.2)
        case .good:
            next.repetitions += 1
            // ease unchanged
            next.intervalDays = Self.nextInterval(reps: next.repetitions,
                                                  previousInterval: prevInterval,
                                                  ease: next.ease,
                                                  multiplier: 1.0)
        case .easy:
            next.repetitions += 1
            next.ease = prevEase + 0.15
            next.intervalDays = Self.nextInterval(reps: next.repetitions,
                                                  previousInterval: prevInterval,
                                                  ease: next.ease,
                                                  multiplier: 1.3)
        }

        next.lastReviewedAt = now
        next.dueAt = Self.addDays(next.intervalDays, to: now)
        return next
    }

    public static func makeReviewLog(cardId: Int64,
                                     previous: CardSRS,
                                     next: CardSRS,
                                     grade: Grade,
                                     now: Date = Date()) -> ReviewLog {
        ReviewLog(
            cardId: cardId,
            reviewedAt: now,
            grade: grade.rawValue,
            prevInterval: previous.intervalDays,
            newInterval: next.intervalDays,
            prevEase: previous.ease,
            newEase: next.ease
        )
    }

    // MARK: - Private

    private static func nextInterval(reps: Int,
                                     previousInterval: Double,
                                     ease: Double,
                                     multiplier: Double) -> Double {
        switch reps {
        case 1:  return 1
        case 2:  return 6
        default:
            let base = previousInterval * ease * multiplier
            return max(1, base.rounded())
        }
    }

    private static func addDays(_ days: Double, to date: Date) -> Date {
        date.addingTimeInterval(days * 86_400)
    }
}
