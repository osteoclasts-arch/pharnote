import SwiftUI

@main
struct PharnoteApp: App {
    @StateObject private var searchInfrastructure = SearchInfrastructure()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(searchInfrastructure)
                .dynamicTypeSize(.medium ... .accessibility3)
                .background(PharTheme.ColorToken.appBackground)
                .task {
                    searchInfrastructure.start()
                }
        }
    }
}
