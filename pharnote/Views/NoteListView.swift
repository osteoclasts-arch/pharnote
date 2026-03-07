import CoreData
import SwiftUI

struct NoteListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var persistence: PersistenceController

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Note.updatedAt, ascending: false)],
        animation: .default
    )
    private var notes: FetchedResults<Note>

    @State private var navigationPath: [NSManagedObjectID] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                if let bannerMessage = persistence.syncState.bannerMessage {
                    SyncStatusBanner(
                        message: bannerMessage,
                        isError: persistence.syncState.isError
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                List {
                    ForEach(notes) { note in
                        NavigationLink(value: note.objectID) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(note.wrappedTitle)
                                    .font(.headline)
                                    .lineLimit(1)

                                Text(note.wrappedBody.isEmpty ? "No content" : note.wrappedBody)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)

                                HStack {
                                    if !note.wrappedTags.isEmpty {
                                        Text("#\(note.wrappedTags)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(note.wrappedUpdatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete(perform: deleteNotes)
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("pharnode")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        createNoteAndOpen()
                    } label: {
                        Label("새 노트", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: NSManagedObjectID.self) { objectID in
                if let note = try? viewContext.existingObject(with: objectID) as? Note {
                    NoteDetailView(note: note)
                } else {
                    ContentUnavailableView(
                        "Note Not Found",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The note may have been deleted on another device.")
                    )
                }
            }
            .overlay {
                if notes.isEmpty {
                    ContentUnavailableView(
                        "노트가 없습니다",
                        systemImage: "note.text",
                        description: Text("+ 버튼으로 첫 노트를 만드세요.")
                    )
                    // Prevent this placeholder overlay from blocking toolbar/tab interactions.
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private func createNoteAndOpen() {
        let note = Note.create(in: viewContext)
        persistence.saveViewContextIfNeeded()
        navigationPath.append(note.objectID)
    }

    private func deleteNotes(offsets: IndexSet) {
        offsets.map { notes[$0] }.forEach(viewContext.delete)
        persistence.saveViewContextIfNeeded()
    }
}

private struct SyncStatusBanner: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isError {
                Image(systemName: "exclamationmark.triangle.fill")
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.primary)
            }

            Text(message)
                .font(.footnote)
                .fontWeight(.medium)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(isError ? Color.red.opacity(0.15) : Color.blue.opacity(0.12))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
