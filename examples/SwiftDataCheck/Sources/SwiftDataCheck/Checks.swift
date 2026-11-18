import SwiftData
import SwiftUI
import UIKit

@Model
final class Shelf {
    #Index<Shelf>([\.name])
    var name: String
    @Relationship(deleteRule: .cascade, inverse: \Book.shelf) var books: [Book] = []
    init(name: String) { self.name = name }
}

@Model
final class Book {
    var title: String
    var shelf: Shelf?
    init(title: String, shelf: Shelf?) {
        self.title = title
        self.shelf = shelf
    }
}

@Model
final class Tag {
    #Unique<Tag>([\.name])
    var name: String
    var uses: Int
    init(name: String, uses: Int) {
        self.name = name
        self.uses = uses
    }
}

@Model
final class Link {
    @Attribute(.transformable(by: NSSecureUnarchiveFromDataTransformer.self)) var url: NSURL
    init(url: NSURL) { self.url = url }
}

@ModelActor
actor Importer {
    func add(_ count: Int) throws {
        for n in 0..<count { modelContext.insert(Tag(name: "imported \(n)", uses: n)) }
        try modelContext.save()
    }
}

func say(_ line: String) {
    print(line)
    fflush(stdout)  // reaches peek even if the next step crashes
}

@MainActor
func runChecks(_ report: @escaping ([(String, Bool)]) -> Void) async {
    var results: [(String, Bool)] = []
    func check(_ name: String, _ body: () throws -> Bool) {
        let ok = (try? body()) ?? false
        results.append((name, ok))
        report(results)
        say("peek check: \(ok ? "PASS" : "FAIL") \(name)")
    }
    func memory(_ types: [any PersistentModel.Type]) throws -> ModelContainer {
        try ModelContainer(for: Schema(types), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    do {
        let container = try memory([Shelf.self, Book.self, Tag.self])
        let context = container.mainContext
        check("container with #Index and #Unique") { true }

        let shelf = Shelf(name: "Fiction")
        context.insert(shelf)
        context.insert(Book(title: "Dune", shelf: shelf))
        context.insert(Book(title: "Emma", shelf: shelf))
        try context.save()
        check("inverse relationship fills shelf.books") { shelf.books.count == 2 }

        context.delete(shelf)
        try context.save()
        check("deleteRule .cascade deletes the books") { try context.fetchCount(FetchDescriptor<Book>()) == 0 }

        context.insert(Tag(name: "swift", uses: 1))
        try context.save()
        context.insert(Tag(name: "swift", uses: 5))
        try context.save()
        check("#Unique upserts a duplicate") {
            let tags = try context.fetch(FetchDescriptor<Tag>(predicate: #Predicate { $0.name == "swift" }))
            return tags.count == 1 && tags[0].uses == 5
        }

        try await Importer(modelContainer: container).add(3)
        check("@ModelActor inserts on its own context") {
            try context.fetchCount(FetchDescriptor<Tag>(predicate: #Predicate { $0.name.starts(with: "imported") })) == 3
        }

        let links = try memory([Link.self])
        links.mainContext.insert(Link(url: NSURL(string: "https://swift.org")!))
        try links.mainContext.save()
        check("transformable (Apple's transformer) survives a fresh context") {
            try ModelContext(links).fetch(FetchDescriptor<Link>()).first?.url.absoluteString == "https://swift.org"
        }

    } catch {
        say("peek check: FAIL \(error)")
        results.append(("\(error)", false))
        report(results)
    }
}

struct ChecksView: View {
    @State private var results: [(String, Bool)] = []

    var body: some View {
        NavigationStack {
            List(results.indices, id: \.self) { i in
                Label(results[i].0, systemImage: results[i].1 ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(results[i].1 ? .green : .red)
            }
            .navigationTitle("SwiftData checks")
        }
        .task { await runChecks { results = $0 } }
    }
}

#Preview { ChecksView() }
