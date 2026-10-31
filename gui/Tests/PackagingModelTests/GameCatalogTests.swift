import XCTest
@testable import PackagingModel

/// The supported-games list must describe a profile the same way the engine
/// does, and must never turn "a profile exists" into "this game is verified".
///
/// The catalog is decoded from a fixture. FIFA 23 is the profile this project
/// ships; the other two rows are placeholders, so the generic list (sorting,
/// search, capability and evidence columns) is still exercised on more than one
/// row without naming another game.
final class GameCatalogTests: XCTestCase {
    private let payload = """
    {"schema": 1, "source": "dm/games", "generated": "2026-10-26T00:00:00Z", "count": 3,
     "games": [
      {"id": "01001C8016B4E000", "title_id": "01001C8016B4E000", "name": "FIFA 23", "app_name": "FIFA 23",
       "error": "",
       "versions": [{"version": "v0", "display": "v1.0.0", "modules": ["main", "sdk"],
                     "build_ids": {"main": "5C8E0E1E", "sdk": "A1B2C3D4"}},
                    {"version": "v196608", "display": "v1.0.3", "modules": ["main", "sdk"],
                     "build_ids": {"main": "11223344", "sdk": "55667788"}}],
       "package": "v196608", "shader_versions": ["v0"], "modules": ["main", "sdk"],
       "romfs_marker": "datax.big", "graphics_api": "nvn", "archive_format": "easf",
       "capability": {"targets": [{"id": "macos", "name": "macOS App", "supported": true, "reason": ""},
                                  {"id": "ios", "name": "iOS IPA", "supported": true, "reason": ""}],
                      "modes": [{"id": "nsp", "name": "External XCI / NSP", "supported": true, "reason": ""},
                                {"id": "directory", "name": "Bundled resources (Directory)", "supported": true, "reason": ""}],
                      "graphics_api": "nvn", "archive_format": "easf", "shader_reuse": true,
                      "shader_generation": "preview-only", "plan_supported": true,
                      "limitations": ["Shader source is EASF: reuse needs a completed EASF source build"]},
       "evidence": {"build": "fork-audited", "runtime": "fork-report",
                    "source": "docs/fifa23/validation.md", "note": "v1.0.0 and v1.0.3"}},
      {"id": "0100F00000000001", "title_id": "0100F00000000001", "name": "Fixture Alpha",
       "app_name": "Fixture Alpha", "error": "",
       "versions": [{"version": "v0", "display": "v1.0.0", "modules": ["main"],
                     "build_ids": {"main": "1D2E3F40"}}],
       "package": "v0", "shader_versions": ["v0"], "modules": ["main"], "romfs_marker": "",
       "graphics_api": "nvn", "archive_format": "nvn",
       "capability": {"targets": [{"id": "macos", "name": "macOS App", "supported": true, "reason": ""},
                                  {"id": "ios", "name": "iOS IPA", "supported": true, "reason": ""}],
                      "modes": [{"id": "nsp", "name": "External XCI / NSP", "supported": true, "reason": ""},
                                {"id": "directory", "name": "Bundled resources (Directory)", "supported": true, "reason": ""}],
                      "graphics_api": "nvn", "archive_format": "nvn", "shader_reuse": true,
                      "shader_generation": "preview-only", "plan_supported": true, "limitations": []},
       "evidence": {"build": "none", "runtime": "none", "source": "", "note": ""}},
      {"id": "0100F00000000002", "title_id": "0100F00000000002", "name": "Placeholder Title",
       "app_name": "Placeholder Title", "error": "",
       "versions": [{"version": "v0", "display": "v1.0.0", "modules": ["main"],
                     "build_ids": {"main": "99AABBCC"}}],
       "package": "v0", "shader_versions": [], "modules": ["main"], "romfs_marker": "",
       "graphics_api": "vulkan", "archive_format": "nvn",
       "capability": {"targets": [{"id": "macos", "name": "macOS App", "supported": false,
                                   "reason": "vulkan Shader libraries have no artifact audit in this engine"},
                                  {"id": "ios", "name": "iOS IPA", "supported": false,
                                   "reason": "vulkan Shader libraries have no artifact audit in this engine"}],
                      "modes": [{"id": "nsp", "name": "External XCI / NSP", "supported": true, "reason": ""},
                                {"id": "directory", "name": "Bundled resources (Directory)", "supported": true, "reason": ""}],
                      "graphics_api": "vulkan", "archive_format": "nvn", "shader_reuse": false,
                      "shader_generation": "preview-only", "plan_supported": false,
                      "limitations": ["macOS App: vulkan Shader libraries have no artifact audit in this engine"]},
       "evidence": {"build": "upstream-release", "runtime": "upstream-iphone",
                    "source": "docs/UPSTREAM.md", "note": ""}}
     ]}
    """

