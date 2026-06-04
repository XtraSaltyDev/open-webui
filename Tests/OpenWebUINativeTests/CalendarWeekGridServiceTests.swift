import XCTest
@testable import OpenWebUINative

final class CalendarWeekGridServiceTests: XCTestCase {
    func testWeekGridBuildsSevenDaysStartingOnFirstWeekday() {
        let calendar = Calendar.gregorianUTC(firstWeekday: 1)
        let service = CalendarWeekGridService(calendar: calendar)
        let weekDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 3))!

        let grid = service.weekGrid(containing: weekDate, events: [])

        XCTAssertEqual(grid.days.count, 7)
        XCTAssertEqual(grid.weekStart, calendar.date(from: DateComponents(year: 2026, month: 5, day: 31)))
        XCTAssertEqual(grid.days.first?.date, calendar.date(from: DateComponents(year: 2026, month: 5, day: 31)))
        XCTAssertEqual(grid.days.last?.date, calendar.date(from: DateComponents(year: 2026, month: 6, day: 6)))
    }

    func testWeekGridRespectsMondayFirstCalendar() {
        let calendar = Calendar.gregorianUTC(firstWeekday: 2)
        let service = CalendarWeekGridService(calendar: calendar)
        let weekDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 3))!

        let grid = service.weekGrid(containing: weekDate, events: [])

        XCTAssertEqual(grid.weekStart, calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        XCTAssertEqual(grid.days.map { calendar.component(.weekday, from: $0.date) }, [2, 3, 4, 5, 6, 7, 1])
    }

    func testWeekGridBucketsSingleAndMultiDayEventsByDayOverlap() {
        let calendar = Calendar.gregorianUTC(firstWeekday: 1)
        let service = CalendarWeekGridService(calendar: calendar)
        let weekDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 3))!
        let teamCalendarID = "team"
        let personalCalendarID = "personal"
        let designReview = AppCalendarEvent(
            calendarID: teamCalendarID,
            title: "Design review",
            startAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 2, hour: 10))!,
            endAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 2, hour: 11))!
        )
        let retreat = AppCalendarEvent(
            calendarID: teamCalendarID,
            title: "Retreat",
            startAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 9))!,
            endAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 17))!
        )
        let personalErrand = AppCalendarEvent(
            calendarID: personalCalendarID,
            title: "Errand",
            startAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 12))!,
            endAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 13))!
        )

        let grid = service.weekGrid(
            containing: weekDate,
            events: [retreat, personalErrand, designReview],
            calendarIDs: [teamCalendarID]
        )

        XCTAssertEqual(grid.events(onYear: 2026, month: 6, day: 2).map(\.title), ["Design review"])
        XCTAssertEqual(grid.events(onYear: 2026, month: 6, day: 3).map(\.title), ["Retreat"])
        XCTAssertEqual(grid.events(onYear: 2026, month: 6, day: 4).map(\.title), ["Retreat"])
        XCTAssertEqual(grid.events(onYear: 2026, month: 6, day: 5).map(\.title), ["Retreat"])
        XCTAssertTrue(grid.events(onYear: 2026, month: 6, day: 6).isEmpty)
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

private extension CalendarWeekGrid {
    func events(onYear year: Int, month: Int, day: Int) -> [AppCalendarEvent] {
        days.first { gridDay in
            let components = calendar.dateComponents([.year, .month, .day], from: gridDay.date)
            return components.year == year && components.month == month && components.day == day
        }?.events ?? []
    }
}
