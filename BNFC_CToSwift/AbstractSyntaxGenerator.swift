//
//  AbstractSyntaxGenerator.swift
//  BNFC_cToSwift
//
//  Created by Jan Wittler on 04.06.17.
//  Copyright © 2017 Jan Wittler. All rights reserved.
//

import Foundation

/**
 A structure that generates Swift abstract syntax from an array of `BNFCRules`.
 */
struct AbstractSyntaxGenerator {
    /**
     Generates Swift abstract syntax from the given array of `BNFCRules`. Additionally generates helpers for abstract syntax printing and token comparison. Additional enum cases that can not be derived from the `BNFCRules` can be specified using the `additionalCases` dictionary.
     - parameters:
       - rules: The array of rules to create the abstract syntax from.
       - additionalCases: Additional enum cases to add. The key must match the type name. All values are added as a `case` statement without validation.
     - returns: Returns the source code for the abstract syntax Swift file.
    */
    static func generateSwift(from rules: [BNFCRule], additionalCases: [String : [String]] = [:]) -> String {
        var tokens = Set<String>()
        var constructors = [String : [(String, [String])]]()
        var output = [String]()
        
        //group rules by tokens and constructors
        rules.forEach {
            switch $0 {
            case let .constructor(label: label, type: type, construction: construction):
                var rules = constructors[type] ?? []
                rules.append((label, construction))
                constructors[type] = rules
            case let .token(type: type):
                tokens.insert(type)
            case .entrypoint(types: _):
                break
            }
        }
        
        //generate one enum per type
        let typesAndEnums = constructors.map { (type, rules) -> (String, String) in
            var cases: [String] = rules.map {
                var rCase = "case \(enumCaseFromLabel($0, forType: type))"
                //constructions are mapped to associated enum values
                if !$1.isEmpty {
                    rCase += "(" + $1.map { adjustType($0) }.joined(separator: ", ") + ")"
                }
                return rCase
            }
            
            //add all additional cases for this type
            if let extraCases = additionalCases[type], !extraCases.isEmpty {
                cases.append("//additional cases")
                extraCases.forEach {
                    let extraCase = $0.hasPrefix("case") ? $0 : "case " + $0
                    if !cases.contains(extraCase) {
                        cases.append(extraCase)
                    }
                }
            }
            //TODO: not every enum requires the `indirect` flag
            // rather it is only required for those which can create a cycle (possibly with itself or other enums)
            let enumString = "public indirect enum \(type) {" + "\n" +
                cases.joined(separator: "\n") + "\n" +
            "}"
            return (type, enumString)
        }
        
        output += typesAndEnums.sorted { $0.0 < $0.1 }.map { $1 }
        
        //tokens are represented as structs holding their values in the `value` field
        if !tokens.isEmpty {
            output.append("//MARK:- Tokens")
        }
        output += tokens.sorted().map {
            "public struct \($0) {" + "\n" +
                "public let value: String" + "\n" +
                "\n" +
                "public init(_ value: String) {" + "\n" +
                "self.value = value" + "\n"
                + "}" + "\n" +
            "}"
        }
        
        output += generateConvenienceHelpers(for: rules)
        return output.joined(separator: "\n\n")
    }
    
    /**
     Generates the helper methods for abstract syntax printing and token comparison.
     - parameters:
       - rules: The array of `BNFCRules`.
     - returns: Returns an array of Swift source code strings which together form the helper methods.
    */
    private static func generateConvenienceHelpers(for rules: [BNFCRule]) -> [String] {
        var tokens = Set<String>()
        var types = Set<String>()
        //get used types and tokens
        rules.forEach {
            switch $0 {
            case let .constructor(label: _, type: type, construction: _):
                types.insert(type)
            case let .token(type: type):
                tokens.insert(type)
                types.insert(type)
            case .entrypoint(types: _):
                break
            }
        }
        
        var output = [String]()
        if !types.isEmpty {
            //declaration of protocol to print abstract syntax
            let customPrintingProtocol =
                "public protocol CustomAbstractSyntaxPrinting {" + "\n" +
                "func show() -> String" + "\n" +
                "}"
            //default implementation of abstract syntax printing
            let customPrintingImplementation =
                "public extension CustomAbstractSyntaxPrinting {" + "\n" +
                "public func show() -> String {" + "\n" +
                "let description = String(reflecting: self)" + "\n" +
                "let moduleName = description.components(separatedBy: \".\").first!" + "\n" +
                "return description.replacingOccurrences(of: \"\\(moduleName).\", with: \"\")" + "\n" +
                "}" + "\n" +
                "}"
            
            output.append("//MARK:- Custom printing")
            output.append(customPrintingProtocol)
            output.append(customPrintingImplementation)
        }
        
        // conforming to protocol gives default implemention of `show()`
        output += types.sorted().map { "extension \($0): CustomAbstractSyntaxPrinting {" + "\n" + "}" }
        
        if !tokens.isEmpty {
            output.append("//MARK:- Token helpers")
        }
        
        //tokens have additional helper methods
        output += tokens.sorted().map { tokenHelpers(for: $0) }.reduce([], +)
        return output
    }
    
    /// Generates token conformance to protocols `CustomStringConvertible`, `Equatable` and `Hashable`.
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
    
    /// Mapping of BNFC types to Swift types.
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
    
    /**
     Returns the name of the enum case for the given label. If the label has its own type as a prefix, the type is trimmed from the case value to follow Swift naming conventions.
     - parameters:
       - label: The label to generate the enum case for.
       - type: The type with which the label is associated.
     - returns: Returns the enum case which is used in the abstract syntax for this label and its type. Values that require escaping are returned escaped.
    */
    static func enumCaseFromLabel(_ label: String, forType type: String) -> String {
        var enumCase = label
        //check if the label has the type as a prefix but contains more than that to not return empty string
        if let prefix = label.range(of: type, options: .caseInsensitive, range: nil, locale: nil), prefix.lowerBound == label.startIndex, prefix.upperBound != label.endIndex {
            enumCase = label.substring(from: prefix.upperBound)
        }
        //trimm leading '_'
        if enumCase.hasPrefix("_") && enumCase != "_" {
            enumCase = enumCase.substring(from: enumCase.index(after: enumCase.startIndex))
        }
        
        enumCase = enumCase.firstCharLowercased()
        //list of values that must be escaped in a case statement
        let escapingRequiredCases = ["case", "init", "return", "default", "true", "false"]
        if escapingRequiredCases.contains(enumCase) {
            return "`\(enumCase)`"
        }
        return enumCase
    }
}

private extension String {
    /// A helper method to lowercase only the first character of the string without changing the rest.
    func firstCharLowercased() -> String {
        guard let firstChar = characters.first else {
            return self
        }
        let otherChars = characters.dropFirst()
        return String(firstChar).lowercased() + String(otherChars)
    }
}
