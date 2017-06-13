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
                let structString = "public struct \(type) {" + "\n" +
                    "public let value: String" + "\n" +
                    "\n" +
                    "public init(_ value: String) {" + "\n" +
                    "self.value = value" + "\n"
                    + "}" +
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
                    cases.append(rCase)
                }
                //TODO: not every enum requires the `indirect` flag
                // rather it is only required for those which can create a cycle (possibly with itself or other enums)
                let enumString = "public indirect enum \(type) {" + "\n" +
                    cases.joined(separator: "\n") + "\n" +
                    "}"
                decls.append(enumString)
            }
        }
        
        decls += generatePrinting(for: groupedRules)
        return decls.joined(separator: "\n\n")
    }
    
    private static func generatePrinting(for groupedRules: [String : [BNFCRule]]) -> [String] {
        var decls = [String]()
        var tokenDecls = [String]()
        for (type, rules) in groupedRules {
            if let rule = rules.first, rules.count == 1, rule.ruleType == .token {
                tokenDecls += tokenHelpers(for: type)
            }
            else {
                decls.append("extension \(type): CustomAbstractSyntaxPrinting {" + "\n" + "}")
            }
        }
        
        if !decls.isEmpty {
            let customSyntaxPrinting = "public protocol CustomAbstractSyntaxPrinting {" + "\n" + "}" + "\n\n" +
                "public extension CustomAbstractSyntaxPrinting {" + "\n" +
                "public func show() -> String {" + "\n" +
                "let description = String(reflecting: self)" + "\n" +
                "let moduleName = description.components(separatedBy: \".\").first!" + "\n" +
                "return description.replacingOccurrences(of: \"\\(moduleName).\", with: \"\")" + "\n" +
                "}" + "\n" +
            "}"
            
            decls.insert("//MARK:- custom printing", at: 0)
            decls.insert(customSyntaxPrinting, at: 1)
        }
        
        if !tokenDecls.isEmpty {
            tokenDecls.insert("//MARK: Token helpers", at: 0)
        }
        
        return (decls + tokenDecls)
    }
    
    private static func tokenHelpers(for type: String) -> [String] {
        let tokenPrinting = "extension \(type): CustomStringConvertible {" + "\n" +
            "public var description: String { return \"\\(type(of: self))(\\(String(reflecting: value)))\" }" + "\n" +
        "}"
        
        let tokenEquatable = "extension \(type): Equatable {" + "\n" +
            "public static func ==(lhs: \(type), rhs: \(type)) -> Bool {" + "\n" +
            "return lhs.value == rhs.value" + "\n" +
            "}" + "\n" +
        "}"
        
        let tokenHashable = "extension \(type): Hashable {" + "\n" +
            "public var hashValue: Int { return value.hashValue }" + "\n" +
        "}"
        return [tokenPrinting, tokenEquatable, tokenHashable]
    }
    
    private static func adjustType(_ type: String) -> String {
        if type == "Integer" {
            return "Int"
        }
        else if type == "Double" {
            return "Double"
        }
        else if type == "String" {
            return "String"
        }
        else if type == "Char" {
            return "Character"
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
