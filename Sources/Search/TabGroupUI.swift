import SwiftUI

/// Internal drags carry an id, never a page address. The ordinary URL drop
/// path can then keep opening links without mistaking a tab for a website.
enum GroupDrag {
    static let type = "com.officecommun.search.tab-item"

    enum Item {
        case tab(UUID)
        case group(UUID)
    }

    static func provider(_ item: Item) -> NSItemProvider {
        let text: String
        switch item {
        case .tab(let id): text = "tab:\(id.uuidString)"
        case .group(let id): text = "group:\(id.uuidString)"
        }
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .ownProcess) { done in
            done(Data(text.utf8), nil)
            return nil
        }
        return provider
    }

    static func receive(_ providers: [NSItemProvider], use: @escaping (Item) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type) }) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
            guard let data, let text = String(data: data, encoding: .utf8),
                  let colon = text.firstIndex(of: ":"),
                  let id = UUID(uuidString: String(text[text.index(after: colon)...])) else { return }
            let item: Item = text[..<colon] == "tab" ? .tab(id) : .group(id)
            DispatchQueue.main.async { use(item) }
        }
        return true
    }
}

struct GroupHeader: View {
    @ObservedObject var browser: Browser
    let group: TabGroup
    var vertical = false

    @State private var hovering = false
    @State private var renaming = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        Button { browser.toggleGroup(group.id) } label: {
            HStack(spacing: 6) {
                Circle().fill(group.tint).frame(width: 8, height: 8)
                Text(browser.groupTitle(group))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(browser.groupCount(group))")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
                Image(systemName: group.expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .medium))
            }
            .font(.system(size: vertical ? 12.5 : 11, weight: .medium))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, vertical ? 10 : 8)
            .frame(width: vertical ? nil : 120, height: 28)
            .frame(maxWidth: vertical ? .infinity : nil, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(browser.groupHasActiveTab(group) && !group.expanded ? Palette.wash :
                          (hovering ? Palette.hover : .clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(browser.groupTitle(group)) · \(browser.groupCount(group)) tabs")
        .accessibilityLabel("\(browser.groupTitle(group)), \(browser.groupCount(group)) tabs")
        .accessibilityValue(group.expanded ? "Expanded" : "Collapsed")
        .contextMenu {
            Button("Rename…") {
                draft = group.name ?? ""
                renaming = true
            }
            Menu("Color") {
                ForEach(TabGroup.colors.indices, id: \.self) { index in
                    Button {
                        browser.colorGroup(group.id, with: index)
                    } label: {
                        Label(TabGroup.colors[index].0, systemImage: group.color == index ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            }
            Divider()
            Button("Ungroup") { browser.ungroup(group.id) }
            Button("Close Group") { browser.closeGroup(group.id) }
        }
        .popover(isPresented: $renaming) {
            HStack(spacing: 8) {
                TextField("Group name", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit { saveName() }
                Button("Save") { saveName() }
            }
            .padding(14)
            .frame(width: 260)
            .onAppear { nameFocused = true }
        }
        .onDrag { GroupDrag.provider(.group(group.id)) }
        .onDrop(of: [GroupDrag.type], isTargeted: nil) { providers in
            GroupDrag.receive(providers) { item in
                switch item {
                case .tab(let id):
                    if let tab = browser.tabs.first(where: { $0.id == id }) { browser.add(tab, to: group.id) }
                case .group(let id):
                    let first = browser.tabs.first { $0.groupID == group.id }
                    browser.moveGroup(id, before: first)
                }
            }
        }
    }

    private func saveName() {
        browser.renameGroup(group.id, to: draft)
        renaming = false
    }
}

struct TabGroupTarget: ViewModifier {
    @ObservedObject var browser: Browser
    let tab: Tab
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
            .onDrag { GroupDrag.provider(.tab(tab.id)) }
            .onDrop(of: [GroupDrag.type], isTargeted: nil) { providers in
                GroupDrag.receive(providers) { item in
                    switch item {
                    case .tab(let id):
                        if let source = browser.tabs.first(where: { $0.id == id }) {
                            browser.move(source, before: tab)
                        }
                    case .group(let id):
                        browser.moveGroup(id, before: tab)
                    }
                }
            }
        } else {
            content
        }
    }
}

struct GroupMemberMark: ViewModifier {
    let group: TabGroup?
    let vertical: Bool

    func body(content: Content) -> some View {
        content
            .padding(.leading, vertical && group != nil ? 12 : 0)
            .overlay(alignment: vertical ? .leading : .bottom) {
                if let group {
                    Capsule()
                        .fill(group.tint)
                        .frame(width: vertical ? 3 : 20, height: vertical ? 17 : 2)
                        .padding(.leading, vertical ? 3 : 0)
                        .accessibilityHidden(true)
                }
            }
    }
}

struct UngroupDropTarget: ViewModifier {
    @ObservedObject var browser: Browser

    func body(content: Content) -> some View {
        content.onDrop(of: [GroupDrag.type], isTargeted: nil) { providers in
            GroupDrag.receive(providers) { item in
                switch item {
                case .tab(let id):
                    if let tab = browser.tabs.first(where: { $0.id == id }) { browser.moveOutside(tab) }
                case .group(let id): browser.moveGroup(id, before: nil)
                }
            }
        }
    }
}
