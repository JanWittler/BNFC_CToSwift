//
//  MappingGenerator.swift
//  BNFC_cToSwift
//
//  Created by Jan Wittler on 04.06.17.
//  Copyright © 2017 Jan Wittler. All rights reserved.
//

import Foundation

/**
 A structure that creates Swift source code to bridge output of the parser generated by BNFC in C to Swift abstract syntax generated by the `AbstractSyntaxGenerator`.
 */
struct MappingGenerator {
    /// The name of the module in the Xcode project to which the BNFC-generated files belong. This is neccessary for namespaces.
    let moduleName: String
    
    /**
     Creates a new instance of `MappingGenerator` if the given module name is valid.
     - parameters:
       - moduleName: The name of the module in the Xcode project to which the BNFC-generated files belong. This must not be empty.
    */
    init?(moduleName: String) {
        guard !moduleName.isEmpty else {
            print("module name must not be empty")
            return nil
        }
        self.moduleName = moduleName
    }
    
    /**
    Generates Swift source code that bridges the C output of the BNFC generated parser to Swift abstract syntax.
     - parameters:
       - rules: The array of rules to create the mapping for.
     - returns: Returns the source code for the mapping Swift file.
    */
    func generateSwift(from rules: [BNFCRule]) -> String {
        var tokens = Set<String>()
        var constructors = [String : [(String, [String])]]()
        
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
        
        //check for each type if the list version of it (`[type]`) is used in any rule, this requires an additional generated method
        let listTypeIsUsed = constructors.keys.reduce([String : Bool]()) { (previous, type) in
            let listUsed = rules.reduce(false, {
                let usedInCurrentRule: Bool
                let listType = "[\(type)]"
                switch $1 {
                case let .constructor(label: _, type: _, construction: construction):
                    usedInCurrentRule = construction.contains(listType)
                case .token(type: _):
                    usedInCurrentRule = false
                case let .entrypoint(types: types):
                    usedInCurrentRule = types.contains(listType)
                }
                return $0 || usedInCurrentRule
            })
            var result = previous
            result[type] = listUsed
            return result
        }
        
        var output = [String]()
        
        //generate constructor mappings
        output += constructors.map {
            var mappings = [generateMapping(forType: $0, withLabelsAndConstructions: $1)]
            if listTypeIsUsed[$0] ?? false {
                mappings.append(generateListMapping(for: $0))
            }
            return mappings
        }.reduce([], +)
        
        //generate token mappings
        if !tokens.isEmpty {
            output.append("//MARK:- Tokens")
            output += tokens.map { generateTokenMapping(forType: $0) }
        }
        
        output += defaultTypeMapping()
        
        let prefix = ["import \(moduleName)"] + generateParseFileFunctions(for: rules) + ["//MARK:- C to Swift mapping"]
        return (prefix + output).joined(separator: "\n\n")
    }
    
    /**
     Generates the mapping for the given type and its corresponding labels and constructions.
     - parameters:
       - type: The type to create the mapping for.
       - labelsAndConstructions: The array of labels and corresponding constructions that are related to the given type.
     - returns: The Swift source code to map the given type from C to Swift.
    */
    private func generateMapping(forType type: String, withLabelsAndConstructions labelsAndConstructions: [(String, [String])]) -> String {
        let switchBody = labelsAndConstructions.enumerated().map {
            // C abstract syntax differentiates between cases by using an anonymous enum value. The enum accessors are not bridged to Swift thus they must be addressed by their raw value, which starts at 0 for the first case and increases per case by 1.
            "case \($0):" + "\n" +
                "return " + generateReturnStatement(forLabel: $1.0, type: type, andConstruction: $1.1)
        }.joined(separator: "\n") + ("\n" +
        "default:" + "\n" +
        "print(\"Error: bad `kind` field when bridging `\(type)` to Swift!\")\nexit(1)")
        
        //<x>.Type is a reserved keyword in swift and thus must be escaped
        let paramType = type == "Type" ? "`\(type)`" : type
        // The method unwraps the value from the pointer and then maps based on the `kind` attribute.
        return "private func visit\(type)(_ pValue: \(moduleName).\(paramType)) -> \(type) {" + "\n" +
            "let value = pValue.pointee" + "\n" +
            "switch value.kind {" + "\n" +
            switchBody + "\n" +
            "}" + "\n}"
    }
    
    /**
     A helper method to get the statement that creates the enum instance for the given label and construction
     - parameters:
       - label: The label of the rule to map.
       - type: The type of the rule to map.
       - construction: The construction of the rule to map.
     - returns: Returns the Swift source code that initializes an enum instance for the given label and construction.
     */
    private func generateReturnStatement(forLabel label: String, type: String, andConstruction construction: [String]) -> String {
        let enumCase = AbstractSyntaxGenerator.enumCaseFromLabel(label, forType: type)
        let accessorPrefix = "value.u.\(label.lowercased())_."
        
        // create each argument to the enum initialization by calling the corresponding `visit`-function on it
        let arguments = construction.enumerated().map { (index, type) -> String in
            let cleanedType = typeFromListType(type)
            return "visit" + cleanedType + "(" + accessorPrefix + cAccessorFromConstruction(construction, at: index) + ")"
        }
        if arguments.isEmpty {
            return ".\(enumCase)"
        }
        return ".\(enumCase)(" + arguments.joined(separator: ", ") + ")"
    }
    
