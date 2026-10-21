import Foundation
import Synchronization
import Testing
import TopophanyKit
@testable import TopophanyEngine

@Suite struct CapabilitiesCacheTests {
    @Test func concurrentChecksShareOneProbeAndExpire() throws {
        let path = try FakeTopo.install()
        let caps = try ProcessEngine.probe(path, timeout: 5).get()
        let calls = Mutex(0)
        let clock = ManualClock(Date())
        let cache = CapabilitiesCache(clock: clock) { _, _ in
            calls.withLock { $0 += 1 }
            Thread.sleep(forTimeInterval: 0.05)
            return .success(caps)
        }
        DispatchQueue.concurrentPerform(iterations: 12) { _ in _ = cache.check(path, timeout: 5) }
        #expect(calls.withLock { $0 } == 1)
        clock.advance(61)
        _ = cache.check(path, timeout: 5)
        #expect(calls.withLock { $0 } == 2)
    }

    @Test func replacingTheExecutableInvalidatesItsCapabilities() throws {
        let path = try FakeTopo.install()
        let cache = CapabilitiesCache(probe: ProcessEngine.probe)
        #expect(try cache.check(path, timeout: 5).get().version == "9.9.9-fake")
        try FakeTopo.script.replacingOccurrences(of: "9.9.9-fake", with: "10.0.0-updated")
            .write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        #expect(try cache.check(path, timeout: 5).get().version == "10.0.0-updated")
    }

    @Test func failuresAreRetriedSoonAndDoNotMaskLongerDeadlines() throws {
        let path = try FakeTopo.install()
        let caps = try ProcessEngine.probe(path, timeout: 5).get()
        let calls = Mutex(0)
        let clock = ManualClock(Date())
        let cache = CapabilitiesCache(clock: clock) { path, _ in
            let n = calls.withLock { n in n += 1; return n }
            return n < 3 ? .failure(.launchFailed(path: path, message: "timeout")) : .success(caps)
        }
        _ = cache.check(path, timeout: 1)
        _ = cache.check(path, timeout: 1)
        #expect(calls.withLock { $0 } == 1)
        _ = cache.check(path, timeout: 5)
        #expect(calls.withLock { $0 } == 2)
        clock.advance(3)
        #expect(try cache.check(path, timeout: 5).get().version == caps.version)
        #expect(calls.withLock { $0 } == 3)
    }
}
