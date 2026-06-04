import Foundation

struct AutomationSchedulePreview: Equatable, Sendable {
    var isValid: Bool
    var message: String
    var nextRunAt: Date?
}

struct AutomationScheduleService: Sendable {
    private var calendar: Calendar

    init(calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.calendar = calendar
    }

    func dueAutomations(_ automations: [AppAutomation], at now: Date = Date()) -> [AppAutomation] {
        automations
            .filter { automation in
                guard automation.isActive, let nextRunAt = automation.nextRunAt else {
                    return false
                }
                return nextRunAt <= now
            }
            .sorted { lhs, rhs in
                (lhs.nextRunAt ?? .distantFuture) < (rhs.nextRunAt ?? .distantFuture)
            }
    }

    func nextRunDate(for automation: AppAutomation, after referenceDate: Date = Date()) -> Date? {
        let rule = RRule(rawValue: automation.rrule)
        let anchor = automation.lastRunAt ?? automation.createdAt
        return nextRunDate(rule: rule, anchor: anchor, after: referenceDate)
    }

    func preview(
        for rrule: String,
        createdAt: Date = Date(),
        lastRunAt: Date? = nil,
        after referenceDate: Date = Date()
    ) -> AutomationSchedulePreview {
        let trimmedRRule = rrule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRRule.isEmpty else {
            return AutomationSchedulePreview(
                isValid: false,
                message: "Enter an RRULE schedule.",
                nextRunAt: nil
            )
        }

        let rule = RRule(rawValue: trimmedRRule)
        guard !rule.frequency.isEmpty else {
            return AutomationSchedulePreview(
                isValid: false,
                message: "Add FREQ=DAILY or FREQ=WEEKLY.",
                nextRunAt: nil
            )
        }

        guard ["DAILY", "WEEKLY"].contains(rule.frequency) else {
            return AutomationSchedulePreview(
                isValid: false,
                message: "Only DAILY and WEEKLY schedules are supported.",
                nextRunAt: nil
            )
        }

        guard rule.hasValidInterval else {
            return AutomationSchedulePreview(
                isValid: false,
                message: "INTERVAL must be a positive whole number.",
                nextRunAt: nil
            )
        }

        if rule.frequency == "WEEKLY", !rule.invalidWeekdayTokens.isEmpty {
            return AutomationSchedulePreview(
                isValid: false,
                message: "BYDAY supports SU, MO, TU, WE, TH, FR, and SA.",
                nextRunAt: nil
            )
        }

        guard let nextRunAt = nextRunDate(rule: rule, anchor: lastRunAt ?? createdAt, after: referenceDate) else {
            return AutomationSchedulePreview(
                isValid: false,
                message: "No future run could be calculated.",
                nextRunAt: nil
            )
        }

        return AutomationSchedulePreview(
            isValid: true,
            message: "Next run available.",
            nextRunAt: nextRunAt
        )
    }

    private func nextRunDate(rule: RRule, anchor: Date, after referenceDate: Date) -> Date? {
        switch rule.frequency {
        case "DAILY":
            return nextDailyRun(anchor: anchor, after: referenceDate, interval: rule.interval)
        case "WEEKLY":
            return nextWeeklyRun(
                anchor: anchor,
                after: referenceDate,
                interval: rule.interval,
                weekdays: rule.weekdays(in: calendar)
            )
        default:
            return nil
        }
    }

    private func nextDailyRun(anchor: Date, after referenceDate: Date, interval: Int) -> Date? {
        var candidate = anchor
        while candidate <= referenceDate {
            guard let next = calendar.date(byAdding: .day, value: interval, to: candidate) else {
                return nil
            }
            candidate = next
        }
        return candidate
    }

    private func nextWeeklyRun(
        anchor: Date,
        after referenceDate: Date,
        interval: Int,
        weekdays: Set<Int>
    ) -> Date? {
        let anchorWeekdays = weekdays.isEmpty ? [calendar.component(.weekday, from: anchor)] : Array(weekdays)
        guard let anchorWeekStart = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start else {
            return nil
        }
        let anchorTime = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: anchor)
        let searchStart = min(anchor, referenceDate)
        let searchStartDay = calendar.startOfDay(for: searchStart)

        for dayOffset in 0..<(366 * 5) {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: searchStartDay) else {
                return nil
            }
            guard day >= calendar.startOfDay(for: anchor),
                  anchorWeekdays.contains(calendar.component(.weekday, from: day)),
                  let candidateWeekStart = calendar.dateInterval(of: .weekOfYear, for: day)?.start else {
                continue
            }
            let weekDelta = calendar.dateComponents([.weekOfYear], from: anchorWeekStart, to: candidateWeekStart).weekOfYear ?? 0
            guard weekDelta >= 0, weekDelta.isMultiple(of: interval) else {
                continue
            }
            guard let candidate = date(on: day, withTimeFrom: anchorTime),
                  candidate > referenceDate,
                  candidate >= anchor else {
                continue
            }
            return candidate
        }
        return nil
    }

    private func date(on day: Date, withTimeFrom time: DateComponents) -> Date? {
        var dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        dayComponents.hour = time.hour
        dayComponents.minute = time.minute
        dayComponents.second = time.second
        dayComponents.nanosecond = time.nanosecond
        return calendar.date(from: dayComponents)
    }
}

private struct RRule {
    private var values: [String: String]

    init(rawValue: String) {
        values = rawValue
            .split(separator: ";")
            .reduce(into: [String: String]()) { result, part in
                let keyValue = part.split(separator: "=", maxSplits: 1)
                guard keyValue.count == 2 else {
                    return
                }
                let key = keyValue[0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let value = keyValue[1].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard !key.isEmpty, !value.isEmpty else {
                    return
                }
                result[key] = value
            }
    }

    var frequency: String {
        values["FREQ"] ?? ""
    }

    var interval: Int {
        max(Int(values["INTERVAL"] ?? "") ?? 1, 1)
    }

    var hasValidInterval: Bool {
        guard let rawInterval = values["INTERVAL"] else {
            return true
        }
        guard let interval = Int(rawInterval) else {
            return false
        }
        return interval > 0
    }

    var invalidWeekdayTokens: [String] {
        guard let byDay = values["BYDAY"] else {
            return []
        }
        return byDay
            .split(separator: ",")
            .map(String.init)
            .filter { Self.weekday($0) == nil }
    }

    func weekdays(in calendar: Calendar) -> Set<Int> {
        guard let byDay = values["BYDAY"] else {
            return []
        }
        return Set(
            byDay
                .split(separator: ",")
                .compactMap { Self.weekday(String($0), in: calendar) }
        )
    }

    private static func weekday(_ value: String, in calendar: Calendar) -> Int? {
        guard let index = weekday(value) else {
            return nil
        }
        return index + 1
    }

    private static func weekday(_ value: String) -> Int? {
        let symbols = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
        return symbols.firstIndex(of: value)
    }
}
