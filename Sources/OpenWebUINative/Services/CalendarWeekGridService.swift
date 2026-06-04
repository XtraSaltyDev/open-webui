import Foundation

struct CalendarWeekGridDay {
    var date: Date
    var events: [AppCalendarEvent]
}

struct CalendarWeekGrid {
    var calendar: Calendar
    var weekStart: Date
    var days: [CalendarWeekGridDay]
}

struct CalendarWeekGridService {
    var calendar: Calendar

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    func weekGrid(
        containing date: Date,
        events: [AppCalendarEvent],
        calendarIDs: Set<String>? = nil
    ) -> CalendarWeekGrid {
        let weekStart = weekStartDate(containing: date)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let visibleEvents = CalendarRecurrenceService(calendar: calendar).occurrences(
            of: events,
            in: weekStart...weekEnd,
            calendarIDs: calendarIDs
        )

        let days = (0..<7).compactMap { offset -> CalendarWeekGridDay? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else {
                return nil
            }
            let dayStart = calendar.startOfDay(for: day)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let dayEvents = visibleEvents
                .filter { eventOverlaps($0, dayStart: dayStart, nextDay: nextDay) }
                .sorted { $0.startAt < $1.startAt }
            return CalendarWeekGridDay(date: dayStart, events: dayEvents)
        }

        return CalendarWeekGrid(
            calendar: calendar,
            weekStart: weekStart,
            days: days
        )
    }

    private func weekStartDate(containing date: Date) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: dayStart)
        let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -leadingDays, to: dayStart) ?? dayStart
    }

    private func eventOverlaps(_ event: AppCalendarEvent, dayStart: Date, nextDay: Date) -> Bool {
        let eventStart = event.startAt
        let eventEnd = event.endAt ?? event.startAt
        return eventStart < nextDay && eventEnd >= dayStart
    }
}
