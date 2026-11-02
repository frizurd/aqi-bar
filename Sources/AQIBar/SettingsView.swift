import AQICore
import SwiftUI
import ServiceManagement

extension AQIBand {
    var nsColor: NSColor {
        NSColor(srgbRed: Double((rgb >> 16) & 255) / 255,
                green: Double((rgb >> 8) & 255) / 255,
                blue: Double(rgb & 255) / 255, alpha: 1)
    }
    var color: Color { Color(nsColor: nsColor) }
}

@MainActor
struct SettingsView: View {
    @ObservedObject var store: AQIStore
    @StateObject private var search: LocationSearch
    @State private var keyInput = ""
    @State private var keyMessage: String?
    @State private var loginEnabled = false
    @State private var loginMessage: String?
    @State private var credentialSummary: String

    init(store: AQIStore, search: LocationSearch? = nil, isDemo: Bool = false) {
        self.store = store
        _search = StateObject(wrappedValue: search ?? LocationSearch())
        _loginEnabled = State(initialValue: isDemo ? false : SMAppService.mainApp.status == .enabled)
        _credentialSummary = State(initialValue: isDemo ? "Demo API key configured." : (Credentials.savedKey.isEmpty
            ? (Credentials.existingPluginKey.isEmpty ? "An IQAir API key is required." : "Using your existing SketchyBar IQAir key.")
            : "Using an API key saved in your Mac’s Keychain."))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("AQI Bar").font(.system(size: 25, weight: .semibold))
                        Text("Air quality in your menu bar.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.isRefreshing { ProgressView().controlSize(.small).padding(.top, 8) }
                }
                readingCard
                VStack(alignment: .leading, spacing: 10) {
                    Text("Location").font(.headline)
                    Label(store.selection.title, systemImage: "mappin.and.ellipse")
                        .font(.callout).textSelection(.enabled)
                    HStack {
                        TextField("City and country, e.g. Jakarta, Indonesia", text: $search.query)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { search.find() }
                            .onChange(of: search.query) { _ in search.clear() }
                            .accessibilityIdentifier("location-input")
                        Button("Search") { search.find() }
                            .disabled(search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if search.isSearching {
                        HStack { ProgressView().controlSize(.small); Text("Searching locations…").foregroundStyle(.secondary) }
                    }
                    ForEach(search.results.prefix(5)) { result in
                        Button {
                            store.select(.fixed(result))
                            search.clear()
                        } label: {
                            HStack {
                                Image(systemName: "mappin.circle")
                                Text(result.name).multilineTextAlignment(.leading)
                                Spacer()
                                Text("Use location").foregroundStyle(.secondary)
                            }
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain)
                    }
                    if let error = search.error { Text(error).foregroundStyle(.red).font(.caption) }
                    Button("Use automatic location (public IP)") { store.select(.automatic); search.clear() }
                        .buttonStyle(.link)
                    Text("Choose a result to save it. IQAir reports the nearest supported city; its name may differ from your search. Automatic location can follow your VPN.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                DisclosureGroup("IQAir API key") {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(credentialSummary).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            SecureField("Paste your IQAir API key", text: $keyInput)
                                .textFieldStyle(.roundedBorder)
                            Button("Save key") {
                                do {
                                    try Credentials.save(keyInput)
                                    keyInput = ""
                                    credentialSummary = "Using an API key saved in your Mac’s Keychain."
                                    keyMessage = "Saved securely."
                                    store.refresh()
                                } catch { keyMessage = error.localizedDescription }
                            }.disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if let keyMessage { Text(keyMessage).font(.caption).textSelection(.enabled) }
                        Link("Get a free IQAir Community API key", destination: URL(string: "https://www.iqair.com/air-pollution-data-api")!)
                            .font(.caption)
                    }.padding(.top, 8)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Open at login", isOn: $loginEnabled)
                        .onChange(of: loginEnabled) { enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register() }
                                else { try SMAppService.mainApp.unregister() }
                                loginMessage = SMAppService.mainApp.status == .requiresApproval
                                    ? "Allow AQI Bar in System Settings → General → Login Items." : nil
                            } catch {
                                loginMessage = "Couldn’t change login settings: \(error.localizedDescription)"
                                loginEnabled = SMAppService.mainApp.status == .enabled
                            }
                        }
                    if let loginMessage { Text(loginMessage).font(.caption).foregroundStyle(.secondary) }
                    Text("Refreshes every 15 minutes and when your Mac wakes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("US AQI colors") {
                    VStack(spacing: 8) {
                        ForEach(AQIBand.allCases, id: \.rawValue) { band in
                            HStack {
                                Circle().fill(band.color).frame(width: 9, height: 9)
                                Text(band.title)
                                Spacer()
                                Text(band.range).foregroundStyle(.secondary).monospacedDigit()
                            }.font(.caption)
                        }
                    }.padding(.top, 10)
                }
                HStack {
                    Link("Data from IQAir", destination: URL(string: "https://www.iqair.com/")!)
                    Spacer()
                    Button("Refresh now") { store.refresh() }.disabled(store.isRefreshing)
                }.font(.caption)
            }.padding(26)
        }
        .frame(width: 510, height: 670)
    }

    private var readingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let reading = store.reading {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(reading.value)").font(.system(size: 46, weight: .medium, design: .rounded))
                        .foregroundStyle(reading.band.color).monospacedDigit()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("US AQI").font(.caption).foregroundStyle(.secondary)
                        Text(reading.band.title).font(.headline)
                    }
                    Spacer()
                    if store.isStale { Label("Last known", systemImage: "clock.badge.exclamationmark").font(.caption) }
                }
                Text(reading.place).font(.callout).textSelection(.enabled)
                if let observed = reading.observedAt {
                    Text("Measured \(observed.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Checked \(reading.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(store.isRefreshing ? "Checking air quality…" : "AQI unavailable")
                    .font(.title3.weight(.medium))
                Text("Choose a location below to see its air quality.")
                    .foregroundStyle(.secondary)
            }
            if let message = store.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
    }
}
