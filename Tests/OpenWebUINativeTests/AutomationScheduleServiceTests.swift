import XCTest
@testable import OpenWebUINative

final class AutomationScheduleServiceTests: XCTestCase {
    func testDailyScheduleUsesIntervalAndCreatedTime() throws {
        let service = AutomationScheduleService(calendar: Self.utcCalendar)
        let automation = AppAutomation(
            name: "Daily summary",
            prompt: "Summarize notes.",
            modelID: "llama3.2",
            rrule: "FREQ=DAILY;INTERVAL=2",
            createdAt: Self.date("2026-06-01T09:30:00Z"),
            updatedAt: Self.date("2026-06-01T09:30:00Z")
        )

        let nextRun = service.nextRunDate(
            for: automation,
            after: Self.date("2026-06-02T10:00:00Z")
        )

        XCTAssertEqual(nextRun, Self.date("2026-06-03T09:30:00Z"))
    }

    func testWeeklyScheduleUsesByDayAndInterval() throws {
        let service = AutomationScheduleService(calendar: Self.utcCalendar)
        let automation = AppAutomation(
            name: "Research brief",
            prompt: "Prepare a brief.",
            modelID: "llama3.2",
            rrule: "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE",
            createdAt: Self.date("2026-06-01T08:15:00Z"),
            updatedAt: Self.date("2026-06-01T08:15:00Z")
        )

        let nextRun = service.nextRunDate(
            for: automation,
            after: Self.date("2026-06-03T09:00:00Z")
        )

        XCTAssertEqual(nextRun, Self.date("2026-06-15T08:15:00Z"))
    }

    func testPreviewReturnsNextRunForSupportedDailyRule() throws {
        let service = AutomationScheduleService(calendar: Self.utcCalendar)

        let preview = service.preview(
            for: "FREQ=DAILY;INTERVAL=2",
            createdAt: Self.date("2026-06-01T09:30:00Z"),
            after: Self.date("2026-06-02T10:00:00Z")
        )

        XCTAssertTrue(preview.isValid)
        XCTAssertEqual(preview.message, "Next run available.")
        XCTAssertEqual(preview.nextRunAt, Self.date("2026-06-03T09:30:00Z"))
    }

    func testPreviewRejectsUnsupportedFrequencyBeforeSaving() throws {
        let service = AutomationScheduleService(calendar: Self.utcCalendar)

        let preview = service.preview(
            for: "FREQ=MONTHLY;BYMONTHDAY=1",
            createdAt: Self.date("2026-06-01T09:30:00Z"),
            after: Self.date("2026-06-02T10:00:00Z")
        )

        XCTAssertFalse(preview.isValid)
        XCTAssertEqual(preview.message, "Only DAILY and WEEKLY schedules are supported.")
        XCTAssertNil(preview.nextRunAt)
    }

    func testPreviewRejectsInvalidWeeklyByDayTokens() throws {
        let service = AutomationScheduleService(calendar: Self.utcCalendar)

        let preview = service.preview(
            for: "FREQ=WEEKLY;BYDAY=MO,XX",
            createdAt: Self.date("2026-06-01T09:30:00Z"),
            after: Self.date("2026-06-02T10:00:00Z")
        )

        XCTAssertFalse(preview.isValid)
        XCTAssertEqual(preview.message, "BYDAY supports SU, MO, TU, WE, TH, FR, and SA.")
        XCTAssertNil(preview.nextRunAt)
    }

    func testDueAutomationsOnlyReturnsActivePastDueItemsSortedByNextRun() throws {
        let service = AutomationScheduleService(calendar: Self.utcCalendar)
        let now = Self.date("2026-06-02T12:00:00Z")
        let olderDue = AppAutomation(
            id: "older",
            name: "Older due",
            prompt: "Run first.",
            modelID: "llama3.2",
            rrule: "FREQ=DAILY",
            nextRunAt: Self.date("2026-06-02T08:00:00Z")
        )
        let newerDue = AppAutomation(
            id: "newer",
            name: "Newer due",
            prompt: "Run second.",
            modelID: "llama3.2",
            rrule: "FREQ=DAILY",
            nextRunAt: Self.date("2026-06-02T10:00:00Z")
        )
        let inactiveDue = AppAutomation(
            id: "inactive",
            name: "Paused",
            prompt: "Skip.",
            modelID: "llama3.2",
            rrule: "FREQ=DAILY",
            isActive: false,
            nextRunAt: Self.date("2026-06-02T07:00:00Z")
        )
        let future = AppAutomation(
            id: "future",
            name: "Future",
            prompt: "Skip.",
            modelID: "llama3.2",
            rrule: "FREQ=DAILY",
            nextRunAt: Self.date("2026-06-02T13:00:00Z")
        )

        let dueIDs = service.dueAutomations(
            [future, newerDue, inactiveDue, olderDue],
            at: now
        ).map(\.id)

        XCTAssertEqual(dueIDs, ["older", "newer"])
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
