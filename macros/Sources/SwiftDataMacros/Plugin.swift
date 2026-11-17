// An open reimplementation of SwiftData's macros (Apple ships them only as a macOS binary), so
// SwiftData apps build on Linux. The expansions follow the ones Xcode shows for each macro.
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

@main
struct SwiftDataMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        PersistentModelMacro.self,
        PersistedPropertyMacro.self,
        TransformablePersistedPropertyMacro.self,
        AttributePropertyMacro.self,
        RelationshipPropertyMacro.self,
        TransientPropertyMacro.self,
        UniqueConstraintsMacro.self,
        IndexMacro.self,
        PersistentModelActorMacro.self,
        QueryMacro.self,
    ]
}

// MARK: - Stored properties of a model

struct ModelProperty {
    let name: String
    let decl: VariableDeclSyntax
    let binding: PatternBindingSyntax

    var initializer: ExprSyntax? { binding.initializer?.value }

    func attribute(_ name: String) -> AttributeSyntax? {
        decl.attributes.lazy.compactMap { $0.as(AttributeSyntax.self) }.first { attr in
            let type = attr.attributeName.trimmedDescription
            return type == name || type == "SwiftData." + name
        }
    }

    var isTransient: Bool { attribute("Transient") != nil }

    /// @Attribute(.transformable(by:)) values go through the transformable accessors.
    var isTransformable: Bool {
        attribute("Attribute")?.arguments?.trimmedDescription.contains(".transformable") ?? false
    }
}

extension VariableDeclSyntax {
    var isStatic: Bool {
        modifiers.contains { $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class) }
    }

    /// A property with storage: no accessors, or only willSet/didSet observers.
    func isStored(_ binding: PatternBindingSyntax) -> Bool {
        guard let accessors = binding.accessorBlock?.accessors else { return true }
        guard case .accessors(let list) = accessors else { return false }
        return list.allSatisfy { [.keyword(.willSet), .keyword(.didSet)].contains($0.accessorSpecifier.tokenKind) }
    }
}

func storedProperties(of decl: some DeclGroupSyntax) -> [ModelProperty] {
    decl.memberBlock.members.flatMap { member -> [ModelProperty] in
        guard let variable = member.decl.as(VariableDeclSyntax.self), !variable.isStatic else { return [] }
        return variable.bindings.compactMap { binding in
            guard variable.isStored(binding),
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.trimmedDescription,
                  !name.hasPrefix("_") else { return nil }
            return ModelProperty(name: name, decl: variable, binding: binding)
        }
    }
}

/// The arguments of the first `#Unique` / `#Index` in the class body.
func freestandingArguments(_ name: String, in decl: some DeclGroupSyntax) -> String? {
    for member in decl.memberBlock.members {
        if let macro = member.decl.as(MacroExpansionDeclSyntax.self), macro.macroName.text == name {
            let generic = macro.genericArgumentClause?.trimmedDescription ?? ""
            return generic + "(" + macro.arguments.trimmedDescription + ")"
        }
    }
    return nil
}

// MARK: - @Model

