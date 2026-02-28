import Foundation
import XCTest
 import STJSON
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

    func testCompatibilityExtensionsAreExplicitlyScopedAndIsolated() {
        XCTAssertEqual(ACPMethodCatalog.compatibilityExtensions, [ACPMethods.sessionStop])
        XCTAssertFalse(ACPMethodCatalog.unstableBaseline.contains(ACPMethods.sessionStop))
        XCTAssertFalse(ACPMethodCatalog.stableBaseline.contains(ACPMethods.sessionStop))
        XCTAssertFalse(ACPMethodCatalog.projectExtensions.contains(ACPMethods.sessionStop))
    }

    func testCompatibilityExtensionsAreOutsideOfficialBaselinesAndDocumented() throws {
        XCTAssertTrue(ACPMethodCatalog.officialBaselines.isSuperset(of: ACPMethodCatalog.stableBaseline))
        XCTAssertTrue(ACPMethodCatalog.officialBaselines.isSuperset(of: ACPMethodCatalog.unstableBaseline))
        XCTAssertTrue(ACPMethodCatalog.officialBaselines.isDisjoint(with: ACPMethodCatalog.compatibilityExtensions))
        XCTAssertTrue(ACPMethodCatalog.projectExtensions.isDisjoint(with: ACPMethodCatalog.compatibilityExtensions))

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let boundaryURL = root.appendingPathComponent("docs-dev/features/ACP-Protocol-Extension-Boundaries.md")
        let boundaryContent = try String(contentsOf: boundaryURL, encoding: .utf8)
        for method in ACPMethodCatalog.compatibilityExtensions {
            XCTAssertTrue(
                boundaryContent.contains("`\(method)`"),
                "Compatibility method \(method) must be documented in ACP-Protocol-Extension-Boundaries.md"
            )
        }
    }

    func testCompatibilityExtensionsAreNotPresentInOfficialMetaSnapshots() throws {
        let stable = try loadMeta(named: "meta")
        let unstable = try loadMeta(named: "meta.unstable")
        let officialFixtureMethods = Set(stable.agentMethods.values)
            .union(stable.clientMethods.values)
            .union(Set(Array(stable.protocolMethods?.values ?? [:].values)))
            .union(unstable.agentMethods.values)
            .union(unstable.clientMethods.values)
            .union(Set(Array(unstable.protocolMethods?.values ?? [:].values)))

        let overlap = ACPMethodCatalog.compatibilityExtensions.intersection(officialFixtureMethods)
        XCTAssertTrue(
            overlap.isEmpty,
            """
            Compatibility methods already exist in official ACP fixtures: \(overlap.sorted()).
            Migrate them from compatibilityExtensions into official baselines.
            """
        )
    }

    private func loadMeta(named baseName: String) throws -> ACPMetaFile {
        guard let url = Bundle.module.url(forResource: baseName, withExtension: "json") else {
            throw XCTSkip("Missing fixture: \(baseName).json")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ACPMetaFile.self, from: data)
    }
}
