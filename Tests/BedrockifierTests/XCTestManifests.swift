import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(BackupConfigTests.allTests),
        testCase(OwnershipStringTests.allTests),
    ]
}
#endif
