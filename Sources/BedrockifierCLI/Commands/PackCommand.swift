//
//  File.swift
//  
//
//  Created by Alex Hadden on 4/9/21.
//

import ConsoleKit
import Foundation

final class PackCommand: Command {
    struct Signature: CommandSignature {
        @Argument(name: "mcworld", help: "Filename to pack into (as .mcworld)")
        var mcworld: String
        
        @Argument(name: "inputFolderPath", help: "Folder to pack")
        var inputFolderPath: String
                
        init() {}
    }
    
    var help: String {
        "Packs a folder world into an mcworld for you."
    }
    
    func run(using context: CommandContext, signature: Signature) throws {
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
            let _ = try world.pack(to: URL(fileURLWithPath: signature.mcworld))
            context.console.print("Done.")
        } catch {
            context.console.error("Exception Was Hit")
            context.console.error(error.localizedDescription)
        }
    }
}
