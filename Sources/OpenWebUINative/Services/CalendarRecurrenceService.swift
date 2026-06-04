import Foundation

struct CalendarRecurrenceService: Sendable {
    var calendar: Calendar

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    func occurrences(
        of events: [AppCalendarEvent],
        in range: ClosedRange<Date>,
        calendarIDs: Set<String>? = nil
    ) -> [AppCalendarEvent] {
        events
            .filter { event in
                guard let calendarIDs else {
                    return true
                }
                return calendarIDs.contains(event.calendarID)
            }
            .flatMap { occurrences(of: $0, in: range) }
            .sorted { $0.startAt < $1.startAt }
    }

    private func occurrences(of event: AppCalendarEvent, in range: ClosedRange<Date>) -> [AppCalendarEvent] {
        guard let rawRule = event.rrule?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawRule.isEmpty else {
            return eventOverlaps(event, range: range) ? [event] : []
        }

        let rule = CalendarRRule(rawValue: rawRule)
        switch rule.frequency {
        case "DAILY":
            return dailyOccurrences(of: event, rule: rule, in: range)
        case "WEEKLY":
            return weeklyOccurrences(of: event, rule: rule, in: range)
        case "MONTHLY":
            return monthlyOccurrences(of: event, rule: rule, in: range)
        case "YEARLY" where rule.hasSupportedYearlyComponents:
            return yearlyOccurrences(of: event, rule: rule, in: range)
        default:
            return eventOverlaps(event, range: range) ? [event] : []
        }
    }

    private func dailyOccurrences(
        of event: AppCalendarEvent,
        rule: CalendarRRule,
        in range: ClosedRange<Date>
    ) -> [AppCalendarEvent] {
        guard rule.hasValidInterval,
              let recurrenceLimit = rule.recurrenceLimit(in: calendar) else {
            return eventOverlaps(event, range: range) ? [event] : []
        }

        var result: [AppCalendarEvent] = []
        var limit = recurrenceLimit
        var candidateStart = event.startAt
        while candidateStart <= range.upperBound {
            guard limit.consume(candidateStart) else {
                break
            }

            let occurrence = occurrence(from: event, startAt: candidateStart)
            if eventOverlaps(occurrence, range: range) {
                result.append(occurrence)
            }
            guard let nextStart = calendar.date(byAdding: .day, value: rule.interval, to: candidateStart) else {
                return result
            }
            candidateStart = nextStart
        }
        return result
    }

    private func monthlyOccurrences(
        of event: AppCalendarEvent,
        rule: CalendarRRule,
        in range: ClosedRange<Date>
    ) -> [AppCalendarEvent] {
        guard rule.hasValidInterval,
              rule.hasValidMonthDays,
              let recurrenceLimit = rule.recurrenceLimit(in: calendar) else {
            return eventOverlaps(event, range: range) ? [event] : []
        }

        let sourceMonthDay = calendar.component(.day, from: event.startAt)
        let monthDays = rule.monthDays.isEmpty ? [sourceMonthDay] : rule.monthDays.sorted()
        let anchorComponents = calendar.dateComponents([.year, .month], from: event.startAt)
        let anchorTime = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: event.startAt)
        guard let anchorMonthStart = calendar.date(from: anchorComponents) else {
            return eventOverlaps(event, range: range) ? [event] : []
        }

        var result: [AppCalendarEvent] = []
        var limit = recurrenceLimit
        var monthStart = anchorMonthStart

        while monthStart <= range.upperBound {
            defer {
                monthStart = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? range.upperBound.addingTimeInterval(1)
            }

            let monthDelta = calendar.dateComponents([.month], from: anchorMonthStart, to: monthStart).month ?? 0
            guard monthDelta >= 0, monthDelta.isMultiple(of: rule.interval) else {
                continue
            }

            for monthDay in monthDays {
                guard let candidateStart = date(inMonthStartingAt: monthStart, day: monthDay, withTimeFrom: anchorTime),
                      candidateStart >= event.startAt else {
                    continue
                }
                guard limit.consume(candidateStart) else {
                    return result.sorted { $0.startAt < $1.startAt }
                }

                let occurrence = occurrence(from: event, startAt: candidateStart)
                if eventOverlaps(occurrence, range: range) {
                    result.append(occurrence)
                }
            }
        }

