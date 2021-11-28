import XCTest
@testable import Bedrockifier

final class OwnershipStringTests: XCTestCase {
    func testInvalidString() {
        do {
            let _ = try parse(ownership: "helloworld")
            XCTFail("Expected string to throw")
        } catch {
            // Expected
        }
        
        do {
            let _ = try parse(ownership: "hello:world")
            XCTFail("Expected string to throw")
        } catch {
            // Expected
        }
        
        do {
            let _ = try parse(ownership: "123:world")
            XCTFail("Expected string to throw")
        } catch {
            // Expected
        }
        
        do {
            let _ = try parse(ownership: "hello:456")
            XCTFail("Expected string to throw")
        } catch {
            // Expected
        }
    }
    
    func testNoOp() {
        do {
            let (uid, gid) = try parse(ownership: ":")
            XCTAssertEqual(uid, nil)
            XCTAssertEqual(gid, nil)
        } catch let error {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testUserOnly() {
        do {
            let (uid, gid) = try parse(ownership: "123")
            XCTAssertEqual(uid, 123)
            XCTAssertEqual(gid, nil)
        } catch let error {
            XCTFail(error.localizedDescription)
        }
        
        do {
            let (uid, gid) = try parse(ownership: "123:")
            XCTAssertEqual(uid, 123)
            XCTAssertEqual(gid, nil)
        } catch let error {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testGroupOnly() {
        do {
            let (uid, gid) = try parse(ownership: ":456")
            XCTAssertEqual(uid, nil)
            XCTAssertEqual(gid, 456)
        } catch let error {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testBothUserAndGroup() {
        do {
            let (uid, gid) = try parse(ownership: "123:456")
            XCTAssertEqual(uid, 123)
            XCTAssertEqual(gid, 456)
        } catch let error {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testInvalidPermissions() {
        do {
            let _ = try parse(permissions: "hello")
            XCTFail("Expected string to throw")
        } catch {
            // Expected
        }
        
        do {
            let _ = try parse(permissions: "world")
            XCTFail("Expected string to throw")
        } catch {
            // Expected
        }
        
        do {
            let _ = try parse(permissions: "123:456")
            XCTFail("Expected string to throw")
        } catch {
            // Expected
        }
    }
    
    func testOutOfBoundsPermissions() {
        do {
            let _ = try parse(permissions: "778")
            XCTFail("Expected string to throw")
        } catch {
            // Expected
        }
        
        do {
            let _ = try parse(permissions: "888")
            XCTFail("Expected string to throw")
        } catch {
            // Expected
        }
        
        do {
            let _ = try parse(permissions: "1000")
            XCTFail("Expected string to throw")
        } catch {
            // Expected
        }
    }
    
    func testValidPermissions() {
        do {
            let result = try parse(permissions: "666")
            XCTAssertEqual(result, 666)
        } catch let error {
            XCTFail(error.localizedDescription)
        }
        
        do {
            let result = try parse(permissions: "644")
            XCTAssertEqual(result, 644)
        } catch let error {
            XCTFail(error.localizedDescription)
        }

        do {
            let result = try parse(permissions: "777")
            XCTAssertEqual(result, 777)
        } catch let error {
            XCTFail(error.localizedDescription)
        }

        do {
            let result = try parse(permissions: "444")
            XCTAssertEqual(result, 444)
        } catch let error {
            XCTFail(error.localizedDescription)
        }

    }
    
    static var allTests = [
        ("testInvalidString", testInvalidString),
        ("testNoOp", testNoOp),
        ("testUserOnly", testUserOnly),
        ("testGroupOnly", testGroupOnly),
        ("testBothUserAndGroup", testBothUserAndGroup),
        ("testInvalidPermissions", testInvalidPermissions),
        ("testOutOfBoundsPermissions", testOutOfBoundsPermissions),
        ("testValidPermissions", testValidPermissions),
    ]
}
