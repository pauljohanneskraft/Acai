import Testing
@testable import AcaiCore
@testable import AcaiJS

@Suite("JS/TS: Documentation Comments")
struct JSDocumentationTests {
    private let tsParser = JSCodeParser(isTypeScript: true)
    private let jsParser = JSCodeParser(isTypeScript: false)

    @Test func jsDocOnAnExportedClassAndItsMembers() {
        let artifact = tsParser.parse(source: """
        /**
         * The zoo.
         *
         * Holds animals.
         */
        export class Zoo {
            /** Every animal, by name. */
            animals: Map<string, Animal>;
            // Not documentation.
            count: number;
            /** Feeds everyone. */
            feed(): void {}
        }
        """, fileName: "zoo.ts")
        let zoo = artifact.types.first
        #expect(zoo?.documentation == "The zoo.\n\nHolds animals.")
        #expect(zoo?.members.first { $0.name == "animals" }?.documentation == "Every animal, by name.")
        #expect(zoo?.members.first { $0.name == "count" }?.documentation == nil)
        #expect(zoo?.members.first { $0.name == "feed" }?.documentation == "Feeds everyone.")
    }

    @Test func tripleSlashIsADirectiveNotDocumentation() {
        let artifact = tsParser.parse(source: """
        /// <reference types="node" />
        export class Zoo {}
        """, fileName: "zoo.ts")
        #expect(artifact.types.first?.documentation == nil)
    }

    @Test func interfacesTypeAliasesAndEnumsAreDocumented() {
        let artifact = tsParser.parse(source: """
        /** A keeper. */
        export interface Keeper {
            /** Their name. */
            name: string;
        }

        /** A name. */
        export type Name = string;

        /** What an animal can be. */
        export enum Species {
            /** A dog. */
            Dog = "dog"
        }
        """, fileName: "zoo.ts")
        let keeper = artifact.types.first { $0.name == "Keeper" }
        #expect(keeper?.documentation == "A keeper.")
        #expect(keeper?.members.first?.documentation == "Their name.")
        #expect(artifact.types.first { $0.name == "Name" }?.documentation == "A name.")
        let species = artifact.types.first { $0.name == "Species" }
        #expect(species?.documentation == "What an animal can be.")
        #expect(species?.enumCases.first?.documentation == "A dog.")
    }

    @Test func functionsAndModuleVariablesAreDocumented() {
        let artifact = jsParser.parse(source: """
        /** Boots the app. */
        export function main() {}

        /** The shared zoo. */
        const shared = new Zoo();
        """, fileName: "main.js")
        #expect(artifact.freestandingFunctions.first { $0.name == "main" }?.documentation == "Boots the app.")
        #expect(artifact.globalVariables.first { $0.name == "shared" }?.documentation == "The shared zoo.")
    }

    @Test func aClassExpressionAssignedToAConstantIsDocumented() {
        let artifact = jsParser.parse(source: """
        /** The zoo. */
        const Zoo = class {
            feed() {}
        };
        """, fileName: "zoo.js")
        #expect(artifact.types.first?.documentation == "The zoo.")
    }

    @Test func namespacesAreDocumented() {
        let artifact = tsParser.parse(source: """
        /** Everything zoo. */
        export namespace Zoo {
            /** An animal. */
            export class Animal {}
        }
        """, fileName: "zoo.ts")
        let namespace = artifact.types.first { $0.kind == .module }
        #expect(namespace?.documentation == "Everything zoo.")
        #expect(namespace?.nestedTypes.first?.documentation == "An animal.")
    }

    @Test func anUndocumentedDeclarationHasNone() {
        let artifact = tsParser.parse(source: """
        /* A plain block, not JSDoc. */
        export class Zoo {}
        """, fileName: "zoo.ts")
        #expect(artifact.types.first?.documentation == nil)
    }

    @Test func aLicenseHeaderIsNotTheFirstClassesDocumentation() {
        let artifact = tsParser.parse(source: """
        /**
         * @license MIT
         */

        class Zoo {}

        /** Something else. */

        /** The keeper. */
        class Keeper {}
        """, fileName: "zoo.ts")
        #expect(artifact.types.first { $0.name == "Zoo" }?.documentation == nil)
        #expect(artifact.types.first { $0.name == "Keeper" }?.documentation == "The keeper.")
    }

    @Test func documentationSurvivesAMethodDecorator() {
        let artifact = tsParser.parse(source: """
        class Zoo {
            /** Handles a click. */
            @HostListener('click')
            onClick(): void {}
        }
        """, fileName: "zoo.ts")
        #expect(artifact.types.first?.members.first { $0.name == "onClick" }?.documentation == "Handles a click.")
    }
}