        return result.sorted { $0.startAt < $1.startAt }
    }

    private func yearlyOccurrences(
        of event: AppCalendarEvent,
        rule: CalendarRRule,
        in range: ClosedRange<Date>
    ) -> [AppCalendarEvent] {
        guard rule.hasValidInterval,
              rule.hasValidMonths,
              let recurrenceLimit = rule.recurrenceLimit(in: calendar) else {
            return eventOverlaps(event, range: range) ? [event] : []
        }

        let sourceMonth = calendar.component(.month, from: event.startAt)
        let sourceDay = calendar.component(.day, from: event.startAt)
        let months = rule.months.isEmpty ? [sourceMonth] : rule.months.sorted()
        let anchorYear = calendar.component(.year, from: event.startAt)
        let upperYearBound = calendar.component(.year, from: range.upperBound)
        let anchorTime = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: event.startAt)

        var result: [AppCalendarEvent] = []
        var limit = recurrenceLimit
        var year = anchorYear

        while year <= upperYearBound {
            for month in months {
                guard let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                      let candidateStart = date(inMonthStartingAt: monthStart, day: sourceDay, withTimeFrom: anchorTime),
                      candidateStart >= event.startAt else {
                    continue
                }

                guard limit.consume(candidateStart) else {
                    return result.sorted { $0.startAt < $1.startAt }
                }

                let occurrence = occurrence(from: event, startAt: candidateStart)
                if eventOverlaps(occurrence, range: range) {
                    result.append(occurrence)
                }
            }

            year += rule.interval
        }

        return result.sorted { $0.startAt < $1.startAt }
    }

    private func weeklyOccurrences(
        of event: AppCalendarEvent,
        rule: CalendarRRule,
        in range: ClosedRange<Date>
    ) -> [AppCalendarEvent] {
        guard rule.hasValidInterval,
              rule.invalidWeekdayTokens.isEmpty,
              let recurrenceLimit = rule.recurrenceLimit(in: calendar) else {
            return eventOverlaps(event, range: range) ? [event] : []
        }
        guard let anchorWeekStart = calendar.dateInterval(of: .weekOfYear, for: event.startAt)?.start else {
            return eventOverlaps(event, range: range) ? [event] : []
        }

        let weekdays = rule.weekdays(in: calendar)
        let targetWeekdays = weekdays.isEmpty ? [calendar.component(.weekday, from: event.startAt)] : Array(weekdays)
        let anchorTime = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: event.startAt)
        var result: [AppCalendarEvent] = []
        var limit = recurrenceLimit
        var day = calendar.startOfDay(for: event.startAt)

        while day <= range.upperBound {
            defer {
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? range.upperBound.addingTimeInterval(1)
            }

            guard targetWeekdays.contains(calendar.component(.weekday, from: day)),
                  let candidateWeekStart = calendar.dateInterval(of: .weekOfYear, for: day)?.start else {
                continue
            }

            let weekDelta = calendar.dateComponents([.weekOfYear], from: anchorWeekStart, to: candidateWeekStart).weekOfYear ?? 0
            guard weekDelta >= 0, weekDelta.isMultiple(of: rule.interval),
                  let candidateStart = date(on: day, withTimeFrom: anchorTime),
                  candidateStart >= event.startAt else {
                continue
            }

            guard limit.consume(candidateStart) else {
                break
            }

            let occurrence = occurrence(from: event, startAt: candidateStart)
            if eventOverlaps(occurrence, range: range) {
                result.append(occurrence)
            }
        }

        return result
    }

    private func occurrence(from event: AppCalendarEvent, startAt: Date) -> AppCalendarEvent {
        var occurrence = event
        occurrence.startAt = startAt
        if let endAt = event.endAt {
            occurrence.endAt = startAt.addingTimeInterval(endAt.timeIntervalSince(event.startAt))
        }
        return occurrence
    }

    private func eventOverlaps(_ event: AppCalendarEvent, range: ClosedRange<Date>) -> Bool {
        let eventEnd = event.endAt ?? event.startAt
        return event.startAt <= range.upperBound && eventEnd >= range.lowerBound
    }

    private func date(on day: Date, withTimeFrom time: DateComponents) -> Date? {
        var dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        dayComponents.hour = time.hour
        dayComponents.minute = time.minute
        dayComponents.second = time.second
        dayComponents.nanosecond = time.nanosecond
        return calendar.date(from: dayComponents)
    }

    private func date(inMonthStartingAt monthStart: Date, day: Int, withTimeFrom time: DateComponents) -> Date? {
        guard day > 0,
              let range = calendar.range(of: .day, in: .month, for: monthStart),
              range.contains(day) else {
            return nil
        }

        var components = calendar.dateComponents([.year, .month], from: monthStart)
        components.day = day
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        components.nanosecond = time.nanosecond
        return calendar.date(from: components)
    }
}

private struct CalendarRRule {
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

    var monthDays: [Int] {
        guard let byMonthDay = values["BYMONTHDAY"] else {
            return []
        }
        return byMonthDay
            .split(separator: ",")
            .compactMap { Int($0) }
            .filter { $0 > 0 }
    }

