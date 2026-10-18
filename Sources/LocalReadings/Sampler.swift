import Foundation

/// Reads one thing about this Mac. Samplers that measure a rate keep the
/// previous counters; their first call only primes them and returns `nil`.
public protocol Sampler: Sendable {
    associatedtype Reading: Sendable
    mutating func sample(at date: Date) -> Reading?
}
