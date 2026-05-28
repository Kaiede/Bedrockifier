import Testing
@testable import Bedrockifier

@Suite struct OwnershipStringTests {
    @Test(arguments: ["helloworld", "hello:world", "123:world", "hello:456"])
    func invalidOwnershipString(_ input: String) {
        #expect(throws: (any Error).self) { _ = try parse(ownership: input) }
    }

    @Test func noOp() throws {
        let (uid, gid) = try parse(ownership: ":")
        #expect(uid == nil)
        #expect(gid == nil)
    }

    @Test(arguments: ["123", "123:"])
    func userOnly(_ input: String) throws {
        let (uid, gid) = try parse(ownership: input)
        #expect(uid == 123)
        #expect(gid == nil)
    }

    @Test func groupOnly() throws {
        let (uid, gid) = try parse(ownership: ":456")
        #expect(uid == nil)
        #expect(gid == 456)
    }

    @Test func bothUserAndGroup() throws {
        let (uid, gid) = try parse(ownership: "123:456")
        #expect(uid == 123)
        #expect(gid == 456)
    }

    @Test(arguments: ["hello", "world", "123:456"])
    func invalidPermissions(_ input: String) {
        #expect(throws: (any Error).self) { _ = try parse(permissions: input) }
    }

    @Test(arguments: ["778", "888", "1000"])
    func outOfBoundsPermissions(_ input: String) {
        #expect(throws: (any Error).self) { _ = try parse(permissions: input) }
    }

    @Test(arguments: zip(["666", "644", "777", "444"], [0o666, 0o644, 0o777, 0o444] as [Platform.Mode]))
    func validPermissions(_ input: String, _ expected: Platform.Mode) throws {
        #expect(try parse(permissions: input) == expected)
    }

    @Test func octalFormatting() {
        #expect(String(format: "%o", 0o664) == "664")
    }
}
