import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var persistence: PersistenceController

    var body: some View {
        NavigationStack {
            Form {
                Section("Sync") {
                    Toggle(
                        "iCloud 동기화 사용",
                        isOn: Binding(
                            get: { persistence.isCloudSyncEnabled },
                            set: { persistence.setCloudSyncEnabled($0) }
                        )
                    )

                    HStack {
                        Text("상태")
                        Spacer()
                        statusLabel
                    }

                    Button("iCloud 계정 다시 확인") {
                        persistence.refreshICloudAccountStatus()
                    }
                    .disabled(!persistence.isCloudSyncEnabled)
                }

                Section("개인정보") {
                    Text("노트는 본인 iCloud Private Database에만 동기화됩니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("오프라인 동작") {
                    Text("iCloud가 불가한 경우에도 로컬 편집은 계속 가능하며, 연결 복구 시 자동 동기화됩니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("설정")
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch persistence.syncState {
        case .disabled:
            Text("꺼짐")
                .foregroundStyle(.secondary)
        case .syncing:
            Label("동기화 중", systemImage: "arrow.triangle.2.circlepath")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.blue)
        case .idle:
            Label("연결됨", systemImage: "checkmark.icloud")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.green)
        case .unavailable:
            Label("사용 불가", systemImage: "icloud.slash")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.orange)
        case .error:
            Label("오류", systemImage: "exclamationmark.octagon")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(PersistenceController.shared)
}
