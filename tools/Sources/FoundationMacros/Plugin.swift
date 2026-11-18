// swift-foundation's FoundationMacros built for Apple platforms (FOUNDATION_FRAMEWORK): the copy in
// the Linux toolchain expands #Predicate to FoundationEssentials.*, a module iOS does not have.
// PredicateMacro.swift and BundleMacro.swift are swift-foundation's, unchanged (Apache 2.0 with
// Runtime Library Exception), from commit 9402598280de9eade9b307d39d3c5106244ec4dc.
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct FoundationMacrosPlugin: CompilerPlugin {
    var providingMacros: [Macro.Type] = [PredicateMacro.self, ExpressionMacro.self, BundleMacro.self]
}
