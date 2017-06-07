//
//  PrettyPrinter.swift
//  BNFC_cToSwift
//
//  Created by Jan Wittler on 04.06.17.
//  Copyright © 2017 Jan Wittler. All rights reserved.
//

import Foundation

struct PrettyPrinter {
    static func makePretty(_ code: String, indentationWidth: Int = 4) -> String {
        let lines = code.components(separatedBy: "\n")
        var indentationLevel = 0
        var code = lines.map { line -> String in
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                return ""
            }
            
            //handling multiple `{` or `}` in one line
            var indentChange = line.characters.filter({$0 == "{" }).count - line.characters.filter({$0 == "}" }).count
            //if line is prefixed with `}` we can already indent this line less
            if line.hasPrefix("}") {
                indentationLevel -= 1
                indentChange += 1
            }
            let value = String(repeating: " ", count: indentationLevel * indentationWidth) + line
            indentationLevel += indentChange
            //TODO: switches cases are not correctly indented
            return value
        }.joined(separator: "\n")
        
        if !code.hasSuffix("\n") {
            code += "\n"
        }
        return code
    }
}
