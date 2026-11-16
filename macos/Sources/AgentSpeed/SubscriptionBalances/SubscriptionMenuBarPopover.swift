import SwiftUI

struct SubscriptionBalancePopover: View {
    @Bindable var state: SubscriptionBalanceState
    @State private var baseURLDraft = ""
    @State private var adminAPIKeyDraft = ""
    @State private var tokenDraft = ""
    @State private var refreshTokenDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Customize Sub 4 Tokens").font(.headline)
                    Text(state.lastRefresh.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Waiting for first refresh")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await state.refresh() } } label: {
                    Image(systemName: state.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(state.isRefreshing)
            }

            if let error = state.credentialError ?? state.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }

            if state.statuses.isEmpty {
                ContentUnavailableView("No balances yet", systemImage: "chart.bar.xaxis", description: Text("Connect this app to your Sub2API external subscriptions below."))
                    .frame(height: 110)
            } else {
                ForEach(state.statuses, id: \.provider, content: { (status: SubscriptionBalanceStatus) in
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(
                            get: { state.selectedProviderIDs.contains(status.provider) },
                            set: { enabled in
                                if enabled { state.selectedProviderIDs.insert(status.provider) }
                                else { state.selectedProviderIDs.remove(status.provider) }
                                state.restartRotation()
                            }
                        ))
                        .labelsHidden().toggleStyle(.checkbox)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(status.name).font(.subheadline.weight(.medium))
                            Text(status.errorMessage ?? status.currency.uppercased())
                                .font(.caption2).foregroundStyle(status.errorMessage == nil ? Color.secondary : Color.orange)
                        }
                        Spacer()
                        Text(status.remainingUSD.map { SubscriptionMoneyFormatter.string(amount: $0, currency: status.currency) } ?? "—")
                            .font(.system(.body, design: .monospaced)).fontWeight(.medium)
                    }
                })
            }

            Divider()
            Picker("Display", selection: $state.displayMode) {
                ForEach(SubscriptionBalanceMode.allCases) { Text($0.title).tag($0) }
            }
            .onChange(of: state.displayMode) { state.restartRotation() }

            HStack {
                Text("Refresh").frame(width: 80, alignment: .leading)
                Stepper(value: $state.refreshSeconds, in: 30...3600, step: 30) {
                    Text("\(Int(state.refreshSeconds)) sec")
                }
                .onChange(of: state.refreshSeconds) { state.scheduleRefresh() }
            }
            if state.displayMode == .rotation {
                HStack {
                    Text("Rotate").frame(width: 80, alignment: .leading)
                    Stepper(value: $state.rotationSeconds, in: 3...300, step: 1) {
                        Text("\(Int(state.rotationSeconds)) sec")
                    }
                    .onChange(of: state.rotationSeconds) { state.restartRotation() }
                }
            }

            DisclosureGroup("Sub2API connection") {
                TextField("https://ai.kreeper.cc", text: $baseURLDraft)
                    .textFieldStyle(.roundedBorder)
                SecureField("Sub2API global Admin API Key", text: Binding(
                    get: { adminAPIKeyDraft },
                    set: { adminAPIKeyDraft = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Sync providers") {
                        state.credentialError = nil
                        state.baseURL = baseURLDraft
                        state.setAdminAPIKey(adminAPIKeyDraft)
                        state.setToken(tokenDraft)
                        state.setRefreshToken(refreshTokenDraft)
                        if state.credentialError == nil { Task { await state.refresh() } }
                    }
                    .disabled(state.isRefreshing)
                    Spacer()
                    Text("Admin API Key · cached status").font(.caption2).foregroundStyle(.secondary)
                }

                DisclosureGroup("Legacy login tokens") {
                    SecureField("Sub2API access token", text: Binding(
                        get: { tokenDraft },
                        set: { tokenDraft = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    SecureField("Sub2API refresh token", text: Binding(
                        get: { refreshTokenDraft },
                        set: { refreshTokenDraft = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Text("Used only when no Admin API Key is set.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Text("A6API Cookie stays in Sub2API. This app only reads balance status.")
                .font(.caption2).foregroundStyle(.secondary)
            Text("The Admin API Key is stored in this Mac's Keychain. Keep it private.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .onAppear {
            baseURLDraft = state.baseURL
            adminAPIKeyDraft = state.adminAPIKey
            tokenDraft = state.accessToken
            refreshTokenDraft = state.refreshToken
        }
    }
}
