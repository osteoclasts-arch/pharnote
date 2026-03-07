import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NoteListView()
                .tabItem {
                    Label("노트", systemImage: "note.text")
                }

            SettingsView()
                .tabItem {
                    Label("설정", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    ContentView()
}
