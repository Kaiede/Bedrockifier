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
    struct Unpack: ParsableCommand {
        fileprivate static let terminal = Terminal()

        static let configuration = CommandConfiguration(
            commandName: "unpack",
            abstract: "Unpacks an exported world into a given folder. Useful for unpacking a backup into a server's worlds folder."
        )
        
        @Argument(help: "World to unpack (as .mcworld or .zip)")
        var mcworld: String
        
        @Argument(help: "Folder to unpack into")
        var outputFolderPath: String
        
        @Flag(help: "Overwrite existing world folder; deletes everything in the folder")
        var overwrite = false
        
        func run() throws {
            let world = try World(url: URL(fileURLWithPath: mcworld))
            guard world.type != .folder else {
                Self.terminal.error("Archive is not a Bedrock or Java world.")
                return
            }
            
            let targetFolder = URL(fileURLWithPath: outputFolderPath)
            let worldFolder = targetFolder.appendingPathComponent(world.name)
            
            guard try !worldFolder.checkResourceIsReachable() || overwrite else {
                Self.terminal.error("World already exists at output folder.")
                return
            }
            
            if try worldFolder.checkResourceIsReachable() {
                let activity = Self.terminal.loadingBar(title: "Removing existing world")
                do {
                    activity.start()
                    try FileManager.default.removeItem(at: worldFolder)
                    activity.succeed()
                } catch {
                    activity.fail()
                    Self.terminal.error("Could not remove existing world: \(error.localizedDescription)")
                    return
                }
            }
            
            Self.terminal.output("World Name: \(world.name)")
            Self.terminal.output("Unpacking to: \(outputFolderPath)")
            Self.terminal.output("")
            
            let activity = Self.terminal.loadingBar(title: "Unpacking")
            do {
                activity.start()
                _ = try world.unpack(to: URL(fileURLWithPath: outputFolderPath))
                activity.succeed()
            } catch {
                activity.fail()
                Self.terminal.error("Could not unpack world: \(error.localizedDescription)")
            }
        }
    }
}
