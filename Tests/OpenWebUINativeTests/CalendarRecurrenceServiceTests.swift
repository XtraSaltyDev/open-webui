import XCTest
@testable import OpenWebUINative

final class CalendarRecurrenceServiceTests: XCTestCase {
    func testWeeklyRuleExpandsByDayOccurrencesInsideRange() {
        let calendar = Calendar.gregorianUTC(firstWeekday: 2)
        let service = CalendarRecurrenceService(calendar: calendar)
        let event = AppCalendarEvent(
            calendarID: "team",
            title: "Team sync",
            startAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!,
            endAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10))!,
            rrule: "FREQ=WEEKLY;BYDAY=MO,WE"
        )
        let rangeStart = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let rangeEnd = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8))!

        let occurrences = service.occurrences(of: [event], in: rangeStart...rangeEnd)

        XCTAssertEqual(
            occurrences.map(\.startAt),
            [
                calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!,
                calendar.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 9))!
            ]
        )
        XCTAssertEqual(
            occurrences.map(\.endAt),
            [
                calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10))!,
                calendar.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 10))!
            ]
        )
    }

    func testUnsupportedRuleFallsBackToOriginalEventOnly() {
        let calendar = Calendar.gregorianUTC(firstWeekday: 2)
        let service = CalendarRecurrenceService(calendar: calendar)
        let event = AppCalendarEvent(
            calendarID: "team",
            title: "Yearly sync",
            startAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!,
            endAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10))!,
            rrule: "FREQ=YEARLY;BYMONTH=7;COUNT=2"
        )
        let rangeStart = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let rangeEnd = calendar.date(from: DateComponents(year: 2026, month: 7, day: 3))!

        let occurrences = service.occurrences(of: [event], in: rangeStart...rangeEnd)

        XCTAssertEqual(occurrences.map(\.startAt), [event.startAt])
    }

    func testYearlyRuleExpandsByIntervalAndCountInsideRange() {
        let calendar = Calendar.gregorianUTC(firstWeekday: 2)
        let service = CalendarRecurrenceService(calendar: calendar)
        let event = AppCalendarEvent(
            calendarID: "team",
            title: "Annual planning",
            startAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!,
            endAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10))!,
            rrule: "FREQ=YEARLY;INTERVAL=2;COUNT=3"
        )
        let rangeStart = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let rangeEnd = calendar.date(from: DateComponents(year: 2031, month: 6, day: 1))!

        let occurrences = service.occurrences(of: [event], in: rangeStart...rangeEnd)

        XCTAssertEqual(
            occurrences.map(\.startAt),
            [
                calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!,
                calendar.date(from: DateComponents(year: 2028, month: 6, day: 1, hour: 9))!,
                calendar.date(from: DateComponents(year: 2030, month: 6, day: 1, hour: 9))!
            ]
        )
        XCTAssertEqual(
            occurrences.map(\.endAt),
            [
                calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10))!,
                calendar.date(from: DateComponents(year: 2028, month: 6, day: 1, hour: 10))!,
                calendar.date(from: DateComponents(year: 2030, month: 6, day: 1, hour: 10))!
            ]
        )
    }

    func testMonthlyRuleExpandsByMonthDayOccurrencesInsideRange() {
        let calendar = Calendar.gregorianUTC(firstWeekday: 2)
        let service = CalendarRecurrenceService(calendar: calendar)
        let event = AppCalendarEvent(
            calendarID: "team",
            title: "Billing review",
            startAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!,
            endAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10))!,
            rrule: "FREQ=MONTHLY;BYMONTHDAY=1"
        )
        let rangeStart = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let rangeEnd = calendar.date(from: DateComponents(year: 2026, month: 8, day: 2))!

        let occurrences = service.occurrences(of: [event], in: rangeStart...rangeEnd)

        XCTAssertEqual(
            occurrences.map(\.startAt),
            [
                calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!,
                calendar.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 9))!,
                calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 9))!
            ]
        )
        XCTAssertEqual(
            occurrences.map(\.endAt),
            [
                calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10))!,
                calendar.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 10))!,
                calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 10))!
            ]
        )
    }

    func testMonthlyRuleUsesStartDayWhenByMonthDayIsOmitted() {
        let calendar = Calendar.gregorianUTC(firstWeekday: 2)
        let service = CalendarRecurrenceService(calendar: calendar)
        let event = AppCalendarEvent(
            calendarID: "team",
            title: "Finance sync",
            startAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 11))!,
            endAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!,
            rrule: "FREQ=MONTHLY;INTERVAL=2"
        )
        let rangeStart = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let rangeEnd = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!

        let occurrences = service.occurrences(of: [event], in: rangeStart...rangeEnd)

        XCTAssertEqual(
            occurrences.map(\.startAt),
            [
                calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 11))!,
                calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 11))!,
                calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 11))!
            ]
        )
    }

    func testDailyRuleHonorsCountLimit() {
        let calendar = Calendar.gregorianUTC(firstWeekday: 2)
        let service = CalendarRecurrenceService(calendar: calendar)
        let event = AppCalendarEvent(
            calendarID: "team",
            title: "Standup",
            startAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!,
            endAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9, minute: 30))!,
            rrule: "FREQ=DAILY;COUNT=3"
        )
        let rangeStart = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let rangeEnd = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!

        let occurrences = service.occurrences(of: [event], in: rangeStart...rangeEnd)

        XCTAssertEqual(
            occurrences.map(\.startAt),
            [
                calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!,
                calendar.date(from: DateComponents(year: 2026, month: 6, day: 2, hour: 9))!,
                calendar.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 9))!
            ]
        )
    }

    func testWeeklyRuleHonorsCountLimitAcrossHiddenOccurrences() {
        let calendar = Calendar.gregorianUTC(firstWeekday: 2)
        let service = CalendarRecurrenceService(calendar: calendar)
        let event = AppCalendarEvent(
            calendarID: "team",
            title: "Review",
            startAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 14))!,
            endAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 15))!,
            rrule: "FREQ=WEEKLY;BYDAY=MO,WE;COUNT=3"
        )
        let rangeStart = calendar.date(from: DateComponents(year: 2026, month: 6, day: 3))!
        let rangeEnd = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!

        let occurrences = service.occurrences(of: [event], in: rangeStart...rangeEnd)

        XCTAssertEqual(
            occurrences.map(\.startAt),
            [
                calendar.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 14))!,
                calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 14))!
            ]
        )
    }

    func testDailyRuleHonorsUntilDateTimeLimit() {
        let calendar = Calendar.gregorianUTC(firstWeekday: 2)
        let service = CalendarRecurrenceService(calendar: calendar)
        let event = AppCalendarEvent(
            calendarID: "team",
            title: "Focus block",
            startAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!,
            endAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10))!,
            rrule: "FREQ=DAILY;UNTIL=20260603T090000Z"
        )
        let rangeStart = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let rangeEnd = calendar.date(from: DateComponents(year: 2026, month: 6, day: 5))!

        let occurrences = service.occurrences(of: [event], in: rangeStart...rangeEnd)

        XCTAssertEqual(
            occurrences.map(\.startAt),
            [
                calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!,
                calendar.date(from: DateComponents(year: 2026, month: 6, day: 2, hour: 9))!,
                calendar.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 9))!
            ]
        )
    }
}

private extension Calendar {
    static func gregorianUTC(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = firstWeekday
        return calendar
    }
}
