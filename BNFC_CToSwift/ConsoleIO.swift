//
//  ConsoleIO.swift
//  BNFC_cToSwift
//
//  Created by Jan Wittler on 05.06.17.
//  Copyright © 2017 Jan Wittler. All rights reserved.
//

import Foundation

struct ProgramConfiguration {
    fileprivate(set) var outputPath: URL = URL(fileURLWithPath: "")
    fileprivate(set) var moduleName: String = "CGrammar"
    fileprivate(set) var inputFile: String?
    
}

struct ConsoleIO {
    static func parseCommandLineArguments() -> ProgramConfiguration {
        var i = 1
        var config = ProgramConfiguration()
        while Int32(i) < CommandLine.argc {
            let arg = CommandLine.arguments[i]
            switch arg {
            case "-o":
                i += 1
                config.outputPath = URL(fileURLWithPath: CommandLine.arguments[i])
            case "-m":
                i += 1
                config.moduleName = CommandLine.arguments[i]
                
            default:
                config.inputFile = arg
                
            }
            i += 1
        }
        return config
    }
}
