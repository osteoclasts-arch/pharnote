import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var persistence: PersistenceController

    var body: some View {
        NavigationStack {
            Form {
                Section("Sync") {
                    Toggle(
                        "Enable iCloud Sync",
                        isOn: Binding(
                            get: { persistence.isCloudSyncEnabled },
                            set: { persistence.setCloudSyncEnabled($0) }
                        )
                    )

                    HStack {
                        Text("Status")
                        Spacer()
                        statusLabel
                    }

                    Button("Recheck iCloud Account") {
                        persistence.refreshICloudAccountStatus()
                    }
                    .disabled(!persistence.isCloudSyncEnabled)
                }

                Section("Privacy") {
                    Text("Notes sync only to your private iCloud database.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Fallback") {
                    Text("If iCloud is unavailable, notes remain editable offline and sync resumes automatically when iCloud is available again.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch persistence.syncState {
        case .disabled:
            Text("Disabled")
                .foregroundStyle(.secondary)
        case .syncing:
            Label("Syncing", systemImage: "arrow.triangle.2.circlepath")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.blue)
        case .idle:
            Label("Connected", systemImage: "checkmark.icloud")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.green)
        case .unavailable:
            Label("Unavailable", systemImage: "icloud.slash")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.orange)
        case .error:
            Label("Error", systemImage: "exclamationmark.octagon")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(PersistenceController.shared)
}
