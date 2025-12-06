/*
    Bedrockifier

    Copyright (c) 2021 Adam Thayer
    Licensed under the MIT license, as follows:

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.)
*/

import Foundation
import Logging

//
// Logger Objects
//
public struct Library {
    static let log = Logger(label: "bedrockifier")

    public static let dateFormatter: DateFormatter = {
        var formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    public static let dayFormatter: DateFormatter = {
        var formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        formatter.dateStyle = .medium
        return formatter
    }()
}

extension Logger {
    fileprivate func markerCharacter(for value: Bool, char: String) -> String {
        value ? char : "-"
    }

    public func traceFolderContents(_ folder: URL) {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isReadableKey, .isWritableKey]
            )

            self.trace("Contents of Folder: \(folder.path)")
            for url in contents {
                let values = try url.resourceValues(forKeys: [.isReadableKey])
                let isReadable = markerCharacter(for: values.isReadable ?? false, char: "r")
                let isWritable = markerCharacter(for: values.isWritable ?? false, char: "w")
                self.trace(" - \(url.path) [\(isReadable)\(isWritable)]")
            }
        }
        catch {
            self.trace("Unable to trace contents of folder: \(folder.path), \(error)")
        }
    }
}
