import SwiftUI

struct FlightView: View {
    @Environment(AppModel.self) private var model
    var tastingID: UUID
    var flightID: UUID
    var focusPour: UUID?

    var body: some View {
        if let t = model.tastings[tastingID], let f = t.flight(flightID) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(f.title).font(.display(.largeTitle)).foregroundStyle(Theme.cream)
                            if !f.intro.isEmpty {
                                Text(f.intro).font(.body).foregroundStyle(Theme.cream.opacity(0.9))
                            }
                            ConnectionPill(tasting: t)
                        }
                        if f.pours.isEmpty {
                            Text(t.isHost ? "No pours yet. Add some in Host tools → Edit menu." : "No pours yet.")
                                .foregroundStyle(Theme.muted)
                        }
                        ForEach(Array(f.pours.enumerated()), id: \.element.id) { i, p in
                            PourCard(tasting: t, pour: p, label: String(format: "%02d", i + 1))
                                .id(p.id)
                        }
                        NavigationLink(value: Route.results(t.id, f.id)) { Text("\(f.title) results") }
                            .buttonStyle(.primary)
                            .padding(.top, 8)
                    }
                    .padding()
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    PourStrip(tasting: t, flight: f) { id in
                        withAnimation { proxy.scrollTo(id, anchor: .top) }
                    }
                }
                .task {
                    if let focusPour {
                        try? await Task.sleep(for: .milliseconds(150))
                        proxy.scrollTo(focusPour, anchor: .top)
                    }
                }
            }
            .screen()
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("This flight isn't on the menu anymore", systemImage: "wineglass").screen()
        }
    }
}

