import Foundation

struct CalendarExportService: Sendable {
    func jsonData(for snapshot: CalendarSnapshot) throws -> Data {
        let bundle = CalendarExportBundle(
            format: "open-webui-native-calendar",
            version: 1,
            exportedAt: Date(),
            calendars: snapshot.calendars.map(CalendarExportRecord.init(calendar:)),
            events: snapshot.events.map(CalendarEventExportRecord.init(event:))
        )
        return try JSONEncoder.openWebUIEncoder.encode(bundle)
    }

    func openWebUIJSONData(for snapshot: CalendarSnapshot) throws -> Data {
        let bundle = OpenWebUICalendarExportBundle(
            calendars: snapshot.calendars.map(OpenWebUICalendarExportRecord.init(calendar:)),
            events: snapshot.events.map(OpenWebUICalendarEventExportRecord.init(event:))
        )
        return try JSONEncoder.openWebUIEncoder.encode(bundle)
    }

    func snapshot(fromJSONData data: Data) throws -> CalendarSnapshot {
        let decoder = JSONDecoder.openWebUIDecoder
        if let bundle = try? decoder.decode(CalendarExportBundle.self, from: data) {
            return bundle.calendarSnapshot
        }
        if let snapshot = try? decoder.decode(CalendarSnapshot.self, from: data) {
            return snapshot
        }
        let events = try decoder.decode([CalendarEventExportRecord].self, from: data)
        return CalendarSnapshot(events: events.compactMap(\.appEvent))
    }
}

private struct CalendarExportBundle: Codable {
    var format: String?
    var version: Int?
    var exportedAt: Date?
    var calendars: [CalendarExportRecord]
    var events: [CalendarEventExportRecord]

    var calendarSnapshot: CalendarSnapshot {
        CalendarSnapshot(
            calendars: calendars.compactMap(\.appCalendar),
            events: events.compactMap(\.appEvent)
        )
    }
}

private struct CalendarExportRecord: Codable {
    var id: String?
    var userID: String?
    var name: String
    var color: String?
    var isDefault: Bool?
    var isSystem: Bool?
    var allowedUserIDs: [String]?
    var allowedGroupIDs: [String]?
    var accessGrants: [JSONValue]?
    var data: JSONValue?
    var meta: JSONValue?
    var createdAt: Date?
    var updatedAt: Date?
    var createdAtUnix: Int64?
    var updatedAtUnix: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case color
        case isDefault = "is_default"
        case isSystem = "is_system"
        case allowedUserIDs
        case allowedGroupIDs
        case accessGrants = "access_grants"
        case data
        case meta
        case createdAt
        case updatedAt
        case createdAtUnix = "created_at"
        case updatedAtUnix = "updated_at"
    }

    init(calendar: AppCalendar) {
        id = calendar.id
        userID = calendar.userID
        name = calendar.name
        color = calendar.color
        isDefault = calendar.isDefault
        isSystem = calendar.isSystem
        allowedUserIDs = calendar.allowedUserIDs
        allowedGroupIDs = calendar.allowedGroupIDs
        accessGrants = nil
        data = calendar.data
        meta = calendar.meta
        createdAt = calendar.createdAt
        updatedAt = calendar.updatedAt
        createdAtUnix = nil
        updatedAtUnix = nil
    }

    var appCalendar: AppCalendar? {
        let resolvedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedName.isEmpty else {
            return nil
        }
        return AppCalendar(
            id: id?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? UUID().uuidString,
            userID: userID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "local-user",
            name: resolvedName,
            color: color?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            isDefault: isDefault ?? false,
            isSystem: isSystem ?? false,
            allowedUserIDs: AppCalendar.normalizedAccessIDs(allowedUserIDs ?? accessGrants?.userIDs ?? []),
            allowedGroupIDs: AppCalendar.normalizedAccessIDs(allowedGroupIDs ?? accessGrants?.groupIDs ?? []),
            data: data,
            meta: meta,
            createdAt: createdAt ?? createdAtUnix.map(CalendarExportRecord.date(fromEpochValue:)) ?? Date(),
            updatedAt: updatedAt ?? updatedAtUnix.map(CalendarExportRecord.date(fromEpochValue:)) ?? Date()
        )
    }

    private static func date(fromEpochValue value: Int64) -> Date {
        CalendarEpoch.date(from: value)
    }
}

