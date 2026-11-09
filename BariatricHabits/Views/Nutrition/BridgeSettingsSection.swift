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
            guard health.claude else {
                message = "המק מחובר, אבל Claude Code לא נמצא בו. התקינו אותו והריצו שוב את bridge/install.sh."
                return
            }
            message = "המק מחובר. בודק ש-Claude עונה…"
            message = await selfTestMessage(client)
            // The token is right either way, so meals that failed on a wrong token can go again.
            store.requeueUnauthorized()
            analysisQueue.kick()
        } catch {
            message = ((error as? BridgeError) ?? .unreachable).messageHe
        }
    }

    /// `health` only proves the bridge is up; this runs Claude once so a logged-out Mac shows here,
    /// not later as meals that never get identified.
    private func selfTestMessage(_ client: BridgeClienting) async -> String {
        do {
            try await client.selfTest()
            return "מחובר. Claude עונה במק."
        } catch BridgeError.server(404) {
            return "המק מחובר. הגשר במק בגרסה ישנה — עדכנו את הקוד במק והפעילו את הגשר מחדש כדי לבדוק גם את Claude."
        } catch BridgeError.timeout {
            return "המק מחובר, אבל Claude לא ענה בזמן. נסו שוב בעוד דקה."
        } catch {
            return ((error as? BridgeError) ?? .unreachable).messageHe
        }
    }
}
