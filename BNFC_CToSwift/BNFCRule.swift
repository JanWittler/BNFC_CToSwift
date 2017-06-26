//
//  BNFCRule.swift
//  BNFC_cToSwift
//
//  Created by Jan Wittler on 04.06.17.
//  Copyright © 2017 Jan Wittler. All rights reserved.
//

import Foundation

internal enum BNFCRule {
    case constructor(label: String, type: String, construction: [String])
    case token(type: String)
    case entrypoint(types: [String])
    
    static func rules(from path: String) throws -> [BNFCRule] {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        var rules = try content.components(separatedBy: "\n").filter {!$0.isEmpty}.map { try BNFCRule.rules(fromLine: $0) }.reduce([], +)
        if BNFCRule.identUsed(in: rules) {
            rules.append(identToken())
        }
        return rules
    }
    
    private static func rules(fromLine line: String) throws -> [BNFCRule] {
        let line = line.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("rules") {
            return try rulesFromBNFCRulesKeyword(line)
        }
        else {
            if let rule = try BNFCRule(line) {
                return [rule]
            }
        }
        return []
    }
    
    private static func rulesFromBNFCRulesKeyword(_ string: String) throws -> [BNFCRule] {
        let string = string.trimmingCharacters(in: .whitespaces)
        guard let declLocation = string.range(of: "::=") else {
            throw AbstractSyntaxGenerator.GeneratorError.parsingFailed("invalid rule: \(string)")
        }
        guard let rulesLocation = string.range(of: "rules") else {
            print("rules method called with non-`rules` rule: \(string)")
            return []
        }
        guard string.hasSuffix(";") else {
            throw AbstractSyntaxGenerator.GeneratorError.parsingFailed("rules must be terminated with `;`")
        }
        
        let type = string.substring(to: declLocation.lowerBound).substring(from: rulesLocation.upperBound).trimmingCharacters(in: .whitespaces)
        var constructionsString = string.substring(from: declLocation.upperBound)
        //trimm trailing `;`
        constructionsString = constructionsString.substring(to: constructionsString.index(before: constructionsString.endIndex))
        let constructions = constructionsString.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return try constructions.flatMap {
            guard $0.components(separatedBy: " ").count == 1 else {
                //TODO: update rules support for n constructors per case
                throw AbstractSyntaxGenerator.GeneratorError.parsingFailed("currently this parser is not able to parse bnfc `rules` keyword with more than one constructor per case")
            }
            //normal bnfc generated rule would be `type_value. type ::= value ;` but we go with `value. type ::= value ;` to have generated enums closer to swift naming conventions
            let ruleString = "\($0.replacingOccurrences(of: "\"", with: "")). \(type) ::= \($0) ;"
            return try BNFCRule(ruleString)
        }
    }
    
    init?(_ rule: String) throws {
        let tempRule = rule.trimmingCharacters(in: .whitespaces)
        guard tempRule.hasSuffix(";") else {
            throw AbstractSyntaxGenerator.GeneratorError.parsingFailed("rules must be terminated with `;`")
        }
        let rule = tempRule.substring(to: tempRule.index(before: tempRule.endIndex))
        //rules below can be ignored
        if rule.hasPrefix("comment") {
            return nil
        }
        if rule.hasPrefix("terminator") {
            return nil
        }
        if rule.hasPrefix("separator") {
            return nil
        }
        if rule.hasPrefix("coercions") {
            return nil
        }
        
        guard !rule.hasPrefix("token") else {
            //get token name
            let type = BNFCRule.cleanType(rule.components(separatedBy: " ").filter { !$0.isEmpty }[1])
            self = .token(type: type)
            return
        }
        
        guard !rule.hasPrefix("entrypoints") else {
            //get entrypoints
            let types = rule.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map { BNFCRule.cleanType($0) }
            self = .entrypoint(types: types)
            return
        }
        
        guard let dotLocation = rule.range(of: "."), let declLocation = rule.range(of: "::=") else {
            throw AbstractSyntaxGenerator.GeneratorError.parsingFailed("invalid rule: \(rule)")
        }
        let label = BNFCRule.cleanLabel(rule.substring(to: dotLocation.lowerBound))
        let type  = BNFCRule.cleanType(rule.substring(to: declLocation.lowerBound).substring(from: dotLocation.upperBound))
        let construction = BNFCRule.cleanConstruction(rule.substring(from: declLocation.upperBound))
        self = .constructor(label: label, type: type, construction: construction)
    }
    
    private static func cleanLabel(_ pLabel: String) -> String {
        var label = pLabel.trimmingCharacters(in: .whitespaces)
        //remove leading `internal`
        if let internalRange = label.range(of: "internal"), internalRange.lowerBound == label.startIndex {
            label = label.substring(from: internalRange.upperBound).trimmingCharacters(in: .whitespaces)
        }
        return label
    }
    
    private static func cleanType(_ pType: String) -> String {
        var type = pType.trimmingCharacters(in: .whitespaces)
        //remove trailing decimals since they are used for precedence and don't affect the type
        while String(type.characters.last!).rangeOfCharacter(from: .decimalDigits) != nil {
            type = type.substring(to: type.index(before: type.endIndex))
        }
        return type
    }
    
    private static func cleanConstruction(_ pConstruction: String) -> [String] {
        //filter out constants
        let construction = pConstruction.components(separatedBy: "\"").enumerated().flatMap { $0.0 % 2 == 0 ? $0.element : nil }.joined(separator: " ")
        return construction.components(separatedBy: " ").filter { !$0.isEmpty }.map { cleanType($0) }
    }
    
    //MARK:- custom handling for `Ident`
    //BNFC has the built-in type `Ident` which is effectively a String so we treat it as if it is a token declaration
    
    private static var Ident = "Ident"
    
    /**
     a helper method to check if the `Ident` key of BNFC is used in any of the given rules
     - parameters:
     - rules: the rules to check for
     - returns: returns `true` in case the `Ident` key is used, otherwise `false`
     */
    private static func identUsed(in rules: [BNFCRule]) -> Bool {
        return rules.reduce(false) { previous, rule in
            let containsIdent: Bool
            switch rule {
            case let .constructor(label: _, type: _, construction: construction):
                containsIdent = construction.contains(Ident)
            case let .entrypoint(types: types):
                containsIdent = types.contains(Ident)
            case .token(type: _):
                containsIdent = false
            }
            return previous || containsIdent
        }
    }
    
    private static func identToken() -> BNFCRule {
        return .token(type: Ident)
    }
}