private struct CalendarEventExportRecord: Codable {
    var id: String?
    var calendarID: String?
    var userID: String?
    var title: String
    var description: String?
    var startAt: Date?
    var endAt: Date?
    var startAtUnix: Int64?
    var endAtUnix: Int64?
    var allDay: Bool?
    var rrule: String?
    var color: String?
    var location: String?
    var reminderMinutesBefore: Int?
    var data: JSONValue?
    var meta: JSONValue?
    var isCancelled: Bool?
    var attendees: [CalendarAttendeeExportRecord]?
    var createdAt: Date?
    var updatedAt: Date?
    var createdAtUnix: Int64?
    var updatedAtUnix: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case calendarID = "calendar_id"
        case userID = "user_id"
        case title
        case description
        case startAt
        case endAt
        case startAtUnix = "start_at"
        case endAtUnix = "end_at"
        case allDay = "all_day"
        case rrule
        case color
        case location
        case reminderMinutesBefore = "reminder_minutes_before"
        case data
        case meta
        case isCancelled = "is_cancelled"
        case attendees
        case createdAt
        case updatedAt
        case createdAtUnix = "created_at"
        case updatedAtUnix = "updated_at"
    }

    init(event: AppCalendarEvent) {
        id = event.id
        calendarID = event.calendarID
        userID = event.userID
        title = event.title
        description = event.description
        startAt = event.startAt
        endAt = event.endAt
        startAtUnix = nil
        endAtUnix = nil
        allDay = event.allDay
        rrule = event.rrule
        color = event.color
        location = event.location
        reminderMinutesBefore = event.reminderMinutesBefore
        data = event.data
        meta = event.meta
        isCancelled = event.isCancelled
        attendees = event.attendees.map(CalendarAttendeeExportRecord.init(attendee:))
        createdAt = event.createdAt
        updatedAt = event.updatedAt
        createdAtUnix = nil
        updatedAtUnix = nil
    }

    var appEvent: AppCalendarEvent? {
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCalendarID = calendarID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedTitle.isEmpty, let calendarID = resolvedCalendarID?.nilIfEmpty else {
            return nil
        }
        return AppCalendarEvent(
            id: id?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? UUID().uuidString,
            calendarID: calendarID,
            userID: userID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "local-user",
            title: resolvedTitle,
            description: description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            startAt: startAt ?? startAtUnix.map(CalendarEpoch.date(from:)) ?? Date(),
            endAt: endAt ?? endAtUnix.map(CalendarEpoch.date(from:)),
            allDay: allDay ?? false,
            rrule: rrule?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            color: color?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            location: location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            reminderMinutesBefore: CalendarEventExportRecord.normalizedReminderMinutesBefore(reminderMinutesBefore ?? CalendarEventExportRecord.reminderMinutes(from: meta)),
            data: data,
            meta: meta,
            isCancelled: isCancelled ?? false,
            attendees: attendees?.compactMap(\.appAttendee) ?? [],
            createdAt: createdAt ?? createdAtUnix.map(CalendarEpoch.date(from:)) ?? Date(),
            updatedAt: updatedAt ?? updatedAtUnix.map(CalendarEpoch.date(from:)) ?? Date()
        )
    }

    private static func reminderMinutes(from meta: JSONValue?) -> Int? {
        guard let object = meta?.objectValue else {
            return nil
        }

        for key in ["reminder_minutes_before", "reminderMinutesBefore", "alert_minutes"] {
            if let value = object[key],
               let minutes = reminderMinutes(from: value) {
                return minutes
            }
        }
        return nil
    }

    private static func reminderMinutes(from value: JSONValue) -> Int? {
        switch value {
        case .number(let rawValue) where rawValue.isFinite && rawValue >= 0:
            return Int(rawValue)
        case .string(let rawValue):
            return CalendarEventExportRecord.normalizedReminderMinutesBefore(Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)))
        default:
            return nil
        }
    }

    private static func normalizedReminderMinutesBefore(_ value: Int?) -> Int? {
        guard let value, value >= 0 else {
            return nil
        }
        return value
    }
}

private struct CalendarAttendeeExportRecord: Codable {
    var id: String?
    var eventID: String?
    var userID: String?
    var status: String?
    var meta: JSONValue?
    var createdAt: Date?
    var updatedAt: Date?
    var createdAtUnix: Int64?
    var updatedAtUnix: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case userID = "user_id"
        case status
        case meta
        case createdAt
        case updatedAt
        case createdAtUnix = "created_at"
        case updatedAtUnix = "updated_at"
    }

    init(attendee: AppCalendarEventAttendee) {
        id = attendee.id
        eventID = attendee.eventID
        userID = attendee.userID
        status = attendee.status
        meta = attendee.meta
        createdAt = attendee.createdAt
        updatedAt = attendee.updatedAt
        createdAtUnix = nil
        updatedAtUnix = nil
    }

    var appAttendee: AppCalendarEventAttendee? {
        guard let eventID = eventID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
              let userID = userID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }
        return AppCalendarEventAttendee(
            id: id?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? UUID().uuidString,
            eventID: eventID,
            userID: userID,
            status: status?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "pending",
            meta: meta,
            createdAt: createdAt ?? createdAtUnix.map(CalendarEpoch.date(from:)) ?? Date(),
            updatedAt: updatedAt ?? updatedAtUnix.map(CalendarEpoch.date(from:)) ?? Date()
        )
    }
}

private struct OpenWebUICalendarExportBundle: Encodable {
    var calendars: [OpenWebUICalendarExportRecord]
    var events: [OpenWebUICalendarEventExportRecord]
}

