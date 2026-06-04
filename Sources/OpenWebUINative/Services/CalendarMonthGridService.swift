import Foundation

struct CalendarMonthGridDay {
    var date: Date
    var isInDisplayedMonth: Bool
    var events: [AppCalendarEvent]
}

struct CalendarMonthGrid {
    var calendar: Calendar
    var displayedMonthStart: Date
    var days: [CalendarMonthGridDay]
}

struct CalendarMonthGridService {
    var calendar: Calendar

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    func monthGrid(
        containing date: Date,
        events: [AppCalendarEvent],
        calendarIDs: Set<String>? = nil
    ) -> CalendarMonthGrid {
        let displayedMonthStart = monthStart(containing: date)
        let gridStart = gridStartDate(for: displayedMonthStart)
        let gridEnd = calendar.date(byAdding: .day, value: 42, to: gridStart) ?? gridStart
        let displayedMonth = calendar.component(.month, from: displayedMonthStart)
        let displayedYear = calendar.component(.year, from: displayedMonthStart)
        let visibleEvents = CalendarRecurrenceService(calendar: calendar).occurrences(
            of: events,
            in: gridStart...gridEnd,
            calendarIDs: calendarIDs
        )

        let days = (0..<42).compactMap { offset -> CalendarMonthGridDay? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }
            let dayStart = calendar.startOfDay(for: day)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let dayEvents = visibleEvents
                .filter { eventOverlaps($0, dayStart: dayStart, nextDay: nextDay) }
                .sorted { $0.startAt < $1.startAt }
            let components = calendar.dateComponents([.year, .month], from: dayStart)
            return CalendarMonthGridDay(
                date: dayStart,
                isInDisplayedMonth: components.year == displayedYear && components.month == displayedMonth,
                events: dayEvents
            )
        }

        return CalendarMonthGrid(
            calendar: calendar,
            displayedMonthStart: displayedMonthStart,
            days: days
        )
    }

    private func monthStart(containing date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components).map(calendar.startOfDay) ?? calendar.startOfDay(for: date)
    }

    private func gridStartDate(for displayedMonthStart: Date) -> Date {
        let weekday = calendar.component(.weekday, from: displayedMonthStart)
        let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -leadingDays, to: displayedMonthStart) ?? displayedMonthStart
    }

    private func eventOverlaps(_ event: AppCalendarEvent, dayStart: Date, nextDay: Date) -> Bool {
        let eventStart = event.startAt
        let eventEnd = event.endAt ?? event.startAt
        return eventStart < nextDay && eventEnd >= dayStart
    }
}
