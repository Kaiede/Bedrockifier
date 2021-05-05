//
//  DateExtensions.swift
//  BackupTrimmer
//
//  Created by Alex Hadden on 4/5/21.
//

import Foundation

extension Date {
    func toDayComponents(calendar: Calendar = Calendar.current) -> DateComponents {
        calendar.dateComponents([.day, .month, .year], from: self)
    }
}

extension DateFormatter {
    static var backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