/// Filled = you've scored it; green ring = the table's scores are revealed.
struct PourStrip: View {
    var tasting: Tasting
    var flight: Flight
    var jump: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(flight.pours.enumerated()), id: \.element.id) { i, p in
                    let scored = tasting.myEntry(p.id)?.score != nil
                    let revealed = tasting.statuses[p.id]?.revealed == true
                    Button { jump(p.id) } label: {
                        Text(String(format: "%02d", i + 1))
                            .font(.numeral(.headline))
                            .frame(minWidth: 48, minHeight: 44)
                            .foregroundStyle(scored ? Theme.night : Theme.muted)
                            .background(scored ? Theme.gold : Theme.card, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(revealed ? Theme.moss : Theme.line, lineWidth: revealed ? 2.5 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(p.name)\(scored ? ", scored" : "")\(revealed ? ", revealed" : "")")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Theme.night.opacity(0.96))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

struct PourCard: View {
    @Environment(AppModel.self) private var model
    var tasting: Tasting
    var pour: Pour
    var label: String
    @State private var notesOpen = false

    var body: some View {
        let entry = tasting.myEntry(pour.id)
        let locked = tasting.isLocked(pour.id)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    Text(label).font(.numeral(.title)).foregroundStyle(Theme.gold)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pour.name).font(.display(.title2)).foregroundStyle(Theme.cream)
                        let bits = [pour.proof.map { "\(Results.fmtProof($0)) proof" }, pour.descriptor.isEmpty ? nil : pour.descriptor].compactMap { $0 }
                        if !bits.isEmpty {
                            Text(bits.joined(separator: " · ").uppercased())
                                .font(.caption.weight(.semibold)).tracking(1.2)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                ForEach(NoteLine.lines(for: pour)) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(line.label.uppercased()).font(.caption2.weight(.bold)).tracking(1.2)
                            .foregroundStyle(Theme.amber).frame(width: 58, alignment: .leading)
                        Text(line.text).foregroundStyle(Theme.cream.opacity(0.95))
                    }
                }
                if !pour.trivia.isEmpty {
                    Text(pour.trivia).italic().foregroundStyle(Theme.muted)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) { Rectangle().fill(Theme.gold).frame(width: 2) }
                }
            }
            .padding(18)

            if tasting.me != nil && tasting.role != .archive {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("YOUR SCORE").font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(Theme.muted)
                        if let s = entry?.score, let w = Copy.scoreWords[s] {
                            Text(w).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.gold)
                        }
                        Spacer()
                        if locked {
                            Label("Locked", systemImage: "lock.fill").font(.footnote).foregroundStyle(Theme.muted)
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { n in
                            let on = entry?.score == n
                            Button {
                                model.edit(tasting.id, pour: pour.id) { $0.score = on ? nil : n }
                            } label: {
                                Text("\(n)")
                                    .font(.numeral(.title2))
                                    .frame(maxWidth: .infinity, minHeight: 54)
                                    .foregroundStyle(on ? Theme.night : Theme.cream)
                                    .background(on ? Theme.gold : Theme.night, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Theme.gold : Theme.line))
                                    .opacity(locked && !on ? 0.3 : 1)
                            }
                            .buttonStyle(.plain)
                            .disabled(locked)
                            .accessibilityLabel("\(n), \(Copy.scoreWords[n] ?? "")")
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .sensoryFeedback(.selection, trigger: entry?.score)
                    HStack(spacing: 8) {
                        Button {
                            model.edit(tasting.id, pour: pour.id) { $0.water.toggle() }
                        } label: {
                            Label(entry?.water == true ? "Watered" : "+ Water", systemImage: "drop")
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(entry?.water == true ? Theme.water : Theme.muted)
                                .background(Theme.night, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(entry?.water == true ? Theme.water.opacity(0.6) : Theme.line))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(entry?.water == true ? .isSelected : [])
                        Button {
                            notesOpen.toggle()
                        } label: {
                            Label(entry?.notes.isEmpty == false ? "Your notes" : "Notes", systemImage: "pencil")
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(entry?.notes.isEmpty == false ? Theme.cream : Theme.muted)
                                .background(Theme.night, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                        }
                        .buttonStyle(.plain)
                    }
                    if notesOpen || entry?.notes.isEmpty == false {
                        NotesField(tastingID: tasting.id, pourID: pour.id, initial: entry?.notes ?? "")
                    }
                    TableStatusView(tasting: tasting, pour: pour)
                }
                .padding(16)
                .background(Theme.card2.opacity(0.55))
            } else {
                TableStatusView(tasting: tasting, pour: pour).padding(16)
            }
        }
        .card()
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct NotesField: View {
    @Environment(AppModel.self) private var model
    var tastingID: UUID
    var pourID: UUID
    var initial: String
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        TextField("What did you actually taste?", text: $text, axis: .vertical)
            .lineLimit(3...8)
            .padding(12)
            .background(Theme.night, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
            .onAppear {
                if !loaded { text = initial; loaded = true }
            }
            .task(id: text) {
                guard loaded, text != initial else { return }
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                let value = String(text.prefix(Limits.longText))
                model.edit(tastingID, pour: pourID) { $0.notes = value }
            }
    }
}

struct TableStatusView: View {
    @Environment(AppModel.self) private var model
    var tasting: Tasting
    var pour: Pour

    var body: some View {
        let st = tasting.statuses[pour.id]
        VStack(alignment: .leading, spacing: 8) {
            if st?.revealed == true {
                let table = Results.tableEntries(pour.id, tasting)
                let avg = Results.mean(table.compactMap(\.score).map(Double.init))
                HStack(alignment: .firstTextBaseline) {
                    Text("THE TABLE").font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("avg").foregroundStyle(Theme.muted)
                    Text(Results.fmt(avg)).font(.numeral(.title2)).foregroundStyle(Theme.gold)
                }
                ForEach(table.sorted { ($0.score ?? 0) > ($1.score ?? 0) }, id: \.tasterID) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            tasting.avatar(e.tasterID, size: 26)
                            Text(tasting.name(of: e.tasterID)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.cream)
                            if e.water { Image(systemName: "drop.fill").font(.caption).foregroundStyle(Theme.water).accessibilityLabel("with water") }
                            Spacer()
                            Text(e.score.map(String.init) ?? "–").font(.numeral(.title3)).foregroundStyle(Theme.cream)
                        }
                        if !e.notes.isEmpty {
                            Text("“\(e.notes)”").font(.footnote).italic().foregroundStyle(Theme.muted).padding(.leading, 34)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } else {
                hiddenStatus(st)
            }
            if tasting.isHost { HostRevealControls(tasting: tasting, pourID: pour.id, status: st) }
        }
        .padding(12)
        .background(Theme.night.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }

    @ViewBuilder
    private func hiddenStatus(_ st: PourStatus?) -> some View {
        if let st {
            let done = Set(st.scoredBy)
            let mineScored = tasting.myEntry(pour.id)?.score != nil
            let people = st.required + ((mineScored && tasting.me.map { !st.required.contains($0) } == true) ? [tasting.me!] : [])
            let isDone: (UUID) -> Bool = { done.contains($0) || ($0 == tasting.me && mineScored) }
            let waiting = people.filter { !isDone($0) }
            FlowChips(ids: people, tasting: tasting, isDone: isDone)
            Text(message(st: st, waiting: waiting, total: people.count))
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        } else {
            Text(tasting.role == .guest ? "Who has scored shows up once you connect to the host." : "Hidden until everyone has scored.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
    }

    private func message(st: PourStatus, waiting: [UUID], total: Int) -> String {
        var m: String
        if st.override == .hide { m = "The host is holding the reveal." }
        else if waiting.isEmpty { m = tasting.role == .guest ? "Everyone is in. Reveals when the host's phone catches up." : "Everyone is in." }
        else if waiting.count <= 2 { m = "Waiting on \(Results.join(waiting.map { tasting.name(of: $0) }))." }
        else { m = "Hidden until everyone is in (\(total - waiting.count)/\(total))." }
        if tasting.role == .guest, !model.isConnected(tasting), let last = tasting.lastSync {
            m += " As of \(last.formatted(date: .omitted, time: .shortened))."
        }
        return m
    }
}

struct FlowChips: View {
    var ids: [UUID]
    var tasting: Tasting
    var isDone: (UUID) -> Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips }
            VStack(alignment: .leading, spacing: 6) { chips }
        }
    }

    @ViewBuilder private var chips: some View {
        ForEach(ids, id: \.self) { id in
            let done = isDone(id)
            HStack(spacing: 5) {
                tasting.avatar(id, size: 22).opacity(done ? 1 : 0.5)
                if done { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                Text(tasting.name(of: id)).font(.footnote.weight(.semibold))
            }
            .padding(.leading, 3).padding(.trailing, 10).padding(.vertical, 3)
            .foregroundStyle(done ? Theme.moss : Theme.muted)
            .background(done ? Theme.moss.opacity(0.18) : Theme.card2, in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(tasting.name(of: id)), \(done ? "scored" : "not scored yet")")
        }
    }
}

struct HostRevealControls: View {
    @Environment(AppModel.self) private var model
    var tasting: Tasting
    var pourID: UUID
    var status: PourStatus?

    var body: some View {
        HStack(spacing: 8) {
            if status?.revealed != true {
                Button("Reveal now") { model.update(tasting.id) { $0.setOverride(pourID, .show) } }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Hide again") { model.update(tasting.id) { $0.setOverride(pourID, .hide) } }
                    .buttonStyle(.bordered)
            }
            if status?.override != nil {
                Button("Back to auto") { model.update(tasting.id) { $0.setOverride(pourID, nil) } }
                    .buttonStyle(.bordered)
            }
        }
        .font(.footnote.weight(.semibold))
        .tint(Theme.gold)
        .padding(.top, 6)
    }
}

struct NoteLine: Identifiable {
    var label: String
    var text: String
    var id: String { label }

    static func lines(for pour: Pour) -> [NoteLine] {
        [NoteLine(label: "Nose", text: pour.nose), NoteLine(label: "Palate", text: pour.palate), NoteLine(label: "Finish", text: pour.finish)]
            .filter { !$0.text.isEmpty }
    }
}
