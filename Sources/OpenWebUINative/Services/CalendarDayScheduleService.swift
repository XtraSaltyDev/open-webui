import Foundation

struct CalendarDayHourSlot {
    var hour: Int
    var startAt: Date
    var events: [AppCalendarEvent]
}

struct CalendarDaySchedule {
    var calendar: Calendar
    var dayStart: Date
    var allDayEvents: [AppCalendarEvent]
    var hourSlots: [CalendarDayHourSlot]
}

struct CalendarDayScheduleService {
    var calendar: Calendar

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    func daySchedule(
        containing date: Date,
        events: [AppCalendarEvent],
        calendarIDs: Set<String>? = nil
    ) -> CalendarDaySchedule {
        let dayStart = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let visibleEvents = CalendarRecurrenceService(calendar: calendar).occurrences(
            of: events,
            in: dayStart...nextDay,
            calendarIDs: calendarIDs
        )
            .filter { eventOverlaps($0, start: dayStart, end: nextDay) }
            .sorted { $0.startAt < $1.startAt }
        let allDayEvents = visibleEvents.filter(\.allDay)
        let timedEvents = visibleEvents.filter { !$0.allDay }

        let hourSlots = (0..<24).compactMap { hour -> CalendarDayHourSlot? in
            guard let hourStart = calendar.date(byAdding: .hour, value: hour, to: dayStart) else {
                return nil
            }
            let nextHour = calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? hourStart
            let hourEvents = timedEvents.filter { eventOverlaps($0, start: hourStart, end: nextHour) }
            return CalendarDayHourSlot(hour: hour, startAt: hourStart, events: hourEvents)
        }

        return CalendarDaySchedule(
            calendar: calendar,
            dayStart: dayStart,
            allDayEvents: allDayEvents,
            hourSlots: hourSlots
        )
    }

    private func eventOverlaps(_ event: AppCalendarEvent, start: Date, end: Date) -> Bool {
        let eventStart = event.startAt
        let eventEnd = event.endAt ?? event.startAt
        return eventStart < end && eventEnd >= start
    }
}
