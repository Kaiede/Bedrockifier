//
//  main.swift
//  BackupTrimmer
//
//  Created by Alex Hadden on 4/5/21.
//

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
