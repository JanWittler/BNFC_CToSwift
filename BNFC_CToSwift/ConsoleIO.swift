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
    
    /// The dicitionary of additional enum cases that gets used by the abstract syntax generator.
    fileprivate(set) var additionalCases: [String : [String]] = [:]
    
    /**
     Adds an additional case with the given type and the given case string to the additional cases dictionary.
     - parameters:
       - case: The Swift source code of the additional case. Does not get validated.
       - type: The type to which to add the additional case.
    */
    mutating func addAdditionalCase(_ case: String, forType type: String) {
        var cases = additionalCases[type] ?? []
        cases.append(`case`)
        additionalCases[type] = cases
    }
    
}

/**
 A helper structure to parse command line arguments into a dictionary
 */
struct ConsoleIO {
    static func parseCommandLineArguments() -> ProgramConfiguration {
        var i = 1
        var currentOption: String? = nil
        var config = ProgramConfiguration()
        while i < CommandLine.arguments.count {
            let arg = CommandLine.arguments[i]
            if arg.hasPrefix("-") {
                currentOption = arg
            }
            else if let currOpt = currentOption {
                switch currOpt {
                case "-o":
                    config.outputPath = URL(fileURLWithPath: arg)
                case "-m":
                    config.moduleName = arg
                case "-extra-case":
                    let type = arg
                    i += 1
                    if i < CommandLine.arguments.count {
                        let `case` = CommandLine.arguments[i]
                        config.addAdditionalCase(`case`, forType: type)
                    }
                default:
                    print("ignoring unknown command line paramater '\(currOpt)'")
                }
                currentOption = nil
            }
            else {
                config.inputFile = URL(fileURLWithPath: arg)
            }
            i += 1
        }
        return config
    }
}