    private func catalog() throws -> GameCatalog {
        try JSONDecoder().decode(GameCatalog.self, from: Data(payload.utf8))
    }

    private func game(_ id: String) throws -> GameEntry {
        try XCTUnwrap(try catalog().games.first { $0.id == id })
    }

    func testCatalogDecodesEveryFieldTheWindowShows() throws {
        let catalog = try catalog()
        XCTAssertEqual(catalog.schema, 1)
        XCTAssertEqual(catalog.registered, 3)
        XCTAssertEqual(catalog.source, "dm/games", "the list must say where it came from")
        let fifa = try game("01001C8016B4E000")
        XCTAssertEqual(fifa.name, "FIFA 23")
        XCTAssertEqual(fifa.app_name, "FIFA 23")
        XCTAssertTrue(fifa.readable)
        XCTAssertEqual(fifa.title_id, "01001C8016B4E000")
        XCTAssertEqual(fifa.versions.map(\.version), ["v0", "v196608"])
        XCTAssertEqual(fifa.versions[1].build_ids["main"], "11223344")
        XCTAssertEqual(fifa.modules, ["main", "sdk"])
        XCTAssertEqual(fifa.shader_versions, ["v0"])
        XCTAssertEqual(fifa.romfs_marker, "datax.big")
        XCTAssertEqual(fifa.graphics_api, "nvn")
        XCTAssertEqual(fifa.archive_format, "easf")
    }

    func testTheProfileVersionColumnListsRegisteredVersionsNotBuiltOnes() throws {
        let fifa = try game("01001C8016B4E000")
        XCTAssertEqual(fifa.registeredVersions, ["v1.0.0", "v1.0.3"])
        XCTAssertEqual(fifa.versionText, "v1.0.0, v1.0.3")
        XCTAssertEqual(try game("0100F00000000002").versionText, "v1.0.0")
    }

    func testCapabilityAndEvidenceAreSeparateAnswers() throws {
        let catalog = try catalog()
        // Three profiles are registered, two of them can be built and audited by
        // this engine, two carry a build record (one made here, one upstream) and
        // two carry a runtime record. No column is derived from another.
        XCTAssertEqual(catalog.registered, 3)
        XCTAssertEqual(catalog.buildable, 2)
        XCTAssertEqual(catalog.buildVerified, 2)
        XCTAssertEqual(catalog.runtimeVerified, 2)
        let fixture = try game("0100F00000000001")
        XCTAssertTrue(fixture.capability.plan_supported)
        XCTAssertEqual(fixture.evidence.buildState, .none, "a registered profile is not a build record")
        XCTAssertEqual(fixture.evidence.runtimeState, .none)
        XCTAssertEqual(fixture.evidence.buildLabel.render(.english), "No build record")
        XCTAssertEqual(fixture.evidence.buildLabel.render(.simplifiedChinese), "无构建记录")
    }

    func testEvidenceLabelsDistinguishThisForkFromAnUpstreamRecord() throws {
        let fifa = try game("01001C8016B4E000")
        XCTAssertEqual(fifa.evidence.buildState, .fork)
        XCTAssertEqual(fifa.evidence.runtimeState, .fork)
        XCTAssertEqual(fifa.evidence.buildLabel.render(.english), "Built and audited (this fork)")
        XCTAssertEqual(fifa.evidence.runtimeLabel.render(.simplifiedChinese), "运行已报告（本 fork）")
        XCTAssertTrue(fifa.evidence.source.contains("validation.md"))
        let upstream = try game("0100F00000000002")
        XCTAssertEqual(upstream.evidence.buildState, .upstream)
        XCTAssertEqual(upstream.evidence.buildLabel.render(.english), "Built (upstream record)")
        XCTAssertNotEqual(upstream.evidence.buildState, .fork, "an upstream build is not this fork's audit")
    }

