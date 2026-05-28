import Foundation
import Testing
@testable import BedrockifierLib

@Suite struct TrimmingTests {
    @Test func trimmingOfBucket() throws {
        let testBackupItems = [
            MockBackupItem("file:///backups/first.zip"),
            MockBackupItem("file:///backups/second.zip"),
            MockBackupItem("file:///backups/third.zip"),
            MockBackupItem("file:///backups/fourth.zip")
        ]

        let testBackupArray = createBackupArray(testBackupItems)
        let newest = try #require(testBackupArray.last)

        testBackupArray.trimBucket()
        let keep = testBackupArray.filter({ $0.action == .keep })
        let trim = testBackupArray.filter({ $0.action == .trim })
        #expect(keep.count == 1)
        #expect(trim.count == 3)
        #expect(keep.first?.item.name == newest.item.name)
    }

    @Test func trimmingWithKeepLast() {
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
            let testBackupArray = createBackupArray(testBackupItems)
            testBackupArray.trimBucket(keepLast: 3)
            let keep = testBackupArray.filter({ $0.action == .keep })
            let keepNames = keep.map({ $0.item.name })
            #expect(keep.count == 3)
            #expect(keepNames == testBackupArray.suffix(3).map({ $0.item.name }))
        }

        // Case 2: Keep 6
        do {
            let testBackupArray = createBackupArray(testBackupItems)
            testBackupArray.trimBucket(keepLast: 6)
            let keep = testBackupArray.filter({ $0.action == .keep })
            let keepNames = keep.map({ $0.item.name })
            #expect(keep.count == 6)
            #expect(keepNames == testBackupArray.suffix(6).map({ $0.item.name }))
        }
    }

    private func createBackupArray(_ testItems: [MockBackupItem]) -> [Backup<MockBackupItem>] {
        let startDate = Date()
        var result: [Backup<MockBackupItem>] = []
        for index in testItems.indices {
            result.append(
                Backup(
                    item: testItems[index],
                    date: Date(timeInterval: 1.0 * TimeInterval(index), since: startDate)
                )
            )
        }
        return result.sorted(by: { $0.modificationDate < $1.modificationDate })
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
