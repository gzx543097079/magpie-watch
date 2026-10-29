import Foundation
import XCTest
@testable import MagpieWatch

final class MagpieWebTests: XCTestCase {
    func testFingerprintChangesWhenBinaryIsReplaced() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let binary = dir.appendingPathComponent("magpie")
        try Data("old".utf8).write(to: binary)
        let before = try XCTUnwrap(MagpieWeb.binaryFingerprint(path: binary.path))
        try Data("new binary".utf8).write(to: binary, options: .atomic)
        let after = try XCTUnwrap(MagpieWeb.binaryFingerprint(path: binary.path))
        XCTAssertNotEqual(before, after)
    }
}
