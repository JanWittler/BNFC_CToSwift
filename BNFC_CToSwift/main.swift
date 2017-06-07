//
//  main.swift
//  BNFC_cToSwift
//
//  Created by Jan Wittler on 04.06.17.
//  Copyright © 2017 Jan Wittler. All rights reserved.
//

import Foundation

private let prefix: String = {
    return "//" + "\n" +
        "//  Swift Abstract Syntax Interface generated by a custom BNF Converter from Jan Wittler" + "\n" +
        "//" + "\n" +
        "//  This converter assumes files generated by GNU Bison 2.3" + "\n" +
        "//  compatibility with other versions can not be guaranteed" + "\n" +
        "//" + "\n" +
    "\n"
}()

private func printFile(_ file: String, to path: URL) -> Bool {
    let output = PrettyPrinter.makePretty(file)
    do {
        try output.write(to: path, atomically: false, encoding: .utf8)
        print("generated file \(path.lastPathComponent)")
        return true
    }
    catch {
        print("writing file at path \(path.absoluteString) failed")
        return false
    }
}

let configuration = ConsoleIO.parseCommandLineArguments()
guard let inputFile = configuration.inputFile else {
    print("missing argument")
    exit(-1)
    //TODO: usage function
}

do {
    let path = CommandLine.arguments[1]
    let content = try String(contentsOfFile: path, encoding: .utf8)
    
    print("parsing...")
    
    let rules = try content.components(separatedBy: "\n").filter {!$0.isEmpty}.map { try BNFCRule.rules(from: $0) }.reduce([], +)
    let abstractSyntax = try prefix + AbstractSyntaxGenerator.generateSwift(from: rules)
    let mapping = try prefix + MappingGenerator(moduleName: configuration.moduleName)!.generateSwift(from: rules)
    
    print("parsing successful\n")
    
    var outputFiles = [("AbstractSyntax.swift", abstractSyntax),
                       ("\(configuration.moduleName)ToSwiftBridge.swift", mapping)]
    var success = outputFiles.reduce(true) {
        $0 && printFile($1.1, to: URL(fileURLWithPath: $1.0, relativeTo: configuration.outputPath))
    }
    guard success else {
        print("writing files failed")
        exit(-1)
    }
    print("")
}
catch let AbstractSyntaxGenerator.GeneratorError.parsingFailed(message) {
    print("parsing failed")
    print(message)
    exit(-1)
}
catch let error {
    
}
