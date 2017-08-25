//
//  BNFCRule.swift
//  BNFC_cToSwift
//
//  Created by Jan Wittler on 04.06.17.
//  Copyright © 2017 Jan Wittler. All rights reserved.
//

import Foundation

/// A `BNFCRule` represents a rule taken from a BNFC-conforming grammar file.
internal enum BNFCRule {
    /// A construction rule, coming either from a labeled rule or using the `rules` keyword
    case constructor(label: String, type: String, construction: [String])
    /// A token, created using the `token` keyword
    case token(type: String)
    /// a entrypoint rule, created using the `entrypoints` keyword
    case entrypoint(types: [String])
    
    /// Errors that may occur during grammar parsing
    enum ParsingError: Error {
        /// Indicates that parsing failed. Associated value contains detailed information about failure reason.
        case parsingFailed(String)
    }
    
    /**
     Parses the file at the given path into an array of `BNFCRules`, ignoring rules only relevant for parser, which includes rules starting with keywords `comment`, `terminator`, `separator` and `coercions`.
     - parameters:
       - path: The path at which the grammar file is located.
     - returns: An array of `BNFCRules` constructed from the given file. This may not match the input file exactly since some rules may get changed, split or added to have a better conformance with Swift.
     - throws: Throws an error if the file does not exists or cannot be parsed.
     */
    static func rules(from path: URL) throws -> [BNFCRule] {
        let content = try String(contentsOf: path, encoding: .utf8)
        var rules = try content.components(separatedBy: "\n").filter {!$0.isEmpty}.map { try BNFCRule.rules(fromLine: $0) }.reduce([], +)
        if BNFCRule.identUsed(in: rules) {
            rules.append(identToken())
        }
        return rules
    }
    
    /** Returns an array of `BNFCRules` generated from a single line of the original grammar file. May return `0` to `n` rules since some rules are ignored and others are split.
     - parameters:
       - line: The line of the grammar file.
     - returns: An array of `BNFCRules` generated from the input line.
     - throws: Throws an error if the line could not be parsed.
     */
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
    
    /**
     Returns an array of `BNFCRules` generated from a single line of the original grammar file which must begin with the `rules` keyword. For every rule in the rules-list, an instance of `BNFCRule` is created where each rule's label matches the label that gets generated for the C abstract syntax.
     - parameters:
       - string: The single line of the original grammar. Must start with `rules` keyword.
     - returns: An array of `BNFCRules` generated from the input line.
     - throws: Throws an error if the line could not be parsed.
    */
    private static func rulesFromBNFCRulesKeyword(_ string: String) throws -> [BNFCRule] {
        let string = string.trimmingCharacters(in: .whitespaces)
        guard let declLocation = string.range(of: "::=") else {
            throw BNFCRule.ParsingError.parsingFailed("invalid rule: \(string)")
        }
        guard let rulesLocation = string.range(of: "rules"), rulesLocation.upperBound < declLocation.lowerBound else {
            print("rules method called with non-`rules` rule: \(string)")
            return []
        }
        guard string.hasSuffix(";") else {
            throw BNFCRule.ParsingError.parsingFailed("rules must be terminated with `;`")
        }
        
        let type = string.substring(to: declLocation.lowerBound).substring(from: rulesLocation.upperBound).trimmingCharacters(in: .whitespaces)
        var constructionsString = string.substring(from: declLocation.upperBound)
        //trimm trailing `;`
        constructionsString = constructionsString.substring(to: constructionsString.index(before: constructionsString.endIndex))
        let constructions = constructionsString.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return try constructions.flatMap {
            guard $0.components(separatedBy: " ").count == 1 else {
                //TODO: Currently only rules with 1 production element are supported. Future versions should include support for n production elements.
                throw BNFCRule.ParsingError.parsingFailed("currently this parser is not able to parse bnfc `rules` keyword with more than one constructor per case")
            }
            // " is not allowed in label name
            let trimmedValue = $0.replacingOccurrences(of: "\"", with: "")
            //match bnfc generated rule which would be `type_value. type ::= value ;`
            let ruleString = "\(type)_\(trimmedValue). \(type) ::= \($0) ;"
            return try BNFCRule(ruleString)
        }
    }
    
    /**
     Creates a new instance of a `BNFCRule` from the given rule. Does not create an instance in case the rule is only relevant for the parser, which are rules with keyword `comment`, `terminator`, `separator` and `coercions`.
     - parameters:
       - rule: The rule to create a `BNFCRule` from.
     - throws: Throws an error if the rule could not be parsed.
    */
    init?(_ rule: String) throws {
        let tempRule = rule.trimmingCharacters(in: .whitespaces)
        guard tempRule.hasSuffix(";") else {
            throw BNFCRule.ParsingError.parsingFailed("rules must be terminated with `;`")
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
            throw BNFCRule.ParsingError.parsingFailed("invalid rule: \(rule)")
        }
        let label = BNFCRule.cleanLabel(rule.substring(to: dotLocation.lowerBound))
        let type  = BNFCRule.cleanType(rule.substring(to: declLocation.lowerBound).substring(from: dotLocation.upperBound))
        let construction = BNFCRule.cleanConstruction(rule.substring(from: declLocation.upperBound))
        self = .constructor(label: label, type: type, construction: construction)
    }
    
    /// Cleans the label string from unused keyword `internal`.
    private static func cleanLabel(_ pLabel: String) -> String {
        var label = pLabel.trimmingCharacters(in: .whitespaces)
        //remove leading `internal`
        if let internalRange = label.range(of: "internal"), internalRange.lowerBound == label.startIndex {
            label = label.substring(from: internalRange.upperBound).trimmingCharacters(in: .whitespaces)
        }
        return label
    }
    
    /// Cleans the type string from only for parser relevant precendence numbers.
    private static func cleanType(_ pType: String) -> String {
        var type = pType.trimmingCharacters(in: .whitespaces)
        //remove trailing decimals since they are used for precedence and don't affect the type
        while String(type.characters.last!).rangeOfCharacter(from: .decimalDigits) != nil {
            type = type.substring(to: type.index(before: type.endIndex))
        }
        return type
    }
    
    /// Filters terminals from the construction string and returns an array of all contained non-terminals in original order.
    private static func cleanConstruction(_ pConstruction: String) -> [String] {
        //filter out constants
        let construction = pConstruction.components(separatedBy: "\"").enumerated().flatMap { $0.0 % 2 == 0 ? $0.element : nil }.joined(separator: " ")
        return construction.components(separatedBy: " ").filter { !$0.isEmpty }.map { cleanType($0) }
    }
    
    //MARK:- custom handling for `Ident`
    //BNFC has the built-in type `Ident` which is effectively a String so we treat it as if it is a token declaration
    
    private static var Ident = "Ident"
    
    /**
     A helper method to check if the `Ident` key of BNFC is used in any of the given rules.
     - parameters:
       - rules: The rules to check for.
     - returns: Returns `true` in case the `Ident` key is used, otherwise `false`.
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
