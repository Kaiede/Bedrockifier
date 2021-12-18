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
import Logging

import Bedrockifier

// Configure Console
let terminal = Terminal()
var input = CommandInput(arguments: CommandLine.arguments)

var commands = Commands()
commands.use(BackupCommand(), as: "backup")
commands.use(BackupJobCommand(), as: "backupjob")
commands.use(PackCommand(), as: "pack")
commands.use(TrimCommand(), as: "trim")
commands.use(UnpackCommand(), as: "unpack")
var allCommands = commands.group(help: "Minecraft Bedrock Backup Tool")

LoggingSystem.bootstrap(console: terminal, level: .trace, metadata: .init())

do {
    try terminal.run(allCommands, input: input)
} catch let error {
    terminal.error(error.localizedDescription)
    exit(1)
}