    /** A helper method to get the C accessor for the construction argument at the given index.
     - parameters:
       - construction: The construction of the rule.
       - index: The index in the construction array for which the C accessor should be created.
     - returns: Returns the C accessor for the construction argument at the given index.
    */
    private func cAccessorFromConstruction(_ construction: [String], at index: Int) -> String {
        let type = construction[index]
        let cleanedType = typeFromListType(type).lowercased()
        let accessor: String
        //if type appears only once, it does not get an index
        if construction.filter({ $0 == type }).count == 1 {
            accessor = cleanedType + "_"
        }
        //if type appears multiple times, it is indexed, starting at 1
        else {
            var count = 1
            for i in 0..<index {
                count += construction[i] == type ? 1 : 0
            }
            accessor = cleanedType + "_\(count)"
        }
        return accessor
    }
    
    /// Returns the token mapping for the given type.
    private func generateTokenMapping(forType type: String) -> String {
        //tokens are mapped by initializing the Swift token's struct with the token's value
        return "private func visit\(type)(_ pValue: \(moduleName).\(type)) -> \(type) {" + "\n" +
        "return \(type)(String(cString: pValue))" + "\n" +
        "}"
    }
    
    /// Returns the list mapping for the given type.
    private func generateListMapping(for type: String) -> String {
        // if the argument or its pointer value are nil, an empty array is returned, otherwise the first list entry is unwrapped and concatenated with the list's tail which is constructed recursively
        return "private func visitList\(type)(_ pValue: \(moduleName).List\(type)?) -> [\(type)] {" + "\n" +
        "guard let value = pValue?.pointee else {" + "\n" +
        "return []" + "\n" +
        "}" + "\n" +
        "if value.\(type.lowercased())_ == nil {" + "\n" +
        "return []" + "\n" +
        "}" + "\n" +
        "return [visit\(type)(value.\(type.lowercased())_)] + visitList\(type)(value.list\(type.lowercased())_)" + "\n" +
        "}"
    }
    
    /// Returns the default type mappings for `Char`, `Double`, `Integer` and `String`.
    private func defaultTypeMapping() -> [String] {
        return ["//MARK:- Default types",
        "private func visitChar(_ pChar: \(moduleName).Char) -> Swift.Character {" + "\n" +
        "return Swift.Character(Swift.UnicodeScalar(Swift.Int(pChar))!)" + "\n" +
        "}",
        "private func visitDouble(_ pDouble: \(moduleName).Double) -> Swift.Double {" + "\n" +
        "return pDouble" + "\n" +
        "}",
        "private func visitInteger(_ pInteger: \(moduleName).Integer) -> Swift.Int {" + "\n" +
        "return Swift.Int(pInteger)" + "\n" +
        "}",
        "private func visitString(_ pString: \(moduleName).String) -> Swift.String {" + "\n" +
        "return Swift.String(cString: pString)" + "\n" +
        "}"]
    }
    
    /**
     Generates the `parseFile` function for the given rules. The `parseFile` function is used to open a file, parse it using the C parser and bridge the result to Swift, returning Swift abstract syntax. The `parseFile` function is generated for all types mentioned in a `entrypoints` rule, or if not specified, the function is generated for the type of the first rule (following BNFC convention).
     - parameters:
       - rules: The rules to consider.
     - returns: Returns an array of `parseFile` functions.
    */
    private func generateParseFileFunctions(for rules: [BNFCRule]) -> [String] {
        //get all types mentioned in entrypoint rules
        var entrypoints = rules.flatMap { rule -> [String]? in
            if case let .entrypoint(types: types) = rule {
                return types
            }
            return nil
        }.reduce([], +)
        
        if entrypoints.isEmpty {
            //if `entrypoints` key not specified, BNFC uses by default the type of the first rule
            guard let entrypoint = rules.flatMap({ rule -> String? in
                if case let .constructor(label: _, type: type, construction: _) = rule {
                    return type
                }
                return nil
            }).first else {
                return []
            }
            entrypoints = [entrypoint]
        }
        
        // `parseFile` tries to open the file, parse it using the C parser and bridge it to C. Before the method returns, the file is closed.
        return entrypoints.map {
            "public func parseFile(at path: Swift.String) -> \($0)? {" + "\n" +
            "if let file = fopen(path, \"r\") {" + "\n" +
            "defer { fclose(file) }" + "\n" +
            "if let cTree = \(moduleName).p\($0)(file) {" + "\n" +
            "return visit\($0)(cTree)" + "\n" +
            "}" + "\n" +
            "}" + "\n" +
            "return nil" + "\n" +
            "}"
        }
    }
    
    /// Returns the list's object type from a list type. If the type is not a list type, it returns the type itself.
    private func typeFromListType(_ type: String) -> String {
        guard type.hasPrefix("[") && type.hasSuffix("]") else {
            return type
        }
        //trimm leading `[` and trailing `]`
        return "List" + type.substring(to: type.index(before: type.endIndex)).substring(from: type.index(after: type.startIndex))
    }
}
