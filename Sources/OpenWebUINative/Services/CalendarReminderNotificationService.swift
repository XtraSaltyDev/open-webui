import Foundation
import UserNotifications

struct CalendarReminderNotificationRequest: Equatable, Sendable {
    var id: String
    var eventID: String
    var calendarID: String
    var title: String
    var body: String
    var deliveryDate: Date
}

protocol CalendarReminderDelivering {
    func deliver(_ requests: [CalendarReminderNotificationRequest]) async throws
}

struct CalendarReminderNotificationService {
    func requests(
        for reminders: [AppCalendarReminder],
        calendars: [AppCalendar]
    ) -> [CalendarReminderNotificationRequest] {
        let calendarNamesByID = Dictionary(uniqueKeysWithValues: calendars.map { ($0.id, $0.name) })

        return reminders.map { reminder in
            let event = reminder.event
            let calendarName = calendarNamesByID[event.calendarID]
            return CalendarReminderNotificationRequest(
                id: "calendar-reminder-\(reminder.id)",
                eventID: event.id,
                calendarID: event.calendarID,
                title: event.title,
                body: body(for: event, calendarName: calendarName),
                deliveryDate: reminder.reminderAt
            )
        }
    }

    private func body(for event: AppCalendarEvent, calendarName: String?) -> String {
        var parts: [String] = []

        if let calendarName, !calendarName.isEmpty {
            parts.append(calendarName)
        }

        if let reminderMinutesBefore = event.reminderMinutesBefore {
            parts.append("\(reminderMinutesBefore) min before")
        }

        if let location = event.location, !location.isEmpty {
            parts.append(location)
        }

        if let description = event.description, !description.isEmpty {
            parts.append(description)
        }

        return parts.joined(separator: " • ")
    }
}

final class UserNotificationCalendarReminderDeliverer: CalendarReminderDelivering {
    private let centerProvider: () -> UNUserNotificationCenter

    init(centerProvider: @escaping () -> UNUserNotificationCenter = { .current() }) {
        self.centerProvider = centerProvider
    }

    func deliver(_ requests: [CalendarReminderNotificationRequest]) async throws {
        guard !requests.isEmpty else {
            return
        }

        let center = centerProvider()
        let isAuthorized = try await center.requestAuthorization(options: [.alert, .sound])
        guard isAuthorized else {
            return
        }

        for request in requests {
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default

            let secondsUntilDelivery = max(1, request.deliveryDate.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: secondsUntilDelivery,
                repeats: false
            )
            let notificationRequest = UNNotificationRequest(
                identifier: request.id,
                content: content,
                trigger: trigger
            )

            try await center.add(notificationRequest)
        }
    }
}
