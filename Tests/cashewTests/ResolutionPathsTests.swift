import Testing
import Foundation
import ArrayTrie
@testable import cashew

@Suite("ResolutionPaths")
struct ResolutionPathsTests {
    @Test("ResolutionPaths is stable and converts to ArrayTrie")
    func stableAndTrieBacked() {
        let paths = ResolutionPaths([
            ResolutionPath(["transactions"], strategy: .recursive),
            ResolutionPath(["children", ""], strategy: .list),
            ResolutionPath(["spec"], strategy: .targeted),
        ])

        #expect(paths.entries.map(\.components) == [
            ["children", ""],
            ["spec"],
            ["transactions"],
        ])

        let trie = paths.asTrie()
        #expect(trie.get(["spec"]) == .targeted)
        #expect(trie.get(["transactions"]) == .recursive)
        #expect(trie.get(["children", ""]) == .list)
    }

    @Test("ResolutionPaths round-trips through Codable")
    func codableRoundTrip() throws {
        let paths = ResolutionPaths([
            ResolutionPath([], strategy: .targeted),
            ResolutionPath(["accounts"], strategy: .range(after: "alice", limit: 10)),
            ResolutionPath(["transactions"], strategy: .recursive),
        ])

        let data = try JSONEncoder().encode(paths)
        let decoded = try JSONDecoder().decode(ResolutionPaths.self, from: data)

        #expect(decoded == paths)
        #expect(decoded.asTrie().get([]) == .targeted)
        #expect(decoded.asTrie().get(["accounts"]) == .range(after: "alice", limit: 10))
    }

    @Test("ResolutionPaths canonicalizes duplicate exact paths")
    func canonicalizesDuplicateExactPaths() {
        let paths = ResolutionPaths([
            ResolutionPath(["children"], strategy: .targeted),
            ResolutionPath(["children"], strategy: .list),
            ResolutionPath(["children"], strategy: .recursive),
            ResolutionPath(["children"], strategy: .targeted),
        ])

        #expect(paths.entries == [
            ResolutionPath(["children"], strategy: .recursive),
        ])
        #expect(paths.asTrie().get(["children"]) == .recursive)
    }

    @Test("ResolutionPaths keeps prefix paths distinct")
    func keepsPrefixPathsDistinct() {
        let paths = ResolutionPaths([
            ResolutionPath(["children"], strategy: .list),
            ResolutionPath(["children", "alice"], strategy: .targeted),
        ])

        #expect(paths.entries == [
            ResolutionPath(["children"], strategy: .list),
            ResolutionPath(["children", "alice"], strategy: .targeted),
        ])
    }

    @Test("ResolutionStrategy merge uses resolver precedence")
    func mergePrecedence() {
        #expect(ResolutionStrategy.merge(.targeted, .list) == .list)
        #expect(ResolutionStrategy.merge(.list, .recursive) == .recursive)
        #expect(ResolutionStrategy.merge(.range(after: nil, limit: 3), .targeted) == .range(after: nil, limit: 3))
        #expect(ResolutionStrategy.merge(.range(after: nil, limit: 3), .list) == .list)
        #expect(ResolutionStrategy.merge(.range(after: nil, limit: 3), .recursive) == .recursive)
    }

    @Test("ResolutionPath ordering distinguishes nil and empty range cursors")
    func rangeSortKeyDistinguishesNilAndEmptyCursor() {
        let nilCursor = ResolutionPath(["a"], strategy: .range(after: nil, limit: 1))
        let emptyCursor = ResolutionPath(["a"], strategy: .range(after: "", limit: 1))

        #expect(nilCursor < emptyCursor)
    }
}
