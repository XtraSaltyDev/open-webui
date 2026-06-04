import SwiftUI

struct CalendarSidebarView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        let canManageCalendar = store.currentUserCanManageCalendar

        Button {
            store.selectCalendarDashboard()
        } label: {
            Label("Calendar", systemImage: "calendar")
        }
        .buttonStyle(.plain)

        HStack {
            Button {
                store.importCalendarJSONWithOpenPanel()
            } label: {
                Label("Import Calendar", systemImage: "square.and.arrow.down")
            }
            .help("Import calendar JSON")
            .disabled(!canManageCalendar)

            Menu {
                Button("Native JSON") {
                    store.exportCalendarJSONWithSavePanel()
                }

                Button("Open WebUI JSON") {
                    store.exportCalendarOpenWebUIJSONWithSavePanel()
                }
            } label: {
                Label("Export Calendar", systemImage: "square.and.arrow.up")
            }
            .help("Export calendar JSON")
            .disabled(store.calendars.isEmpty && store.calendarEvents.isEmpty)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.caption)
    }
}

struct CalendarDashboardView: View {
    @ObservedObject var store: AppStore
    @State private var eventEditorMode: CalendarEventEditorMode?
    @State private var newCalendarName = ""
    @State private var newCalendarColor = "#3b82f6"
    @State private var newCalendarAllowedUserIDs = ""
    @State private var newCalendarAllowedGroupIDs = ""
    @State private var visibleCalendarDate = Date()
    @State private var calendarDisplayMode: CalendarDisplayMode = .month

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Divider()

            HSplitView {
                calendarList
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

                calendarContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(item: $eventEditorMode) { mode in
            CalendarEventEditorSheet(
                mode: mode,
                calendars: store.visibleCalendars.filter { !$0.isSystem },
                onSave: { calendarID, title, description, startAt, endAt, allDay, location, rrule, isCancelled, reminderMinutesBefore, attendees in
                    Task {
                        switch mode {
                        case .create:
                            await store.createCalendarEvent(
                                calendarID: calendarID,
                                title: title,
                                description: description,
                                startAt: startAt,
                                endAt: endAt,
                                allDay: allDay,
                                location: location,
                                reminderMinutesBefore: reminderMinutesBefore,
                                rrule: rrule
                            )
                        case .edit(let event):
                            await store.updateCalendarEvent(
                                event.id,
                                calendarID: calendarID,
                                title: title,
                                description: description,
                                startAt: startAt,
                                endAt: endAt,
                                allDay: allDay,
                                location: location,
                                isCancelled: isCancelled,
                                reminderMinutesBefore: reminderMinutesBefore,
                                rrule: rrule
                            )
                            await reconcileAttendees(for: event, editedAttendees: attendees)
                        }
                        eventEditorMode = nil
                    }
                },
                onCancel: {
                    eventEditorMode = nil
                },
                onDelete: { event in
                    Task {
                        await store.deleteCalendarEvent(event.id)
                        eventEditorMode = nil
                    }
                }
            )
        }
    }

