import SwiftUI

struct AgeGateView: View {
    @Environment(AppModel.self) private var model
    @State private var declined = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Logo(size: 160).padding(.top, 48)
                Text("Drunkin")
                    .font(.display(.largeTitle))
                    .foregroundStyle(Theme.cream)
                Text("Blind-scored tastings with your friends. Everyone scores each pour, and the table's scores stay hidden until everyone is in.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.muted)

                if declined {
                    VStack(spacing: 8) {
                        Text("Sorry, Drunkin is only for adults of legal drinking age.")
                            .font(.headline)
                            .foregroundStyle(Theme.cream)
                        Text("Come back when you are.")
                            .foregroundStyle(Theme.muted)
                    }
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .card()
                } else {
                    VStack(spacing: 12) {
                        Text("Are you of legal drinking age where you live?")
                            .font(.headline)
                            .foregroundStyle(Theme.cream)
                            .multilineTextAlignment(.center)
                        Button("Yes, I am") { model.ageConfirmed = true }
                            .buttonStyle(.primary)
                        Button("No") { declined = true }
                            .buttonStyle(.ghost)
                    }
                    .padding(.top, 8)
                }

                Text("Please drink responsibly. Never drink and drive.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 12)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.night.ignoresSafeArea())
    }
}