public struct PersistentModelMacro: MemberMacro, MemberAttributeMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf decl: some DeclGroupSyntax,
                                 conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let cls = decl.as(ClassDeclSyntax.self) else { return [] }
        let type = cls.name.trimmedDescription
        let properties = storedProperties(of: decl)
        let persisted = properties.filter { !$0.isTransient }

        let metadata = persisted.map { property -> String in
            var meta = "nil"
            if let attr = property.attribute("Attribute") {
                meta = "SwiftData.Schema.Attribute(\(attr.arguments?.trimmedDescription ?? ""))"
            } else if let attr = property.attribute("Relationship") {
                meta = "SwiftData.Schema.Relationship(\(attr.arguments?.trimmedDescription ?? ""))"
            }
            let value = property.initializer?.trimmedDescription ?? "nil"
            return "SwiftData.Schema.PropertyMetadata(name: \"\(property.name)\", keypath: \\\(type).\(property.name), defaultValue: \(value), metadata: \(meta))"
        }
        var other = ""
        for (macro, kind) in [("Unique", "Unique"), ("Index", "Index")] {
            if let args = freestandingArguments(macro, in: decl) {
                let generic = args.hasPrefix("<") ? "" : "<\(type)>"
                other += """
                if #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) {
                    otherProperties.append(SwiftData.Schema.PropertyMetadata(name: "SwiftData.Schema.\(kind)", keypath: \\SwiftData.Schema.encodingVersion, defaultValue: nil, metadata: SwiftData.Schema.\(kind)\(generic)\(args)))
                }

                """
            }
        }
        let initializers = persisted.map { "_\($0.name) = _SwiftDataNoType()" }.joined(separator: "\n")

        return [
            """
            @Transient
            private var _$backingData: any SwiftData.BackingData<\(raw: type)> = \(raw: type).createBackingData()
            """,
            """
            public var persistentBackingData: any SwiftData.BackingData<\(raw: type)> {
                get { return _$backingData }
                set { _$backingData = newValue }
            }
            """,
            """
            static var schemaMetadata: [SwiftData.Schema.PropertyMetadata] {
                let storedProperties = [
                    \(raw: metadata.joined(separator: ",\n"))
                ] as [SwiftData.Schema.PropertyMetadata]
                var otherProperties = [SwiftData.Schema.PropertyMetadata]()
                \(raw: other)
                return storedProperties + otherProperties
            }
            """,
            """
            required init(backingData: any SwiftData.BackingData<\(raw: type)>) {
                \(raw: initializers)
                self.persistentBackingData = backingData
            }
            """,
            """
            @Transient
            private let _$observationRegistrar = Observation.ObservationRegistrar()
            """,
            """
            internal nonisolated func access<_M>(keyPath: KeyPath<\(raw: type), _M>) {
                _$observationRegistrar.access(self, keyPath: keyPath)
            }
            """,
            """
            internal nonisolated func withMutation<_M, _MR>(keyPath: KeyPath<\(raw: type), _M>, _ mutation: () throws -> _MR) rethrows -> _MR {
                try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
            }
            """,
            "struct _SwiftDataNoType {}",
        ]
    }

    public static func expansion(of node: AttributeSyntax, attachedTo decl: some DeclGroupSyntax,
                                 providingAttributesFor member: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AttributeSyntax] {
        guard let variable = member.as(VariableDeclSyntax.self), !variable.isStatic,
              variable.bindings.count == 1, let binding = variable.bindings.first, variable.isStored(binding),
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text, !name.hasPrefix("_")
        else { return [] }
        let property = ModelProperty(name: name, decl: variable, binding: binding)
        if property.isTransient || property.attribute("_PersistedProperty") != nil
            || property.attribute("_TransformablePersistedProperty") != nil { return [] }
        return [property.isTransformable ? "@_TransformablePersistedProperty" : "@_PersistedProperty"]
    }

    public static func expansion(of node: AttributeSyntax, attachedTo decl: some DeclGroupSyntax,
                                 providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        let wanted = protocols.map(\.trimmedDescription)
        return ["PersistentModel", "Observable"].compactMap { name -> ExtensionDeclSyntax? in
            guard wanted.contains(where: { $0.hasSuffix(name) }) else { return nil }
            let module = name == "Observable" ? "Observation" : "SwiftData"
            return try? ExtensionDeclSyntax("extension \(type.trimmed): \(raw: module).\(raw: name) {}")
        }
    }
}

// MARK: - Persisted properties

func persistedAccessors(_ decl: some DeclSyntaxProtocol, get: String, set: String) -> [AccessorDeclSyntax] {
    guard let variable = decl.as(VariableDeclSyntax.self), let binding = variable.bindings.first,
          let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return [] }
    return [
        """
        @storageRestrictions(accesses: _$backingData, initializes: _\(raw: name))
        init(initialValue) {
            _$backingData.\(raw: set)(forKey: \\.\(raw: name), to: initialValue)
            _\(raw: name) = _SwiftDataNoType()
        }
        """,
        """
        get {
            _$observationRegistrar.access(self, keyPath: \\.\(raw: name))
            return self.\(raw: get)(forKey: \\.\(raw: name))
        }
        """,
        """
        set {
            _$observationRegistrar.withMutation(of: self, keyPath: \\.\(raw: name)) {
                self.\(raw: set)(forKey: \\.\(raw: name), to: newValue)
            }
        }
        """,
    ]
}

