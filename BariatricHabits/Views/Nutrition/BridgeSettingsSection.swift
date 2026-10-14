import SwiftUI

struct BridgeSettingsSection: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var analysisQueue: AnalysisQueue
    @State private var token = KeychainStore.load(account: BridgeConfig.tokenAccount) ?? ""
    @State private var message: String?
    @State private var isChecking = false

    private var address: Binding<String> {
        Binding(get: { store.state.settings.bridgeURL ?? "" },
                set: { store.state.settings.bridgeURL = $0.isEmpty ? nil : $0 })
    }

    var body: some View {
        Section {
            TextField("כתובת Tailscale של המק, למשל mac.tailnet.ts.net", text: address)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .environment(\.layoutDirection, .leftToRight)
            SecureField("טוקן", text: $token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: token) { _, newValue in saveToken(newValue) }
            Button {
                Task { await check() }
            } label: {
                HStack {
                    Text("בדיקת חיבור")
                    if isChecking { Spacer(); ProgressView() }
                }
            }
            .disabled(isChecking)
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("זיהוי ארוחות דרך המק")
        } footer: {
            Text("את הכתובת והטוקן מקבלים מהפקודה bridge/install.sh במק. רק כתובת Tailscale מתקבלת (100.x.x.x או שם שמסתיים ב-ts.net). הטוקן נשמר ב-Keychain.")
        }
    }

    private func saveToken(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            KeychainStore.delete(account: BridgeConfig.tokenAccount)
            return
        }
        do {
            try KeychainStore.save(trimmed, account: BridgeConfig.tokenAccount)
        } catch {
            message = "שמירת הטוקן נכשלה (\(error))."
        }
    }

    private func check() async {
        isChecking = true
        defer { isChecking = false }
        guard let client = BridgeConfig.makeClient(settings: store.state.settings) else {
            message = "חסרים כתובת או טוקן, או שהכתובת אינה כתובת Tailscale (100.x.x.x או שם שמסתיים ב-ts.net)."
            return
        }
        do {
            let health = try await client.health()
            if health.claude {
                message = "מחובר. Claude זמין במק."
                store.requeueUnauthorized()
                analysisQueue.kick()
            } else {
                message = BridgeError.claudeUnavailable.messageHe
            }
        } catch {
            message = ((error as? BridgeError) ?? .unreachable).messageHe
        }
    }
}
