import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(BackupConfigJsonTests.allTests),
        testCase(BackupConfigYamlTests.allTests),
        testCase(OwnershipStringTests.allTests),
    ]
}
#endif
