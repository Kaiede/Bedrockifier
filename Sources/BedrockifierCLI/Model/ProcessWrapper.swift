//
//  File.swift
//  
//
//  Created by Alex Hadden on 4/9/21.
//

import Foundation

import PtyKit

enum ProcessError: Error {
    case NotRunning
}

class ProcessWrapper {
    let process: Process
    let hostHandle: FileHandle
    let targetHandle: FileHandle
    let outPipe: Pipe
    var outObserver: NSObjectProtocol?
    let readSemaphore: DispatchSemaphore
    let bufferSemaphore: DispatchSemaphore
    var linesBuffer: [String]
    
    init(_ launchExecutable: URL, _ arguments: [String]) throws {
        readSemaphore = DispatchSemaphore(value: 0)
        bufferSemaphore = DispatchSemaphore(value: 1)
        linesBuffer = []
        
        process = Process()
        process.executableURL = launchExecutable
        process.arguments = arguments
        
        // Setup the pipe
        outPipe = Pipe()
        
        hostHandle = try FileHandle.openPty()
        targetHandle = try hostHandle.getChildPty()
    }
    
    func launch() {
        process.standardInput = targetHandle
        process.standardError = outPipe
        process.standardOutput = outPipe
        
        print("Launching: \(String(describing: process.arguments))")
        self.process.launch()
        
        self.process.terminationHandler = { _ in
            print("Process Terminated")
            self.readSemaphore.signal()
        }
    }
    
    func waitUntilExit() {
        process.waitUntilExit()
    }
    
    func send(_ content: String) throws {
        guard process.isRunning else {
            print("Process is not Running")
            throw ProcessError.NotRunning
        }
        
        guard let data = content.data(using: .utf8) else {
            return
        }
        
        print("Sending: \(content)")
        hostHandle.write(data)
    }
    
    func expect(_ content: String) throws -> String {
        return try expect([content])
    }
    
    func expect(_ content: [String]) throws -> String {
        guard process.isRunning else {
            print("Process is not Running")
            throw ProcessError.NotRunning
        }
        
        print("Expecting: \(content)")
        while process.isRunning {
            let outHandle = outPipe.fileHandleForReading
            if !outHandle.availableData.isEmpty {
                if let match = findMatches(inputHandle: outHandle, expressions: content) {
                    return match
                }
            } else {
                Thread.sleep(forTimeInterval: 1.0)
            }
        }
        
        throw ProcessError.NotRunning
    }
    
    private func findMatches(inputHandle: FileHandle, expressions: [String]) -> String? {
        let data = inputHandle.availableData
        if data.count > 0 {
            if let str = String(data: data, encoding: String.Encoding.utf8) {
                print("Content Read: \(str)")
                for expression in expressions {
                    let range = str.range(of: expression, options: [.regularExpression, .caseInsensitive])
                    if range != nil {
                        return expression
                    }
                }
            }
        }
        
        return nil
    }
}