    var hasValidMonthDays: Bool {
        guard let byMonthDay = values["BYMONTHDAY"] else {
            return true
        }
        let tokens = byMonthDay.split(separator: ",")
        guard !tokens.isEmpty else {
            return false
        }
        return tokens.allSatisfy { token in
            guard let value = Int(token) else {
                return false
            }
            return value > 0
        }
    }

    var months: [Int] {
        guard let byMonth = values["BYMONTH"] else {
            return []
        }
        return Array(
            Set(
                byMonth
                    .split(separator: ",")
                    .compactMap { Int($0) }
                    .filter { (1...12).contains($0) }
            )
        )
        .sorted()
    }

    var hasValidMonths: Bool {
        guard let byMonth = values["BYMONTH"] else {
            return true
        }
        let tokens = byMonth.split(separator: ",")
        guard !tokens.isEmpty else {
            return false
        }
        return tokens.allSatisfy { token in
            guard let value = Int(token) else {
                return false
            }
            return (1...12).contains(value)
        }
    }

    var hasSupportedYearlyComponents: Bool {
        let supportedKeys: Set<String> = ["FREQ", "INTERVAL", "COUNT", "UNTIL", "BYMONTH"]
        return values.keys.allSatisfy { supportedKeys.contains($0) }
    }

    func recurrenceLimit(in calendar: Calendar) -> CalendarRecurrenceLimit? {
        guard hasValidCount, hasValidUntil(in: calendar) else {
            return nil
        }
        return CalendarRecurrenceLimit(count: count, until: untilDate(in: calendar))
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

    private var count: Int? {
        guard let rawCount = values["COUNT"] else {
            return nil
        }
        return Int(rawCount)
    }

    private var hasValidCount: Bool {
        guard let rawCount = values["COUNT"] else {
            return true
        }
        guard let count = Int(rawCount) else {
            return false
        }
        return count > 0
    }

    private func untilDate(in calendar: Calendar) -> Date? {
        guard let rawUntil = values["UNTIL"] else {
            return nil
        }
        return Self.parseUntil(rawUntil, in: calendar)
    }

    private func hasValidUntil(in calendar: Calendar) -> Bool {
        guard let rawUntil = values["UNTIL"] else {
            return true
        }
        return Self.parseUntil(rawUntil, in: calendar) != nil
    }

    private static func parseUntil(_ rawValue: String, in calendar: Calendar) -> Date? {
        let usesUTC = rawValue.hasSuffix("Z")
        let trimmedValue = usesUTC ? String(rawValue.dropLast()) : rawValue

        if trimmedValue.count == 8 {
            guard let components = dateComponents(from: trimmedValue) else {
                return nil
            }
            var parseCalendar = calendar
            if usesUTC {
                parseCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
            }
            guard let startOfDay = parseCalendar.date(from: components),
                  let startOfNextDay = parseCalendar.date(byAdding: .day, value: 1, to: startOfDay) else {
                return nil
            }
            return startOfNextDay.addingTimeInterval(-0.001)
        }

        guard trimmedValue.count == 15,
              trimmedValue[trimmedValue.index(trimmedValue.startIndex, offsetBy: 8)] == "T",
              var components = dateComponents(from: String(trimmedValue.prefix(8))) else {
            return nil
        }

        let timeValue = String(trimmedValue.suffix(6))
        guard let hour = integer(in: timeValue, from: 0, length: 2),
              let minute = integer(in: timeValue, from: 2, length: 2),
              let second = integer(in: timeValue, from: 4, length: 2) else {
            return nil
        }

        components.hour = hour
        components.minute = minute
        components.second = second

        var parseCalendar = calendar
        if usesUTC {
            parseCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        }
        return parseCalendar.date(from: components)
    }

    private static func dateComponents(from value: String) -> DateComponents? {
        guard let year = integer(in: value, from: 0, length: 4),
              let month = integer(in: value, from: 4, length: 2),
              let day = integer(in: value, from: 6, length: 2) else {
            return nil
        }
        return DateComponents(year: year, month: month, day: day)
    }

    private static func integer(in value: String, from offset: Int, length: Int) -> Int? {
        guard value.count >= offset + length else {
            return nil
        }
        let start = value.index(value.startIndex, offsetBy: offset)
        let end = value.index(start, offsetBy: length)
        return Int(value[start..<end])
    }
}

private struct CalendarRecurrenceLimit {
    var count: Int?
    var until: Date?
    private var generatedCount = 0

    init(count: Int?, until: Date?) {
        self.count = count
        self.until = until
    }

    mutating func consume(_ startAt: Date) -> Bool {
        if let count, generatedCount >= count {
            return false
        }
        if let until, startAt > until {
            return false
        }

        generatedCount += 1
        return true
    }
}
