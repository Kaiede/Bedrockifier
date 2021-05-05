//
//  File.swift
//  
//
//  Created by Alex Hadden on 4/9/21.
//

import ConsoleKit
import Foundation

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
            guard world.type == .mcworld else {
                context.console.error("Input was not an mcworld")
                return
            }
            
            context.console.print("World Name: \(world.name)")
            context.console.print("Unpacking to: \(signature.outputFolderPath)")
            context.console.print()
            
            context.console.print("Unpacking...")
            let _ = try world.unpack(to: URL(fileURLWithPath: signature.outputFolderPath))
            context.console.print("Done.")
        } catch(let error) {
            context.console.error("Exception Was Hit")
            context.console.error(error.localizedDescription)
        }
    }
}
