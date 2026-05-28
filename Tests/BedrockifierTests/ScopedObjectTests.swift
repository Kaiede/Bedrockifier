import Testing
@testable import Bedrockifier

private final class MockScopedObject {
    private let deinitHandler: () -> Void

    init(deinitHandler: @escaping () -> Void) {
        self.deinitHandler = deinitHandler
    }

    static func makeOptional(succeed: Bool, deinitHandler: @escaping () -> Void) -> MockScopedObject? {
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

private struct MockScopedObjectError: Error {}

@Suite struct ScopedObjectTests {
    @Test func scopedObject() {
        var didDeinit = false
        with(scopedObject: MockScopedObject(deinitHandler: { didDeinit = true })) { scopedObject in
            scopedObject.doSomething()
            #expect(!didDeinit)
        }
        #expect(didDeinit)
    }

    @Test func tryScopedObjectSuccess() throws {
        var didDeinit = false
        try with(scopedOptional: MockScopedObject.makeOptional(
            succeed: true,
            deinitHandler: { didDeinit = true }
        )) { scopedObject in
            scopedObject.doSomething()
            #expect(!didDeinit)
        }
        #expect(didDeinit)
    }

    @Test func tryScopedObjectFailure() {
        #expect(throws: NullScopedObjectError.self) {
            try with(scopedOptional: MockScopedObject.makeOptional(succeed: false, deinitHandler: {})) { _ in
                Issue.record("Should not be able to act on anything")
            }
        }
    }

    @Test func throwingScope() {
        var didDeinit = false
        do {
            try with(scopedOptional: MockScopedObject.makeOptional(
                succeed: true,
                deinitHandler: { didDeinit = true }
            )) { _ in
                #expect(!didDeinit)
                throw MockScopedObjectError()
            }
        } catch is NullScopedObjectError {
            Issue.record("Wrong Error Thrown")
        } catch {}
        #expect(didDeinit)
    }
}
