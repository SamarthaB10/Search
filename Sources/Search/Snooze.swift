import AppKit
import SwiftUI
import WebKit

/// A tab's return time and place. Private tabs are kept only in memory.
struct SnoozeRecord: Codable, Identifiable {
    let id: UUID
    let due: Date
    let url: String
    let title: String
    let pin: String?
    let name: String?
    let spaceID: UUID
    let index: Int
    let shy: Bool
    let state: Data?
    let mediaPosition: Double?
}

struct SnoozedTab: Identifiable {
    let record: SnoozeRecord
    let tab: Tab?
    var id: UUID { record.id }
}

enum SnoozeStore {
    private static var file: URL { Store.file("snoozed.json") }

    static func read() -> [SnoozeRecord] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        guard let records = try? JSONDecoder().decode([SnoozeRecord].self, from: data) else {
            Store.quarantine(file)
            return []
        }
        return records.filter { !$0.shy }
    }

    @discardableResult
    static func write(_ records: [SnoozeRecord]) -> Bool {
        do {
            let data = try JSONEncoder().encode(records.filter { !$0.shy })
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            return true
        } catch { return false }
    }
}

extension Browser {
    func armSnoozeAlarm() {
        snoozeAlarm?.invalidate()
        guard let next = snoozed.map(\.record.due).min() else { snoozeAlarm = nil; return }
        let timer = Timer(timeInterval: max(0.1, next.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.restoreDueSnoozes() }
        }
        RunLoop.main.add(timer, forMode: .common)
        snoozeAlarm = timer
    }

    private func snoozeBlocker(for tab: Tab) -> String? {
        guard tabs.contains(where: { $0.id == tab.id }) else { return "Tab is no longer open" }
        if tab.bench { return "Test tabs cannot be snoozed" }
        if tab.isBlank { return "A blank tab has nothing to snooze" }
        if tab.asleep { return nil }
        guard let web = tab.built else { return "This page is not ready" }
        if tab.loading { return "Wait for the page to load" }
        if tab.floating || floating == tab.id { return "This tab has a floating video" }
        if web.cameraCaptureState != .none || web.microphoneCaptureState != .none { return "This tab is on a call" }
        if downloading.contains(where: { $0.webView === web }) { return "This tab is downloading" }
        if active?.opener == tab.id { return "This tab opened the active sign-in page" }
        return nil
    }

    func scheduleSnooze(_ tab: Tab, until due: Date) {
        guard prefs.snoozesTabs, due > Date(), let url = tab.pending ?? tab.address,
              let index = tabs.firstIndex(where: { $0.id == tab.id }) else {
            announce("Choose a future time for an open tab")
            return
        }
        if let reason = snoozeBlocker(for: tab) { announce(reason); return }

        tab.unsaved { [weak self, weak tab] typed in
            guard let self, let tab else { return }
            if typed { self.announce("This tab has text that has not been sent"); return }
            if let reason = self.snoozeBlocker(for: tab) { self.announce(reason); return }
            tab.captureMediaPosition { [weak self, weak tab] position in
                guard let self, let tab else { return }
                let position = position ?? tab.mediaPosition
                tab.built?.pauseAllMediaPlayback()
                // Keep WebKit's history and scroll position for this run. A normal
                // snooze also needs a disk copy before the web view can be closed.
                let state = tab.archivedInteractionState()
                if !tab.shy, state == nil {
                    self.announce("This page cannot keep its place after a restart")
                    return
                }
                let finish: (Data?) -> Void = { [weak self, weak tab] picture in
                    guard let self, let tab else { return }
                    if let reason = self.snoozeBlocker(for: tab) { self.announce(reason); return }
                    let record = SnoozeRecord(
                        id: UUID(), due: due, url: url.absoluteString, title: tab.title,
                        pin: tab.pin, name: tab.name, spaceID: self.spaceID,
                        index: index, shy: tab.shy, state: state, mediaPosition: position
                    )
                    let item = SnoozedTab(record: record, tab: tab)
                    let saved = (self.snoozed + [item]).map(\.record).filter { !$0.shy }
                    guard SnoozeStore.write(saved) else {
                        self.announce("Could not save this snooze")
                        return
                    }
                    if !tab.asleep { tab.sleep(picture: picture) }
                    tab.keepMediaPosition(position)
                    self.snoozed.append(item)
                    self.removeForSnooze(tab)
                    self.armSnoozeAlarm()
                    self.announce("Snoozed until \(due.formatted(date: .abbreviated, time: .shortened))")
                }
                if tab.asleep { finish(nil) } else { tab.snapshot(finish) }
            }
        }
    }

    func restoreDueSnoozes() {
        let due = snoozed.filter { $0.record.due <= Date() }.sorted { $0.record.due < $1.record.due }
        guard !due.isEmpty else { return }
        for item in due { returnSnoozed(item) }
        let ids = Set(due.map(\.id))
        snoozed.removeAll { ids.contains($0.id) }
        SnoozeStore.write(snoozed.map(\.record))
        if spaceID == Space.firstID || prefs.usesSpaces { writeSession(now: true) }
        armSnoozeAlarm()
        announce(due.count == 1 ? "A snoozed tab is back" : "\(due.count) snoozed tabs are back")
    }

