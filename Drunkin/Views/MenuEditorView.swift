import SwiftUI

/// Edits a draft; nothing reaches the table until Save. Pour ids never
/// change when renamed, so scores follow the pour.
struct MenuEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var tastingID: UUID

    @State private var draft = TastingMenu()
    @State private var loaded = false
    @State private var confirmDiscard = false

    var body: some View {
        Form {
            Section("Tasting") {
                TextField("Title", text: $draft.title)
                TextField("Place or date", text: $draft.subtitle)
            }
            Section {
                ForEach($draft.flights) { $flight in
                    NavigationLink {
                        FlightEditor(flight: $flight)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(flight.title.isEmpty ? "Untitled flight" : flight.title)
                            Text("\(flight.pours.count) \(flight.pours.count == 1 ? "pour" : "pours")")
                                .font(.footnote).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .onDelete { draft.flights.remove(atOffsets: $0) }
                .onMove { draft.flights.move(fromOffsets: $0, toOffset: $1) }
                Button("Add flight") {
                    draft.flights.append(Flight(title: "Flight \(draft.flights.count + 1)"))
                }
                .disabled(draft.flights.count >= Limits.flights)
            } header: {
                Text("Flights")
            } footer: {
                Text("Removing a pour hides its scores from results.")
            }
        }
        .screen()
        .navigationTitle("Edit menu")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isDirty)
        .toolbar {
            if isDirty {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { confirmDiscard = true }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    model.update(tastingID) { $0.replaceMenu(draft) }
                    dismiss()
                }
                .disabled(!isDirty)
            }
            ToolbarItem(placement: .bottomBar) { EditButton() }
        }
        .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
        }
        .onAppear {
            if !loaded, let t = model.tastings[tastingID] {
                draft = t.menu
                loaded = true
            }
        }
    }

    private var isDirty: Bool {
        loaded && model.tastings[tastingID]?.menu != draft
    }
}

struct FlightEditor: View {
    @Binding var flight: Flight

    var body: some View {
        Form {
            Section("Flight") {
                TextField("Title", text: $flight.title)
                TextField("Intro for the table", text: $flight.intro, axis: .vertical).lineLimit(2...6)
            }
            Section("Pours, in order") {
                ForEach($flight.pours) { $pour in
                    NavigationLink {
                        PourEditor(pour: $pour)
                    } label: {
                        Text(pour.name.isEmpty ? "Unnamed pour" : pour.name)
                    }
                }
                .onDelete { flight.pours.remove(atOffsets: $0) }
                .onMove { flight.pours.move(fromOffsets: $0, toOffset: $1) }
                Button("Add pour") { flight.pours.append(Pour(name: "Pour \(flight.pours.count + 1)")) }
                    .disabled(flight.pours.count >= Limits.poursPerFlight)
            }
        }
        .screen()
        .navigationTitle(flight.title.isEmpty ? "Flight" : flight.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }
}

struct PourEditor: View {
    @Binding var pour: Pour
    @State private var proofText = ""

    var body: some View {
        Form {
            Section("Pour") {
                TextField("Name", text: $pour.name)
                TextField("Proof", text: $proofText)
                    .keyboardType(.decimalPad)
                    .onChange(of: proofText) { _, v in
                        pour.proof = Sanitize.proof(Double(v.replacingOccurrences(of: ",", with: ".")))
                    }
                TextField("Style, age or batch", text: $pour.descriptor)
            }
            Section("Tasting notes (optional)") {
                TextField("Nose", text: $pour.nose, axis: .vertical)
                TextField("Palate", text: $pour.palate, axis: .vertical)
                TextField("Finish", text: $pour.finish, axis: .vertical)
            }
            Section("Fun fact (optional)") {
                TextField("Something to talk about", text: $pour.trivia, axis: .vertical).lineLimit(2...5)
            }
        }
        .screen()
        .navigationTitle(pour.name.isEmpty ? "Pour" : pour.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { proofText = pour.proof.map(Results.fmtProof) ?? "" }
    }
}
