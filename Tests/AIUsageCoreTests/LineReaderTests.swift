import Foundation
import Testing
@testable import AIUsageCore

@Test func lineReaderRetainsTrailingPartialAcrossChunkBoundaries() throws {
    let dir = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("log.jsonl")
    try write(Data("alpha\nbeta\npart".utf8), to: url)
    var lines: [String] = []
    let first = try LineReader.read(url, chunkSize: 2) { lines.append(String(decoding: $0, as: UTF8.self)) }
    #expect(lines == ["alpha", "beta"])
    #expect(first.offset == 11)
    try append(Data("ial\n".utf8), to: url)
    lines = []
    let second = try LineReader.read(url, fromOffset: first.offset, chunkSize: 3) { lines.append(String(decoding: $0, as: UTF8.self)) }
    #expect(lines == ["partial"])
    #expect(second.offset == 19)
}

@Test func lineReaderBoundsLargeLinesAndStopsAtSnapshotSize() throws {
    let dir = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("log.jsonl")
    try write(Data((String(repeating: "x", count: 40) + "\nok\nextra\n").utf8), to: url)
    var lines: [String] = []
    let result = try LineReader.read(url, throughOffset: 44, chunkSize: 4, maxLineBytes: 8) {
        lines.append(String(decoding: $0, as: UTF8.self))
    }
    #expect(lines == ["ok"])
    #expect(result.oversizedLines == 1)
    #expect(result.offset == 44)
    #expect(result.bytesRead == 44)
    try write(Data(String(repeating: "x", count: 40).utf8), to: url)
    let incomplete = try LineReader.read(url, chunkSize: 4, maxLineBytes: 8) { _ in Issue.record("Partial row consumed") }
    #expect(incomplete.offset == 0)
}

@Test func reusableBuffersPreserveUTF8AndExactSizeBoundaries() throws {
    let dir = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("log.jsonl")
    let rows = (0..<70).map { String(repeating: "🌿", count: $0) }
    let complete = Data((rows.joined(separator: "\n") + "\n").utf8)
    try write(complete + Data("unfinished".utf8), to: url)
    let expected = rows.filter { $0.utf8.count <= 128 }
    for chunkSize in [1, 2, 3, 7, 16, 127, 1024] {
        var actual: [String] = []
        let result = try LineReader.read(url, chunkSize: chunkSize, maxLineBytes: 128) {
            actual.append(String(decoding: $0, as: UTF8.self))
        }
        #expect(actual == expected)
        #expect(result.offset == UInt64(complete.count))
        #expect(result.oversizedLines == rows.count - expected.count)
    }
}
