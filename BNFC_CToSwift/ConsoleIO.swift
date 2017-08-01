//
//  ConsoleIO.swift
//  BNFC_cToSwift
//
//  Created by Jan Wittler on 05.06.17.
//  Copyright © 2017 Jan Wittler. All rights reserved.
//

import Foundation

/// Options that can be set using command line arguments.
struct ProgramConfiguration {
    /// The folder to which all output is written
    fileprivate(set) var outputPath: URL = URL(fileURLWithPath: "")
    /// The name of the module in the Xcode project to which the BNFC-generated files belong
    fileprivate(set) var moduleName: String = "CGrammar" {
        didSet { moduleName = moduleName.trimmingCharacters(in: .whitespaces) }
    }
    /// The path to the grammar file
    fileprivate(set) var inputFile: URL?
    
}

/**
 A helper structure to parse command line arguments into a dictionary
 */
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
                config.inputFile = URL(fileURLWithPath: arg)
                
            }
            i += 1
        }
        return config
    }
}
