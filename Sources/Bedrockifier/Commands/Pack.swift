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

import ArgumentParser
import ConsoleKitTerminal

extension Bedrockifier {
    struct Pack: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "pack",
            abstract: "Packs a folder world into an mcworld (Bedrock) or zip archive (Java) for you."
        )

        @Argument(help: "Filename to pack into (.mcworld or .zip)")
        var archive: String

        @Argument(help: "World folder to pack")
        var inputFolderPath: String

        @Flag(help: "Overwrite existing files")
        var overwrite = false

        func run() async throws {
            let terminal = Bedrockifier.initializeTerminal()

            let world = try World(url: URL(fileURLWithPath: inputFolderPath))
            guard world.type == .folder else {
                terminal.error("World at path must be a folder.")
                return
            }

            guard !FileManager.default.fileExists(atPath: archive) || overwrite else {
                terminal.error("Cannot overwrite existing file at \(archive).")
                return
            }

            do {
                if FileManager.default.fileExists(atPath: archive) {
                    try FileManager.default.removeItem(atPath: archive)
                }
            } catch {
                terminal.error("Failed to remove existing file at \(archive).")
                return
            }

            terminal.output("World Name: \(world.name)")
            terminal.output("Packing into: \(archive)")
            terminal.emptyLine()

            let activity = terminal.loadingBar(title: "Packing")
            do {
                activity.start()
                _ = try world.pack(to: URL(fileURLWithPath: archive))
                activity.succeed()
            } catch {
                activity.fail()
                terminal.error("Could not pack world: \(error.localizedDescription)")
            }
        }
    }
}
