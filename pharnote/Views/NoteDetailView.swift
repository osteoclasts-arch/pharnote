import SwiftUI

struct NoteDetailView: View {
    @ObservedObject var note: Note

    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var persistence: PersistenceController

    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Note") {
                TextField("Title", text: titleBinding)
                    .font(.headline)

                TextEditor(text: bodyBinding)
                    .frame(minHeight: 240)
                    .disabled(note.isLocked)
            }

            Section("Metadata") {
                TextField("Tags", text: tagsBinding)
                Toggle("Lock Note", isOn: lockBinding)

                LabeledContent("Created") {
                    Text(note.wrappedCreatedAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Updated") {
                    Text(note.wrappedUpdatedAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            saveTask?.cancel()
            persistence.saveViewContextIfNeeded()
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { note.wrappedTitle },
            set: { newValue in
                note.title = newValue
                note.updatedAt = Date()
                scheduleSave()
            }
        )
    }

    private var bodyBinding: Binding<String> {
        Binding(
            get: { note.wrappedBody },
            set: { newValue in
                note.body = newValue
                note.updatedAt = Date()
                scheduleSave()
            }
        )
    }

    private var tagsBinding: Binding<String> {
        Binding(
            get: { note.wrappedTags },
            set: { newValue in
                note.tags = newValue
                note.updatedAt = Date()
                scheduleSave()
            }
        )
    }

    private var lockBinding: Binding<Bool> {
        Binding(
            get: { note.isLocked },
            set: { newValue in
                note.isLocked = newValue
                note.updatedAt = Date()
                scheduleSave()
            }
        )
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            persistence.saveViewContextIfNeeded()
        }
    }
}
