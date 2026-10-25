import XCTest
import LayoutEngine
@testable import LinkrCore

final class TemplateLibraryTests: XCTestCase {
    let custom = Template(id: "custom-1", name: "Mía",
                          columns: [TemplateColumn(width: 0.25, slots: 1), TemplateColumn(width: 0.75, slots: 2)])

    func testRoundTrip() throws {
        let data = try XCTUnwrap(TemplateCodec.encode([custom]))
        XCTAssertEqual(TemplateCodec.decode(data), [custom])
    }

    func testDecodeGarbageGivesEmpty() {
        XCTAssertEqual(TemplateCodec.decode(Data("nope".utf8)), [])
    }

    func testDecodeDropsInvalidAndNormalizes() throws {
        let bad = [
            Template(id: "custom-a", name: "Sin columnas", columns: []),
            Template(id: "custom-b", name: "Ancho cero", columns: [TemplateColumn(width: 0, slots: 1)]),
            Template(id: "custom-c", name: "Suma 0.99", columns: [TemplateColumn(width: 0.66, slots: 1), TemplateColumn(width: 0.33, slots: 1)]),
        ]
        let decoded = TemplateCodec.decode(try JSONEncoder().encode(bad))
        XCTAssertEqual(decoded.map(\.id), ["custom-c"])
        XCTAssertEqual(decoded[0].columns.reduce(0) { $0 + $1.width }, 1, accuracy: 1e-9)
    }

    func testDecodeDropsDuplicateIds() throws {
        let data = try JSONEncoder().encode([custom, custom])
        XCTAssertEqual(TemplateCodec.decode(data).count, 1)
    }

    func testLibraryPutsBuiltInsFirstAndIgnoresIdCollisions() {
        let clash = Template(id: "halves", name: "Falsa", columns: [TemplateColumn(width: 1, slots: 1)])
        let all = TemplateLibrary.all(custom: [custom, clash])
        XCTAssertEqual(all.map(\.id), Template.builtIn.map(\.id) + ["custom-1"])
    }
}
