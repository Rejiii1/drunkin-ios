import SwiftUI

@main
struct DrunkinApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
        }
        .onChange(of: phase) { _, newPhase in
            model.setActive(newPhase != .background)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()
    @State private var importError: String?

    var body: some View {
        Group {
            if model.ageConfirmed {
                NavigationStack(path: $path) {
                    HomeView(path: $path)
                        .navigationDestination(for: Route.self) { route in
                            route.destination
                        }
                }
            } else {
                AgeGateView()
            }
        }
        .overlay(alignment: .bottom) { ToastView(path: $path) }
        .onChange(of: model.openRequest) { _, id in
            guard let id else { return }
            model.openRequest = nil
            path = NavigationPath()
            path.append(Route.tasting(id))
        }
        .onOpenURL { url in
            guard model.ageConfirmed else { return }
            do {
                let id = try model.importFile(url)
                path = NavigationPath()
                path.append(Route.tasting(id))
            } catch {
                importError = (error as? LocalizedError)?.errorDescription ?? ImportError.unreadable.errorDescription
            }
        }
        .alert("Couldn't import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }
}

enum Route: Hashable {
    case tasting(UUID)
    case flight(UUID, UUID, focus: UUID?)
    case results(UUID, UUID)
    case leaderboard(UUID)
    case journal(UUID)
    case hostTools(UUID)
    case menuEditor(UUID)
    case join
    case settings

    @ViewBuilder var destination: some View {
        switch self {
        case .tasting(let id): TastingView(tastingID: id)
        case .flight(let t, let f, let focus): FlightView(tastingID: t, flightID: f, focusPour: focus)
        case .results(let t, let f): FlightResultsView(tastingID: t, flightID: f)
        case .leaderboard(let t): LeaderboardView(tastingID: t)
        case .journal(let t): JournalView(tastingID: t)
        case .hostTools(let t): HostToolsView(tastingID: t)
        case .menuEditor(let t): MenuEditorView(tastingID: t)
        case .join: JoinView()
        case .settings: SettingsView()
        }
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model
    @Binding var path: NavigationPath

    var body: some View {
        if let toast = model.toast {
            Button {
                model.toast = nil
                if let t = toast.tastingID, let p = toast.pourID, let tasting = model.tastings[t],
                   let f = tasting.flight(containing: p) {
                    path.append(Route.flight(t, f.id, focus: p))
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: toast.pourID == nil ? "info.circle.fill" : "sparkles")
                        .foregroundStyle(Theme.gold)
                    Text(toast.text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.cream)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if toast.pourID != nil {
                        Text("See").font(.footnote).foregroundStyle(Theme.muted)
                    }
                }
                .padding(14)
                .background(Theme.card2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.gold))
                .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: toast.id) {
                try? await Task.sleep(for: .seconds(6))
                if model.toast?.id == toast.id { withAnimation { model.toast = nil } }
            }
        }
    }
}