    func openSnoozedNow(_ item: SnoozedTab) {
        guard snoozed.contains(where: { $0.id == item.id }) else { return }
        guard item.record.spaceID == spaceID || prefs.usesSpaces else {
            announce("Turn on Spaces to open this tab now")
            return
        }
        if item.record.spaceID != spaceID { switchSpace(to: item.record.spaceID) }
        let returned = returnSnoozed(item)
        snoozed.removeAll { $0.id == item.id }
        SnoozeStore.write(snoozed.map(\.record))
        armSnoozeAlarm()
        if let returned, item.record.spaceID == spaceID { select(returned) }
        writeSession(now: true)
        showingSnoozed = false
    }

    func deleteSnoozed(_ item: SnoozedTab) {
        snoozed.removeAll { $0.id == item.id }
        SnoozeStore.write(snoozed.map(\.record))
        armSnoozeAlarm()
        writeSession(now: true)
    }

    func discardSnoozes(in space: UUID) {
        snoozed.removeAll { $0.record.spaceID == space }
        SnoozeStore.write(snoozed.map(\.record))
        armSnoozeAlarm()
    }
}

/// Lucide alarm-clock, drawn at its 24-point source coordinates.
struct LucideSnooze: View {
    var color: Color = Palette.muted
    var size: CGFloat = 16

    var body: some View {
        Canvas { context, dimensions in
            let unit = dimensions.width / 24
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * unit, y: y * unit) }
            var path = Path()
            path.addEllipse(in: CGRect(x: 4 * unit, y: 5 * unit, width: 16 * unit, height: 16 * unit))
            path.move(to: point(12, 9)); path.addLine(to: point(12, 13)); path.addLine(to: point(14, 15))
            path.move(to: point(5, 3)); path.addLine(to: point(2, 6))
            path.move(to: point(22, 6)); path.addLine(to: point(19, 3))
            path.move(to: point(6.38, 18.7)); path.addLine(to: point(4, 21))
            path.move(to: point(17.64, 18.67)); path.addLine(to: point(20, 21))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2 * unit, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SnoozedButton: View {
    @ObservedObject var browser: Browser

    var body: some View {
        Button { browser.showingSnoozed = true } label: {
            HStack(spacing: 4) {
                LucideSnooze()
                if !browser.snoozed.isEmpty {
                    Text("\(browser.snoozed.count)")
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 7)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Snoozed tabs")
    }
}

struct SnoozeComposer: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab
    @State private var byDuration = true
    @State private var hours = 3
    @State private var minutes = 0
    @State private var clock = Date().addingTimeInterval(3 * 3600)

    private var due: Date? {
        if byDuration {
            guard hours >= 0, minutes >= 0, minutes < 60,
                  hours > 0 || minutes > 0 else { return nil }
            return Date().addingTimeInterval(Double(hours) * 3600 + Double(minutes) * 60)
        }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: clock)
        return Calendar.current.nextDate(after: Date(), matching: parts, matchingPolicy: .nextTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                LucideSnooze(color: Palette.ink, size: 22)
                Text("Snooze “\(tab.label)”").font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Spacer()
                Door(icon: "xmark", help: "Cancel") { browser.snoozeTarget = nil }
            }
            Picker("Return", selection: $byDuration) {
                Text("For").tag(true)
                Text("Until").tag(false)
            }
            .pickerStyle(.segmented)
            if byDuration {
                HStack(spacing: 10) {
                    TextField("Hours", value: $hours, format: .number)
                        .frame(width: 62)
                    Text("hours")
                    TextField("Minutes", value: $minutes, format: .number)
                        .frame(width: 62)
                    Text("minutes")
                }
            } else {
                DatePicker("Time", selection: $clock, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.field)
            }
            if let due {
                Text("Returns \(due.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
            } else {
                Text("Enter a time after now")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
            }
            HStack {
                Spacer()
                Pill("Cancel") { browser.snoozeTarget = nil }
                if let due {
                    Pill("Snooze", filled: true) {
                        browser.snoozeTarget = nil
                        browser.scheduleSnooze(tab, until: due)
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 380)
        .foregroundStyle(Palette.ink)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.16), radius: 34, y: 12)
    }
}

struct SnoozedPanel: View {
    @ObservedObject var browser: Browser

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                LucideSnooze(color: Palette.ink, size: 21)
                Text("Snoozed tabs").font(.system(size: 17, weight: .semibold))
                Spacer()
                Door(icon: "xmark", help: "Done") { browser.showingSnoozed = false }
            }
            if browser.snoozed.isEmpty {
                Text("No tabs are waiting.").foregroundStyle(Palette.muted)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(browser.snoozed.sorted { $0.record.due < $1.record.due }) { item in
                            HStack(spacing: 10) {
                                Mark(
                                    icon: item.tab?.icon ?? URL(string: item.record.url)
                                        .flatMap { $0.host()?.lowercased() }
                                        .flatMap { Favicons.shared.cached($0) },
                                    letter: URL(string: item.record.url)?.host()?.first
                                        .map { String($0).uppercased() } ?? "•",
                                    size: 17
                                )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.record.title.isEmpty ? item.record.url : item.record.title)
                                        .lineLimit(1)
                                    Text(item.record.due.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 11))
                                        .foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                Pill("Open Now") { browser.openSnoozedNow(item) }
                                Pill("Delete") { browser.deleteSnoozed(item) }
                            }
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 510, height: 320, alignment: .topLeading)
        .foregroundStyle(Palette.ink)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.16), radius: 34, y: 12)
    }
}
