// Standalone XCTest entry point for environments without SwiftPM build services.
import XCTest
import Darwin

let suite = XCTestSuite(name: "Packaging GUI")
suite.addTest(ConfigurationTests.defaultTestSuite)
suite.addTest(StandaloneTests.defaultTestSuite)
suite.addTest(ApprovalTests.defaultTestSuite)
suite.addTest(BuildExecutorTests.defaultTestSuite)
suite.addTest(GameIdentityTests.defaultTestSuite)
suite.addTest(GameCatalogTests.defaultTestSuite)
suite.addTest(StageProgressTests.defaultTestSuite)
suite.addTest(LocalizationTests.defaultTestSuite)
suite.addTest(MenuPresentationTests.defaultTestSuite)
suite.run()
exit(suite.testRun?.hasSucceeded == true ? EXIT_SUCCESS : EXIT_FAILURE)