    func testAnUnauditableBackendIsShownWithItsReasonAndNeverAsBuildable() throws {
        let upstream = try game("0100F00000000002")
        XCTAssertFalse(upstream.capability.plan_supported)
        XCTAssertFalse(upstream.supports(target: "macos"))
        XCTAssertTrue(upstream.targetSummary.isEmpty)
        XCTAssertEqual(upstream.capability.targets.map(\.supported), [false, false])
        XCTAssertTrue(upstream.capability.limitations.first?.contains("vulkan") == true)
        XCTAssertEqual(upstream.capability.shader_generation, "preview-only")
        let fifa = try game("01001C8016B4E000")
        XCTAssertTrue(fifa.supports(target: "ios"))
        XCTAssertEqual(fifa.targetSummary, ["macos", "ios"], "canonical order, not JSON order")
    }

    func testSearchMatchesNamesAndTitleIDsWithoutSpacesOrCase() throws {
        let games = try catalog().games
        func ids(_ search: String) -> [String] {
            GameQuery(search: search).apply(to: games).map(\.id)
        }
        XCTAssertEqual(ids("fifa"), ["01001C8016B4E000"])
        XCTAssertEqual(ids("FIFA 23"), ["01001C8016B4E000"])
        XCTAssertEqual(ids("placeholder"), ["0100F00000000002"])
        // Title IDs match in either case, with or without a separating space.
        XCTAssertEqual(ids("0100f00000000001"), ["0100F00000000001"])
        XCTAssertEqual(ids("0100F0 0000000002"), ["0100F00000000002"])
        XCTAssertEqual(ids("vulkan").count, 0, "a graphics API is not a name")
        XCTAssertEqual(ids("").count, 3, "an empty search keeps everything")
    }

    func testSearchFoldsDiacriticsAndWidth() {
        XCTAssertEqual(GameQuery.normalized("Pokémon"), GameQuery.normalized("pokemon"))
        XCTAssertEqual(GameQuery.normalized("FIFA 23"), "fifa23")
        XCTAssertEqual(GameQuery.normalized("ＦＩＦＡ"), "fifa", "fullwidth letters match their ASCII form")
        // Folded so a Title ID compares in either case, without separators.
        XCTAssertEqual(GameQuery.titleNeedle("0100-1C80-16B4-E000"), "01001c8016b4e000")
    }

    func testSortOrdersByNameAndTitleID() throws {
        let games = try catalog().games
        XCTAssertEqual(GameQuery(sort: .name).apply(to: games).map(\.name),
                       ["FIFA 23", "Fixture Alpha", "Placeholder Title"])
        XCTAssertEqual(GameQuery(sort: .titleID).apply(to: games).map(\.id),
                       ["01001C8016B4E000", "0100F00000000001", "0100F00000000002"])

    }

    func testFilteringKeepsTheChosenSortSoSelectionIsStable() throws {
        let games = try catalog().games
        // A needle with a non-hex letter cannot match a Title ID, so this
        // filters on the name only and still keeps the chosen order.
        let filtered = GameQuery(search: "fixture", sort: .name).apply(to: games)
        XCTAssertEqual(filtered.map(\.name), ["Fixture Alpha"])
        XCTAssertEqual(Set(filtered.map(\.id)).count, filtered.count)
        XCTAssertEqual(GameSort.allCases.map { $0.label.render() }, ["Name (A–Z)", "Title ID"])
    }

    func testUserDirectoryUsesAvailableTargetsAndIgnoresHistoricalEvidence() throws {
        var loaded = try catalog()
        XCTAssertEqual(Set(loaded.supportedGames.map(\.id)), ["01001C8016B4E000", "0100F00000000001"])
        // One usable target is enough even when the old all-target aggregate is false.
        loaded.games[0].capability.targets[1].supported = false
        loaded.games[0].capability.plan_supported = false
        XCTAssertEqual(loaded.supportedGames.count, 2)
        XCTAssertFalse(loaded.supportedGames.contains { $0.name == "Placeholder Title" })
        XCTAssertTrue(loaded.supportedGames.contains { $0.evidence.buildState == .none })
        let before = try JSONEncoder().encode(loaded)
        _ = loaded.supportedGames
        XCTAssertEqual(try JSONDecoder().decode(GameCatalog.self, from: before), loaded)
    }

