import XCTest
@testable import OpenWebUINative

final class CalendarDayScheduleServiceTests: XCTestCase {
    func testDayScheduleBuildsDayStartAndTwentyFourHourSlots() {
        let calendar = Calendar.gregorianUTC(firstWeekday: 1)
        let service = CalendarDayScheduleService(calendar: calendar)
        let day = calendar.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 14, minute: 30))!

        let schedule = service.daySchedule(containing: day, events: [])

        XCTAssertEqual(schedule.dayStart, calendar.date(from: DateComponents(year: 2026, month: 6, day: 3)))
        XCTAssertEqual(schedule.hourSlots.count, 24)
        XCTAssertEqual(schedule.hourSlots.first?.hour, 0)
        XCTAssertEqual(schedule.hourSlots.first?.startAt, calendar.date(from: DateComponents(year: 2026, month: 6, day: 3)))
        XCTAssertEqual(schedule.hourSlots.last?.hour, 23)
        XCTAssertEqual(schedule.hourSlots.last?.startAt, calendar.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 23)))
    }

    func testDayScheduleSeparatesAllDayEventsAndBucketsTimedEventsByHourOverlap() {
        let calendar = Calendar.gregorianUTC(firstWeekday: 1)
        let service = CalendarDayScheduleService(calendar: calendar)
        let day = calendar.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 12))!
        let teamCalendarID = "team"
        let personalCalendarID = "personal"
        let allDayLaunch = AppCalendarEvent(
            calendarID: teamCalendarID,
            title: "Launch day",
            startAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 3))!,
            endAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 23, minute: 59))!,
            allDay: true
        )
        let designReview = AppCalendarEvent(
            calendarID: teamCalendarID,
            title: "Design review",
            startAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 10, minute: 30))!,
            endAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 12, minute: 15))!
        )
        let personalErrand = AppCalendarEvent(
            calendarID: personalCalendarID,
            title: "Errand",
            startAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 11))!,
            endAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 12))!
        )

        let schedule = service.daySchedule(
            containing: day,
            events: [personalErrand, designReview, allDayLaunch],
            calendarIDs: [teamCalendarID]
        )

        XCTAssertEqual(schedule.allDayEvents.map(\.title), ["Launch day"])
        XCTAssertTrue(schedule.events(inHour: 9).isEmpty)
        XCTAssertEqual(schedule.events(inHour: 10).map(\.title), ["Design review"])
        XCTAssertEqual(schedule.events(inHour: 11).map(\.title), ["Design review"])
        XCTAssertEqual(schedule.events(inHour: 12).map(\.title), ["Design review"])
        XCTAssertTrue(schedule.events(inHour: 13).isEmpty)
    }

    func testDayScheduleIncludesOvernightEventsOnBothTouchedDays() {
        let calendar = Calendar.gregorianUTC(firstWeekday: 1)
        let service = CalendarDayScheduleService(calendar: calendar)
        let day = calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 9))!
        let incident = AppCalendarEvent(
            calendarID: "ops",
            title: "Overnight incident",
            startAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 23, minute: 30))!,
            endAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 1, minute: 15))!
        )

        let schedule = service.daySchedule(containing: day, events: [incident])

        XCTAssertEqual(schedule.events(inHour: 0).map(\.title), ["Overnight incident"])
        XCTAssertEqual(schedule.events(inHour: 1).map(\.title), ["Overnight incident"])
        XCTAssertTrue(schedule.events(inHour: 2).isEmpty)
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

private extension CalendarDaySchedule {
    func events(inHour hour: Int) -> [AppCalendarEvent] {
        hourSlots.first { $0.hour == hour }?.events ?? []
    }
}
