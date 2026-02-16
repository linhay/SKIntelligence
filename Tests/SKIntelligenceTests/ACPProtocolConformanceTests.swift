import Foundation
import XCTest
@testable import SKIACP

final class ACPProtocolConformanceTests: XCTestCase {
    private struct ACPMetaFile: Decodable {
        let agentMethods: [String: String]
        let clientMethods: [String: String]
        let protocolMethods: [String: String]?
        let version: Int
    }

    func testUnstableMethodBaselineMatchesOfficialMetaSnapshot() throws {
        let meta = try loadMeta(named: "meta.unstable")
        XCTAssertEqual(meta.version, 1)

        let expected = Set(meta.agentMethods.values)
            .union(meta.clientMethods.values)
            .union(Set(Array(meta.protocolMethods?.values ?? [:].values)))

        XCTAssertEqual(expected, ACPMethodCatalog.unstableBaseline)
    }

    func testStableMethodBaselineMatchesOfficialMetaSnapshot() throws {
        let meta = try loadMeta(named: "meta")
        XCTAssertEqual(meta.version, 1)

        let expected = Set(meta.agentMethods.values)
            .union(meta.clientMethods.values)
            .union(Set(Array(meta.protocolMethods?.values ?? [:].values)))

        XCTAssertEqual(expected, ACPMethodCatalog.stableBaseline)
    }

    func testProjectExtensionMethodsAreExplicitlyScoped() {
        XCTAssertEqual(ACPMethodCatalog.projectExtensions, [ACPMethods.logout, ACPMethods.sessionDelete, ACPMethods.sessionExport])
        XCTAssertEqual(ACPMethodCatalog.allSupported, ACPMethodCatalog.unstableBaseline.union(ACPMethodCatalog.projectExtensions))
    }

    private func loadMeta(named baseName: String) throws -> ACPMetaFile {
        guard let url = Bundle.module.url(forResource: baseName, withExtension: "json") else {
            throw XCTSkip("Missing fixture: \(baseName).json")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ACPMetaFile.self, from: data)
    }
}
