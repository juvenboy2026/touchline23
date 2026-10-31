import XCTest
@testable import PackagingModel

/// The window must show what the resource says, never what a name suggests.
final class GameIdentityTests: XCTestCase {
    private func identity(_ json: String) throws -> GameIdentity {
        try JSONDecoder().decode(GameIdentity.self, from: Data(json.utf8))
    }

    func testBaseGameIsRecognisedByItsTitleID() throws {
        let found = try identity("""
        {"ok": true, "kind": "base", "title_id": 72058693550006272, "title_hex": "01001C8016B4E000",
         "game": "01001C8016B4E000", "name": "FIFA 23",
         "message": "已识别：FIFA 23（01001C8016B4E000）"}
        """)
        XCTAssertTrue(found.isBase)
        XCTAssertEqual(found.title_hex, "01001C8016B4E000")
        XCTAssertEqual(found.headline, "FIFA 23 · 01001C8016B4E000")
    }

    func testUpdatePackageIsNeverMistakenForABaseGame() throws {
        let found = try identity("""
        {"ok": false, "kind": "update", "title_hex": "01001C8016B4E800", "game": "01001C8016B4E000",
         "name": "FIFA 23", "message": "这是 FIFA 23 的更新包，不是游戏本体。"}
        """)
        XCTAssertFalse(found.isBase)
        XCTAssertEqual(found.kind, "update")
        XCTAssertEqual(found.headline, found.message, "a rejected file must show its reason, not a title")
        XCTAssertTrue(found.message.contains("不是游戏本体"))
    }

    func testUnknownTitleIsReportedWithItsIdentifier() throws {
        let found = try identity("""
        {"ok": false, "kind": "unknown", "title_hex": "0100FFFFFFFFE000", "message": "无法识别的游戏：资源内的 Title ID 是 0100FFFFFFFFE000。"}
        """)
        XCTAssertNil(found.game)
        XCTAssertTrue(found.message.contains("0100FFFFFFFFE000"))
    }

    func testCheckReportCarriesChecksPlanTilesAndReason() throws {
        let report = try JSONDecoder().decode(CheckReport.self, from: Data("""
        {"schema": 1, "input_checks_passed": true, "issues": [],
         "identified": {"ok": true, "kind": "base", "title_hex": "01001C8016B4E000",
                        "game": "01001C8016B4E000", "name": "FIFA 23", "message": "已识别"},
         "checks": [{"name": "container-identity", "ok": true, "detail": "title_id=01001C8016B4E000"},
                    {"name": "shader-cache", "ok": false, "detail": "Shader inputs.tsv does not match"}],
         "plan": {"commands": 6,
                  "stages": [{"key": "revalidate", "label": "复核输入与审核指纹"},
                             {"key": "rewrite-main", "label": "重写主程序"}],
                  "artifact": "/game/gameresource/FIFA 23.app",
                  "program_version": "v0", "shader_source_versions": ["v0"]},
         "execution_allowed": false, "disabled_reason": "Input inspection failed"}
        """.utf8))
        XCTAssertEqual(report.checks.count, 2)
        XCTAssertEqual(report.checks[1].ok, false)
        XCTAssertEqual(report.plan?.commands, 6)
        XCTAssertEqual(report.plan?.stages.map(\.key), ["revalidate", "rewrite-main"])
        XCTAssertEqual(report.plan?.stages[0].label, "复核输入与审核指纹")
        XCTAssertFalse(report.execution_allowed)
        // The grid groups the two checks; the failing shader family turns red.
        XCTAssertEqual(report.tiles.map(\.id), ["game", "shader"])
        XCTAssertEqual(report.tiles[1].ok, false)
        let placeholders = CheckPlaceholder.tiles
        XCTAssertTrue(placeholders.allSatisfy { $0.ok == nil })
        XCTAssertEqual(CheckLabel.text("container-identity"), "Game and container identity")
        XCTAssertEqual(CheckLabel.text("shader-cache"), "Shader cache")
        XCTAssertEqual(CheckLabel.text("tool-xcrun"), "Tool: xcrun")
        XCTAssertEqual(CheckLabel.text("brand-new-check"), "brand-new-check")
    }
}