    private var header: some View {
        let canManageCalendar = store.currentUserCanManageCalendar

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Calendar")
                    .font(.title2.weight(.semibold))
                Text("\(store.calendarEvents.count) events across \(store.visibleCalendars.count) calendars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                eventEditorMode = .create(defaultCalendarID: defaultEditableCalendarID)
            } label: {
                Label("New Event", systemImage: "calendar.badge.plus")
            }
            .disabled(!canManageCalendar || store.calendars.isEmpty)

            Button {
                store.importCalendarJSONWithOpenPanel()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .disabled(!canManageCalendar)

            Menu {
                Button("Native JSON") {
                    store.exportCalendarJSONWithSavePanel()
                }

                Button("Open WebUI JSON") {
                    store.exportCalendarOpenWebUIJSONWithSavePanel()
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(store.calendars.isEmpty && store.calendarEvents.isEmpty)
        }
    }

    private var calendarList: some View {
        let canManageCalendar = store.currentUserCanManageCalendar

        return VStack(alignment: .leading, spacing: 12) {
            Text("Calendars")
                .font(.headline)

            if store.calendars.isEmpty {
                Text("No calendars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.visibleCalendars) { calendar in
                    CalendarRow(
                        calendar: calendar,
                        eventCount: eventCount(for: calendar),
                        isSelected: store.selectedCalendarID == calendar.id,
                        canManageCalendar: canManageCalendar,
                        onSelect: {
                            store.selectedCalendarID = calendar.id
                        },
                        onDelete: {
                            Task {
                                await store.deleteCalendar(calendar.id)
                            }
                        }
                    )
                }
            }

            Divider()

            TextField("New calendar", text: $newCalendarName)
                .textFieldStyle(.roundedBorder)

            TextField("Allowed user IDs", text: $newCalendarAllowedUserIDs)
                .textFieldStyle(.roundedBorder)

            TextField("Allowed group IDs", text: $newCalendarAllowedGroupIDs)
                .textFieldStyle(.roundedBorder)

            HStack {
                TextField("Color", text: $newCalendarColor)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task {
                        await store.createCalendar(
                            name: newCalendarName,
                            color: newCalendarColor,
                            allowedUserIDs: parsedCommaSeparatedValues(newCalendarAllowedUserIDs),
                            allowedGroupIDs: parsedCommaSeparatedValues(newCalendarAllowedGroupIDs)
                        )
                        newCalendarName = ""
                        newCalendarAllowedUserIDs = ""
                        newCalendarAllowedGroupIDs = ""
                    }
                } label: {
                    Label("Add Calendar", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .disabled(!canManageCalendar || newCalendarName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Spacer()
        }
        .padding(16)
    }

    private var calendarContent: some View {
        let events = agendaEvents
        let canManageCalendar = store.currentUserCanManageCalendar

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search events", text: $store.calendarSearchText)
                            .textFieldStyle(.plain)
                        if !store.calendarSearchText.isEmpty {
                            Button {
                                store.calendarSearchText = ""
                            } label: {
                                Label("Clear Search", systemImage: "xmark.circle.fill")
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Clear search")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .frame(maxWidth: 360)

                    Spacer()

                    Picker("Calendar View", selection: $calendarDisplayMode) {
                        ForEach(CalendarDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }

                switch calendarDisplayMode {
                case .month:
                    CalendarMonthGridView(
                        grid: store.calendarMonthGrid(containing: visibleCalendarDate),
                        calendars: store.visibleCalendars,
                        visibleMonthDate: $visibleCalendarDate,
                        canManageCalendar: canManageCalendar,
                        canShareEvent: canShareEvent,
                        onEdit: { event in
                            editEvent(event)
                        },
                        onShare: { event in
                            shareEvent(event)
                        }
                    )
                case .week:
                    CalendarWeekGridView(
                        grid: store.calendarWeekGrid(containing: visibleCalendarDate),
                        calendars: store.visibleCalendars,
                        visibleWeekDate: $visibleCalendarDate,
                        canManageCalendar: canManageCalendar,
                        canShareEvent: canShareEvent,
                        onEdit: { event in
                            editEvent(event)
                        },
                        onShare: { event in
                            shareEvent(event)
                        }
                    )
                case .day:
                    CalendarDayScheduleView(
                        schedule: store.calendarDaySchedule(containing: visibleCalendarDate),
                        calendars: store.visibleCalendars,
                        visibleDayDate: $visibleCalendarDate,
                        canManageCalendar: canManageCalendar,
                        canShareEvent: canShareEvent,
                        onEdit: { event in
                            editEvent(event)
                        },
                        onShare: { event in
                            shareEvent(event)
                        }
                    )
                }

                Text("Agenda")
                    .font(.headline)
                    .padding(.top, 6)

                if events.isEmpty {
                    ContentUnavailableView(
                        "No Events",
                        systemImage: "calendar",
                        description: Text("Create events or import calendar JSON to populate this calendar.")
                    )
                } else {
                    ForEach(events.sorted { $0.startAt < $1.startAt }) { event in
                        CalendarEventRow(
                            event: event,
                            calendar: store.visibleCalendars.first { $0.id == event.calendarID },
                            canManageCalendar: canManageCalendar,
                            canShare: canShareEvent(event),
                            onEdit: {
                                editEvent(event)
                            },
                            onShare: {
                                shareEvent(event)
                            }
                        )
                    }
                }
            }
            .padding(20)
        }
    }

    private var agendaEvents: [AppCalendarEvent] {
        let calendarIDs = store.selectedCalendarID.map { Set([$0]) }
        return store.filteredCalendarEvents(in: agendaDateRange, calendarIDs: calendarIDs)
    }

    private var agendaDateRange: ClosedRange<Date> {
        let calendar = Calendar.autoupdatingCurrent
        switch calendarDisplayMode {
        case .month:
            let components = calendar.dateComponents([.year, .month], from: visibleCalendarDate)
            let start = calendar.date(from: components).map(calendar.startOfDay) ?? calendar.startOfDay(for: visibleCalendarDate)
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return start...end
        case .week:
            let dayStart = calendar.startOfDay(for: visibleCalendarDate)
            let weekday = calendar.component(.weekday, from: dayStart)
            let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
            let start = calendar.date(byAdding: .day, value: -leadingDays, to: dayStart) ?? dayStart
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            return start...end
        case .day:
            let start = calendar.startOfDay(for: visibleCalendarDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return start...end
        }
    }

    private func eventCount(for calendar: AppCalendar) -> Int {
        if calendar.id == AppCalendar.scheduledTasksCalendarID {
            return store.automations.filter(\.isActive).count
        }
        return store.calendarEvents.filter { $0.calendarID == calendar.id }.count
    }

    private func editEvent(_ event: AppCalendarEvent) {
        guard store.currentUserCanManageCalendar,
              event.calendarID != AppCalendar.scheduledTasksCalendarID else {
            return
        }
        eventEditorMode = .edit(event)
    }

    private func shareEvent(_ event: AppCalendarEvent) {
        guard canShareEvent(event) else {
            return
        }
        store.shareCalendarEvent(event.id)
    }

    private func canShareEvent(_ event: AppCalendarEvent) -> Bool {
        event.calendarID != AppCalendar.scheduledTasksCalendarID
    }

    private var defaultEditableCalendarID: String {
        if let selectedCalendarID = store.selectedCalendarID,
           store.calendars.contains(where: { $0.id == selectedCalendarID }) {
            return selectedCalendarID
        }
        return store.calendars.first?.id ?? ""
    }

    private func reconcileAttendees(for event: AppCalendarEvent, editedAttendees: [AppCalendarEventAttendee]) async {
        let editedIDs = Set(editedAttendees.map(\.id))
        for attendee in event.attendees where !editedIDs.contains(attendee.id) {
            await store.removeCalendarEventAttendee(eventID: event.id, attendeeID: attendee.id)
        }

        let existingIDs = Set(event.attendees.map(\.id))
        for attendee in editedAttendees {
            if existingIDs.contains(attendee.id) {
                await store.updateCalendarEventAttendee(eventID: event.id, attendeeID: attendee.id, status: attendee.status)
            } else {
                await store.addCalendarEventAttendee(eventID: event.id, userID: attendee.userID, status: attendee.status)
            }
        }
    }
}

private enum CalendarDisplayMode: String, CaseIterable, Identifiable {
    case month
    case week
    case day

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month:
            "Month"
        case .week:
            "Week"
        case .day:
            "Day"
        }
    }
}

private struct CalendarMonthGridView: View {
    var grid: CalendarMonthGrid
    var calendars: [AppCalendar]
    @Binding var visibleMonthDate: Date
    var canManageCalendar: Bool
    var canShareEvent: (AppCalendarEvent) -> Bool
    var onEdit: (AppCalendarEvent) -> Void
    var onShare: (AppCalendarEvent) -> Void

    private let columns = Array(repeating: GridItem(.flexible(minimum: 70), spacing: 8), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(monthTitle)
                    .font(.title3.weight(.semibold))

                Spacer()

                Button {
                    moveMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Previous month")

                Button("Today") {
                    visibleMonthDate = Date()
                }

                Button {
                    moveMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Next month")
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(grid.days, id: \.date) { day in
                    CalendarMonthGridDayCell(
                        day: day,
                        calendars: calendars,
                        canManageCalendar: canManageCalendar,
                        canShareEvent: canShareEvent,
                        onEdit: onEdit,
                        onShare: onShare
                    )
                }
            }
        }
    }

    private var monthTitle: String {
        grid.displayedMonthStart.formatted(.dateTime.month(.wide).year())
    }

    private var weekdaySymbols: [String] {
        let symbols = grid.calendar.shortStandaloneWeekdaySymbols
        let firstIndex = max(grid.calendar.firstWeekday - 1, 0)
        return Array(symbols[firstIndex...] + symbols[..<firstIndex])
    }

    private func moveMonth(by value: Int) {
        visibleMonthDate = grid.calendar.date(byAdding: .month, value: value, to: visibleMonthDate) ?? visibleMonthDate
    }
}

private struct CalendarMonthGridDayCell: View {
    var day: CalendarMonthGridDay
    var calendars: [AppCalendar]
    var canManageCalendar: Bool
    var canShareEvent: (AppCalendarEvent) -> Bool
    var onEdit: (AppCalendarEvent) -> Void
    var onShare: (AppCalendarEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(day.date.formatted(.dateTime.day()))
                .font(.caption.weight(day.isInDisplayedMonth ? .semibold : .regular))
                .foregroundStyle(day.isInDisplayedMonth ? Color.primary : Color.secondary)

            ForEach(day.events.prefix(3)) { event in
                Button {
                    if canManageCalendar {
                        onEdit(event)
                    } else if canShareEvent(event) {
                        onShare(event)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(color(from: calendars.first { $0.id == event.calendarID }?.color))
                            .frame(width: 6, height: 6)
                        Text(event.title)
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(event.isCancelled ? .secondary : .primary)
                }
                .buttonStyle(.plain)
                .disabled(!canManageCalendar && !canShareEvent(event))
                .contextMenu {
                    if canManageCalendar {
                        Button("Edit Event", systemImage: "pencil") {
                            onEdit(event)
                        }
                    }
                    if canShareEvent(event) {
                        Button("Share Event", systemImage: "square.and.arrow.up") {
                            onShare(event)
                        }
                    }
                }
                .help(event.title)
            }

            if day.events.count > 3 {
                Text("+\(day.events.count - 3) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(7)
        .frame(minHeight: 92, maxHeight: .infinity, alignment: .topLeading)
        .background(day.isInDisplayedMonth ? Color.secondary.opacity(0.07) : Color.secondary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct CalendarWeekGridView: View {
    var grid: CalendarWeekGrid
    var calendars: [AppCalendar]
    @Binding var visibleWeekDate: Date
    var canManageCalendar: Bool
    var canShareEvent: (AppCalendarEvent) -> Bool
    var onEdit: (AppCalendarEvent) -> Void
    var onShare: (AppCalendarEvent) -> Void

    private let columns = Array(repeating: GridItem(.flexible(minimum: 96), spacing: 8), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(weekTitle)
                    .font(.title3.weight(.semibold))

                Spacer()

                Button {
                    moveWeek(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Previous week")

                Button("Today") {
                    visibleWeekDate = Date()
                }

                Button {
                    moveWeek(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Next week")
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(grid.days, id: \.date) { day in
                    CalendarWeekGridDayCell(
                        day: day,
                        calendars: calendars,
                        canManageCalendar: canManageCalendar,
                        canShareEvent: canShareEvent,
                        onEdit: onEdit,
                        onShare: onShare
                    )
                }
            }
        }
    }

    private var weekTitle: String {
        guard let weekEnd = grid.calendar.date(byAdding: .day, value: 6, to: grid.weekStart) else {
            return grid.weekStart.formatted(.dateTime.month(.abbreviated).day().year())
        }
        return "\(grid.weekStart.formatted(.dateTime.month(.abbreviated).day())) - \(weekEnd.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    private func moveWeek(by value: Int) {
        visibleWeekDate = grid.calendar.date(byAdding: .day, value: value * 7, to: visibleWeekDate) ?? visibleWeekDate
    }
}

private struct CalendarWeekGridDayCell: View {
    var day: CalendarWeekGridDay
    var calendars: [AppCalendar]
    var canManageCalendar: Bool
    var canShareEvent: (AppCalendarEvent) -> Bool
    var onEdit: (AppCalendarEvent) -> Void
    var onShare: (AppCalendarEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(day.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.headline)
            }

            ForEach(day.events) { event in
                Button {
                    if canManageCalendar {
                        onEdit(event)
                    } else if canShareEvent(event) {
                        onShare(event)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(color(from: calendars.first { $0.id == event.calendarID }?.color))
                                .frame(width: 7, height: 7)
                            Text(event.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                        }
                        Text(eventTimeSummary(event))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(event.isCancelled ? 0.04 : 0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(!canManageCalendar && !canShareEvent(event))
                .contextMenu {
                    if canManageCalendar {
                        Button("Edit Event", systemImage: "pencil") {
                            onEdit(event)
                        }
                    }
                    if canShareEvent(event) {
                        Button("Share Event", systemImage: "square.and.arrow.up") {
                            onShare(event)
                        }
                    }
                }
                .help(event.title)
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(minHeight: 220, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func eventTimeSummary(_ event: AppCalendarEvent) -> String {
        if event.allDay {
            return "All day"
        }
        if let endAt = event.endAt {
            return "\(event.startAt.formatted(.dateTime.hour().minute())) - \(endAt.formatted(.dateTime.hour().minute()))"
        }
        return event.startAt.formatted(.dateTime.hour().minute())
    }
}

private struct CalendarDayScheduleView: View {
    var schedule: CalendarDaySchedule
    var calendars: [AppCalendar]
    @Binding var visibleDayDate: Date
    var canManageCalendar: Bool
    var canShareEvent: (AppCalendarEvent) -> Bool
    var onEdit: (AppCalendarEvent) -> Void
    var onShare: (AppCalendarEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(dayTitle)
                    .font(.title3.weight(.semibold))

                Spacer()

                Button {
                    moveDay(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Previous day")

                Button("Today") {
                    visibleDayDate = Date()
                }

                Button {
                    moveDay(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Next day")
            }

            if !schedule.allDayEvents.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("All Day")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(schedule.allDayEvents) { event in
                        CalendarDayEventButton(
                            event: event,
                            calendar: calendars.first { $0.id == event.calendarID },
                            canManageCalendar: canManageCalendar,
                            canShareEvent: canShareEvent,
                            onEdit: onEdit,
                            onShare: onShare
                        )
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(schedule.hourSlots, id: \.hour) { slot in
                    CalendarDayHourRow(
                        slot: slot,
                        calendars: calendars,
                        canManageCalendar: canManageCalendar,
                        canShareEvent: canShareEvent,
                        onEdit: onEdit,
                        onShare: onShare
                    )
                }
            }
        }
    }

    private var dayTitle: String {
        schedule.dayStart.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    private func moveDay(by value: Int) {
        visibleDayDate = schedule.calendar.date(byAdding: .day, value: value, to: visibleDayDate) ?? visibleDayDate
    }
}

private struct CalendarDayHourRow: View {
    var slot: CalendarDayHourSlot
    var calendars: [AppCalendar]
    var canManageCalendar: Bool
    var canShareEvent: (AppCalendarEvent) -> Bool
    var onEdit: (AppCalendarEvent) -> Void
    var onShare: (AppCalendarEvent) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(slot.startAt.formatted(.dateTime.hour()))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                if slot.events.isEmpty {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.08))
                        .frame(height: 1)
                        .padding(.top, 14)
                } else {
                    ForEach(slot.events) { event in
                        CalendarDayEventButton(
                            event: event,
                            calendar: calendars.first { $0.id == event.calendarID },
                            canManageCalendar: canManageCalendar,
                            canShareEvent: canShareEvent,
                            onEdit: onEdit,
                            onShare: onShare
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .frame(minHeight: 42, alignment: .top)
    }
}

private struct CalendarDayEventButton: View {
    var event: AppCalendarEvent
    var calendar: AppCalendar?
    var canManageCalendar: Bool
    var canShareEvent: (AppCalendarEvent) -> Bool
    var onEdit: (AppCalendarEvent) -> Void
    var onShare: (AppCalendarEvent) -> Void

    var body: some View {
        Button {
            if canManageCalendar {
                onEdit(event)
            } else if canShareEvent(event) {
                onShare(event)
            }
        } label: {
            HStack(alignment: .top, spacing: 7) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(from: calendar?.color))
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(timeSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(event.isCancelled ? 0.04 : 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!canManageCalendar && !canShareEvent(event))
        .contextMenu {
            if canManageCalendar {
                Button("Edit Event", systemImage: "pencil") {
                    onEdit(event)
                }
            }
            if canShareEvent(event) {
                Button("Share Event", systemImage: "square.and.arrow.up") {
                    onShare(event)
                }
            }
        }
        .help(event.title)
    }

    private var timeSummary: String {
        if event.allDay {
            return "All day"
        }
        if let endAt = event.endAt {
            return "\(event.startAt.formatted(.dateTime.hour().minute())) - \(endAt.formatted(.dateTime.hour().minute()))"
        }
        return event.startAt.formatted(.dateTime.hour().minute())
    }
}

private struct CalendarRow: View {
    var calendar: AppCalendar
    var eventCount: Int
    var isSelected: Bool
    var canManageCalendar: Bool
    var onSelect: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                onSelect()
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(color(from: calendar.color))
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(calendar.name)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .lineLimit(1)
                        Text("\(eventCount) events")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if calendar.isDefault {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .help("Default calendar")
            }

            if !calendar.isDefault && !calendar.isSystem {
                Button {
                    onDelete()
                } label: {
                    Label("Delete Calendar", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(!canManageCalendar)
                .help("Delete calendar")
            }
        }
        .padding(8)
        .background(isSelected ? Color.secondary.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct CalendarEventRow: View {
    var event: AppCalendarEvent
    var calendar: AppCalendar?
    var canManageCalendar: Bool
    var canShare: Bool
    var onEdit: () -> Void
    var onShare: () -> Void

    var body: some View {
        Button {
            if canManageCalendar {
                onEdit()
            } else if canShare {
                onShare()
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(timeSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if canShare {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Share event")
                    }

                    if event.isCancelled {
                        Text("Cancelled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let description = event.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    if let calendar {
                        Label(calendar.name, systemImage: "calendar")
                    }
                    if let location = event.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                    }
                    if let rrule = event.rrule, !rrule.isEmpty {
                        Label(rrule, systemImage: "repeat")
                    }
                    if let reminderMinutesBefore = event.reminderMinutesBefore {
                        Label("\(reminderMinutesBefore)m", systemImage: "bell")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!canManageCalendar && !canShare)
        .contextMenu {
            if canManageCalendar {
                Button("Edit Event", systemImage: "pencil") {
                    onEdit()
                }
            }
            if canShare {
                Button("Share Event", systemImage: "square.and.arrow.up") {
                    onShare()
                }
            }
        }
    }

    private var timeSummary: String {
        if event.allDay {
            return "\(event.startAt.formatted(date: .abbreviated, time: .omitted)) - All day"
        }
        if let endAt = event.endAt {
            return "\(event.startAt.formatted(date: .abbreviated, time: .shortened)) - \(endAt.formatted(date: .omitted, time: .shortened))"
        }
        return event.startAt.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct CalendarEventEditorSheet: View {
    var mode: CalendarEventEditorMode
    var calendars: [AppCalendar]
    var onSave: (String, String, String?, Date, Date?, Bool, String?, String?, Bool, Int?, [AppCalendarEventAttendee]) -> Void
    var onCancel: () -> Void
    var onDelete: (AppCalendarEvent) -> Void

    @State private var calendarID: String
    @State private var title: String
    @State private var description: String
    @State private var startAt: Date
    @State private var endAt: Date
    @State private var hasEndDate: Bool
    @State private var allDay: Bool
    @State private var location: String
    @State private var rrule: String
    @State private var isCancelled: Bool
    @State private var hasReminder: Bool
    @State private var reminderMinutesBefore: Int
    @State private var attendees: [AppCalendarEventAttendee]
    @State private var newAttendeeUserID: String
    @State private var newAttendeeStatus: String

    init(
        mode: CalendarEventEditorMode,
        calendars: [AppCalendar],
        onSave: @escaping (String, String, String?, Date, Date?, Bool, String?, String?, Bool, Int?, [AppCalendarEventAttendee]) -> Void,
        onCancel: @escaping () -> Void,
        onDelete: @escaping (AppCalendarEvent) -> Void
    ) {
        self.mode = mode
        self.calendars = calendars
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
        switch mode {
        case .create(let defaultCalendarID):
            _calendarID = State(initialValue: defaultCalendarID)
            _title = State(initialValue: "")
            _description = State(initialValue: "")
            _startAt = State(initialValue: Date())
            _endAt = State(initialValue: Date().addingTimeInterval(3_600))
            _hasEndDate = State(initialValue: true)
            _allDay = State(initialValue: false)
            _location = State(initialValue: "")
            _rrule = State(initialValue: "")
            _isCancelled = State(initialValue: false)
            _hasReminder = State(initialValue: false)
            _reminderMinutesBefore = State(initialValue: 30)
            _attendees = State(initialValue: [])
            _newAttendeeUserID = State(initialValue: "")
            _newAttendeeStatus = State(initialValue: "pending")
        case .edit(let event):
            _calendarID = State(initialValue: event.calendarID)
            _title = State(initialValue: event.title)
            _description = State(initialValue: event.description ?? "")
            _startAt = State(initialValue: event.startAt)
            _endAt = State(initialValue: event.endAt ?? event.startAt.addingTimeInterval(3_600))
            _hasEndDate = State(initialValue: event.endAt != nil)
            _allDay = State(initialValue: event.allDay)
            _location = State(initialValue: event.location ?? "")
            _rrule = State(initialValue: event.rrule ?? "")
            _isCancelled = State(initialValue: event.isCancelled)
            _hasReminder = State(initialValue: event.reminderMinutesBefore != nil)
            _reminderMinutesBefore = State(initialValue: event.reminderMinutesBefore ?? 30)
            _attendees = State(initialValue: event.attendees)
            _newAttendeeUserID = State(initialValue: "")
            _newAttendeeStatus = State(initialValue: "pending")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(mode.title)
                .font(.title3)
                .fontWeight(.semibold)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            Picker("Calendar", selection: $calendarID) {
                ForEach(calendars) { calendar in
                    Text(calendar.name).tag(calendar.id)
                }
            }

            Toggle("All day", isOn: $allDay)

            DatePicker("Starts", selection: $startAt, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])

            Toggle("Ends", isOn: $hasEndDate)
            if hasEndDate {
                DatePicker("Ends at", selection: $endAt, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
            }

            TextField("Location", text: $location)
                .textFieldStyle(.roundedBorder)

            TextField("RRULE", text: $rrule)
                .textFieldStyle(.roundedBorder)

            Toggle("Reminder", isOn: $hasReminder)
            if hasReminder {
                Stepper(value: $reminderMinutesBefore, in: 0...10_080, step: 5) {
                    Text("\(reminderMinutesBefore) min before")
                }
            }

            TextEditor(text: $description)
                .frame(minHeight: 90)
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(.quaternary)
                }

            if case .edit = mode {
                Toggle("Cancelled", isOn: $isCancelled)
                attendeeEditor
            }

            HStack {
                if case .edit(let event) = mode {
                    Button("Delete", role: .destructive) {
                        onDelete(event)
                    }
                }
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Save") {
                    onSave(
                        calendarID,
                        title,
                        description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description,
                        startAt,
                        hasEndDate ? endAt : nil,
                        allDay,
                        location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : location,
                        rrule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : rrule,
                        isCancelled,
                        hasReminder ? reminderMinutesBefore : nil,
                        attendees
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(calendarID.isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 520)
    }

    private var attendeeEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attendees")
                .font(.headline)

            if attendees.isEmpty {
                Text("No attendees")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach($attendees) { $attendee in
                    HStack(spacing: 8) {
                        Text(attendee.userID)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Picker("Status", selection: $attendee.status) {
                            ForEach(calendarAttendeeStatusOptions, id: \.self) { status in
                                Text(status.capitalized).tag(status)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)

                        Button {
                            attendees.removeAll { $0.id == attendee.id }
                        } label: {
                            Label("Remove Attendee", systemImage: "trash")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Remove attendee")
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("User or email", text: $newAttendeeUserID)
                    .textFieldStyle(.roundedBorder)

                Picker("Status", selection: $newAttendeeStatus) {
                    ForEach(calendarAttendeeStatusOptions, id: \.self) { status in
                        Text(status.capitalized).tag(status)
                    }
                }
                .labelsHidden()
                .frame(width: 130)

                Button {
                    addAttendee()
                } label: {
                    Label("Add Attendee", systemImage: "person.badge.plus")
                }
                .labelStyle(.iconOnly)
                .disabled(newAttendeeUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Add attendee")
            }
        }
    }

    private func addAttendee() {
        let trimmedUserID = newAttendeeUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUserID.isEmpty else {
            return
        }

        if let index = attendees.firstIndex(where: { $0.userID.lowercased() == trimmedUserID.lowercased() }) {
            attendees[index].status = newAttendeeStatus
            attendees[index].updatedAt = Date()
        } else {
            let eventID: String
            if case .edit(let event) = mode {
                eventID = event.id
            } else {
                eventID = ""
            }
            attendees.append(
                AppCalendarEventAttendee(
                    eventID: eventID,
                    userID: trimmedUserID,
                    status: newAttendeeStatus
                )
            )
        }
        newAttendeeUserID = ""
        newAttendeeStatus = "pending"
    }
}

private let calendarAttendeeStatusOptions = [
    "pending",
    "accepted",
    "declined",
    "tentative"
]

private enum CalendarEventEditorMode: Identifiable {
    case create(defaultCalendarID: String)
    case edit(AppCalendarEvent)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let event):
            return event.id
        }
    }

    var title: String {
        switch self {
        case .create:
            return "New Event"
        case .edit:
            return "Edit Event"
        }
    }
}

private func color(from hex: String?) -> Color {
    guard let hex else {
        return .accentColor
    }
    let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
        return .accentColor
    }
    return Color(
        red: Double((value >> 16) & 0xff) / 255,
        green: Double((value >> 8) & 0xff) / 255,
        blue: Double(value & 0xff) / 255
    )
}

private func parsedCommaSeparatedValues(_ text: String) -> [String] {
    text.split(separator: ",").map(String.init)
}
