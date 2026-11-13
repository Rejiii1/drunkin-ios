import SwiftUI

struct FlightResultsView: View {
    @Environment(AppModel.self) private var model
    var tastingID: UUID
    var flightID: UUID

    var body: some View {
        if let t = model.tastings[tastingID], let f = t.flight(flightID) {
            let r = Results.flight(f, t)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow("Results")
                        Text(f.title).font(.display(.largeTitle)).foregroundStyle(Theme.cream)
                    }

                    if let top = r.winners.first {
                        VStack(spacing: 6) {
                            Eyebrow(r.winners.count > 1 ? "Tied for pour of the flight" : "Pour of the flight")
                            Text(Results.join(r.winners.map(\.pour.name)))
                                .font(.display(.title)).multilineTextAlignment(.center).foregroundStyle(Theme.cream)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(Results.fmt(top.avg)).font(.numeral(.largeTitle)).foregroundStyle(Theme.gold)
                                Text("/ 5 from \(top.n)").foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(18).frame(maxWidth: .infinity).card(highlighted: true)
                    } else {
                        Text("Nothing revealed yet. Results fill in as each pour reveals.")
                            .foregroundStyle(Theme.muted).padding(18).frame(maxWidth: .infinity).card()
                    }

                    Text("The flight").font(.display(.title3)).foregroundStyle(Theme.cream)
                    ForEach(r.rows) { row in
                        NavigationLink(value: Route.flight(t.id, f.id, focus: row.pour.id)) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.pour.name).font(.headline).foregroundStyle(Theme.cream)
                                    Text(row.revealed
                                         ? row.scores.map { "\(t.name(of: $0.tasterID)) \($0.score ?? 0)\($0.water ? " 💧" : "")" }.joined(separator: " · ")
                                         : "Hidden · \(row.scoredBy.count)/\(row.required.count) scored")
                                        .font(.subheadline).foregroundStyle(Theme.muted)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                Text(row.revealed ? Results.fmt(row.avg) : "?").font(.numeral(.title)).foregroundStyle(Theme.gold)
                            }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
                        }
                        .buttonStyle(.plain)
                    }

                    if !r.favorites.isEmpty {
                        Text("Everybody's favorite").font(.display(.title3)).foregroundStyle(Theme.cream)
                        VStack(spacing: 0) {
                            ForEach(r.favorites, id: \.tasterID) { item in
                                HStack {
                                    t.avatar(item.tasterID, size: 28)
                                    Text(t.name(of: item.tasterID)).font(.headline).foregroundStyle(Theme.cream)
                                    Spacer()
                                    Text(item.favorite.pours.map(\.name).joined(separator: ", "))
                                        .multilineTextAlignment(.trailing).foregroundStyle(Theme.cream.opacity(0.9))
                                    Text("\(item.favorite.score)").font(.numeral(.headline)).foregroundStyle(Theme.gold)
                                }
                                .padding(12)
                                Divider().overlay(Theme.line)
                            }
                        }
                        .card()
                    }

                    if let d = r.disagreement, let hi = r.high, let lo = r.low {
                        Text("Biggest debate").font(.display(.title3)).foregroundStyle(Theme.cream)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(d.pour.name).font(.headline).foregroundStyle(Theme.cream)
                            Text("\(t.name(of: hi.tasterID)) gave it a \(hi.score ?? 0), \(t.name(of: lo.tasterID)) gave it a \(lo.score ?? 0).")
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
                    }

                    if r.hiddenCount > 0 && !r.winners.isEmpty {
                        Text("\(r.hiddenCount) \(r.hiddenCount == 1 ? "pour" : "pours") still hidden.")
                            .font(.footnote).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
                    }

                    if !r.winners.isEmpty {
                        ShareLink(item: Results.shareText(f, t)) {
                            Label("Share results as text", systemImage: "message")
                        }
                        .buttonStyle(.ghost)
                    }
                }
                .padding()
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .screen()
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Not found", systemImage: "wineglass").screen()
        }
    }
}

struct LeaderboardView: View {
    @Environment(AppModel.self) private var model
    var tastingID: UUID