    func testVersionSearchWorksWithinTheSupportedDirectory() throws {
        let games = try catalog().supportedGames
        XCTAssertEqual(GameQuery(search: "1.0.3").apply(to: games).map(\.name), ["FIFA 23"])
        XCTAssertEqual(GameQuery(search: "v196608").apply(to: games).map(\.name), ["FIFA 23"])
        XCTAssertTrue(GameQuery(search: "placeholder").apply(to: games).isEmpty)
        XCTAssertEqual(GameQuery(search: "FIFA").apply(to: games).first?.id,
                       GameQuery(search: "1.0.3").apply(to: games).first?.id)
    }

    func testTheFourConceptsAreExplainedAndNoneClaimsVerification() throws {
        XCTAssertEqual(GameConcept.allCases.count, 4)
        for concept in GameConcept.allCases {
            let text = concept.explanation.render(.english)
            XCTAssertFalse(text.isEmpty)
            XCTAssertFalse(concept.title.render(.simplifiedChinese).isEmpty)
        }
        XCTAssertTrue(GameConcept.profile.explanation.render(.english).contains("not a verification claim"))
        XCTAssertNotEqual(GameConcept.build.title.render(.english),
                          GameConcept.runtime.title.render(.english))
    }
    private func localizedNames() throws -> LocalizedGameNames {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try LocalizedGameNames.load(from: repo.appendingPathComponent("tools/packaging_gui/data/game_names.zh-Hans.json"))
    }

    func testOfflineNamesUseExactIDsAndNeverReplaceTheOriginalProfileName() throws {
        let names = try localizedNames()
        let original = try catalog()
        let local = original.withLocalizedNames(names)
        let fifa = try XCTUnwrap(local.games.first { $0.id == "01001C8016B4E000" })
        XCTAssertEqual(fifa.name, "FIFA 23")
        XCTAssertEqual(fifa.displayName(in: .simplifiedChinese), "FIFA 23 传奇版")
        XCTAssertEqual(fifa.displayName(in: .english), "FIFA 23")
        XCTAssertEqual(local.supportedGames.map(\.id), original.supportedGames.map(\.id))
        XCTAssertEqual(local.games.map(\.app_name), original.games.map(\.app_name))
        XCTAssertEqual(local.games.map(\.capability), original.games.map(\.capability))
        XCTAssertEqual(local.games.map(\.versions), original.games.map(\.versions))
        XCTAssertNil(original.games[0].chineseName)
        // The table lists one title: an unlisted ID has no alias, and an update
        // ID cannot inherit the base title's alias.
        XCTAssertNil(names.chineseName(for: "0100F00000000001"))
        XCTAssertNil(names.chineseName(for: "01001C8016B4E800"), "an update ID cannot inherit the base alias")
    }

    func testBothLanguagesAndTitleIDRemainSearchableInEitherInterfaceLanguage() throws {
        let loaded = try catalog().withLocalizedNames(localizedNames())
        for language in [InterfaceLanguage.english, .simplifiedChinese] {
            for query in ["传奇", "FIFA", "01001c8016b4e000"] {
                XCTAssertEqual(GameQuery(search: query).apply(to: loaded.supportedGames, language: language).map(\.id),
                               ["01001C8016B4E000"])
            }
        }
    }

    func testMissingAmbiguousAndUnsupportedMetadataFallBackToEnglish() throws {
        let names = try localizedNames()
        var game = try game("0100F00000000001")
        game.title_id = "010069401ADB8000" // unresolved regional source ID
        var loaded = try catalog(); loaded.games = [game]
        XCTAssertEqual(loaded.withLocalizedNames(names).games[0].displayName(in: .simplifiedChinese), game.name)
        XCTAssertNil(names.chineseName(for: "0100F5D01DA3A000"))
        let future = try JSONDecoder().decode(LocalizedGameNames.self, from: Data(#"{"schema":2,"names":{}}"#.utf8))
        XCTAssertNil(future.chineseName(for: "01001C8016B4E000"))
        XCTAssertThrowsError(try LocalizedGameNames.load(from: URL(fileURLWithPath: "/nonexistent/display-names.json")))
    }

}
