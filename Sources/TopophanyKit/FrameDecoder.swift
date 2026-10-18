import Foundation

/// Splits `topo monitor stream`'s stdout into frames: one JSON object per
/// line, each line at most 1 MiB (PROTOCOL.md §1). A longer line is dropped
/// up to its newline and reported; the stream goes on.
public struct FrameDecoder: Sendable {
    public static let maxLineBytes = 1 << 20

    public enum Output: Sendable {
        /// A frame and the line it was decoded from.
        case frame(Frame, line: Data)
        case problem(Problem)
    }

    public enum Problem: Error, Sendable, Hashable {
        /// A line longer than the cap; `bytes` is how many were dropped.
        case oversized(bytes: Int)
        /// A line that isn't a schema 1 frame.
        case malformed(String)
    }

    private var buffer = Data()
    private var dropping = false
    private var dropped = 0

    public init() {}

    public mutating func feed(_ chunk: Data) -> [Output] {
        var out: [Output] = []
        var chunk = chunk[...]
        while !chunk.isEmpty {
            if dropping {
                guard let nl = chunk.firstIndex(of: 0x0A) else {
                    dropped += chunk.count
                    return out
                }
                dropped += chunk.distance(from: chunk.startIndex, to: nl)
                out.append(.problem(.oversized(bytes: dropped)))
                dropping = false
                dropped = 0
                chunk = chunk[chunk.index(after: nl)...]
                continue
            }
            if let nl = chunk.firstIndex(of: 0x0A) {
                let head = chunk[chunk.startIndex..<nl]
                chunk = chunk[chunk.index(after: nl)...]
                if buffer.count + head.count > Self.maxLineBytes {
                    out.append(.problem(.oversized(bytes: buffer.count + head.count)))
                    buffer.removeAll(keepingCapacity: true)
                    continue
                }
                buffer.append(contentsOf: head)
                if let o = Self.decode(buffer) { out.append(o) }
                buffer.removeAll(keepingCapacity: true)
            } else {
                if buffer.count + chunk.count > Self.maxLineBytes {
                    dropping = true
                    dropped = buffer.count + chunk.count
                    buffer.removeAll(keepingCapacity: true)
                    return out
                }
                buffer.append(contentsOf: chunk)
                return out
            }
        }
        return out
    }

    /// At end of stream: a last line without its newline still counts.
    public mutating func finish() -> [Output] {
        defer {
            buffer.removeAll()
            dropping = false
            dropped = 0
        }
        if dropping { return [.problem(.oversized(bytes: dropped))] }
        return Self.decode(buffer).map { [$0] } ?? []
    }

    static func decode(_ line: Data) -> Output? {
        var line = line
        if line.last == 0x0D { line.removeLast() }
        guard line.contains(where: { $0 != 0x20 && $0 != 0x09 }) else { return nil }
        do {
            let frame = try JSONDecoder().decode(Frame.self, from: line)
            return .frame(frame, line: line)
        } catch {
            return .problem(.malformed(String(describing: error).prefix(200).description))
        }
    }

    /// Decodes a single frame line, as kept by the widget hand-off.
    public static func frame(from line: Data) -> Frame? {
        if case .frame(let f, _) = decode(line) { return f }
        return nil
    }
}
