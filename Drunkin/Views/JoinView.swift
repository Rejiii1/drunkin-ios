import SwiftUI

struct JoinView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: NearbyHost?
    @State private var code = ""
    @FocusState private var codeFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Join a tasting").font(.display(.largeTitle)).foregroundStyle(Theme.cream)
                Text("Stay close to the host. Phones connect directly over Bluetooth and Wi-Fi, so no cell signal or internet is needed.")
                    .foregroundStyle(Theme.muted)

                if case .failed(let msg) = model.guestLink {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.alert)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                }

                Eyebrow("Nearby")
                if model.nearbyHosts.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Looking for tastings nearby…").foregroundStyle(Theme.muted)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                    Text("Ask the host to open their tasting in Drunkin. If nothing shows up, make sure Local Network is allowed for Drunkin in Settings → Privacy & Security → Local Network, and that Bluetooth is on.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                ForEach(model.nearbyHosts) { h in
                    Button {
                        selected = h
                        code = ""
                        codeFocused = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(h.title).font(.headline).foregroundStyle(Theme.cream)
                                Text("Hosted by \(h.hostName)").font(.subheadline).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            if selected?.id == h.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.gold) }
                        }
                        .padding(16)
                        .card(highlighted: selected?.id == h.id)
                    }
                    .buttonStyle(.plain)
                }

                if let h = selected {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Enter the 6-digit code shown on \(h.hostName)'s phone")
                            .font(.headline).foregroundStyle(Theme.cream)
                        TextField("000000", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .padding(12)
                            .background(Theme.night, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                            .focused($codeFocused)
                            .onChange(of: code) { _, v in
                                let digits = String(v.filter(\.isASCIIDigit).prefix(6))
                                if digits != v { code = digits }
                            }
                        Button {
                            model.guest.join(h, code: code, deviceID: model.deviceID)
                        } label: {
                            if case .connecting(let id) = model.guestLink, id == h.tastingID {
                                ProgressView().tint(Theme.night)
                            } else {
                                Text("Join")
                            }
                        }
                        .buttonStyle(.primary)
                        .disabled(code.count != 6)
                    }
                    .padding(16)
                    .card()
                }
            }
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .screen()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.joinScreenOpen = true }
        .onDisappear { model.joinScreenOpen = false }
    }
}