func persistedPeers(_ decl: some DeclSyntaxProtocol) -> [DeclSyntax] {
    guard let variable = decl.as(VariableDeclSyntax.self), let binding = variable.bindings.first,
          let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return [] }
    return ["@Transient private var _\(raw: name): _SwiftDataNoType"]
}

public struct PersistedPropertyMacro: AccessorMacro, PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingAccessorsOf decl: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        persistedAccessors(decl, get: "getValue", set: "setValue")
    }

    public static func expansion(of node: AttributeSyntax, providingPeersOf decl: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        persistedPeers(decl)
    }
}

public struct TransformablePersistedPropertyMacro: AccessorMacro, PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingAccessorsOf decl: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        persistedAccessors(decl, get: "getTransformableValue", set: "setTransformableValue")
    }

    public static func expansion(of node: AttributeSyntax, providingPeersOf decl: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        persistedPeers(decl)
    }
}

// MARK: - Markers read by @Model (they expand to nothing themselves)

public struct AttributePropertyMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf decl: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}

public struct RelationshipPropertyMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf decl: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}

public struct TransientPropertyMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf decl: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}

public struct UniqueConstraintsMacro: DeclarationMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}

public struct IndexMacro: DeclarationMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}

// MARK: - @ModelActor

public struct PersistentModelActorMacro: MemberMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf decl: some DeclGroupSyntax,
                                 conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        [
            "nonisolated let modelExecutor: any SwiftData.ModelExecutor",
            "nonisolated let modelContainer: SwiftData.ModelContainer",
            """
            init(modelContainer: SwiftData.ModelContainer) {
                let modelContext = ModelContext(modelContainer)
                self.modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
                self.modelContainer = modelContainer
            }
            """,
        ]
    }

    public static func expansion(of node: AttributeSyntax, attachedTo decl: some DeclGroupSyntax,
                                 providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        [try ExtensionDeclSyntax("extension \(type.trimmed): SwiftData.ModelActor {}")]
    }
}

// MARK: - @Query (a macro since iOS 27's SDK; the Query type is no longer a property wrapper)

public struct QueryMacro: AccessorMacro, PeerMacro {
    struct Property {
        let name: String
        let type: TypeSyntax
        let element: String
    }

    static func property(_ decl: some DeclSyntaxProtocol, _ context: some MacroExpansionContext) -> Property? {
        guard let variable = decl.as(VariableDeclSyntax.self), variable.bindingSpecifier.tokenKind == .keyword(.var),
              let binding = variable.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              let type = binding.typeAnnotation?.type else { return nil }
        // [Element], Array<Element> or SectionedResults<Element, String>
        let element: TypeSyntax?
        if let array = type.as(ArrayTypeSyntax.self) {
            element = array.element
        } else {
            element = type.as(IdentifierTypeSyntax.self)?.genericArgumentClause?.arguments.first.flatMap {
                TypeSyntax($0.argument)
            }
        }
        guard let element else { return nil }
        return Property(name: name, type: type, element: element.trimmedDescription)
    }

    public static func expansion(of node: AttributeSyntax, providingAccessorsOf decl: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        guard let property = property(decl, context) else { return [] }
        return ["get { _\(raw: property.name).wrappedValue }"]
    }

    public static func expansion(of node: AttributeSyntax, providingPeersOf decl: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let property = property(decl, context) else { return [] }
        let arguments = node.arguments?.trimmedDescription ?? ""
        return ["""
            private var _\(raw: property.name): SwiftData.Query<\(raw: property.element), \(property.type.trimmed)> \
            = SwiftData.Query(\(raw: arguments))
            """]
    }
}
