import XCTest
@testable import SKICLI

final class TUIByteParserTests: XCTestCase {
    func testASCIICharacterEvent() {
        var parser = TUIByteParser()
        parser.append(bytes: [UInt8(ascii: "a")][...])

        let event = parser.nextEvent(nowMS: 0)
        guard case .character(let value) = event else {
            return XCTFail("expected character event")
        }
        XCTAssertEqual(value, "a")
    }

    func testUTF8CharacterEvent() {
        var parser = TUIByteParser()
        parser.append(bytes: [0xE4, 0xBD, 0xA0][...]) // 你

        let event = parser.nextEvent(nowMS: 0)
        guard case .character(let value) = event else {
            return XCTFail("expected character event")
        }
        XCTAssertEqual(value, "你")
    }

    func testPartialUTF8WaitsForCompletion() {
        var parser = TUIByteParser()
        parser.append(bytes: [0xE4, 0xBD][...])
        XCTAssertNil(parser.nextEvent(nowMS: 0))

        parser.append(bytes: [0xA0][...])
        let event = parser.nextEvent(nowMS: 1)
        guard case .character(let value) = event else {
            return XCTFail("expected character event")
        }
        XCTAssertEqual(value, "你")
    }
}
