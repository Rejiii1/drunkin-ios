import PhotosUI
import SwiftUI

struct TastingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var tastingID: UUID

    @State private var shareURL: URL?
    @State private var shareError: String?
    @State private var photo: PhotosPickerItem?
    @State private var confirmLeave = false
    @State private var confirmDelete = false
    @State private var hostAgainName = ""
    @State private var askHostAgain = false

    var body: some View {
        if let t = model.tastings[tastingID] {
            content(t)
                .onAppear {
                    model.open(tastingID)
                    UIApplication.shared.isIdleTimerDisabled = t.role == .host
                }
                .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        } else {
            ContentUnavailableView("Tasting not found", systemImage: "wineglass")
                .screen()
        }
    }

    @ViewBuilder
    private func content(_ t: Tasting) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(t.menu.title)
                        .font(.display(.largeTitle))
                        .foregroundStyle(Theme.cream)
                    if !t.menu.subtitle.isEmpty {
                        Text(t.menu.subtitle).foregroundStyle(Theme.muted)
                    }
                    ConnectionPill(tasting: t)
                }

                if t.role == .guest && t.me == nil {
                    ClaimSeatView(tasting: t)
                } else if t.role == .host && t.me == nil {
                    HostSeatView(tasting: t)
                }

                if t.role == .host, let code = t.joinCode {
                    JoinCodeCard(code: code, connected: model.hostConnected.count)
                }

                if let f = t.currentFlight {
                    NavigationLink(value: Route.flight(t.id, f.id, focus: nil)) {
                        VStack(spacing: 2) {
                            Text("NOW POURING").font(.caption.weight(.bold)).tracking(1.6).opacity(0.75)
                            Text("\(f.title) →").font(.display(.title2))
                        }
                    }
                    .buttonStyle(.primary)
                }

                ForEach(t.menu.flights) { f in
                    NavigationLink(value: Route.flight(t.id, f.id, focus: nil)) {
                        FlightRow(tasting: t, flight: f)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 12) {
                    NavigationLink(value: Route.leaderboard(t.id)) { Text("Leaderboard") }
                        .buttonStyle(.ghost)
                    if t.me != nil {
                        NavigationLink(value: Route.journal(t.id)) { Text("My notes") }
                            .buttonStyle(.ghost)
                    }
                }

                if t.role == .host {
                    NavigationLink(value: Route.hostTools(t.id)) {
                        Label("Host tools", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.ghost)
                }

                if t.role != .archive, let me = t.me {
                    PhotosPicker(selection: $photo, matching: .images) {
                        HStack(spacing: 12) {
                            t.avatar(me, size: 44)
                            VStack(alignment: .leading) {
                                Text(t.name(of: me)).font(.headline).foregroundStyle(Theme.cream)
                                Text(t.avatars[me] == nil ? "Add a photo for the table" : "Change your photo")
                                    .font(.subheadline).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .card()
                    }
                    .buttonStyle(.plain)
                }

                actions(t)
            }
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .screen()
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), !model.setMyPhoto(t.id, imageData: data) {
                    model.toast = Toast(text: "Couldn't use that photo. Try another one.")
                }
                photo = nil
            }
        }
        .sheet(item: Binding(get: { shareURL.map { ShareItem(url: $0) } }, set: { if $0 == nil { shareURL = nil } })) { item in
            ShareSheet(items: [item.url])
        }
        .alert("Couldn't share", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(shareError ?? "") }
        .confirmationDialog("Leave this tasting?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { model.leave(t.id) }
        } message: {
            Text("You'll keep a read-only copy of what you've seen. To rejoin, ask the host for the code.")
        }
        .confirmationDialog("Delete this tasting from this phone?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.delete(t.id)
                dismiss()
            }
        } message: {
            Text(t.role == .host
                 ? "Everyone at the table will be disconnected and every score on this phone is gone for good. Share the results first if you want to keep them."
                 : "This can't be undone.")
        }
        .alert("Host this menu again", isPresented: $askHostAgain) {
            TextField("Your name", text: $hostAgainName)
            Button("Create") {
                let id = model.hostAgain(from: t, yourName: hostAgainName)
                model.open(id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Starts a new tasting with the same flights and pours. Scores aren't copied.")
        }
    }

    @ViewBuilder
    private func actions(_ t: Tasting) -> some View {
        VStack(spacing: 10) {
            Button {
                do { shareURL = try model.exportResults(t.id) } catch { shareError = "Couldn't create the file." }
            } label: {
                Label("Share tasting file", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.ghost)
            Text("Sends the menu and every revealed score. Anyone with Drunkin can open it, even if they weren't at the table. Hidden scores are never included.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)

            if t.role == .archive {
                Button { askHostAgain = true } label: { Label("Host this menu again", systemImage: "arrow.clockwise") }
                    .buttonStyle(.ghost)
            }
            if t.role == .guest {
                Button("Leave tasting", role: .destructive) { confirmLeave = true }
                    .foregroundStyle(Theme.alert)
                    .padding(.top, 8)
            }
            Button("Delete from this phone", role: .destructive) { confirmDelete = true }
                .foregroundStyle(Theme.alert)
                .padding(.top, 4)
        }
        .padding(.top, 12)
    }
}

struct ShareItem: Identifiable {
    var url: URL
    var id: URL { url }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct ConnectionPill: View {
    @Environment(AppModel.self) private var model
    var tasting: Tasting

    var body: some View {
        let s = state
        HStack(spacing: 6) {
            Circle().fill(s.1).frame(width: 8, height: 8)
            Text(s.0).font(.footnote.weight(.semibold))
        }
        .foregroundStyle(s.1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(Capsule().stroke(s.1.opacity(0.5)))
        .accessibilityElement(children: .combine)
    }

    private var state: (String, Color) {
        switch tasting.role {
        case .archive:
            return ("Saved copy", Theme.muted)
        case .host:
            guard model.hostRunning else { return ("Not open to the table", Theme.muted) }
            let n = model.hostConnected.count
            return (n == 0 ? "Open · waiting for phones" : "Open · \(n) \(n == 1 ? "phone" : "phones") connected", Theme.moss)
        case .guest:
            let pending = tasting.pendingCount
            switch model.guestLink {
            case .connected(let id) where id == tasting.id:
                return (pending > 0 ? "Syncing \(pending)…" : "Connected to \(tasting.hostName ?? "host")", Theme.moss)
            case .connecting(let id) where id == tasting.id:
                return ("Connecting…", Theme.muted)
            case .failed(let msg):
                return (msg, Theme.alert)
            default:
                let since = tasting.lastSync.map { " · as of \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
                return (pending > 0 ? "Looking for host · \(pending) to send" : "Looking for host\(since)", Theme.amber)
            }
        }
    }
}

struct JoinCodeCard: View {
    var code: String
    var connected: Int

    var body: some View {
        VStack(spacing: 6) {
            Eyebrow("Join code")
            Text(code.map(String.init).joined(separator: " "))
                .font(.system(size: 40, weight: .heavy, design: .monospaced))
                .foregroundStyle(Theme.gold)
                .accessibilityLabel("Join code \(code.map(String.init).joined(separator: " "))")
            Text("Friends tap Join a tasting nearby and enter this code. Keep Drunkin open on this phone while you taste.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .card(highlighted: true)
    }
}

struct FlightRow: View {
    var tasting: Tasting
    var flight: Flight

    var body: some View {
        let pours = flight.pours
        let mine = pours.filter { tasting.myEntry($0.id)?.score != nil }.count
        let revealed = pours.filter { tasting.statuses[$0.id]?.revealed == true }.count
        let isNow = tasting.currentFlightID == flight.id
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(flight.title).font(.display(.title3)).foregroundStyle(Theme.cream)
                Spacer()
                if isNow {
                    Text("NOW").font(.caption2.weight(.heavy)).tracking(1)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.gold, in: Capsule())
                        .foregroundStyle(Theme.night)
                }
            }
            Text("\(pours.count) \(pours.count == 1 ? "pour" : "pours")").foregroundStyle(Theme.muted)
            if !pours.isEmpty && (mine > 0 || revealed > 0) {
                ProgressView(value: Double(mine), total: Double(pours.count)).tint(Theme.gold)
                Text("You: \(mine)/\(pours.count) · \(revealed)/\(pours.count) revealed")
                    .font(.footnote)
                    .foregroundStyle(mine == pours.count ? Theme.moss : Theme.muted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(highlighted: isNow)
        .contentShape(Rectangle())
    }
}

struct ClaimSeatView: View {
    @Environment(AppModel.self) private var model
    var tasting: Tasting
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Who are you?").font(.display(.title2)).foregroundStyle(Theme.cream)
            if model.guestLink != .connected(tasting.id) {
                Text("Connect to the host's phone to pick your name.").foregroundStyle(Theme.muted)
            } else {
                let open = tasting.tasters.filter { tasting.claimable.contains($0.id) }
                ForEach(open) { p in
                    Button {
                        model.claim(tasting.id, taster: p.id)
                    } label: {
                        HStack {
                            tasting.avatar(p.id, size: 36)
                            Text(p.name).font(.headline)
                            Spacer()
                        }
                    }
                    .buttonStyle(.ghost)
                }
                HStack {
                    TextField("Or add your name", text: $name)
                        .textInputAutocapitalization(.words)
                        .padding(12)
                        .background(Theme.night, in: RoundedRectangle(cornerRadius: 12))
                    Button("Join") { model.claimNew(tasting.id, name: name) }
                        .buttonStyle(.primary)
                        .frame(width: 100)
                        .disabled(Sanitize.line(name).isEmpty)
                }
            }
        }
        .padding(16)
        .card(highlighted: true)
    }
}

struct HostSeatView: View {
    @Environment(AppModel.self) private var model
    var tasting: Tasting
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You're hosting now. Who are you?").font(.display(.title3)).foregroundStyle(Theme.cream)
            ForEach(tasting.tasters.filter { tasting.claimableTasterIDs().contains($0.id) }) { p in
                Button { model.setHostSeat(tasting.id, taster: p.id) } label: {
                    HStack {
                        tasting.avatar(p.id, size: 36)
                        Text(p.name).font(.headline)
                        Spacer()
                    }
                }
                .buttonStyle(.ghost)
            }
            HStack {
                TextField("Or add your name", text: $name)
                    .textInputAutocapitalization(.words)
                    .padding(12)
                    .background(Theme.night, in: RoundedRectangle(cornerRadius: 12))
                Button("Add") { model.addHostSeat(tasting.id, name: name) }
                    .buttonStyle(.primary)
                    .frame(width: 100)
                    .disabled(Sanitize.line(name).isEmpty)
            }
        }
        .padding(16)
        .card(highlighted: true)
    }
}
