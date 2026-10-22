import CryptoKit
import Foundation
import Testing
@testable import TopophanyKit

struct DirectContractTests {
    static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "docs/contracts/direct-v1")
    struct Manifest: Decodable {
        struct File: Decodable { var path: String; var sha256: String }
        var contract_id: String
        var fixture_schema: Int
        var files: [File]
    }
    @Test func officialBytesAndDecoders() throws {
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: Self.root.appending(path: "manifest.json")))
        #expect(manifest.contract_id == "topophany-direct-v1" && manifest.fixture_schema == 1)
        for file in manifest.files {
            #expect(!file.path.contains("..") && file.path.hasPrefix("fixtures/"))
            let data = try Data(contentsOf: Self.root.appending(path: file.path))
            #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == file.sha256, "\(file.path)")
            if file.path.contains("stream-") {
                let frame = try JSONDecoder().decode(Frame.self, from: data)
                if frame.lifecycle == .running { #expect(frame.source == "direct" && !frame.datasetID.isEmpty) }
                else { #expect(frame.lifecycle == .error && frame.error != nil && frame.datasetID.isEmpty) }
                #expect(!frame.rows.contains { $0.value == .malformed }, "\(file.path)")
                if file.path.contains("malformed-origin") {
                    let card = try #require(frame.rows.compactMap { if case .serverCard(let c) = $0.value { c } else { nil } }.first)
                    #expect(card.resources.first?.cpu?.percent != nil)
                }
            } else if file.path.contains("capabilities") {
                let caps = try JSONDecoder().decode(Capabilities.self, from: data)
                #expect(caps.supports(source: "direct"))
            } else if file.path.contains("request-direct") {
                let request = try JSONDecoder().decode(Request.self, from: data)
                let caps = try JSONDecoder().decode(Capabilities.self, from: Data(contentsOf: Self.root.appending(path: "fixtures/capabilities.json")))
                try request.validate(using: caps)
            } else if file.path.contains("sources-list-success") {
                #expect(try JSONDecoder().decode(SourceEnvelope<DirectProfiles>.self, from: data).data?.profiles.count == 1)
            } else if file.path.contains("sources-inspect-success") || file.path.contains("sources-inspect-truncated") {
                #expect(try JSONDecoder().decode(SourceEnvelope<DirectInspection>.self, from: data).data != nil)
            } else if file.path.contains("sources-save-success") {
                #expect(try JSONDecoder().decode(SourceEnvelope<DirectSaved>.self, from: data).data?.nodes.count == 1)
            } else if file.path.contains("sources-remove-success") {
                #expect(try JSONDecoder().decode(SourceEnvelope<DirectRemoved>.self, from: data).data != nil)
            } else {
                #expect(try JSONDecoder().decode(SourceEnvelope<JSONValue>.self, from: data).error != nil)
            }
        }
    }
}
