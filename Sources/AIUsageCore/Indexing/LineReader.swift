import Foundation
import Darwin

public struct LineReadResult: Sendable {
    public var offset: UInt64
    public var bytesRead: UInt64
    public var lines: Int
    public var oversizedLines: Int
}

public enum LineReader {
    /// Calls `consume` for complete lines only. The pointer is valid only during the callback.
    /// `offset` always points just after a newline, including when a writer is midway through a row.
    public static func read(_ url: URL, fromOffset: UInt64 = 0, throughOffset: UInt64? = nil,
                            chunkSize: Int = 1024 * 1024, maxLineBytes: Int = 16 * 1024 * 1024,
                            consume: (UnsafeRawBufferPointer) throws -> Void) throws -> LineReadResult {
        precondition(chunkSize > 0 && maxLineBytes > 0)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let end = try throughOffset ?? handle.seekToEnd()
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunkSize, alignment: 16)
        // Fixed-capacity spill storage avoids leaving successive array-growth allocations in
        // malloc's cache. Only pages touched by an actual cross-chunk line become resident.
        let pending = UnsafeMutableRawPointer.allocate(byteCount: maxLineBytes, alignment: 16)
        defer { buffer.deallocate(); pending.deallocate() }
        var pendingCount = 0
        var result = LineReadResult(offset: fromOffset, bytesRead: 0, lines: 0, oversizedLines: 0)
        var discarding = false
        while fromOffset + result.bytesRead < end {
            let chunkOffset = fromOffset + result.bytesRead
            let requested = Int(min(UInt64(chunkSize), end - chunkOffset))
            // Reuse one byte buffer. Foundation's allocating reads and Data slices can leave
            // hundreds of MB in allocator caches over a multi-GB scan, even after being freed.
            let count = pread(handle.fileDescriptor, buffer, requested, off_t(chunkOffset))
            if count < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if count == 0 { break }
            result.bytesRead += UInt64(count)
            var start = 0
            while start < count, let newline = memchr(buffer.advanced(by: start), 10, count - start) {
                let index = buffer.distance(to: newline)
                let length = index - start
                if discarding || pendingCount + length > maxLineBytes {
                    result.oversizedLines += 1
                } else if pendingCount == 0 {
                    try consume(UnsafeRawBufferPointer(start: buffer.advanced(by: start), count: length))
                } else {
                    memcpy(pending.advanced(by: pendingCount), buffer.advanced(by: start), length)
                    try consume(UnsafeRawBufferPointer(start: pending, count: pendingCount + length))
                }
                pendingCount = 0
                discarding = false
                result.lines += 1
                start = index + 1
                result.offset = chunkOffset + UInt64(start)
            }
            if start < count && !discarding {
                let length = count - start
                if pendingCount + length > maxLineBytes {
                    pendingCount = 0
                    discarding = true
                } else {
                    memcpy(pending.advanced(by: pendingCount), buffer.advanced(by: start), length)
                    pendingCount += length
                }
            }
        }
        return result
    }

    public static func contains(_ bytes: UnsafeRawBufferPointer, _ needle: [UInt8]) -> Bool {
        guard let base = bytes.baseAddress, bytes.count >= needle.count, !needle.isEmpty else { return false }
        return needle.withUnsafeBytes { pattern in memmem(base, bytes.count, pattern.baseAddress!, pattern.count) != nil }
    }
}
