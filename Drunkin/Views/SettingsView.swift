import SwiftUI

enum AppLinks {
    static let privacy = URL(string: "https://rejiii1.github.io/drunkin-ios/privacy.html")!
    static let support = URL(string: "https://rejiii1.github.io/drunkin-ios/support.html")!
    static let helpline = URL(string: "tel:18006624357")!
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmWipe = false

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Logo(size: 56)
                    VStack(alignment: .leading) {
                        Text("Drunkin").font(.display(.title2))
                        Text("Version \(version)").font(.footnote).foregroundStyle(Theme.muted)
                    }
                }
            }

            Section {
                Text("Drunkin has no accounts, no servers, no ads, no analytics and no tracking. Your tastings are stored only on this phone. They're shared only with phones you let join your table, and as files you choose to send.")
                Link("Privacy policy", destination: AppLinks.privacy)
            } header: {
                Text("Privacy")
            }

            Section {
                Text("Drunkin is for adults of legal drinking age. Pour small, drink water between pours, and never drink and drive.")
                Link("Free, confidential help: SAMHSA 1-800-662-4357", destination: AppLinks.helpline)
            } header: {
                Text("Drink responsibly")
            } footer: {
                Text("US National Helpline, 24/7, 365 days a year.")
            }

            Section("Help") {
                Link("Support", destination: AppLinks.support)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Phones can't find each other?").font(.headline)
                    Text("Keep Drunkin open on the host's phone, turn on Bluetooth and Wi-Fi (you don't need to be on a network), and allow Local Network for Drunkin in Settings → Privacy & Security → Local Network.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                Button("Open iPhone Settings for Drunkin") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }

            Section {
                Button("Delete all Drunkin data on this phone", role: .destructive) { confirmWipe = true }
            } footer: {
                Text("Removes every tasting, photo and score stored on this phone. Copies on other phones aren't affected.")
            }
        }
        .screen()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete everything?", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("Delete all data", role: .destructive) {
                model.deleteEverything()
                dismiss()
            }
        } message: {
            Text("This can't be undone. Share any tastings you want to keep first.")
        }
    }
}