private struct OpenWebUICalendarExportRecord: Encodable {
    var id: String
    var userID: String
    var name: String
    var color: String?
    var isDefault: Bool
    var isSystem: Bool
    var accessGrants: [JSONValue]
    var data: JSONValue?
    var meta: JSONValue?
    var createdAt: Int64
    var updatedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case color
        case isDefault = "is_default"
        case isSystem = "is_system"
        case accessGrants = "access_grants"
        case data
        case meta
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(calendar: AppCalendar) {
        id = calendar.id
        userID = calendar.userID
        name = calendar.name
        color = calendar.color
        isDefault = calendar.isDefault
        isSystem = calendar.isSystem
        accessGrants = calendar.accessGrantJSONValues
        data = calendar.data
        meta = calendar.meta
        createdAt = CalendarEpoch.nanoseconds(from: calendar.createdAt)
        updatedAt = CalendarEpoch.nanoseconds(from: calendar.updatedAt)
    }
}

private struct OpenWebUICalendarEventExportRecord: Encodable {
    var id: String
    var calendarID: String
    var userID: String
    var title: String
    var description: String?
    var startAt: Int64
    var endAt: Int64?
    var allDay: Bool
    var rrule: String?
    var color: String?
    var location: String?
    var reminderMinutesBefore: Int?
    var data: JSONValue?
    var meta: JSONValue?
    var isCancelled: Bool
    var attendees: [OpenWebUICalendarAttendeeExportRecord]
    var createdAt: Int64
    var updatedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case calendarID = "calendar_id"
        case userID = "user_id"
        case title
        case description
        case startAt = "start_at"
        case endAt = "end_at"
        case allDay = "all_day"
        case rrule
        case color
        case location
        case reminderMinutesBefore = "reminder_minutes_before"
        case data
        case meta
        case isCancelled = "is_cancelled"
        case attendees
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(event: AppCalendarEvent) {
        id = event.id
        calendarID = event.calendarID
        userID = event.userID
        title = event.title
        description = event.description
        startAt = CalendarEpoch.nanoseconds(from: event.startAt)
        endAt = event.endAt.map(CalendarEpoch.nanoseconds(from:))
        allDay = event.allDay
        rrule = event.rrule
        color = event.color
        location = event.location
        reminderMinutesBefore = event.reminderMinutesBefore
        data = event.data
        meta = event.meta
        isCancelled = event.isCancelled
        attendees = event.attendees.map(OpenWebUICalendarAttendeeExportRecord.init(attendee:))
        createdAt = CalendarEpoch.nanoseconds(from: event.createdAt)
        updatedAt = CalendarEpoch.nanoseconds(from: event.updatedAt)
    }
}

private struct OpenWebUICalendarAttendeeExportRecord: Encodable {
    var id: String
    var eventID: String
    var userID: String
    var status: String
    var meta: JSONValue?
    var createdAt: Int64
    var updatedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case userID = "user_id"
        case status
        case meta
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(attendee: AppCalendarEventAttendee) {
        id = attendee.id
        eventID = attendee.eventID
        userID = attendee.userID
        status = attendee.status
        meta = attendee.meta
        createdAt = CalendarEpoch.nanoseconds(from: attendee.createdAt)
        updatedAt = CalendarEpoch.nanoseconds(from: attendee.updatedAt)
    }
}

private enum CalendarEpoch {
    static func date(from value: Int64) -> Date {
        if value >= 1_000_000_000 {
            return Date(timeIntervalSince1970: TimeInterval(value) / 1_000_000_000)
        }
        return Date(timeIntervalSince1970: TimeInterval(value))
    }

    static func nanoseconds(from date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000_000_000).rounded())
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension AppCalendar {
    var accessGrantJSONValues: [JSONValue] {
        allowedUserIDs.map { id in
            JSONValue.object([
                "type": .string("user"),
                "id": .string(id)
            ])
        } + allowedGroupIDs.map { id in
            JSONValue.object([
                "type": .string("group"),
                "id": .string(id)
            ])
        }
    }
}

private extension Array where Element == JSONValue {
    var userIDs: [String] {
        compactMap { grantID($0, expectedType: "user", fallbackKeys: ["user_id", "userID"]) }
    }

    var groupIDs: [String] {
        compactMap { grantID($0, expectedType: "group", fallbackKeys: ["group_id", "groupID"]) }
    }

    private func grantID(_ value: JSONValue, expectedType: String, fallbackKeys: [String]) -> String? {
        if case .string(let rawValue) = value {
            let prefix = "\(expectedType):"
            return rawValue.hasPrefix(prefix) ? String(rawValue.dropFirst(prefix.count)) : nil
        }

        guard let object = value.objectValue else {
            return nil
        }
        let type = object["type"]?.stringValue ?? object["kind"]?.stringValue
        guard type == expectedType else {
            return nil
        }

        for key in ["id", "principal_id", "principalID"] + fallbackKeys {
            if let id = object[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
                return id
            }
        }
        return nil
    }
}

private extension JSONValue {
    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}
