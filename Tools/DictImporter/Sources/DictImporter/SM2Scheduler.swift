import Foundation

// Dev-time copy of the runtime SM-2 scheduler for unit testing.
// Keep in sync with Dinger/Core/Cards/SRS/SM2Scheduler.swift.

public enum DevGrade: Int, CaseIterable {
    case again = 0, hard = 1, good = 2, easy = 3
}

public struct DevSRS: Equatable {
    public var ease: Double
    public var intervalDays: Double
    public var repetitions: Int
    public var lapses: Int
    public var dueAt: Date
    public var lastReviewedAt: Date?

    public init(ease: Double = 2.5,
                intervalDays: Double = 0,
                repetitions: Int = 0,
                lapses: Int = 0,
                dueAt: Date = Date(),
                lastReviewedAt: Date? = nil) {
        self.ease = ease
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.lapses = lapses
        self.dueAt = dueAt
        self.lastReviewedAt = lastReviewedAt
    }
}

public enum DevSM2 {
    public static let minEase: Double = 1.3

    public static func update(srs: DevSRS, grade: DevGrade, now: Date = Date()) -> DevSRS {
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
            next.intervalDays = nextInterval(reps: next.repetitions,
                                             previousInterval: prevInterval,
                                             ease: next.ease,
                                             multiplier: 1.2)
        case .good:
            next.repetitions += 1
            next.intervalDays = nextInterval(reps: next.repetitions,
                                             previousInterval: prevInterval,
                                             ease: next.ease,
                                             multiplier: 1.0)
        case .easy:
            next.repetitions += 1
            next.ease = prevEase + 0.15
            next.intervalDays = nextInterval(reps: next.repetitions,
                                             previousInterval: prevInterval,
                                             ease: next.ease,
                                             multiplier: 1.3)
        }

        next.lastReviewedAt = now
        next.dueAt = now.addingTimeInterval(next.intervalDays * 86_400)
        return next
    }

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
}
