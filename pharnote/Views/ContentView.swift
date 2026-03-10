import SwiftUI

struct ContentView: View {
    var body: some View {
        LibraryView()
    }
}

#Preview {
    let analysisCenter = AnalysisCenter()
    let authManager = PharnodeSupabaseAuthManager()
    ContentView()
        .environmentObject(analysisCenter)
        .environmentObject(authManager)
        .environmentObject(PharnodeCloudSyncManager(analysisCenter: analysisCenter, authManager: authManager))
}
