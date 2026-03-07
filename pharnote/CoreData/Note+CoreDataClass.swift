import CoreData
import Foundation

@objc(Note)
public final class Note: NSManagedObject, Identifiable {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Note> {
        NSFetchRequest<Note>(entityName: "Note")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var body: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var tags: String?
    @NSManaged public var isLocked: Bool
}

extension Note {
    var wrappedID: UUID {
        id ?? UUID()
    }

    var wrappedTitle: String {
        get { title ?? "Untitled" }
        set { title = newValue }
    }

    var wrappedBody: String {
        get { body ?? "" }
        set { body = newValue }
    }

    var wrappedTags: String {
        get { tags ?? "" }
        set { tags = newValue }
    }

    var wrappedCreatedAt: Date {
        createdAt ?? Date()
    }

    var wrappedUpdatedAt: Date {
        updatedAt ?? createdAt ?? Date()
    }

    static func create(in context: NSManagedObjectContext) -> Note {
        let note = Note(context: context)
        let now = Date()
        note.id = UUID()
        note.title = "Untitled"
        note.body = ""
        note.tags = ""
        note.createdAt = now
        note.updatedAt = now
        note.isLocked = false
        return note
    }
}
