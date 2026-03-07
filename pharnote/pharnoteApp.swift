import CoreData
import SwiftUI

@main
struct PharnoteApp: App {
    @StateObject private var persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id(persistence.contextToken)
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .environmentObject(persistence)
                .sheet(item: $persistence.presentedError) { error in
                    SyncErrorSheet(error: error)
                }
                .task {
                    persistence.refreshICloudAccountStatus()
                }
        }
    }
}

private struct SyncErrorSheet: View {
    let error: PersistenceController.PresentedError
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(error.title)
                    .font(.title3.weight(.semibold))
                Text(error.message)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(20)
            .navigationTitle("Sync Notice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
