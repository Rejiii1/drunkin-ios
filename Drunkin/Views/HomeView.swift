import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Binding var path: NavigationPath
    @State private var creating = false
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    Logo(size: 120)
                    Text("Drunkin")
                        .font(.display(.largeTitle))
                        .foregroundStyle(Theme.cream)
                    Text("Score every pour. Reveal together.")
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 8)

                VStack(spacing: 10) {
                    Button { creating = true } label: { Label("Host a tasting", systemImage: "wineglass") }
                        .buttonStyle(.primary)
                    Button { path.append(Route.join) } label: { Label("Join a tasting nearby", systemImage: "antenna.radiowaves.left.and.right") }
                        .buttonStyle(.ghost)
                }

                section("Hosting", model.sortedTastings.filter { $0.role == .host })
                section("Joined", model.sortedTastings.filter { $0.role == .guest })
                section("Past tastings", model.sortedTastings.filter { $0.role == .archive })

                if model.tastings.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How it works").font(.display(.title3)).foregroundStyle(Theme.cream)
                        howTo("1", "One person hosts and sets up the flights.")
                        howTo("2", "Everyone else taps Join and types the host's 6-digit code. Phones talk directly over Bluetooth and Wi-Fi, no signal needed.")
                        howTo("3", "Score each pour 1 to 5. Scores stay hidden until the whole table is in, then reveal on every phone.")
                        howTo("4", "Afterwards, share the tasting as a file so everyone keeps the results.")
                    }
                    .padding(16)
                    .card()
                }

                Button { importing = true } label: { Label("Open a tasting file", systemImage: "square.and.arrow.down") }
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 4)
            }
            .padding()
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .screen()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { path.append(Route.settings) } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $creating) {
            NewTastingView { id in
                creating = false
                path.append(Route.tasting(id))
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.drunkinTasting]) { result in
            switch result {
            case .success(let url):
                do {
                    let id = try model.importFile(url)
                    path.append(Route.tasting(id))
                } catch {
                    importError = (error as? LocalizedError)?.errorDescription ?? "Couldn't open that file."
                }
            case .failure:
                importError = "Couldn't open that file."
            }
        }
        .alert("Couldn't import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ list: [Tasting]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(title)
                ForEach(list) { t in
                    Button { path.append(Route.tasting(t.id)) } label: { TastingRow(tasting: t) }
                        .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
    }

    private func howTo(_ n: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(n).font(.numeral(.headline)).foregroundStyle(Theme.gold)
            Text(text).foregroundStyle(Theme.cream.opacity(0.9))
        }
    }
}

struct TastingRow: View {
    var tasting: Tasting

    var body: some View {
        let pours = tasting.allPours.count
        let revealed = tasting.allPours.filter { tasting.statuses[$0.pour.id]?.revealed == true }.count
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tasting.menu.title)
                    .font(.display(.title3))
                    .foregroundStyle(Theme.cream)
                    .lineLimit(2)
                Text(detail(pours: pours, revealed: revealed))
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .contentShape(Rectangle())
    }

    private func detail(pours: Int, revealed: Int) -> String {
        var bits: [String] = []
        if !tasting.menu.subtitle.isEmpty { bits.append(tasting.menu.subtitle) }
        bits.append("\(tasting.tasters.count) \(tasting.tasters.count == 1 ? "taster" : "tasters")")
        bits.append("\(revealed)/\(pours) revealed")
        if tasting.role == .guest, let h = tasting.hostName, !h.isEmpty { bits.append("hosted by \(h)") }
        return bits.joined(separator: " · ")
    }
}

struct NewTastingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    var onCreate: (UUID) -> Void

    @State private var title = ""
    @State private var subtitle = ""
    @State private var name = ""
    @State private var template: TastingTemplate = .bourbonBasics

    var body: some View {
        NavigationStack {
            Form {
                Section("Tasting") {
                    TextField("Name, e.g. Friday Bourbon Night", text: $title)
                        .textInputAutocapitalization(.words)
                    TextField("Place or date (optional)", text: $subtitle)
                }
                Section {
                    TextField("Your name", text: $name)
                        .textInputAutocapitalization(.words)
                        .textContentType(.givenName)
                } header: {
                    Text("You")
                } footer: {
                    Text("This is how you'll show up to the table.")
                }
                Section("Start from") {
                    ForEach(TastingTemplate.allCases) { t in
                        Button {
                            template = t
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title).foregroundStyle(Theme.cream)
                                    Text(t.blurb).font(.footnote).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                if template == t { Image(systemName: "checkmark").foregroundStyle(Theme.gold) }
                            }
                        }
                        .accessibilityAddTraits(template == t ? .isSelected : [])
                    }
                }
            }
            .screen()
            .navigationTitle("Host a tasting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let id = model.createTasting(title: title, subtitle: subtitle, yourName: name, template: template)
                        onCreate(id)
                    }
                    .disabled(Sanitize.line(title).isEmpty || Sanitize.line(name).isEmpty)
                }
            }
        }
    }
}
