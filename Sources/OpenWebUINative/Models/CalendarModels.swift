import Foundation

struct AppCalendar: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var userID: String
    var name: String
    var color: String?
    var isDefault: Bool
    var isSystem: Bool
    var allowedUserIDs: [String]
    var allowedGroupIDs: [String]
    var data: JSONValue?
    var meta: JSONValue?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        userID: String = "local-user",
        name: String,
        color: String? = nil,
        isDefault: Bool = false,
        isSystem: Bool = false,
        allowedUserIDs: [String] = [],
        allowedGroupIDs: [String] = [],
        data: JSONValue? = nil,
        meta: JSONValue? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.name = name
        self.color = color
        self.isDefault = isDefault
        self.isSystem = isSystem
        self.allowedUserIDs = AppCalendar.normalizedAccessIDs(allowedUserIDs)
        self.allowedGroupIDs = AppCalendar.normalizedAccessIDs(allowedGroupIDs)
        self.data = data
        self.meta = meta
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID
        case name
        case color
        case isDefault
        case isSystem
        case allowedUserIDs
        case allowedGroupIDs
        case data
        case meta
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            userID: try container.decodeIfPresent(String.self, forKey: .userID) ?? "local-user",
            name: try container.decode(String.self, forKey: .name),
            color: try container.decodeIfPresent(String.self, forKey: .color),
            isDefault: try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false,
            isSystem: try container.decodeIfPresent(Bool.self, forKey: .isSystem) ?? false,
            allowedUserIDs: try container.decodeIfPresent([String].self, forKey: .allowedUserIDs) ?? [],
            allowedGroupIDs: try container.decodeIfPresent([String].self, forKey: .allowedGroupIDs) ?? [],
            data: try container.decodeIfPresent(JSONValue.self, forKey: .data),
            meta: try container.decodeIfPresent(JSONValue.self, forKey: .meta),
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        )
    }

    static func normalizedAccessIDs(_ ids: [String]) -> [String] {
        Array(Set(ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func defaultPersonal() -> AppCalendar {
        AppCalendar(
            name: "Personal",
            color: "#3b82f6",
            isDefault: true
        )
    }

    static let scheduledTasksCalendarID = "__scheduled_tasks__"

    static func scheduledTasks(now: Date = Date()) -> AppCalendar {
        AppCalendar(
            id: scheduledTasksCalendarID,
            name: "Scheduled Tasks",
            color: "#8b5cf6",
            isSystem: true,
            createdAt: now,
            updatedAt: now
        )
    }
}

struct AppCalendarEvent: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var calendarID: String
    var userID: String
    var title: String
    var description: String?
    var startAt: Date
    var endAt: Date?
    var allDay: Bool
    var rrule: String?
    var color: String?
    var location: String?
    var reminderMinutesBefore: Int?
    var data: JSONValue?
    var meta: JSONValue?
    var isCancelled: Bool
    var attendees: [AppCalendarEventAttendee]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        calendarID: String,
        userID: String = "local-user",
        title: String,
        description: String? = nil,
        startAt: Date,
        endAt: Date? = nil,
        allDay: Bool = false,
        rrule: String? = nil,
        color: String? = nil,
        location: String? = nil,
        reminderMinutesBefore: Int? = nil,
        data: JSONValue? = nil,
        meta: JSONValue? = nil,
        isCancelled: Bool = false,
        attendees: [AppCalendarEventAttendee] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.calendarID = calendarID
        self.userID = userID
        self.title = title
        self.description = description
        self.startAt = startAt
        self.endAt = endAt
        self.allDay = allDay
        self.rrule = rrule
        self.color = color
        self.location = location
        self.reminderMinutesBefore = reminderMinutesBefore
        self.data = data
        self.meta = meta
        self.isCancelled = isCancelled
        self.attendees = attendees
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct AppCalendarReminder: Identifiable, Equatable, Sendable {
    var event: AppCalendarEvent
    var reminderAt: Date

    var id: String {
        "\(event.id)-\(Int(reminderAt.timeIntervalSince1970))"
    }
}

struct AppCalendarEventAttendee: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var eventID: String
    var userID: String
    var status: String
    var meta: JSONValue?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        eventID: String,
        userID: String,
        status: String = "pending",
        meta: JSONValue? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.eventID = eventID
        self.userID = userID
        self.status = status
        self.meta = meta
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct CalendarSnapshot: Codable, Equatable, Sendable {
    var calendars: [AppCalendar]
    var events: [AppCalendarEvent]

    init(calendars: [AppCalendar] = [], events: [AppCalendarEvent] = []) {
        self.calendars = calendars
        self.events = events
    }
}
