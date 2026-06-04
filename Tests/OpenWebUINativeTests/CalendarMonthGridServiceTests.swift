import XCTest
@testable import OpenWebUINative

final class CalendarMonthGridServiceTests: XCTestCase {
    func testMonthGridBuildsSixWeeksStartingOnFirstWeekday() {
        let calendar = Calendar.gregorianUTC(firstWeekday: 1)
        let service = CalendarMonthGridService(calendar: calendar)
        let month = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!

        let grid = service.monthGrid(containing: month, events: [])

        XCTAssertEqual(grid.days.count, 42)
        XCTAssertEqual(grid.displayedMonthStart, calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        XCTAssertEqual(grid.days.first?.date, calendar.date(from: DateComponents(year: 2026, month: 5, day: 31)))
        XCTAssertEqual(grid.days.last?.date, calendar.date(from: DateComponents(year: 2026, month: 7, day: 11)))
        XCTAssertFalse(grid.days.first?.isInDisplayedMonth ?? true)
        XCTAssertTrue(grid.days.contains { day in
            day.date == calendar.date(from: DateComponents(year: 2026, month: 6, day: 30))
                && day.isInDisplayedMonth
        })
    }

    func testMonthGridBucketsSingleAndMultiDayEventsByDayOverlap() {
        let calendar = Calendar.gregorianUTC(firstWeekday: 1)
        let service = CalendarMonthGridService(calendar: calendar)
        let month = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let calendarID = "team"
        let designReview = AppCalendarEvent(
            calendarID: calendarID,
            title: "Design review",
            startAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 2, hour: 10))!,
            endAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 2, hour: 11))!
        )
        let retreat = AppCalendarEvent(
            calendarID: calendarID,
            title: "Retreat",
            startAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 9))!,
            endAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 17))!
        )

        let grid = service.monthGrid(
            containing: month,
            events: [retreat, designReview],
            calendarIDs: [calendarID]
        )

        XCTAssertEqual(grid.events(onYear: 2026, month: 6, day: 2).map(\.title), ["Design review"])
        XCTAssertEqual(grid.events(onYear: 2026, month: 6, day: 3).map(\.title), ["Retreat"])
        XCTAssertEqual(grid.events(onYear: 2026, month: 6, day: 4).map(\.title), ["Retreat"])
        XCTAssertEqual(grid.events(onYear: 2026, month: 6, day: 5).map(\.title), ["Retreat"])
        XCTAssertTrue(grid.events(onYear: 2026, month: 6, day: 6).isEmpty)
    }

    func testMonthGridBucketsRecurringWeeklyOccurrences() {
        let calendar = Calendar.gregorianUTC(firstWeekday: 2)
        let service = CalendarMonthGridService(calendar: calendar)
        let month = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let officeHours = AppCalendarEvent(
            calendarID: "team",
            title: "Office hours",
            startAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 14))!,
            endAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 15))!,
            rrule: "FREQ=WEEKLY;BYDAY=MO,WE"
        )

        let grid = service.monthGrid(containing: month, events: [officeHours])

        XCTAssertEqual(grid.events(onYear: 2026, month: 6, day: 1).map(\.title), ["Office hours"])
        XCTAssertEqual(grid.events(onYear: 2026, month: 6, day: 3).map(\.title), ["Office hours"])
        XCTAssertEqual(grid.events(onYear: 2026, month: 6, day: 8).map(\.title), ["Office hours"])
        XCTAssertTrue(grid.events(onYear: 2026, month: 6, day: 2).isEmpty)
    }

    func testMonthGridBucketsRecurringMonthlyOccurrences() {
        let calendar = Calendar.gregorianUTC(firstWeekday: 2)
        let service = CalendarMonthGridService(calendar: calendar)
        let month = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))!
        let billingReview = AppCalendarEvent(
            calendarID: "team",
            title: "Billing review",
            startAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!,
            endAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10))!,
            rrule: "FREQ=MONTHLY;BYMONTHDAY=1"
        )

        let grid = service.monthGrid(containing: month, events: [billingReview])

        XCTAssertEqual(grid.events(onYear: 2026, month: 7, day: 1).map(\.title), ["Billing review"])
        XCTAssertTrue(grid.events(onYear: 2026, month: 7, day: 2).isEmpty)
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

private extension CalendarMonthGrid {
    func events(onYear year: Int, month: Int, day: Int) -> [AppCalendarEvent] {
        days.first { gridDay in
            let components = calendar.dateComponents([.year, .month, .day], from: gridDay.date)
            return components.year == year && components.month == month && components.day == day
        }?.events ?? []
    }
}
