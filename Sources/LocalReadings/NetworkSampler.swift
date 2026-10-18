import Darwin
import Foundation

/// Byte counters of one interface at one moment.
public struct InterfaceCounters: Sendable, Hashable {
    public var interface: String
    public var received: UInt64
    public var sent: UInt64
    public var at: Date

    public init(interface: String, received: UInt64, sent: UInt64, at: Date) {
        self.interface = interface
        self.received = received
        self.sent = sent
        self.at = at
    }

    /// Bytes per second from `old` to `self`. `nil` when the interface
    /// changed, no time passed, or a counter went backwards (the interface
    /// was reset): the caller starts again from `self`.
    public func rates(since old: InterfaceCounters) -> (received: Double, sent: Double)? {
        guard old.interface == interface, received >= old.received, sent >= old.sent else { return nil }
        let dt = at.timeIntervalSince(old.at)
        guard dt > 0 else { return nil }
        return (Double(received - old.received) / dt, Double(sent - old.sent) / dt)
    }
}

/// Throughput of one interface from its 64-bit `if_data64` counters.
public struct NetworkSampler: Sampler {
    /// The BSD name to measure.
    public var interface: String
    public var displayName: String
    private var previous: InterfaceCounters?

    public init(interface: String, displayName: String? = nil) {
        self.interface = interface
        self.displayName = displayName ?? interface
    }

    public mutating func sample(at date: Date) -> NetworkReading? {
        guard !interface.isEmpty, let c = Self.counters()[interface] else {
            previous = nil
            return nil
        }
        let now = InterfaceCounters(interface: interface, received: c.received, sent: c.sent, at: date)
        defer { previous = now }
        guard let previous, let r = now.rates(since: previous) else { return nil }
        return NetworkReading(interface: interface, displayName: displayName, address: Self.address(of: interface),
                              receivedPerSecond: r.received, sentPerSecond: r.sent)
    }

    /// Every interface's byte counters, by BSD name, from `NET_RT_IFLIST2`.
    static func counters() -> [String: (received: UInt64, sent: UInt64)] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, u_int(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return [:] }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, u_int(mib.count), &buf, &len, nil, 0) == 0 else { return [:] }
        var out: [String: (UInt64, UInt64)] = [:]
        buf.withUnsafeBytes { raw in
            var offset = 0
            let header = MemoryLayout<if_msghdr>.size
            while offset + header <= len {
                let h = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let step = Int(h.ifm_msglen)
                guard step > 0 else { break }
                if Int32(h.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= len {
                    let h2 = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
                    if if_indextoname(UInt32(h2.ifm_index), &name) != nil {
                        let n = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                        out[n] = (h2.ifm_data.ifi_ibytes, h2.ifm_data.ifi_obytes)
                    }
                }
                offset += step
            }
        }
        return out
    }

    /// The interface's IPv4 address, else a global IPv6 one, else a
    /// link-local IPv6 one.
    static func address(of interface: String) -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var v4: String?
        var v6: String?
        var v6Local: String?
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let a = p.pointee
            guard let sa = a.ifa_addr, String(cString: a.ifa_name) == interface else { continue }
            let family = Int32(sa.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let size = socklen_t(family == AF_INET ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size)
            guard getnameinfo(sa, size, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let s = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if family == AF_INET {
                v4 = v4 ?? s
            } else if s.lowercased().hasPrefix("fe80") {
                v6Local = v6Local ?? s.split(separator: "%").first.map(String.init)
            } else {
                v6 = v6 ?? s
            }
        }
        return v4 ?? v6 ?? v6Local
    }

    /// Interfaces that are up, not loopback, and have an address.
    static func activeInterfaces() -> [String] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        var names: [String] = []
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let a = p.pointee
            let flags = Int32(a.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, let sa = a.ifa_addr else { continue }
            let family = Int32(sa.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            let n = String(cString: a.ifa_name)
            if !names.contains(n) { names.append(n) }
        }
        return names
    }
}
