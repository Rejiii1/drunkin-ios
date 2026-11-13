import SwiftUI

struct HostToolsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var tastingID: UUID

    @State private var newName = ""
    @State private var renaming: Taster?
    @State private var renameText = ""
    @State private var removing: Taster?
    @State private var resetting: Flight?
    @State private var resetAll = false
    @State private var confirmEnd = false
    @State private var confirmHandoff = false
    @State private var shareURL: URL?
    @State private var error: String?

    var body: some View {
        Group {
            if let t = model.tastings[tastingID], t.role == .host {
                form(t)
            } else {
                ContentUnavailableView("Only the host's phone has host tools", systemImage: "lock").screen()
            }
        }
        .sheet(item: Binding(get: { shareURL.map { ShareItem(url: $0) } }, set: { if $0 == nil { shareURL = nil; dismiss() } })) { item in
            ShareSheet(items: [item.url])
        }
        .alert("Something went wrong", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func form(_ t: Tasting) -> some View {
        Form {
            Section {
                if let code = t.joinCode {
                    LabeledContent("Join code") {
                        Text(code).font(.system(.title3, design: .monospaced).weight(.bold)).foregroundStyle(Theme.gold)
                    }
                }
                Button("New join code") { model.newJoinCode(t.id) }
            } header: {
                Text("Joining")
            } footer: {
                Text("A new code stops anyone who only knows the old one from joining. Phones already at the table stay connected.")
            }

            Section("Phones at the table") {
                if t.members.isEmpty {
                    Text("No one has joined yet.").foregroundStyle(Theme.muted)
                }
                ForEach(t.members, id: \.deviceID) { m in
                    HStack {
                        Circle().fill(model.hostConnected.contains(m.deviceID) ? Theme.moss : Theme.line).frame(width: 8, height: 8)
                        Text(m.tasterID.map { t.name(of: $0) } ?? "Picking a name…")
                        Spacer()
                        Text(model.hostConnected.contains(m.deviceID) ? "connected" : "away")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) { model.unlinkPhone(t.id, deviceID: m.deviceID) }
                    }
                }
            }

            Section {
                Picker("Now pouring", selection: Binding(
                    get: { t.currentFlightID },
                    set: { id in model.update(t.id) { $0.currentFlightID = id } }
                )) {
                    Text("None").tag(UUID?.none)
                    ForEach(t.menu.flights) { f in Text(f.title).tag(UUID?.some(f.id)) }
                }
                NavigationLink("Edit flights & pours", value: Route.menuEditor(t.id))
            } header: {
                Text("Menu")
            } footer: {
                Text("Now pouring is highlighted on everyone's phone.")
            }

            Section {
                ForEach(t.menu.flights) { f in
                    let table = Set(t.tableIDs(for: f.id))
                    DisclosureGroup {
                        ForEach(t.tasters) { p in
                            Toggle(p.name, isOn: Binding(
                                get: { table.contains(p.id) },
                                set: { on in
                                    var next = table
                                    if on { next.insert(p.id) } else { next.remove(p.id) }
                                    model.update(t.id) { $0.setAttendance(f.id, t.tasters.map(\.id).filter { next.contains($0) }) }
                                }
                            ))
                        }
                        if t.attendance[f.id] != nil {
                            Button("Reset to everyone") { model.update(t.id) { $0.setAttendance(f.id, nil) } }
                        }
                    } label: {
                        HStack {
                            Text(f.title)
                            Spacer()
                            Text("\(table.count) at the table").font(.footnote).foregroundStyle(Theme.muted)
                        }
                    }
                }
            } header: {
                Text("At the table")
            } footer: {
                Text("Who has to score before a pour reveals. If someone heads to bed mid-flight, take them off here or use Reveal now on the pour.")
            }

            Section {
                ForEach(t.tasters) { p in
                    HStack {
                        t.avatar(p.id, size: 30)
                        Text(p.name)
                        if p.id == t.me { Text("you").font(.footnote).foregroundStyle(Theme.muted) }
                        Spacer()
                        if !p.active { Text("benched").font(.footnote).foregroundStyle(Theme.muted) }
                    }
                    .swipeActions(allowsFullSwipe: false) {
                        if p.id != t.me {
                            Button("Remove", role: .destructive) { removing = p }
                        }
                        Button(p.active ? "Bench" : "Unbench") {
                            model.update(t.id) { tt in
                                if let i = tt.tasters.firstIndex(where: { $0.id == p.id }) { tt.tasters[i].active.toggle() }
                                tt.recomputeStatuses()
                            }
                        }
                        .tint(Theme.amber)
                        Button("Rename") { renameText = p.name; renaming = p }
                            .tint(Theme.card2)
                    }
                }
                .onMove { from, to in
                    model.update(t.id) { tt in
                        tt.tasters.move(fromOffsets: from, toOffset: to)
                        tt.recomputeStatuses()
                    }
                }
                HStack {
                    TextField("Add someone", text: $newName).textInputAutocapitalization(.words)
                    Button("Add") {
                        model.addTaster(t.id, name: newName)
                        newName = ""
                    }
                    .disabled(Sanitize.line(newName).isEmpty)
                }
            } header: {
                Text("Tasters")
            } footer: {
                Text("Swipe a name to rename, bench or remove. Benched tasters don't hold up reveals. Removing someone deletes their scores.")
            }

            Section {
                ForEach(t.menu.flights) { f in
                    Button("Clear scores for \(f.title)", role: .destructive) { resetting = f }
                }
                Button("Clear every score", role: .destructive) { resetAll = true }
            } header: {
                Text("Start over")
            } footer: {
                Text("Use this after a test run. Can't be undone.")
            }

            Section {
                Button("Hand off hosting to another phone") { confirmHandoff = true }
                Button("Close the tasting", role: .destructive) { confirmEnd = true }
            } header: {
                Text("Hosting")
            } footer: {
                Text("Hand off creates a file. AirDrop it to the next host and open it in Drunkin there; this phone rejoins as a guest. Closing keeps a read-only copy on every phone.")
            }
        }
        .screen()
        .navigationTitle("Host tools")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let p = renaming {
                    let clean = Sanitize.line(renameText, max: Limits.name)
                    if !clean.isEmpty {
                        model.update(t.id) { tt in
                            if let i = tt.tasters.firstIndex(where: { $0.id == p.id }) { tt.tasters[i].name = clean }
                        }
                    }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove and delete their scores", role: .destructive) {
                if let p = removing { model.update(t.id) { $0.removeTaster(p.id) } }
                removing = nil
            }
        } message: {
            Text("Bench them instead if they might be back.")
        }
        .confirmationDialog("Clear scores for \(resetting?.title ?? "")?", isPresented: Binding(get: { resetting != nil }, set: { if !$0 { resetting = nil } }), titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                if let f = resetting { model.update(t.id) { $0.resetPours(f.pours.map(\.id)) } }
                resetting = nil
            }
        }
        .confirmationDialog("Clear every score in this tasting?", isPresented: $resetAll, titleVisibility: .visible) {
            Button("Clear everything", role: .destructive) {
                model.update(t.id) { $0.resetPours($0.allPours.map(\.pour.id)) }
            }
        }
        .confirmationDialog("Hand off hosting?", isPresented: $confirmHandoff, titleVisibility: .visible) {
            Button("Create hand-off file") {
                do { shareURL = try model.handOffHosting(t.id) } catch { self.error = "Couldn't create the file." }
            }
        } message: {
            Text("The file holds every score, including hidden ones, so only send it to the person taking over.")
        }
        .confirmationDialog("Close this tasting?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Close tasting", role: .destructive) {
                model.endHosting(t.id)
                dismiss()
            }
        } message: {
            Text("Nobody can join or score anymore. Everyone keeps what they've seen.")
        }
    }
}
