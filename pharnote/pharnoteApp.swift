import SwiftUI

@main
struct PharnoteApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var analysisCenter: AnalysisCenter
    @StateObject private var eventLogger: StudyEventLogger
    @StateObject private var authManager: PharnodeSupabaseAuthManager
    @StateObject private var cloudSyncManager: PharnodeCloudSyncManager

    init() {
        let analysisCenter = AnalysisCenter()
        let eventLogger = StudyEventLogger.shared
        let authManager = PharnodeSupabaseAuthManager()
        _analysisCenter = StateObject(wrappedValue: analysisCenter)
        _eventLogger = StateObject(wrappedValue: eventLogger)
        _authManager = StateObject(wrappedValue: authManager)
        _cloudSyncManager = StateObject(wrappedValue: PharnodeCloudSyncManager(analysisCenter: analysisCenter, authManager: authManager))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(analysisCenter)
                .environmentObject(eventLogger)
                .environmentObject(authManager)
                .environmentObject(cloudSyncManager)
                .dynamicTypeSize(.medium ... .accessibility3)
                .background(PharTheme.ColorToken.appBackground)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        eventLogger.log(.appForegrounded, payload: ["reason": .string("resume")])
                        Task {
                            await authManager.handleAppDidBecomeActive()
                            await cloudSyncManager.handleAppDidBecomeActive()
                        }
                    case .background:
                        eventLogger.log(.appBackgrounded, payload: ["reason": .string("system")])
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }
}
