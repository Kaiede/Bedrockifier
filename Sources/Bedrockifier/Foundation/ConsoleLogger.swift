//
//  File.swift
//
//
//  Created by Alex Hadden on 12/18/21.
//

import Foundation
import Logging

// swiftlint:disable function_parameter_count

public final class ConsoleLogger: LogHandler {
    public static var logLevelOverride: Logger.Level?

    public static var showDetails: Bool = false

    public static var showFilePosition: Bool = false

    private static var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.calendar = Calendar.current
        formatter.dateFormat = "HH:mm:ss.SSS";
        return formatter
    }()

    public let label: String

    public var metadata: Logger.Metadata

    public var logLevel: Logger.Level {
        get { return ConsoleLogger.logLevelOverride ?? self.handlerLogLevel }
        set { self.handlerLogLevel = newValue }
    }

    private var handlerLogLevel: Logger.Level = .info

    public init(label: String) {
        self.label = label
        self.metadata = [:]
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { return metadata[key] }
        set(newValue) { metadata[key] = newValue }
    }

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        file: String,
        function: String,
        line: UInt
    ) {
        var outputStream = LoggingOutputStream.appropriateStream(for: level)
        let formattedMessage = formatMessage(message, level: level, file: file, line: line)
        print(formattedMessage, to: &outputStream)
    }

    private func formatMessage(_ message: Logger.Message, level: Logger.Level, file: String, line: UInt) -> String {
        var components: [String] = []

        if (ConsoleLogger.showDetails) {
            let nowString = ConsoleLogger.timeFormatter.string(from: Date())
            components.append("[\(nowString)][\(level.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0))]")
        }

        components.append("\(message)")

        if (ConsoleLogger.showFilePosition) {
            let shortFileName = URL(fileURLWithPath: file).lastPathComponent
            components.append("(\(shortFileName):\(line))")
        }

        return components.joined(separator: " ")
    }
}

private struct LoggingOutputStream: TextOutputStream {
    public static let stdOut = LoggingOutputStream(stdout)
    public static let stdErr = LoggingOutputStream(stderr)

    public static func appropriateStream(for level: Logger.Level) -> LoggingOutputStream {
        if level >= .error {
            return LoggingOutputStream.stdErr
        } else {
            return LoggingOutputStream.stdOut
        }
    }

    private let outStr: UnsafeMutablePointer<FILE>

    init(_ outStr: UnsafeMutablePointer<FILE>) {
        self.outStr = outStr
    }

    public mutating func write(_ string: String) { fputs(string, outStr) }
}
