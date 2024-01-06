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

import Bedrockifier

public final class UnpackCommand: Command {
    public struct Signature: CommandSignature {
        @Argument(name: "mcworld", help: "World to unpack (as .mcworld)")
        var mcworld: String

        @Argument(name: "outputFolderPath", help: "Folder to unpack into")
        var outputFolderPath: String

        public init() {}
    }

    public init() {}

    public var help: String {
        "Unpacks an exported world into a given folder. Useful for unpacking a backup into a server's worlds folder."
    }

    public func run(using context: CommandContext, signature: Signature) throws {
        do {
            let world = try World(url: URL(fileURLWithPath: signature.mcworld))
            guard world.type != .folder else {
                context.console.error("Input was not an mcworld")
                return
            }

            context.console.print("World Name: \(world.name)")
            context.console.print("Unpacking to: \(signature.outputFolderPath)")
            context.console.print()

            context.console.print("Unpacking...")
            _ = try world.unpack(to: URL(fileURLWithPath: signature.outputFolderPath))
            context.console.print("Done.")
        } catch let error {
            context.console.error("Exception Was Hit")
            context.console.error(error.localizedDescription)
        }
    }
}
