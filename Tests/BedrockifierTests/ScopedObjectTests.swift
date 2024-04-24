import XCTest
@testable import Bedrockifier

final class MockScopedObject {
    private let deinitHandler: () -> Void

    init(deinitHandler: @escaping () -> Void) {
        self.deinitHandler = deinitHandler
    }

    static func makeOptional(succeed: Bool, deinitHandler: @escaping () -> ()) -> MockScopedObject? {
        if succeed {
            return MockScopedObject(deinitHandler: deinitHandler)
        }

        return nil
    }

    func doSomething() { print("MockScopedObject Did The Thing") }

    deinit {
        self.deinitHandler()
    }
}

struct MockScopedObjectError: Error {}

final class ScopedObjectTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testScopedObject() throws {
        var didDeinit = false
        with(scopedObject: MockScopedObject(deinitHandler: { didDeinit = true }) ) { scopedObject in
            scopedObject.doSomething()
            XCTAssertFalse(didDeinit)
        }
        XCTAssertTrue(didDeinit)
    }

    func testTryScopedObject_Success() throws {
        var didDeinit = false
        try with(scopedOptional: MockScopedObject.makeOptional(succeed: true, deinitHandler: { didDeinit = true }) ) { scopedObject in
            scopedObject.doSomething()
            XCTAssertFalse(didDeinit)
        }
        XCTAssertTrue(didDeinit)
    }

    func testTryScopedObject_Failure() throws {
        do {
            try with(scopedOptional: MockScopedObject.makeOptional(succeed: false, deinitHandler: {})) { scopedObject in
                XCTFail("Should not be able to act on anything")
            }
            XCTFail("Should have thrown here")
        } catch is NullScopedObjectError {
        } catch {
            XCTFail("Wrong Error Thrown")
        }
    }

    func testThrowingScope() throws {
        var didDeinit = false
        do {
            try with(scopedOptional: MockScopedObject.makeOptional(succeed: true, deinitHandler: { didDeinit = true }) ) { scopedObject in
                XCTAssertFalse(didDeinit)
                throw MockScopedObjectError()
            }
        } catch is NullScopedObjectError {
            XCTFail("Wrong Error Thrown")
        } catch {}
        XCTAssertTrue(didDeinit)
    }
}