    var body: some View {
        if let t = model.tastings[tastingID] {
            let rows = Results.leaderboard(t)
            let prizes = Results.awards(t)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(t.menu.title)
                    Text("Leaderboard").font(.display(.largeTitle)).foregroundStyle(Theme.cream)
                    if rows.isEmpty {
                        Text("No pours revealed yet.").foregroundStyle(Theme.muted).padding(18).frame(maxWidth: .infinity).card()
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                        NavigationLink(value: Route.flight(t.id, r.flight.id, focus: r.pour.id)) {
                            HStack(spacing: 14) {
                                Text("\(i + 1)").font(.numeral(.title2)).foregroundStyle(i == 0 ? Theme.gold : Theme.muted).frame(width: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.pour.name).font(.headline).foregroundStyle(Theme.cream)
                                    Text("\(r.flight.title) · \(r.n) \(r.n == 1 ? "score" : "scores")").font(.subheadline).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Text(Results.fmt(r.avg)).font(.numeral(.title)).foregroundStyle(Theme.gold)
                            }
                            .padding(14).card(highlighted: i == 0)
                        }
                        .buttonStyle(.plain)
                    }

                    if !prizes.isEmpty {
                        Text("Awards").font(.display(.title2)).foregroundStyle(Theme.cream).padding(.top, 12)
                        ForEach(prizes) { a in
                            VStack(alignment: .leading, spacing: 8) {
                                Eyebrow(a.title)
                                HStack(spacing: 10) {
                                    HStack(spacing: -10) { ForEach(a.ids, id: \.self) { t.avatar($0, size: 36) } }
                                    Text(Results.join(a.ids.map { t.name(of: $0) })).font(.display(.title3)).foregroundStyle(Theme.cream)
                                }
                                Text("\(a.blurb) · \(a.stat)").font(.subheadline).foregroundStyle(Theme.muted)
                            }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .screen()
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct JournalView: View {
    @Environment(AppModel.self) private var model
    var tastingID: UUID

    var body: some View {
        if let t = model.tastings[tastingID] {
            let rows = t.allPours.compactMap { item -> JournalRow? in
                guard let e = t.myEntry(item.pour.id), !e.isEmpty else { return nil }
                return JournalRow(flight: item.flight, pour: item.pour, entry: e)
            }
            let scored = rows.compactMap { $0.entry.score }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Eyebrow(t.name(of: t.me))
                    Text("My notes").font(.display(.largeTitle)).foregroundStyle(Theme.cream)
                    if rows.isEmpty {
                        Text("Nothing yet. Score a pour and it shows up here.").foregroundStyle(Theme.muted).padding(18).frame(maxWidth: .infinity).card()
                    } else {
                        HStack(spacing: 12) {
                            stat("\(scored.count)", "pours scored")
                            stat(Results.fmt(Results.mean(scored.map(Double.init))), "your average")
                        }
                        ForEach(t.menu.flights) { f in
                            let mine = rows.filter { $0.flight.id == f.id }
                            if !mine.isEmpty {
                                Text(f.title).font(.display(.title3)).foregroundStyle(Theme.cream).padding(.top, 6)
                                ForEach(mine) { row in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(row.pour.name).font(.headline).foregroundStyle(Theme.cream)
                                            if row.entry.water { Image(systemName: "drop.fill").foregroundStyle(Theme.water).accessibilityLabel("with water") }
                                            Spacer()
                                            Text(row.entry.score.map(String.init) ?? "–").font(.numeral(.title2)).foregroundStyle(Theme.gold)
                                        }
                                        if !row.entry.notes.isEmpty { Text(row.entry.notes).italic().foregroundStyle(Theme.muted) }
                                        let stats = Results.stats(row.pour, in: f, t)
                                        if stats.revealed {
                                            Text("Table avg \(Results.fmt(stats.avg))").font(.footnote).foregroundStyle(Theme.muted)
                                        }
                                    }
                                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
                                }
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .screen()
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.numeral(.largeTitle)).foregroundStyle(Theme.gold)
            Text(label).font(.subheadline).foregroundStyle(Theme.muted)
        }
        .padding(14).frame(maxWidth: .infinity).card()
    }
}

struct JournalRow: Identifiable {
    var flight: Flight
    var pour: Pour
    var entry: Entry
    var id: UUID { pour.id }
}
