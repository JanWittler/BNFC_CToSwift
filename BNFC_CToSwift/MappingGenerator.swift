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
    
    enum GeneratorError: Error {
        case parsingFailed(String)
    }
    
    init?(moduleName: String) {
        guard !moduleName.isEmpty else {
            print("module name must not be empty")
            return nil
        }
        self.moduleName = moduleName
    }
    
    func generateSwift(from rules: [BNFCRule]) throws -> String {
        var groupedRules = [String : [BNFCRule]]()
        for rule in rules {
            var group = groupedRules[rule.type] ?? []
            group.append(rule)
            groupedRules[rule.type] = group
        }
        
        //check for each type if the list version of it (`[type]`) is used in any rule, this requires an additional generated method
        let listTypeIsUsed = groupedRules.keys.reduce([String : Bool]()) { (dict, type) in
            let listUsed = rules.reduce(false, { $0 || $1.construction.contains("[\(type)]")})
            var newDict = dict
            newDict[type] = listUsed
            return newDict
        }
        
        var mappings = try groupedRules.map { (type, rules) -> String in
            let singleMapping = try generateMapping(for: rules, ofType: type)
            if listTypeIsUsed[type] ?? false {
                return singleMapping + (singleMapping.isEmpty ? "" : "\n\n") + generateListMapping(for: type)
            }
            return singleMapping
            }
        mappings.append(generateTokenMapping(for: rules))
        mappings.append(defaultTypeMapping())
        mappings.insert("import \(moduleName)", at: 0)
        mappings.insert("struct \(moduleName)ToSwiftBridge {", at: 1)
        mappings.append("}")
        return mappings.joined(separator: "\n\n")
    }
    
    private func generateMapping(for rules: [BNFCRule], ofType type: String) throws -> String {
        guard rules.filter({ $0.type != type }).isEmpty else {
            throw MappingGenerator.GeneratorError.parsingFailed("rules wrong grouped\nrules: \(rules)")
        }
        guard rules.reduce(true, { $0 && $1.ruleType == .constructor }) else {
            return ""
        }
        
        let returns = try rules.enumerated().map { ($0, try generateReturnStatement(for: $1)) }
        let switchBody = returns.map {
            "case \($0):" + "\n" +
            "return \($1)"
        }.joined(separator: "\n") + ("\n" +
        "default:" + "\n" +
        "print(\"Error: bad `kind` field when printing `\(type)`!\")\nexit(1)")
        
        //<x>.Type is a reserved keyword in swift and thus must be escaped
        let paramType = type == "Type" ? "`\(type)`" : type
        return "func visit\(type)(_ pValue: \(moduleName).\(paramType)) -> \(type) {" + "\n" +
        "let value = pValue.pointee" + "\n" + "switch value.kind {" + "\n" +
        switchBody + "\n" +
        "}" + "\n}"
    }
    
    private func generateReturnStatement(for rule: BNFCRule) throws -> String {
        let enumCase = AbstractSyntaxGenerator.enumCaseFromLabel(rule.label)
        let accessorPrefix = "value.u.\(rule.label.lowercased())_."
        
        let arguments = rule.construction.enumerated().map { (index, type) -> String in
            let cleanedType = typeFromListType(type)
            return "visit" + cleanedType + "(" + accessorPrefix + cAccessorFromConstruction(rule.construction, at: index) + ")"
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
    
    private func generateTokenMapping(for rules: [BNFCRule]) -> String {
        let mappings = rules.filter { $0.ruleType == .token }.map { generateTokenMapping(for: $0) }.joined(separator: "\n\n")
        return "//MARK:- tokens" + "\n\n" + mappings
    }
    
    private func generateTokenMapping(for rule: BNFCRule) -> String {
        let type = rule.type
        return "func visit\(type)(_ pValue: \(moduleName).\(type)) -> \(type) {" + "\n" +
        "return \(type)(value: String(cString: pValue))" + "\n" +
        "}"
    }
    
    private func generateListMapping(for type: String) -> String {
        return "func visitList\(type)(_ pValue: \(moduleName).List\(type)?) -> [\(type)] {" + "\n" +
        "guard let value = pValue?.pointee else {" + "\n" +
        "return []" + "\n" +
        "}" + "\n" +
        "if value.\(type.lowercased())_ == nil {" + "\n" +
        "return []" + "\n" +
        "}" + "\n" +
        "return [visit\(type)(value.\(type.lowercased())_)] + visitList\(type)(value.list\(type.lowercased())_)" + "\n" +
        "}"
    }
    
    private func defaultTypeMapping() -> String {
        return "//MARK:- default types" + "\n\n" +
        "func visitInteger(_ pInteger: \(moduleName).Integer) -> Swift.Int {" + "\n" +
        "return Swift.Int(pInteger)" + "\n" +
        "}" + "\n\n" +
        "func visitDouble(_ pDouble: \(moduleName).Double) -> Swift.Double {" + "\n" +
        "return pDouble" + "\n" +
        "}" + "\n\n" +
        "func visitChar(_ pChar: \(moduleName).Char) -> Swift.Character {" + "\n" +
        "return Swift.Character(Swift.UnicodeScalar(Swift.Int(pChar))!)" + "\n" +
        "}" + "\n\n" +
        "func visitString(_ pString: \(moduleName).String) -> Swift.String {" + "\n" +
        "return String(cString: pString)" + "\n" +
        "}" + "\n\n" +
        "func visitIdent(_ pIdent: \(moduleName).Ident) {" + "\n" +
        "//TODO: ident handling missing" + "\n" +
        //TODO: ident handling missing
        "}"
    }
    
    private func typeFromListType(_ type: String) -> String {
        guard type.hasPrefix("[") && type.hasSuffix("]") else {
            return type
        }
        //trimm leading `[` and trailing `]`
        return "List" + type.substring(to: type.index(before: type.endIndex)).substring(from: type.index(after: type.startIndex))
    }
}
