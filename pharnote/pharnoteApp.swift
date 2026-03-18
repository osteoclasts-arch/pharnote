import SwiftUI

@main
struct PharnoteApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var analysisCenter: AnalysisCenter
    @StateObject private var eventLogger: StudyEventLogger
    @StateObject private var searchInfrastructure: SearchInfrastructure
    @StateObject private var authManager: PharnodeSupabaseAuthManager
    @StateObject private var cloudSyncManager: PharnodeCloudSyncManager
    @StateObject private var plannerCenter: PlannerCenter
    @StateObject private var eventSyncEngine: StudyEventSyncEngine
    @StateObject private var ontologyService: OntologyService

    init() {
        let analysisCenter = AnalysisCenter()
        let eventLogger = StudyEventLogger.shared
        let searchInfrastructure = SearchInfrastructure.shared
        let authManager = PharnodeSupabaseAuthManager()
        let cloudSyncManager = PharnodeCloudSyncManager(analysisCenter: analysisCenter, authManager: authManager)
        let plannerCenter = PlannerCenter()
        
        _analysisCenter = StateObject(wrappedValue: analysisCenter)
        _eventLogger = StateObject(wrappedValue: eventLogger)
        _searchInfrastructure = StateObject(wrappedValue: searchInfrastructure)
        _authManager = StateObject(wrappedValue: authManager)
        _cloudSyncManager = StateObject(wrappedValue: cloudSyncManager)
        _plannerCenter = StateObject(wrappedValue: plannerCenter)
        _eventSyncEngine = StateObject(wrappedValue: StudyEventSyncEngine(authManager: authManager, syncManager: cloudSyncManager))
        _ontologyService = StateObject(wrappedValue: OntologyService(authManager: authManager, syncManager: cloudSyncManager))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(analysisCenter)
                .environmentObject(eventLogger)
                .environmentObject(searchInfrastructure)
                .environmentObject(authManager)
                .environmentObject(cloudSyncManager)
                .environmentObject(plannerCenter)
                .environmentObject(ontologyService)
                .dynamicTypeSize(.medium ... .accessibility3)
                .background(PharTheme.ColorToken.appBackground)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        eventLogger.log(.appForegrounded, payload: ["reason": .string("resume")])
                        searchInfrastructure.start()
                        Task {
                            await authManager.handleAppDidBecomeActive()
                            await cloudSyncManager.handleAppDidBecomeActive()
                            await eventSyncEngine.syncPendingEvents()
                        }
                    case .background:
                        eventLogger.log(.appBackgrounded, payload: ["reason": .string("system")])
                        searchInfrastructure.stop()
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }
}
