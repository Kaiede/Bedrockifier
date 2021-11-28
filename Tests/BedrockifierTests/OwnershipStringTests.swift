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
}
