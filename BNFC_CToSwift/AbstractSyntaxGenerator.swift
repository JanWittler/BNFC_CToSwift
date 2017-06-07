//
//  AbstractSyntaxGenerator.swift
//  BNFC_cToSwift
//
//  Created by Jan Wittler on 04.06.17.
//  Copyright © 2017 Jan Wittler. All rights reserved.
//

import Foundation

struct AbstractSyntaxGenerator {
    enum GeneratorError: Error {
        case parsingFailed(String)
    }
    
    static func generateSwift(from rules: [BNFCRule]) throws -> String {
        var groupedRules = [String : [BNFCRule]]()
        for rule in rules {
            var group = groupedRules[rule.type] ?? []
            group.append(rule)
            groupedRules[rule.type] = group
        }
        
        var decls = [String]()
        for (type, rules) in groupedRules {
            var cases = [String]()
            //check for token rule
            if let rule = rules.first, rules.count == 1, rule.ruleType == .token {
                let structString = "struct \(type) {" + "\n" +
                    "let value: Swift.String" + "\n" +
                    "}"
                decls.append(structString)
            }
            else {
                for rule in rules {
                    guard rule.ruleType == .constructor else {
                        throw AbstractSyntaxGenerator.GeneratorError.parsingFailed("unhandled case where token type `\(type)` is present in another rule")
                    }
                    var rCase = "case \(enumCaseFromLabel(rule.label))"
                    if !rule.construction.isEmpty {
                        rCase += "(" + rule.construction.map { adjustType($0) }.joined(separator: ", ") + ")"
                    }
                    if rule.construction.contains(type) {
                        rCase = "indirect " + rCase
                    }
                    cases.append(rCase)
                }
                let enumString = "enum \(type) {" + "\n" +
                    cases.joined(separator: "\n") + "\n" +
                    "}"
                decls.append(enumString)
            }
            
        }
        return decls.joined(separator: "\n\n") + "\n\n" + generatePrinting(for: groupedRules)
    }
    
    private static func generatePrinting(for groupedRules: [String : [BNFCRule]]) -> String {
        var decls = [String]()
        var tokenDecls = [String]()
        for (type, rules) in groupedRules {
            if let rule = rules.first, rules.count == 1, rule.ruleType == .token {
                let tokenPrinting = "extension \(type): CustomStringConvertible {" + "\n" +
                "var description: String { return \"\\(type(of: self))(\\(String(reflecting: value)))\" }" + "\n" +
                "}"
                tokenDecls.append(tokenPrinting)
            }
            decls.append("extension \(type): CustomAbstractSyntaxPrinting {" + "\n" + "}")
        }
        
        let customSyntaxPrinting = "protocol CustomAbstractSyntaxPrinting {" + "\n" + "}" + "\n\n" +
        "extension CustomAbstractSyntaxPrinting {" + "\n" +
        "func show() -> String {" + "\n" +
        "let description = String(reflecting: self)" + "\n" +
        "let moduleName = description.components(separatedBy: \".\").first!" + "\n" +
        "return description.replacingOccurrences(of: \"\\(moduleName).\", with: \"\")" + "\n" +
        "}" + "\n" +
        "}"
        
        decls.insert("//MARK:- custom printing", at: 0)
        decls.insert(customSyntaxPrinting, at: 1)
        return (decls + tokenDecls).joined(separator: "\n\n")
    }
    
    private static func adjustType(_ type: String) -> String {
        if type == "Integer" {
            return "Swift.Int"
        }
        else if type == "Double" {
            return "Swift.Double"
        }
        else if type == "String" {
            return "Swift.String"
        }
        else if type == "Char" {
            return "Swift.Character"
        }
        else if type == "Ident" {
            //TODO: handle bnfc `Ident` type correctly
        }
        return type
    }
    
    static func enumCaseFromLabel(_ label: String) -> String {
        return label.firstCharLowercased()
    }
}

private extension String {
    func firstCharLowercased() -> String {
        guard let firstChar = characters.first else {
            return self
        }
        let otherChars = characters.dropFirst()
        return String(firstChar).lowercased() + String(otherChars)
    }
}
