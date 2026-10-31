import XCTest
@testable import PackagingModel

final class StageProgressTests: XCTestCase {
    private let stages = [
        BuildStage(key: "revalidate", label: "Revalidate inputs and approval"),
        BuildStage(key: "rewrite-main", label: "Rewrite main program"),
        BuildStage(key: "audit", label: "Audit artifact"),
        BuildStage(key: "publish", label: "Publish artifact"),
    ]

    func testHeadlineCountsStagesFromThePlan() {
        var p = StageProgress(stages: stages)
        XCTAssertEqual(p.total, 4)
        XCTAssertEqual(p.completed, 0)
        XCTAssertTrue(p.headline.isEmpty)
        p.begin("revalidate")
        XCTAssertEqual(p.headline, "Stage 1 / 4: Revalidate inputs and approval")
        XCTAssertEqual(p.statusText, "Running")
        XCTAssertEqual(p.fraction, 0, "progress counts finished stages, not the running one")
        p.begin("rewrite-main")
        XCTAssertEqual(p.headline, "Stage 2 / 4: Rewrite main program")
        XCTAssertEqual(p.completed, 1)
        XCTAssertEqual(p.fraction, 0.25, accuracy: 0.0001)
    }

    func testFinishReportsTheOutcome() {
        var p = StageProgress(stages: stages)
        p.begin("rewrite-main")
        p.finish(.failed)
        XCTAssertEqual(p.statusText, "Failed")
        XCTAssertEqual(p.completed, 1, "a failed stage stops the bar from advancing")
        p.finish(.cancelled)
        XCTAssertEqual(p.statusText, "Cancelled")
        p.begin("publish"); p.finish(.done)
        XCTAssertEqual(p.statusText, "Completed")
        XCTAssertEqual(p.completed, 4)
        XCTAssertEqual(p.fraction, 1)
    }

    func testAnUnknownStageIsAppendedNotHidden() {
        // If the backend ever emits a stage the plan did not name, the window
        // shows reality instead of silently disagreeing with the total.
        var p = StageProgress(stages: stages)
        p.begin("brand-new-stage", label: "New stage")
        XCTAssertEqual(p.total, 5)
        XCTAssertEqual(p.currentStage?.label, "New stage")
        XCTAssertEqual(p.headline, "Stage 5 / 5: New stage")
    }

    func testStageListSurvivesCodableRoundTrip() throws {
        let plan = PlanSummary(commands: 6, stages: stages, artifact: "/out/FIFA 23.app",
                               program_version: "v0", shader_source_versions: ["v0"])
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(PlanSummary.self, from: data)
        XCTAssertEqual(decoded.stages, stages)
        XCTAssertEqual(decoded.artifact, "/out/FIFA 23.app")
    }
}
