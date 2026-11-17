import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import SwiftDataMacros

final class ExpansionTests: XCTestCase {
    func testQuery() {
        assertMacroExpansion(
            """
            struct V {
                @Query(sort: \\Note.created) var notes: [Note]
            }
            """,
            expandedSource: """
            struct V {
                var notes: [Note] {
                    get {
                        _notes.wrappedValue
                    }
                }

                private var _notes: SwiftData.Query<Note, [Note]> = SwiftData.Query(sort: \\Note.created)
            }
            """,
            macros: ["Query": QueryMacro.self])
    }

    func testModelPersistsStoredPropertiesOnly() {
        assertMacroExpansion(
            """
            @Model final class Note {
                @Attribute(.unique) var text: String
                var pinned: Bool = false
                @Transient var editing = false
                var shout: String { text.uppercased() }
            }
            """,
            expandedSource: """
            final class Note {
                @Attribute(.unique)
                @_PersistedProperty var text: String
                @_PersistedProperty
                var pinned: Bool = false
                @Transient var editing = false
                var shout: String { text.uppercased() }

                @Transient
                private var _$backingData: any SwiftData.BackingData<Note> = Note.createBackingData()

                public var persistentBackingData: any SwiftData.BackingData<Note> {
                    get {
                        return _$backingData
                    }
                    set {
                        _$backingData = newValue
                    }
                }

                static var schemaMetadata: [SwiftData.Schema.PropertyMetadata] {
                    let storedProperties = [
                        SwiftData.Schema.PropertyMetadata(name: "text", keypath: \\Note.text, defaultValue: nil, metadata: SwiftData.Schema.Attribute(.unique)),
                        SwiftData.Schema.PropertyMetadata(name: "pinned", keypath: \\Note.pinned, defaultValue: false, metadata: nil)
                    ] as [SwiftData.Schema.PropertyMetadata]
                    var otherProperties = [SwiftData.Schema.PropertyMetadata]()

                    return storedProperties + otherProperties
                }

                required init(backingData: any SwiftData.BackingData<Note>) {
                    _text = _SwiftDataNoType()
                    _pinned = _SwiftDataNoType()
                    self.persistentBackingData = backingData
                }

                @Transient
                private let _$observationRegistrar = Observation.ObservationRegistrar()

                internal nonisolated func access<_M>(keyPath: KeyPath<Note, _M>) {
                    _$observationRegistrar.access(self, keyPath: keyPath)
                }

                internal nonisolated func withMutation<_M, _MR>(keyPath: KeyPath<Note, _M>, _ mutation: () throws -> _MR) rethrows -> _MR {
                    try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
                }

                struct _SwiftDataNoType {
                }
            }

            extension Note: SwiftData.PersistentModel {
            }

            extension Note: Observation.Observable {
            }
            """,
            macroSpecs: ["Model": MacroSpec(type: PersistentModelMacro.self, conformances: ["PersistentModel", "Observable"])])
    }
}
