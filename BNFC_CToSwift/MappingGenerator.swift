//
//  MappingGenerator.swift
//  BNFC_cToSwift
//
//  Created by Jan Wittler on 04.06.17.
//  Copyright © 2017 Jan Wittler. All rights reserved.
//

import Foundation

struct MappingGenerator {
    let moduleName: String
    
    init?(moduleName: String) {
        guard !moduleName.isEmpty else {
            print("module name must not be empty")
            return nil
        }
        self.moduleName = moduleName
    }
    
    func generateSwift(from rules: [BNFCRule]) -> String {
        var tokens = Set<String>()
        var constructors = [String : [(String, [String])]]()
        
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
        
        output += constructors.map {
            var mappings = [generateMapping(forType: $0, withLabelsAndConstructions: $1)]
            if listTypeIsUsed[$0] ?? false {
                mappings.append(generateListMapping(for: $0))
            }
            return mappings
        }.reduce([], +)
        
        if !tokens.isEmpty {
            output.append("//MARK:- tokens")
            output += tokens.map { generateTokenMapping(forType: $0) }
        }
        
        output += defaultTypeMapping()
        
        let prefix = ["import \(moduleName)"] + generateParseFileFunctions(for: rules) + ["//MARK: C to Swift mapping"]
        return (prefix + output).joined(separator: "\n\n")
    }
    
    private func generateMapping(forType type: String, withLabelsAndConstructions labelsAndConstructions: [(String, [String])]) -> String {
        let returns = labelsAndConstructions.enumerated().map { ($0, generateReturnStatement(forLabel: $1.0, andConstruction: $1.1)) }
        let switchBody = returns.map {
            "case \($0):" + "\n" +
            "return \($1)"
        }.joined(separator: "\n") + ("\n" +
        "default:" + "\n" +
        "print(\"Error: bad `kind` field when bridging `\(type)` to Swift!\")\nexit(1)")
        
        //<x>.Type is a reserved keyword in swift and thus must be escaped
        let paramType = type == "Type" ? "`\(type)`" : type
        return "private func visit\(type)(_ pValue: \(moduleName).\(paramType)) -> \(type) {" + "\n" +
            "let value = pValue.pointee" + "\n" +
            "switch value.kind {" + "\n" +
            switchBody + "\n" +
            "}" + "\n}"
    }
    
    private func generateReturnStatement(forLabel label: String, andConstruction construction: [String]) -> String {
        let enumCase = AbstractSyntaxGenerator.enumCaseFromLabel(label)
        let accessorPrefix = "value.u.\(label.lowercased())_."
        
        let arguments = construction.enumerated().map { (index, type) -> String in
            let cleanedType = typeFromListType(type)
            return "visit" + cleanedType + "(" + accessorPrefix + cAccessorFromConstruction(construction, at: index) + ")"
        }
        if arguments.isEmpty {
            return ".\(enumCase)"
        }
        return ".\(enumCase)(" + arguments.joined(separator: ", ") + ")"
    }
    
    private func cAccessorFromConstruction(_ construction: [String], at index: Int) -> String {
        let type = construction[index]
        let cleanedType = typeFromListType(type).lowercased()
        let accessor: String
        //if type appears only once it does not get an index
        if construction.filter({ $0 == type }).count == 1 {
            accessor = cleanedType + "_"
        }
        else {
            var count = 1
            for i in 0..<index {
                count += construction[i] == type ? 1 : 0
            }
            accessor = cleanedType + "_\(count)"
        }
        return accessor
    }
    
    private func generateTokenMapping(forType type: String) -> String {
        return "private func visit\(type)(_ pValue: \(moduleName).\(type)) -> \(type) {" + "\n" +
        "return \(type)(String(cString: pValue))" + "\n" +
        "}"
    }
    
    private func generateListMapping(for type: String) -> String {
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
    
    private func defaultTypeMapping() -> [String] {
        return ["//MARK:- default types",
        "private func visitInteger(_ pInteger: \(moduleName).Integer) -> Swift.Int {" + "\n" +
        "return Swift.Int(pInteger)" + "\n" +
        "}",
        "private func visitDouble(_ pDouble: \(moduleName).Double) -> Swift.Double {" + "\n" +
        "return pDouble" + "\n" +
        "}",
        "private func visitChar(_ pChar: \(moduleName).Char) -> Swift.Character {" + "\n" +
        "return Swift.Character(Swift.UnicodeScalar(Swift.Int(pChar))!)" + "\n" +
        "}",
        "private func visitString(_ pString: \(moduleName).String) -> Swift.String {" + "\n" +
        "return String(cString: pString)" + "\n" +
        "}"]
    }
    
    private func generateParseFileFunctions(for rules: [BNFCRule]) -> [String] {
        //get all types mentioned in entrypoint rules
        var entrypoints = rules.flatMap { rule -> [String]? in
            if case let .entrypoint(types: types) = rule {
                return types
            }
            return nil
        }.reduce([], +)
        
        if entrypoints.isEmpty {
            //if `entrypoints` key not specified, bnfc uses by default the type of the first rule
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
    
    private func typeFromListType(_ type: String) -> String {
        guard type.hasPrefix("[") && type.hasSuffix("]") else {
            return type
        }
        //trimm leading `[` and trailing `]`
        return "List" + type.substring(to: type.index(before: type.endIndex)).substring(from: type.index(after: type.startIndex))
    }
}
