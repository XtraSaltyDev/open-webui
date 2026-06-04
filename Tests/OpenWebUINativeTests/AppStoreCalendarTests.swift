import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreCalendarTests: XCTestCase {
    func testLoadCreatesDefaultPersonalCalendarWhenMissing() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()

        await store.load()

        XCTAssertEqual(store.calendars.map(\.name), ["Personal"])
        XCTAssertTrue(store.calendars.first?.isDefault ?? false)
        XCTAssertEqual(store.selectedCalendarID, store.calendars.first?.id)
    }

    func testVisibleCalendarsIncludesVirtualScheduledTasksCalendarWhenAutomationsAreEnabled() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()

        XCTAssertEqual(store.visibleCalendars.map(\.name), ["Personal", "Scheduled Tasks"])

        let scheduledCalendar = try XCTUnwrap(store.visibleCalendars.first { $0.id == AppCalendar.scheduledTasksCalendarID })
        XCTAssertTrue(scheduledCalendar.isSystem)
        XCTAssertFalse(scheduledCalendar.isDefault)
    }

    func testScheduledTasksCalendarProjectsActiveAutomationOccurrences() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()
        let nextRunAt = Date(timeIntervalSince1970: 1_000)
        store.automations = [
            AppAutomation(
                id: "automation-id",
                name: "Daily summary",
                prompt: "Summarize yesterday's notes.",
                modelID: "llama3.2",
                rrule: "FREQ=DAILY",
                isActive: true,
                nextRunAt: nextRunAt,
                createdAt: nextRunAt,
                updatedAt: nextRunAt
            )
        ]

        let events = store.calendarEvents(
            in: Date(timeIntervalSince1970: 87_300)...Date(timeIntervalSince1970: 88_000),
            calendarIDs: [AppCalendar.scheduledTasksCalendarID]
        )

        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(event.calendarID, AppCalendar.scheduledTasksCalendarID)
        XCTAssertEqual(event.title, "Daily summary")
        XCTAssertEqual(event.description, "Summarize yesterday's notes.")
        XCTAssertEqual(event.startAt, Date(timeIntervalSince1970: 87_400))
        XCTAssertEqual(event.rrule, "FREQ=DAILY")
        XCTAssertEqual(event.meta, .object([
            "automation_id": .string("automation-id"),
            "model_id": .string("llama3.2")
        ]))
    }

    func testScheduledTasksCalendarSkipsInactiveAutomations() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()
        let nextRunAt = Date(timeIntervalSince1970: 1_000)
        store.automations = [
            AppAutomation(
                id: "paused-id",
                name: "Paused summary",
                prompt: "Skip me.",
                modelID: "llama3.2",
                rrule: "FREQ=DAILY",
                isActive: false,
                nextRunAt: nextRunAt,
                createdAt: nextRunAt,
                updatedAt: nextRunAt
            )
        ]

        let events = store.calendarEvents(
            in: Date(timeIntervalSince1970: 900)...Date(timeIntervalSince1970: 1_100),
            calendarIDs: [AppCalendar.scheduledTasksCalendarID]
        )

        XCTAssertTrue(events.isEmpty)
    }

    func testCreateCalendarEventPersistsAndFiltersByVisibleRange() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()
        let calendar = try XCTUnwrap(store.calendars.first)
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 1_600)

        await store.createCalendarEvent(
            calendarID: calendar.id,
            title: "Design review",
            description: "Review native calendar shape.",
            startAt: start,
            endAt: end,
            allDay: false,
            location: "Studio"
        )

        XCTAssertEqual(store.calendarEvents.map(\.title), ["Design review"])
        XCTAssertEqual(store.calendarEvents(in: Date(timeIntervalSince1970: 900)...Date(timeIntervalSince1970: 1_100)).map(\.title), ["Design review"])
        XCTAssertTrue(store.calendarEvents(in: Date(timeIntervalSince1970: 2_000)...Date(timeIntervalSince1970: 3_000)).isEmpty)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.calendarEvents.map(\.title), ["Design review"])
        XCTAssertEqual(reloadedStore.calendarEvents.first?.location, "Studio")
    }

    func testCreateUpdateAndReloadCalendarEventReminder() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()
        let calendar = try XCTUnwrap(store.calendars.first)

        await store.createCalendarEvent(
            calendarID: calendar.id,
            title: "Design review",
            description: nil,
            startAt: Date(timeIntervalSince1970: 10_000),
            endAt: nil,
            allDay: false,
            location: nil,
            reminderMinutesBefore: 30
        )

        XCTAssertEqual(store.calendarEvents.first?.reminderMinutesBefore, 30)

        var reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        var event = try XCTUnwrap(reloadedStore.calendarEvents.first)
        XCTAssertEqual(event.reminderMinutesBefore, 30)

        await reloadedStore.updateCalendarEvent(
            event.id,
            calendarID: calendar.id,
            title: event.title,
            description: event.description,
            startAt: event.startAt,
            endAt: event.endAt,
            allDay: event.allDay,
            location: event.location,
            isCancelled: event.isCancelled,
            reminderMinutesBefore: nil
        )

        reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        event = try XCTUnwrap(reloadedStore.calendarEvents.first)
        XCTAssertNil(event.reminderMinutesBefore)
    }

    func testCalendarRemindersDueReturnsReminderOccurrencesInsideRange() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()
        let calendar = try XCTUnwrap(store.calendars.first)

        await store.createCalendarEvent(
            calendarID: calendar.id,
            title: "Design review",
            description: nil,
            startAt: Date(timeIntervalSince1970: 10_000),
            endAt: nil,
            allDay: false,
            location: nil,
            reminderMinutesBefore: 30
        )

        let reminders = store.calendarRemindersDue(
            in: Date(timeIntervalSince1970: 8_100)...Date(timeIntervalSince1970: 8_300)
        )

        XCTAssertEqual(reminders.map(\.event.title), ["Design review"])
        XCTAssertEqual(reminders.map(\.reminderAt), [Date(timeIntervalSince1970: 8_200)])
    }

    func testDeliverDueCalendarReminderNotificationsSendsRequestsOnce() async throws {
        let reminderDeliverer = CapturingCalendarReminderDeliverer()
        let fixture = try CalendarFixture(reminderDeliverer: reminderDeliverer)
        let store = fixture.makeStore()
        await store.load()
        let calendar = try XCTUnwrap(store.calendars.first)

        await store.createCalendarEvent(
            calendarID: calendar.id,
            title: "Design review",
            description: "Walk through the native calendar flow.",
            startAt: Date(timeIntervalSince1970: 10_000),
            endAt: nil,
            allDay: false,
            location: "Studio",
            reminderMinutesBefore: 30
        )

        await store.deliverDueCalendarReminders(
            in: Date(timeIntervalSince1970: 8_100)...Date(timeIntervalSince1970: 8_300)
        )
        await store.deliverDueCalendarReminders(
            in: Date(timeIntervalSince1970: 8_100)...Date(timeIntervalSince1970: 8_300)
        )

        let request = try XCTUnwrap(reminderDeliverer.requests.first)
        XCTAssertEqual(reminderDeliverer.requests.count, 1)
        XCTAssertEqual(request.title, "Design review")
        XCTAssertEqual(request.eventID, store.calendarEvents.first?.id)
        XCTAssertEqual(request.calendarID, calendar.id)
        XCTAssertEqual(request.deliveryDate, Date(timeIntervalSince1970: 8_200))
        XCTAssertTrue(request.body.contains("Studio"))
    }

    func testCalendarReminderSchedulerDeliversUpcomingRemindersAndCanStop() async throws {
        let reminderDeliverer = CapturingCalendarReminderDeliverer()
        let fixture = try CalendarFixture(reminderDeliverer: reminderDeliverer)
        let store = fixture.makeStore()
        await store.load()
        let calendar = try XCTUnwrap(store.calendars.first)

        await store.createCalendarEvent(
            calendarID: calendar.id,
            title: "Upcoming reminder",
            description: nil,
            startAt: Date().addingTimeInterval(2),
            endAt: nil,
            allDay: false,
            location: nil,
            reminderMinutesBefore: 0
        )

        store.startCalendarReminderScheduler(
            intervalNanoseconds: 1_000_000,
            lookAheadSeconds: 5
        )
        for _ in 0..<50 where reminderDeliverer.requests.isEmpty {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertTrue(store.isCalendarReminderSchedulerRunning)
        XCTAssertEqual(reminderDeliverer.requests.map(\.title), ["Upcoming reminder"])
        store.stopCalendarReminderScheduler()
        XCTAssertFalse(store.isCalendarReminderSchedulerRunning)
    }

    func testCalendarActionsBlockDisabledFeatureBeforeReminderOrPersistenceChanges() async throws {
        let reminderDeliverer = CapturingCalendarReminderDeliverer()
        let shareService = FakeCalendarShareService()
        let fixture = try CalendarFixture(reminderDeliverer: reminderDeliverer, shareService: shareService)
        let store = fixture.makeStore()
        await store.load()
        await store.createCalendar(name: "Team", color: "#22c55e")
        let team = try XCTUnwrap(store.calendars.first { $0.name == "Team" })
        await store.createCalendarEvent(
            calendarID: team.id,
            title: "Existing event",
            description: "Existing details.",
            startAt: Date(timeIntervalSince1970: 10_000),
            endAt: nil,
            allDay: false,
            location: "Studio",
            reminderMinutesBefore: 30
        )
        let event = try XCTUnwrap(store.calendarEvents.first)
        await store.addCalendarEventAttendee(eventID: event.id, userID: "ada@example.com", status: "accepted")
        let attendee = try XCTUnwrap(store.calendarEvents.first?.attendees.first)
        let importData = try CalendarExportService().jsonData(for: CalendarSnapshot(
            calendars: [AppCalendar(id: "blocked-import", name: "Blocked Import")],
            events: [
                AppCalendarEvent(
                    id: "blocked-event",
                    calendarID: "blocked-import",
                    title: "Blocked imported event",
                    startAt: Date(timeIntervalSince1970: 3_000)
                )
            ]
        ))

        store.startCalendarReminderScheduler(intervalNanoseconds: 60_000_000_000, lookAheadSeconds: 1)
        XCTAssertTrue(store.isCalendarReminderSchedulerRunning)
        await store.setFeatureToggle(.calendar, isEnabled: false)
        store.startCalendarReminderScheduler(intervalNanoseconds: 1_000_000, lookAheadSeconds: 5)
        await store.createCalendar(name: "Blocked calendar", color: "#ef4444")
        await store.createCalendarEvent(
            calendarID: team.id,
            title: "Blocked event",
            description: nil,
            startAt: Date(timeIntervalSince1970: 2_000),
            endAt: nil,
            allDay: false,
            location: nil
        )
        await store.updateCalendarEvent(
            event.id,
            calendarID: team.id,
            title: "Blocked update",
            description: "Blocked details.",
            startAt: Date(timeIntervalSince1970: 2_000),
            endAt: nil,
            allDay: true,
            location: "Blocked",
            isCancelled: true
        )
        await store.addCalendarEventAttendee(eventID: event.id, userID: "grace@example.com", status: "pending")
        await store.updateCalendarEventAttendee(eventID: event.id, attendeeID: attendee.id, status: "declined")
        await store.removeCalendarEventAttendee(eventID: event.id, attendeeID: attendee.id)
        await store.deliverDueCalendarReminders(
            in: Date(timeIntervalSince1970: 8_100)...Date(timeIntervalSince1970: 8_300)
        )
        try await store.importCalendarJSONData(importData)
        store.shareCalendarEvent(event.id)
        await store.deleteCalendarEvent(event.id)
        await store.deleteCalendar(team.id)

        let unchangedEvent = try XCTUnwrap(store.calendarEvents.first)
        XCTAssertFalse(store.isCalendarReminderSchedulerRunning)
        XCTAssertEqual(store.calendars.map(\.name).sorted(), ["Personal", "Team"])
        XCTAssertEqual(store.calendarEvents.count, 1)
        XCTAssertEqual(unchangedEvent.title, "Existing event")
        XCTAssertEqual(unchangedEvent.description, "Existing details.")
        XCTAssertEqual(unchangedEvent.location, "Studio")
        XCTAssertFalse(unchangedEvent.isCancelled)
        XCTAssertEqual(unchangedEvent.attendees.map(\.userID), ["ada@example.com"])
        XCTAssertEqual(unchangedEvent.attendees.map(\.status), ["accepted"])
        XCTAssertTrue(reminderDeliverer.requests.isEmpty)
        XCTAssertNil(shareService.sharedText)
        XCTAssertNil(shareService.sharedTitle)
        XCTAssertEqual(store.errorMessage, "Calendar is disabled.")

        let snapshot = try await fixture.calendarStorage.loadSnapshot()
        XCTAssertEqual(snapshot.calendars.map(\.name).sorted(), ["Personal", "Team"])
        XCTAssertEqual(snapshot.events.map(\.title), ["Existing event"])
        XCTAssertEqual(snapshot.events.first?.attendees.map(\.status), ["accepted"])
    }

    func testCreateRecurringCalendarEventPersistsRuleAndFiltersOccurrencesByVisibleRange() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()
        let calendar = try XCTUnwrap(store.calendars.first)
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 1_600)

        await store.createCalendarEvent(
            calendarID: calendar.id,
            title: "Daily standup",
            description: nil,
            startAt: start,
            endAt: end,
            allDay: false,
            location: nil,
            rrule: "FREQ=DAILY"
        )

        XCTAssertEqual(store.calendarEvents.first?.rrule, "FREQ=DAILY")
        XCTAssertEqual(
            store.calendarEvents(in: Date(timeIntervalSince1970: 87_300)...Date(timeIntervalSince1970: 88_000)).map(\.startAt),
            [Date(timeIntervalSince1970: 87_400)]
        )
    }

    func testFilteredCalendarEventsSearchesTextCalendarAndStatusOperators() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()
        let personal = try XCTUnwrap(store.calendars.first)
        await store.createCalendar(name: "Team Calendar", color: "#22c55e")
        let team = try XCTUnwrap(store.calendars.first { $0.name == "Team Calendar" })

        await store.createCalendarEvent(
            calendarID: personal.id,
            title: "Design review",
            description: "Review native calendar shape.",
            startAt: Date(timeIntervalSince1970: 1_000),
            endAt: nil,
            allDay: false,
            location: "Studio"
        )
        await store.createCalendarEvent(
            calendarID: team.id,
            title: "Launch rehearsal",
            description: "Ship checklist.",
            startAt: Date(timeIntervalSince1970: 1_400),
            endAt: nil,
            allDay: false,
            location: "Room 4"
        )
        let launch = try XCTUnwrap(store.calendarEvents.first { $0.title == "Launch rehearsal" })
        await store.updateCalendarEvent(
            launch.id,
            calendarID: team.id,
            title: launch.title,
            description: launch.description,
            startAt: launch.startAt,
            endAt: launch.endAt,
            allDay: launch.allDay,
            location: launch.location,
            isCancelled: true
        )

        store.calendarSearchText = "studio"
        XCTAssertEqual(
            store.filteredCalendarEvents(in: Date(timeIntervalSince1970: 900)...Date(timeIntervalSince1970: 2_000)).map(\.title),
            ["Design review"]
        )

        store.calendarSearchText = "calendar:team status:cancelled checklist"
        XCTAssertEqual(
            store.filteredCalendarEvents(in: Date(timeIntervalSince1970: 900)...Date(timeIntervalSince1970: 2_000)).map(\.title),
            ["Launch rehearsal"]
        )
    }

    func testFilteredCalendarEventsSearchesVirtualScheduledTasksCalendar() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()
        let nextRunAt = Date(timeIntervalSince1970: 1_000)
        store.automations = [
            AppAutomation(
                id: "automation-id",
                name: "Daily summary",
                prompt: "Summarize yesterday's notes.",
                modelID: "llama3.2",
                rrule: "FREQ=DAILY",
                isActive: true,
                nextRunAt: nextRunAt,
                createdAt: nextRunAt,
                updatedAt: nextRunAt
            )
        ]

        store.calendarSearchText = "calendar:scheduled summary"
        let events = store.filteredCalendarEvents(
            in: Date(timeIntervalSince1970: 87_300)...Date(timeIntervalSince1970: 88_000)
        )

        XCTAssertEqual(events.map(\.title), ["Daily summary"])
        XCTAssertEqual(events.first?.calendarID, AppCalendar.scheduledTasksCalendarID)
    }

    func testVisibleCalendarsIncludesCalendarGrantedToCurrentUser() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Local Admin", email: "admin@example.com", role: .admin)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let admin = try XCTUnwrap(store.adminUsers.first { $0.role == .admin })
        let user = try XCTUnwrap(store.adminUsers.first { $0.role == .user })
        store.currentUserID = admin.id
        await store.createCalendar(
            name: "Team",
            color: "#22c55e",
            allowedUserIDs: [user.id],
            allowedGroupIDs: []
        )
        await store.createCalendar(
            name: "Private",
            color: "#ef4444",
            allowedUserIDs: ["someone-else"],
            allowedGroupIDs: []
        )

        store.currentUserID = user.id

        XCTAssertTrue(store.visibleCalendars.contains { $0.name == "Team" })
        XCTAssertFalse(store.visibleCalendars.contains { $0.name == "Private" })
    }

    func testVisibleCalendarsIncludesCalendarGrantedToCurrentUsersGroup() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Local Admin", email: "admin@example.com", role: .admin)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let admin = try XCTUnwrap(store.adminUsers.first { $0.role == .admin })
        let user = try XCTUnwrap(store.adminUsers.first { $0.role == .user })
        store.currentUserID = admin.id
        await store.createAdminGroup(name: "Calendar Viewers", description: "Can view team calendars.", permissions: [])
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        await store.createCalendar(
            name: "Team",
            color: "#22c55e",
            allowedUserIDs: [],
            allowedGroupIDs: [group.id]
        )

        store.currentUserID = user.id

        XCTAssertTrue(store.visibleCalendars.contains { $0.name == "Team" })
    }

    func testCalendarEventsHideEventsForUngrantedCalendar() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Local Admin", email: "admin@example.com", role: .admin)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let admin = try XCTUnwrap(store.adminUsers.first { $0.role == .admin })
        let user = try XCTUnwrap(store.adminUsers.first { $0.role == .user })
        store.currentUserID = admin.id
        await store.createCalendar(name: "Public", color: "#3b82f6")
        await store.createCalendar(
            name: "Private",
            color: "#ef4444",
            allowedUserIDs: ["someone-else"],
            allowedGroupIDs: []
        )
        let publicCalendar = try XCTUnwrap(store.calendars.first { $0.name == "Public" })
        let privateCalendar = try XCTUnwrap(store.calendars.first { $0.name == "Private" })
        await store.createCalendarEvent(
            calendarID: publicCalendar.id,
            title: "Public design review",
            description: "Visible.",
            startAt: Date(timeIntervalSince1970: 1_000),
            endAt: nil,
            allDay: false,
            location: "Studio"
        )
        await store.createCalendarEvent(
            calendarID: privateCalendar.id,
            title: "Private launch review",
            description: "Hidden.",
            startAt: Date(timeIntervalSince1970: 1_100),
            endAt: nil,
            allDay: false,
            location: "War room"
        )

        store.currentUserID = user.id

        XCTAssertEqual(
            store.calendarEvents(in: Date(timeIntervalSince1970: 900)...Date(timeIntervalSince1970: 1_200)).map(\.title),
            ["Public design review"]
        )
        store.calendarSearchText = "review"
        XCTAssertEqual(
            store.filteredCalendarEvents(in: Date(timeIntervalSince1970: 900)...Date(timeIntervalSince1970: 1_200)).map(\.title),
            ["Public design review"]
        )
    }

    func testUpdateCancelAndDeleteCalendarEventPersist() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()
        let calendar = try XCTUnwrap(store.calendars.first)
        await store.createCalendarEvent(
            calendarID: calendar.id,
            title: "Draft event",
            description: nil,
            startAt: Date(timeIntervalSince1970: 1_000),
            endAt: nil,
            allDay: true,
            location: nil
        )
        let event = try XCTUnwrap(store.calendarEvents.first)

        await store.updateCalendarEvent(
            event.id,
            calendarID: calendar.id,
            title: "  Updated event  ",
            description: "  Better details  ",
            startAt: Date(timeIntervalSince1970: 2_000),
            endAt: Date(timeIntervalSince1970: 2_600),
            allDay: false,
            location: "  Office  ",
            isCancelled: true
        )

        XCTAssertEqual(store.calendarEvents.first?.title, "Updated event")
        XCTAssertEqual(store.calendarEvents.first?.description, "Better details")
        XCTAssertEqual(store.calendarEvents.first?.location, "Office")
        XCTAssertTrue(store.calendarEvents.first?.isCancelled ?? false)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertTrue(reloadedStore.calendarEvents.first?.isCancelled ?? false)

        await reloadedStore.deleteCalendarEvent(event.id)
        let deletedStore = fixture.makeStore()
        await deletedStore.load()
        XCTAssertTrue(deletedStore.calendarEvents.isEmpty)
    }

    func testCalendarEventChangesCreateAuditEventsWithoutEventContent() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createCalendar(name: "Team", color: "#22c55e")
        let calendar = try XCTUnwrap(store.calendars.first { $0.name == "Team" })

        await store.createCalendarEvent(
            calendarID: calendar.id,
            title: "Board prep",
            description: "Discuss sensitive runway details.",
            startAt: Date(timeIntervalSince1970: 1_000),
            endAt: Date(timeIntervalSince1970: 1_600),
            allDay: false,
            location: "Secret room",
            reminderMinutesBefore: 30
        )
        let event = try XCTUnwrap(store.calendarEvents.first)
        await store.updateCalendarEvent(
            event.id,
            calendarID: calendar.id,
            title: "Board sync",
            description: "Discuss sensitive runway details.",
            startAt: Date(timeIntervalSince1970: 2_000),
            endAt: Date(timeIntervalSince1970: 2_600),
            allDay: false,
            location: "Secret room",
            isCancelled: true,
            reminderMinutesBefore: nil
        )
        await store.deleteCalendarEvent(event.id)

        let eventAuditEvents = store.auditEvents.filter {
            ["calendarEventCreated", "calendarEventUpdated", "calendarEventDeleted"].contains($0.action.rawValue)
        }
        XCTAssertEqual(Set(eventAuditEvents.map(\.action.rawValue)), [
            "calendarEventCreated",
            "calendarEventUpdated",
            "calendarEventDeleted"
        ])

        let createdEvent = try XCTUnwrap(eventAuditEvents.first { $0.action.rawValue == "calendarEventCreated" })
        XCTAssertEqual(createdEvent.summary, "Created calendar event in Team")
        XCTAssertEqual(createdEvent.metadata["calendarID"], calendar.id)
        XCTAssertEqual(createdEvent.metadata["calendarName"], "Team")
        XCTAssertEqual(createdEvent.metadata["eventID"], event.id)
        XCTAssertEqual(createdEvent.metadata["allDay"], "false")
        XCTAssertEqual(createdEvent.metadata["hasReminder"], "true")

        let updatedEvent = try XCTUnwrap(eventAuditEvents.first { $0.action.rawValue == "calendarEventUpdated" })
        XCTAssertEqual(updatedEvent.summary, "Updated calendar event in Team")
        XCTAssertEqual(updatedEvent.metadata["isCancelled"], "true")
        XCTAssertEqual(updatedEvent.metadata["previousIsCancelled"], "false")
        XCTAssertEqual(updatedEvent.metadata["hasReminder"], "false")
        XCTAssertEqual(updatedEvent.metadata["previousHasReminder"], "true")

        let deletedEvent = try XCTUnwrap(eventAuditEvents.first { $0.action.rawValue == "calendarEventDeleted" })
        XCTAssertEqual(deletedEvent.summary, "Deleted calendar event from Team")
        XCTAssertEqual(deletedEvent.metadata["eventID"], event.id)

        for auditEvent in eventAuditEvents {
            XCTAssertFalse(auditEvent.summary.contains("Board"))
            XCTAssertFalse(auditEvent.metadata.values.contains("Board prep"))
            XCTAssertFalse(auditEvent.metadata.values.contains("Board sync"))
            XCTAssertFalse(auditEvent.metadata.values.contains("Discuss sensitive runway details."))
            XCTAssertFalse(auditEvent.metadata.values.contains("Secret room"))
        }

        let reloadedEvents = try await fixture.auditStorage.loadEvents()
        XCTAssertTrue(reloadedEvents.contains { $0.action.rawValue == "calendarEventCreated" && $0.metadata["eventID"] == event.id })
        XCTAssertTrue(reloadedEvents.contains { $0.action.rawValue == "calendarEventUpdated" && $0.metadata["eventID"] == event.id })
        XCTAssertTrue(reloadedEvents.contains { $0.action.rawValue == "calendarEventDeleted" && $0.metadata["eventID"] == event.id })
    }

    func testAddUpdateAndRemoveCalendarEventAttendeesPersist() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()
        let calendar = try XCTUnwrap(store.calendars.first)
        await store.createCalendarEvent(
            calendarID: calendar.id,
            title: "Design review",
            description: nil,
            startAt: Date(timeIntervalSince1970: 1_000),
            endAt: nil,
            allDay: false,
            location: nil
        )
        let event = try XCTUnwrap(store.calendarEvents.first)

        await store.addCalendarEventAttendee(eventID: event.id, userID: "  ada@example.com  ", status: "  accepted  ")

        var reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        var reloadedEvent = try XCTUnwrap(reloadedStore.calendarEvents.first)
        XCTAssertEqual(reloadedEvent.attendees.map(\.userID), ["ada@example.com"])
        XCTAssertEqual(reloadedEvent.attendees.map(\.status), ["accepted"])

        let attendee = try XCTUnwrap(reloadedEvent.attendees.first)
        await reloadedStore.updateCalendarEventAttendee(eventID: event.id, attendeeID: attendee.id, status: " declined ")

        reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        reloadedEvent = try XCTUnwrap(reloadedStore.calendarEvents.first)
        XCTAssertEqual(reloadedEvent.attendees.first?.status, "declined")

        await reloadedStore.removeCalendarEventAttendee(eventID: event.id, attendeeID: attendee.id)

        let deletedAttendeeStore = fixture.makeStore()
        await deletedAttendeeStore.load()
        XCTAssertTrue(deletedAttendeeStore.calendarEvents.first?.attendees.isEmpty ?? false)
    }

    func testCalendarAttendeeChangesCreateAuditEventsWithoutEventContent() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()
        let calendar = try XCTUnwrap(store.calendars.first)
        await store.createCalendarEvent(
            calendarID: calendar.id,
            title: "Hiring discussion",
            description: "Candidate compensation details.",
            startAt: Date(timeIntervalSince1970: 1_000),
            endAt: nil,
            allDay: false,
            location: "Private room"
        )
        let event = try XCTUnwrap(store.calendarEvents.first)

        await store.addCalendarEventAttendee(eventID: event.id, userID: "  ada@example.com  ", status: "  accepted  ")
        let attendee = try XCTUnwrap(store.calendarEvents.first?.attendees.first)
        await store.updateCalendarEventAttendee(eventID: event.id, attendeeID: attendee.id, status: " declined ")
        await store.removeCalendarEventAttendee(eventID: event.id, attendeeID: attendee.id)

        let attendeeAuditEvents = store.auditEvents.filter {
            ["calendarAttendeeAdded", "calendarAttendeeUpdated", "calendarAttendeeRemoved"].contains($0.action.rawValue)
        }
        XCTAssertEqual(Set(attendeeAuditEvents.map(\.action.rawValue)), [
            "calendarAttendeeAdded",
            "calendarAttendeeUpdated",
            "calendarAttendeeRemoved"
        ])

        let addedEvent = try XCTUnwrap(attendeeAuditEvents.first { $0.action.rawValue == "calendarAttendeeAdded" })
        XCTAssertEqual(addedEvent.summary, "Added calendar event attendee")
        XCTAssertEqual(addedEvent.metadata["calendarID"], calendar.id)
        XCTAssertEqual(addedEvent.metadata["eventID"], event.id)
        XCTAssertEqual(addedEvent.metadata["attendeeID"], attendee.id)
        XCTAssertEqual(addedEvent.metadata["userID"], "ada@example.com")
        XCTAssertEqual(addedEvent.metadata["status"], "accepted")

        let updatedEvent = try XCTUnwrap(attendeeAuditEvents.first { $0.action.rawValue == "calendarAttendeeUpdated" })
        XCTAssertEqual(updatedEvent.summary, "Updated calendar event attendee")
        XCTAssertEqual(updatedEvent.metadata["status"], "declined")
        XCTAssertEqual(updatedEvent.metadata["previousStatus"], "accepted")

        let removedEvent = try XCTUnwrap(attendeeAuditEvents.first { $0.action.rawValue == "calendarAttendeeRemoved" })
        XCTAssertEqual(removedEvent.summary, "Removed calendar event attendee")
        XCTAssertEqual(removedEvent.metadata["attendeeID"], attendee.id)

        for auditEvent in attendeeAuditEvents {
            XCTAssertFalse(auditEvent.metadata.values.contains("Hiring discussion"))
            XCTAssertFalse(auditEvent.metadata.values.contains("Candidate compensation details."))
            XCTAssertFalse(auditEvent.metadata.values.contains("Private room"))
        }

        let reloadedEvents = try await fixture.auditStorage.loadEvents()
        XCTAssertTrue(reloadedEvents.contains { $0.action.rawValue == "calendarAttendeeAdded" && $0.metadata["attendeeID"] == attendee.id })
        XCTAssertTrue(reloadedEvents.contains { $0.action.rawValue == "calendarAttendeeUpdated" && $0.metadata["attendeeID"] == attendee.id })
        XCTAssertTrue(reloadedEvents.contains { $0.action.rawValue == "calendarAttendeeRemoved" && $0.metadata["attendeeID"] == attendee.id })
    }

    func testAddCalendarEventAttendeeUpdatesExistingUserInsteadOfDuplicating() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()
        let calendar = try XCTUnwrap(store.calendars.first)
        await store.createCalendarEvent(
            calendarID: calendar.id,
            title: "Design review",
            description: nil,
            startAt: Date(timeIntervalSince1970: 1_000),
            endAt: nil,
            allDay: false,
            location: nil
        )
        let event = try XCTUnwrap(store.calendarEvents.first)

        await store.addCalendarEventAttendee(eventID: event.id, userID: "ada@example.com", status: "pending")
        await store.addCalendarEventAttendee(eventID: event.id, userID: " ada@example.com ", status: "accepted")

        let updatedEvent = try XCTUnwrap(store.calendarEvents.first)
        XCTAssertEqual(updatedEvent.attendees.count, 1)
        XCTAssertEqual(updatedEvent.attendees.first?.status, "accepted")
    }

    func testExportAndImportCalendarJSONRoundTripsCalendarsAndEvents() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createCalendar(
            name: "Team",
            color: "#22c55e",
            allowedUserIDs: ["user-id"],
            allowedGroupIDs: ["group-id"]
        )
        let team = try XCTUnwrap(store.calendars.first { $0.name == "Team" })
        await store.createCalendarEvent(
            calendarID: team.id,
            title: "Team sync",
            description: "Weekly product sync.",
            startAt: Date(timeIntervalSince1970: 5_000),
            endAt: Date(timeIntervalSince1970: 5_600),
            allDay: false,
            location: "Room 2"
        )

        let data = try store.exportCalendarJSONData()

        let importFixture = try CalendarFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importCalendarJSONData(data)

        XCTAssertEqual(Set(importStore.calendars.map(\.name)), ["Personal", "Team"])
        let importedTeam = try XCTUnwrap(importStore.calendars.first { $0.id == team.id })
        XCTAssertEqual(importedTeam.allowedUserIDs, ["user-id"])
        XCTAssertEqual(importedTeam.allowedGroupIDs, ["group-id"])
        XCTAssertEqual(importStore.calendarEvents.first?.title, "Team sync")
        XCTAssertEqual(importStore.calendarEvents.first?.calendarID, team.id)
    }

    func testExportCalendarOpenWebUIJSONDataBuildsRawCalendarAndEventRecords() async throws {
        let fixture = try CalendarFixture()
        let team = AppCalendar(
            id: "team-calendar",
            userID: "owner-id",
            name: "Team",
            color: "#22c55e",
            isDefault: true,
            allowedUserIDs: ["user-id"],
            allowedGroupIDs: ["group-id"],
            data: .object(["timezone": .string("America/Chicago")]),
            meta: .object(["source": .string("native")]),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let event = AppCalendarEvent(
            id: "design-review",
            calendarID: team.id,
            userID: "owner-id",
            title: "Design review",
            description: "Review native calendar export.",
            startAt: Date(timeIntervalSince1970: 1_000),
            endAt: Date(timeIntervalSince1970: 1_600),
            allDay: false,
            rrule: "FREQ=WEEKLY;COUNT=2",
            color: "#22c55e",
            location: "Studio",
            reminderMinutesBefore: 30,
            data: .object(["source": .string("manual")]),
            meta: .object(["room": .string("A")]),
            attendees: [
                AppCalendarEventAttendee(
                    id: "attendee-1",
                    eventID: "design-review",
                    userID: "ada@example.com",
                    status: "accepted",
                    meta: .object(["role": .string("reviewer")]),
                    createdAt: Date(timeIntervalSince1970: 300),
                    updatedAt: Date(timeIntervalSince1970: 400)
                )
            ],
            createdAt: Date(timeIntervalSince1970: 500),
            updatedAt: Date(timeIntervalSince1970: 600)
        )
        try await fixture.calendarStorage.saveSnapshot(CalendarSnapshot(calendars: [team], events: [event]))
        let store = fixture.makeStore()
        await store.load()

        let data = try store.exportCalendarOpenWebUIJSONData()
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let calendars = try XCTUnwrap(root["calendars"] as? [[String: Any]])
        let events = try XCTUnwrap(root["events"] as? [[String: Any]])
        let exportedCalendar: [String: Any] = try XCTUnwrap(calendars.first)
        let exportedEvent: [String: Any] = try XCTUnwrap(events.first)
        let grants = try XCTUnwrap(exportedCalendar["access_grants"] as? [[String: Any]])
        let attendees = try XCTUnwrap(exportedEvent["attendees"] as? [[String: Any]])
        let attendee: [String: Any] = try XCTUnwrap(attendees.first)

        XCTAssertNil(root["format"])
        XCTAssertEqual(calendars.count, 1)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(exportedCalendar["id"] as? String, team.id)
        XCTAssertEqual(exportedCalendar["user_id"] as? String, "owner-id")
        XCTAssertEqual(exportedCalendar["name"] as? String, "Team")
        XCTAssertEqual(exportedCalendar["is_default"] as? Bool, true)
        XCTAssertEqual(exportedCalendar["created_at"] as? Int64, 100_000_000_000)
        XCTAssertEqual(grants.map { $0["id"] as? String }, ["user-id", "group-id"])
        XCTAssertEqual(grants.map { $0["type"] as? String }, ["user", "group"])
        XCTAssertEqual(exportedEvent["calendar_id"] as? String, team.id)
        XCTAssertEqual(exportedEvent["title"] as? String, "Design review")
        XCTAssertEqual(exportedEvent["start_at"] as? Int64, 1_000_000_000_000)
        XCTAssertEqual(exportedEvent["end_at"] as? Int64, 1_600_000_000_000)
        XCTAssertEqual(exportedEvent["reminder_minutes_before"] as? Int, 30)
        XCTAssertEqual(attendee["event_id"] as? String, event.id)
        XCTAssertEqual(attendee["status"] as? String, "accepted")
        XCTAssertEqual(attendee["created_at"] as? Int64, 300_000_000_000)

        let importFixture = try CalendarFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importCalendarJSONData(data)
        let importedCalendar = try XCTUnwrap(importStore.calendars.first { $0.id == team.id })
        XCTAssertEqual(importedCalendar.allowedUserIDs, ["user-id"])
        XCTAssertEqual(importedCalendar.allowedGroupIDs, ["group-id"])
        XCTAssertEqual(importStore.calendarEvents.first { $0.id == event.id }?.attendees.first?.userID, "ada@example.com")
    }

    func testExportCalendarEventJSONDataExportsSelectedEventWithOwningCalendar() async throws {
        let fixture = try CalendarFixture()
        let team = AppCalendar(
            id: "team-calendar",
            userID: "user-id",
            name: "Team",
            color: "#22c55e",
            meta: .object(["source": .string("native")]),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let selectedEvent = AppCalendarEvent(
            id: "design-review",
            calendarID: team.id,
            userID: "user-id",
            title: "Design review",
            description: "Review native calendar shape.",
            startAt: Date(timeIntervalSince1970: 1_000),
            endAt: Date(timeIntervalSince1970: 1_600),
            rrule: "FREQ=WEEKLY;COUNT=2",
            color: "#22c55e",
            location: "Studio",
            reminderMinutesBefore: 30,
            data: .object(["source": .string("manual")]),
            meta: .object(["room": .string("A")]),
            attendees: [
                AppCalendarEventAttendee(
                    id: "attendee-1",
                    eventID: "design-review",
                    userID: "ada@example.com",
                    status: "accepted",
                    meta: .object(["role": .string("reviewer")]),
                    createdAt: Date(timeIntervalSince1970: 300),
                    updatedAt: Date(timeIntervalSince1970: 400)
                )
            ],
            createdAt: Date(timeIntervalSince1970: 500),
            updatedAt: Date(timeIntervalSince1970: 600)
        )
        let otherEvent = AppCalendarEvent(
            id: "weekly-plan",
            calendarID: team.id,
            title: "Weekly plan",
            startAt: Date(timeIntervalSince1970: 2_000)
        )
        try await fixture.calendarStorage.saveSnapshot(CalendarSnapshot(calendars: [team], events: [selectedEvent, otherEvent]))
        let store = fixture.makeStore()
        await store.load()

        let data = try XCTUnwrap(store.exportCalendarEventJSONData(selectedEvent.id))
        let exportedSnapshot = try CalendarExportService().snapshot(fromJSONData: data)

        XCTAssertEqual(exportedSnapshot.calendars.map(\.id), [team.id])
        XCTAssertEqual(exportedSnapshot.events.map(\.id), [selectedEvent.id])

        let importFixture = try CalendarFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importCalendarJSONData(data)

        let importedEvent = try XCTUnwrap(importStore.calendarEvents.first { $0.id == selectedEvent.id })
        XCTAssertEqual(importStore.calendarEvents.map(\.id), [selectedEvent.id])
        XCTAssertEqual(importStore.calendars.first { $0.id == team.id }?.name, "Team")
        XCTAssertEqual(importedEvent.title, "Design review")
        XCTAssertEqual(importedEvent.description, "Review native calendar shape.")
        XCTAssertEqual(importedEvent.rrule, "FREQ=WEEKLY;COUNT=2")
        XCTAssertEqual(importedEvent.location, "Studio")
        XCTAssertEqual(importedEvent.reminderMinutesBefore, 30)
        XCTAssertEqual(importedEvent.data, .object(["source": .string("manual")]))
        XCTAssertEqual(importedEvent.meta, .object(["room": .string("A")]))
        XCTAssertEqual(importedEvent.attendees.map(\.userID), ["ada@example.com"])
        XCTAssertEqual(importedEvent.attendees.first?.meta, .object(["role": .string("reviewer")]))
    }

    func testShareCalendarEventSharesSelectedEventJSON() async throws {
        let shareService = FakeCalendarShareService()
        let fixture = try CalendarFixture(shareService: shareService)
        let team = AppCalendar(id: "team-calendar", name: "Team", color: "#22c55e")
        let selectedEvent = AppCalendarEvent(
            id: "daily-summary",
            calendarID: team.id,
            title: "Daily summary",
            description: "Summarize yesterday's notes.",
            startAt: Date(timeIntervalSince1970: 1_000),
            endAt: Date(timeIntervalSince1970: 1_600),
            location: "Remote"
        )
        let otherEvent = AppCalendarEvent(
            id: "weekly-plan",
            calendarID: team.id,
            title: "Weekly plan",
            startAt: Date(timeIntervalSince1970: 2_000)
        )
        try await fixture.calendarStorage.saveSnapshot(CalendarSnapshot(calendars: [team], events: [selectedEvent, otherEvent]))
        let store = fixture.makeStore()
        await store.load()

        store.shareCalendarEvent(selectedEvent.id)

        XCTAssertEqual(shareService.sharedTitle, "Daily summary")
        let sharedText = try XCTUnwrap(shareService.sharedText)
        let sharedSnapshot = try CalendarExportService().snapshot(fromJSONData: Data(sharedText.utf8))
        XCTAssertEqual(sharedSnapshot.calendars.map(\.name), ["Team"])
        XCTAssertEqual(sharedSnapshot.events.map(\.title), ["Daily summary"])
        XCTAssertEqual(sharedSnapshot.events.first?.description, "Summarize yesterday's notes.")
        XCTAssertEqual(sharedSnapshot.events.first?.location, "Remote")
    }

    func testImportCalendarJSONAcceptsOpenWebUICalendarAndEventRecords() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            {
              "calendars": [
                {
                  "id": "calendar-id",
                  "user_id": "user-id",
                  "name": "Imported",
                  "color": "#f97316",
                  "is_default": true,
                  "is_system": false,
                  "data": {},
                  "meta": {
                    "source": "open-webui"
                  },
                  "created_at": 1000000000,
                  "updated_at": 2000000000
                }
              ],
              "events": [
                {
                  "id": "event-id",
                  "calendar_id": "calendar-id",
                  "user_id": "user-id",
                  "title": "Imported event",
                  "description": "From Open WebUI.",
                  "start_at": 3000000000,
                  "end_at": 4000000000,
                  "all_day": false,
                  "rrule": "FREQ=WEEKLY",
                  "color": "#f97316",
                  "location": "Remote",
                  "data": {},
                  "meta": {
                    "alert_minutes": 10
                  },
                  "is_cancelled": false,
                  "attendees": [
                    {
                      "id": "attendee-id",
                      "event_id": "event-id",
                      "user_id": "attendee-user",
                      "status": "accepted",
                      "meta": {},
                      "created_at": 5000000000,
                      "updated_at": 6000000000
                    }
                  ],
                  "created_at": 7000000000,
                  "updated_at": 8000000000
                }
              ]
            }
            """.utf8
        )

        try await store.importCalendarJSONData(data)

        let calendar = try XCTUnwrap(store.calendars.first { $0.id == "calendar-id" })
        XCTAssertEqual(calendar.name, "Imported")
        XCTAssertEqual(calendar.meta, .object(["source": .string("open-webui")]))

        let event = try XCTUnwrap(store.calendarEvents.first { $0.id == "event-id" })
        XCTAssertEqual(event.calendarID, "calendar-id")
        XCTAssertEqual(event.title, "Imported event")
        XCTAssertEqual(event.reminderMinutesBefore, 10)
        XCTAssertEqual(event.startAt, Date(timeIntervalSince1970: 3))
        XCTAssertEqual(event.endAt, Date(timeIntervalSince1970: 4))
        XCTAssertEqual(event.rrule, "FREQ=WEEKLY")
        XCTAssertEqual(event.attendees.first?.userID, "attendee-user")
        XCTAssertEqual(event.attendees.first?.status, "accepted")
    }

    func testCalendarWritePermissionAllowsCalendarEventAttendeeDeleteAndImportForCurrentUser() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(name: "Calendar Editors", description: "Can manage calendar.", permissions: ["calendar.write"])
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id

        await store.createCalendar(name: "Team", color: "#22c55e")
        let team = try XCTUnwrap(store.calendars.first { $0.name == "Team" })
        await store.createCalendarEvent(
            calendarID: team.id,
            title: "Design review",
            description: "Review native calendar.",
            startAt: Date(timeIntervalSince1970: 1_000),
            endAt: Date(timeIntervalSince1970: 1_600),
            allDay: false,
            location: "Studio"
        )
        let event = try XCTUnwrap(store.calendarEvents.first)
        await store.updateCalendarEvent(
            event.id,
            calendarID: team.id,
            title: "Updated review",
            description: "Updated details.",
            startAt: Date(timeIntervalSince1970: 2_000),
            endAt: Date(timeIntervalSince1970: 2_600),
            allDay: false,
            location: "Room 4",
            isCancelled: true
        )
        await store.addCalendarEventAttendee(eventID: event.id, userID: "ada@example.com", status: "accepted")
        let attendee = try XCTUnwrap(store.calendarEvents.first?.attendees.first)
        await store.updateCalendarEventAttendee(eventID: event.id, attendeeID: attendee.id, status: "declined")
        await store.removeCalendarEventAttendee(eventID: event.id, attendeeID: attendee.id)
        await store.deleteCalendarEvent(event.id)
        await store.deleteCalendar(team.id)

        let data = try CalendarExportService().jsonData(for: CalendarSnapshot(
            calendars: [AppCalendar(id: "imported-calendar", name: "Imported")],
            events: [
                AppCalendarEvent(
                    id: "imported-event",
                    calendarID: "imported-calendar",
                    title: "Imported event",
                    startAt: Date(timeIntervalSince1970: 3_000)
                )
            ]
        ))
        try await store.importCalendarJSONData(data)

        XCTAssertEqual(Set(store.calendars.map(\.name)), ["Personal", "Imported"])
        XCTAssertEqual(store.calendarEvents.map(\.title), ["Imported event"])
        XCTAssertNil(store.errorMessage)
    }

    func testCalendarWritePermissionBlocksCalendarEventAttendeeDeleteAndImportForCurrentUser() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        store.currentUserID = user.id
        let personal = try XCTUnwrap(store.calendars.first)

        await store.createCalendar(name: "Blocked", color: "#ef4444")

        XCTAssertEqual(store.calendars.map(\.name), ["Personal"])
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage calendar.")

        store.errorMessage = nil
        store.currentUserID = "local-admin"
        await store.createAdminUser(name: "Local Admin", email: "admin@example.com", role: .admin)
        let admin = try XCTUnwrap(store.adminUsers.first { $0.role == .admin })
        store.currentUserID = admin.id
        await store.createCalendar(name: "Team", color: "#22c55e")
        let team = try XCTUnwrap(store.calendars.first { $0.name == "Team" })
        await store.createCalendarEvent(
            calendarID: team.id,
            title: "Existing event",
            description: "Existing details.",
            startAt: Date(timeIntervalSince1970: 1_000),
            endAt: nil,
            allDay: false,
            location: "Studio"
        )
        let event = try XCTUnwrap(store.calendarEvents.first)
        await store.addCalendarEventAttendee(eventID: event.id, userID: "ada@example.com", status: "accepted")
        let attendee = try XCTUnwrap(store.calendarEvents.first?.attendees.first)
        let importData = try CalendarExportService().jsonData(for: CalendarSnapshot(
            calendars: [AppCalendar(id: "blocked-import", name: "Blocked Import")],
            events: [
                AppCalendarEvent(
                    id: "blocked-event",
                    calendarID: "blocked-import",
                    title: "Blocked imported event",
                    startAt: Date(timeIntervalSince1970: 3_000)
                )
            ]
        ))

        store.currentUserID = user.id
        await store.createCalendarEvent(
            calendarID: personal.id,
            title: "Blocked event",
            description: nil,
            startAt: Date(timeIntervalSince1970: 2_000),
            endAt: nil,
            allDay: false,
            location: nil
        )
        await store.updateCalendarEvent(
            event.id,
            calendarID: team.id,
            title: "Blocked update",
            description: "Blocked details.",
            startAt: Date(timeIntervalSince1970: 2_000),
            endAt: nil,
            allDay: true,
            location: "Blocked",
            isCancelled: true
        )
        await store.addCalendarEventAttendee(eventID: event.id, userID: "grace@example.com", status: "pending")
        await store.updateCalendarEventAttendee(eventID: event.id, attendeeID: attendee.id, status: "declined")
        await store.removeCalendarEventAttendee(eventID: event.id, attendeeID: attendee.id)
        try await store.importCalendarJSONData(importData)
        await store.deleteCalendarEvent(event.id)
        await store.deleteCalendar(team.id)

        let unchangedEvent = try XCTUnwrap(store.calendarEvents.first)
        XCTAssertEqual(store.calendars.map(\.name).sorted(), ["Personal", "Team"])
        XCTAssertEqual(store.calendarEvents.count, 1)
        XCTAssertEqual(unchangedEvent.title, "Existing event")
        XCTAssertEqual(unchangedEvent.description, "Existing details.")
        XCTAssertFalse(unchangedEvent.isCancelled)
        XCTAssertEqual(unchangedEvent.attendees.map(\.userID), ["ada@example.com"])
        XCTAssertEqual(unchangedEvent.attendees.map(\.status), ["accepted"])
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage calendar.")

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        let reloadedEvent = try XCTUnwrap(reloadedStore.calendarEvents.first)
        XCTAssertEqual(reloadedStore.calendars.map(\.name).sorted(), ["Personal", "Team"])
        XCTAssertEqual(reloadedStore.calendarEvents.count, 1)
        XCTAssertEqual(reloadedEvent.title, "Existing event")
        XCTAssertEqual(reloadedEvent.attendees.map(\.status), ["accepted"])
    }

    func testUnmanagedLocalUserCanManageCalendarWhenAdminDirectoryExists() async throws {
        let fixture = try CalendarFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)

        await store.createCalendar(name: "Local", color: "#3b82f6")

        XCTAssertEqual(Set(store.calendars.map(\.name)), ["Personal", "Local"])
        XCTAssertNil(store.errorMessage)
    }
}

private struct CalendarFixture {
    let rootURL: URL
    let storage: JSONStorageService
    let folderStorage: JSONFolderStorageService
    let settingsStore: SettingsStore
    let calendarStorage: JSONCalendarStorageService
    let auditStorage: JSONAuditLogStorageService
    let adminStorage: JSONAdminDirectoryStorageService
    let reminderDeliverer: any CalendarReminderDelivering
    let shareService: FakeCalendarShareService?

    init(
        reminderDeliverer: any CalendarReminderDelivering = CapturingCalendarReminderDeliverer(),
        shareService: FakeCalendarShareService? = nil
    ) throws {
        self.reminderDeliverer = reminderDeliverer
        self.shareService = shareService
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        folderStorage = JSONFolderStorageService(rootURL: rootURL.appendingPathComponent("Folders", isDirectory: true))
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        calendarStorage = JSONCalendarStorageService(
            snapshotURL: rootURL.appendingPathComponent("calendar.json")
        )
        auditStorage = JSONAuditLogStorageService(
            rootURL: rootURL.appendingPathComponent("AuditLog", isDirectory: true)
        )
        adminStorage = JSONAdminDirectoryStorageService(
            snapshotURL: rootURL.appendingPathComponent("admin-directory.json")
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore() -> AppStore {
        AppStore(
            storage: storage,
            folderStorage: folderStorage,
            settingsStore: settingsStore,
            secretStore: InMemorySecretStore(),
            shareService: shareService ?? FakeCalendarShareService(),
            auditLogStorage: auditStorage,
            calendarReminderDeliverer: reminderDeliverer,
            adminDirectoryStorage: adminStorage,
            calendarStorage: calendarStorage
        )
    }
}

@MainActor
private final class FakeCalendarShareService: ChatSharing {
    private(set) var sharedText: String?
    private(set) var sharedTitle: String?

    func share(text: String, title: String) {
        sharedText = text
        sharedTitle = title
    }
}

private final class CapturingCalendarReminderDeliverer: CalendarReminderDelivering {
    private(set) var requests: [CalendarReminderNotificationRequest] = []

    func deliver(_ requests: [CalendarReminderNotificationRequest]) async throws {
        self.requests.append(contentsOf: requests)
    }
}
