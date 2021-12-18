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

import ConsoleKit
import Foundation

public final class PackCommand: Command {
    public struct Signature: CommandSignature {
        @Argument(name: "mcworld", help: "Filename to pack into (as .mcworld)")
        var mcworld: String

        @Argument(name: "inputFolderPath", help: "Folder to pack")
        var inputFolderPath: String

        public init() {}
    }

    public init() {}

    public var help: String {
        "Packs a folder world into an mcworld for you."
    }

    public func run(using context: CommandContext, signature: Signature) throws {
        do {
            let world = try World(url: URL(fileURLWithPath: signature.inputFolderPath))
            guard world.type == .folder else {
                context.console.error("Input was not a folder")
                return
            }

            guard !FileManager.default.fileExists(atPath: signature.mcworld) else {
                context.console.error("Output file already exists")
                return
            }

            context.console.print("World Name: \(world.name)")
            context.console.print("Packing into: \(signature.mcworld)")
            context.console.print()

            context.console.print("Packing...")
            _ = try world.pack(to: URL(fileURLWithPath: signature.mcworld))
            context.console.print("Done.")
        } catch {
            context.console.error("Exception Was Hit")
            context.console.error(error.localizedDescription)
        }
    }
}
