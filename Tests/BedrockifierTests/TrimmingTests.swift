import XCTest
@testable import Bedrockifier

final class TrimmingTests: XCTestCase {
    func testTrimmingOfBucket() {
        let testBackupItems = [
            MockBackupItem("file:///backups/first.zip"),
            MockBackupItem("file:///backups/second.zip"),
            MockBackupItem("file:///backups/third.zip"),
            MockBackupItem("file:///backups/fourth.zip")
        ]

        let testBackupArray = testBackupItems.map({ Backup(item: $0, date: Date())})
        guard let newest = testBackupArray.max(by: { $0.modificationDate < $1.modificationDate }) else {
            XCTFail("Getting newest item from array failed")
            return
        }

        // Do trim and confirm
        testBackupArray.trimBucket()
        let keep = testBackupArray.filter({ $0.action == .keep })
        let trim = testBackupArray.filter({ $0.action == .trim })
        XCTAssertEqual(keep.count, 1) // One should be kept by default.
        XCTAssertEqual(trim.count, 3) // All others should be marked trim.
        XCTAssertEqual(keep.first?.item.name, newest.item.name) // The one kept should be the newest one in the bucket.
    }

    func testTrimmingWithKeepLast() {
        let testBackupItems = [
            MockBackupItem("file:///backups/first.zip"),
            MockBackupItem("file:///backups/second.zip"),
            MockBackupItem("file:///backups/third.zip"),
            MockBackupItem("file:///backups/fourth.zip"),
            MockBackupItem("file:///backups/fifth.zip"),
            MockBackupItem("file:///backups/sixth.zip"),
            MockBackupItem("file:///backups/seventh.zip"),
            MockBackupItem("file:///backups/eighth.zip")
        ]

        // Case 1: Keep 3
        do {
            let testBackupArray = testBackupItems
                .map({ Backup(item: $0, date: Date())})
                .sorted(by: { $0.modificationDate < $1.modificationDate })

            testBackupArray.trimBucket(keepLast: 3)
            let keep = testBackupArray.filter({ $0.action == .keep })
            let keepNames = keep.map({ $0.item.name })
            XCTAssertEqual(keep.count, 3)
            XCTAssertEqual(keepNames, testBackupArray.suffix(3).map({ $0.item.name }))
        }


        // Case 2: Keep 6
        do {
            let testBackupArray = testBackupItems
                .map({ Backup(item: $0, date: Date())})
                .sorted(by: { $0.modificationDate < $1.modificationDate })

            testBackupArray.trimBucket(keepLast: 6)
            let keep = testBackupArray.filter({ $0.action == .keep })
            let keepNames = keep.map({ $0.item.name })
            XCTAssertEqual(keep.count, 6)
            XCTAssertEqual(keepNames, testBackupArray.suffix(6).map({ $0.item.name }))
        }
    }
}

struct MockBackupItem: BackupItem {
    var name: String
    var location: URL

    init(url: URL) {
        self.location = url
        self.name = url.lastPathComponent
    }

    init(_ string: String) {
        let url = URL(fileURLWithPath: string)
        self.init(url: url)
    }
}
