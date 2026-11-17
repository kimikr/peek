import SwiftData
import SwiftUI

// SwiftData on Linux: `peek dev examples/Notes` builds @Model, @Query and #Predicate with peek's
// own macros. Notes are saved on the phone, so they are still there after a relaunch.

@Model
final class Folder {
    @Attribute(.unique) var name: String
    @Relationship(deleteRule: .cascade, inverse: \Note.folder) var notes: [Note] = []

    init(name: String) { self.name = name }
}

@Model
final class Note {
    var text: String
    var created: Date = Date.now
    var pinned: Bool = false
    var folder: Folder?
    @Transient var editing = false

    init(text: String, folder: Folder?) {
        self.text = text
        self.folder = folder
    }
}

struct NotesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Note.created, order: .reverse) private var notes: [Note]
    @Query(filter: #Predicate<Note> { $0.pinned }, sort: \Note.created) private var pinned: [Note]
    @Query private var folders: [Folder]
    @State private var text = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("New note", text: $text)
                        .onSubmit(add)
                }
                if !pinned.isEmpty {
                    Section("Pinned") {
                        ForEach(pinned) { Text($0.text) }
                    }
                }
                Section("All notes (\(notes.count)) · folders \(folders.count)") {
                    ForEach(notes) { note in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(note.text)
                                Text("\(note.folder?.name ?? "-") · \(note.created.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                note.pinned.toggle()
                            } label: {
                                Image(systemName: note.pinned ? "pin.fill" : "pin")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(notes[index]) }
                    }
                }
            }
            .navigationTitle("Notes")
        }
    }

    private func add() {
        guard !text.isEmpty else { return }
        let inbox = folders.first { $0.name == "Inbox" } ?? Folder(name: "Inbox")
        context.insert(Note(text: text, folder: inbox))
        try? context.save()
        text = ""
    }
}

#Preview {
    NotesView()
        .modelContainer(for: [Note.self, Folder.self])
}
