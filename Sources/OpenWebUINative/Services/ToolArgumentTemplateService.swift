import Foundation

struct JSONSchemaFormField: Identifiable, Equatable, Sendable {
    enum FieldType: String, Equatable, Sendable {
        case string
        case number
        case integer
        case boolean
        case array
        case object
        case unknown
    }

    var id: String { name }
    let name: String
    let title: String
    let description: String?
    let type: FieldType
    let isRequired: Bool
    let defaultValue: JSONValue?
    let enumValues: [JSONValue]
    let minimum: Double?
    let maximum: Double?
    let minLength: Int?
    let maxLength: Int?
}

struct ValvesSchemaDraft: Equatable, Sendable {
    let templateJSON: String
    let fields: [JSONSchemaFormField]
}

enum JSONSchemaFormEditingError: Error, Equatable {
    case invalidJSON
    case nonObjectRoot
}

struct ToolArgumentTemplateService: Sendable {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    func argumentsTemplate(for tool: AppToolServerTool) throws -> String {
        try jsonTemplate(forSchema: tool.inputSchema)
    }

    func jsonTemplate(forSchema schema: JSONValue) throws -> String {
        let value = templateValue(from: schema)
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func formFields(forSchema schema: JSONValue) -> [JSONSchemaFormField] {
        guard let schemaObject = schema.objectValue,
              schemaTypes(from: schemaObject).contains("object"),
              let properties = schemaObject["properties"]?.objectValue else {
            return []
        }

        let requiredNames = Set(requiredPropertyNames(from: schemaObject))
        return properties.keys.sorted().compactMap { name in
            guard let propertySchema = properties[name]?.objectValue else {
                return nil
            }
            return JSONSchemaFormField(
                name: name,
                title: propertySchema["title"]?.stringValue ?? name,
                description: propertySchema["description"]?.stringValue,
                type: fieldType(from: primarySchemaType(from: propertySchema)),
                isRequired: requiredNames.contains(name),
                defaultValue: propertySchema["default"],
                enumValues: propertySchema["enum"]?.arrayValue ?? [],
                minimum: propertySchema["minimum"]?.numberValue,
                maximum: propertySchema["maximum"]?.numberValue,
                minLength: propertySchema["minLength"]?.integerValue,
                maxLength: propertySchema["maxLength"]?.integerValue
            )
        }
    }

    func fieldValue(for field: JSONSchemaFormField, in jsonBody: String) -> JSONValue {
        guard let data = jsonBody.data(using: .utf8),
              let value = try? JSONDecoder.openWebUIDecoder.decode(JSONValue.self, from: data),
              let object = value.objectValue,
              let fieldValue = object[field.name] else {
            return fallbackValue(for: field)
        }
        return fieldValue
    }

    func jsonBody(
        _ jsonBody: String,
        settingField field: JSONSchemaFormField,
        to value: JSONValue
    ) throws -> String {
        let trimmedBody = jsonBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmedBody.isEmpty ? "{}" : trimmedBody
        guard let data = body.data(using: .utf8),
              let decodedValue = try? JSONDecoder.openWebUIDecoder.decode(JSONValue.self, from: data) else {
            throw JSONSchemaFormEditingError.invalidJSON
        }
        guard var object = decodedValue.objectValue else {
            throw JSONSchemaFormEditingError.nonObjectRoot
        }

        object[field.name] = value
        return JSONValue.object(object).jsonString
    }

    func validationError(for arguments: JSONValue, tool: AppToolServerTool) -> String? {
        validationError(
            for: arguments,
            schema: tool.inputSchema,
            valueLabel: "Tool argument",
            missingLabel: "Missing required tool argument"
        )
    }

    func validationError(
        for arguments: JSONValue,
        schema: JSONValue,
        valueLabel: String,
        missingLabel: String
    ) -> String? {
        guard let schemaObject = schema.objectValue,
              schemaTypes(from: schemaObject).contains("object"),
              let argumentsObject = arguments.objectValue else {
            return nil
        }

        return validationError(
            forObject: argumentsObject,
            schemaObject: schemaObject,
            pathPrefix: "",
            valueLabel: valueLabel,
            missingLabel: missingLabel
        )
    }

    private func validationError(
        forObject argumentsObject: [String: JSONValue],
        schemaObject: [String: JSONValue],
        pathPrefix: String,
        valueLabel: String,
        missingLabel: String
    ) -> String? {
        for requiredName in requiredPropertyNames(from: schemaObject) {
            if argumentsObject[requiredName] == nil {
                return "\(missingLabel): \(pathPrefix)\(requiredName)."
            }
        }

        let properties = schemaObject["properties"]?.objectValue ?? [:]

        if schemaObject["additionalProperties"] == .bool(false) {
            let allowedNames = Set(properties.keys)
            for argumentName in argumentsObject.keys.sorted() where !allowedNames.contains(argumentName) {
                return "\(valueLabel) '\(pathPrefix)\(argumentName)' is not allowed."
            }
        }

        guard !properties.isEmpty else {
            return nil
        }

        for propertyName in properties.keys.sorted() {
            guard let value = argumentsObject[propertyName],
                  let propertySchema = properties[propertyName]?.objectValue else {
                continue
            }

            let path = "\(pathPrefix)\(propertyName)"
            if let error = validationError(
                for: value,
                schemaObject: propertySchema,
                path: path,
                valueLabel: valueLabel,
                missingLabel: missingLabel
            ) {
                return error
            }
        }

        return nil
    }

    private func validationError(
        for value: JSONValue,
        schemaObject: [String: JSONValue],
        path: String,
        valueLabel: String,
        missingLabel: String
    ) -> String? {
        if let constValue = schemaObject["const"],
           constValue != value {
            return "\(valueLabel) '\(path)' must be \(constValue.displayValue)."
        }

        if let allOfSchemas = schemaObject["allOf"]?.arrayValue,
           !allOfSchemas.isEmpty {
            for branchSchema in allOfSchemas {
                guard let branchObject = branchSchema.objectValue else {
                    continue
                }
                if validationError(
                    for: value,
                    schemaObject: branchObject,
                    path: path,
                    valueLabel: valueLabel,
                    missingLabel: missingLabel
                ) != nil {
                    return "\(valueLabel) '\(path)' must match all required schemas."
                }
            }
        }

        if let oneOfSchemas = schemaObject["oneOf"]?.arrayValue,
           !oneOfSchemas.isEmpty {
            let matchingBranchCount = matchingBranchCount(
                for: value,
                schemas: oneOfSchemas,
                path: path,
                valueLabel: valueLabel,
                missingLabel: missingLabel
            )
            if matchingBranchCount != 1 {
                return "\(valueLabel) '\(path)' must match exactly one allowed schema."
            }
        }

        if let anyOfSchemas = schemaObject["anyOf"]?.arrayValue,
           !anyOfSchemas.isEmpty {
            let matchingBranchCount = matchingBranchCount(
                for: value,
                schemas: anyOfSchemas,
                path: path,
                valueLabel: valueLabel,
                missingLabel: missingLabel
            )
            if matchingBranchCount == 0 {
                return "\(valueLabel) '\(path)' must match one of the allowed schemas."
            }
        }

        let expectedTypes = schemaTypes(from: schemaObject)
        guard !expectedTypes.isEmpty else {
            return nil
        }

        guard let expectedType = expectedTypes.first(where: value.matchesJSONSchemaType) else {
            return "\(valueLabel) '\(path)' must be \(humanReadableTypes(expectedTypes))."
        }

        if let enumValues = schemaObject["enum"]?.arrayValue,
           !enumValues.contains(value) {
            let allowedValues = enumValues.map(\.displayValue).joined(separator: ", ")
            return "\(valueLabel) '\(path)' must be one of: \(allowedValues)."
        }

        if expectedType == "null" {
            return nil
        }

        switch (expectedType, value) {
        case ("string", .string(let text)):
            if let minLength = schemaObject["minLength"]?.integerValue,
               text.count < minLength {
                return "\(valueLabel) '\(path)' must be at least \(minLength) characters."
            }
            if let maxLength = schemaObject["maxLength"]?.integerValue,
               text.count > maxLength {
                return "\(valueLabel) '\(path)' must be at most \(maxLength) characters."
            }
            if let pattern = schemaObject["pattern"]?.stringValue,
               !text.matchesJSONSchemaPattern(pattern) {
                return "\(valueLabel) '\(path)' must match pattern \(pattern)."
            }
        case ("number", .number(let number)), ("integer", .number(let number)):
            if expectedType == "integer", number.rounded() != number {
                return "\(valueLabel) '\(path)' must be an integer."
            }
            if let minimum = schemaObject["minimum"]?.numberValue,
               number < minimum {
                return "\(valueLabel) '\(path)' must be at least \(formatNumber(minimum))."
            }
            if let maximum = schemaObject["maximum"]?.numberValue,
               number > maximum {
                return "\(valueLabel) '\(path)' must be at most \(formatNumber(maximum))."
            }
            if let exclusiveMinimum = schemaObject["exclusiveMinimum"]?.numberValue,
               number <= exclusiveMinimum {
                return "\(valueLabel) '\(path)' must be greater than \(formatNumber(exclusiveMinimum))."
            }
            if schemaObject["exclusiveMinimum"] == .bool(true),
               let minimum = schemaObject["minimum"]?.numberValue,
               number <= minimum {
                return "\(valueLabel) '\(path)' must be greater than \(formatNumber(minimum))."
            }
            if let exclusiveMaximum = schemaObject["exclusiveMaximum"]?.numberValue,
               number >= exclusiveMaximum {
                return "\(valueLabel) '\(path)' must be less than \(formatNumber(exclusiveMaximum))."
            }
            if schemaObject["exclusiveMaximum"] == .bool(true),
               let maximum = schemaObject["maximum"]?.numberValue,
               number >= maximum {
                return "\(valueLabel) '\(path)' must be less than \(formatNumber(maximum))."
            }
            if let multipleOf = schemaObject["multipleOf"]?.numberValue,
               multipleOf > 0,
               !number.isMultiple(ofJSONSchemaValue: multipleOf) {
                return "\(valueLabel) '\(path)' must be a multiple of \(formatNumber(multipleOf))."
            }
        case ("array", .array(let values)):
            if let minItems = schemaObject["minItems"]?.integerValue,
               values.count < minItems {
                return "\(valueLabel) '\(path)' must include at least \(minItems) items."
            }
            if let maxItems = schemaObject["maxItems"]?.integerValue,
               values.count > maxItems {
                return "\(valueLabel) '\(path)' must include at most \(maxItems) items."
            }
            if schemaObject["uniqueItems"] == .bool(true),
               !values.hasUniqueJSONItems {
                return "\(valueLabel) '\(path)' must include unique items."
            }
            guard let itemSchema = schemaObject["items"]?.objectValue else {
                return nil
            }
            for (index, item) in values.enumerated() {
                if let error = validationError(
                    for: item,
                    schemaObject: itemSchema,
                    path: "\(path)[\(index)]",
                    valueLabel: valueLabel,
                    missingLabel: missingLabel
                ) {
                    return error
                }
            }
        case ("object", .object(let object)):
            return validationError(
                forObject: object,
                schemaObject: schemaObject,
                pathPrefix: "\(path).",
                valueLabel: valueLabel,
                missingLabel: missingLabel
            )
        default:
            break
        }

        return nil
    }

    private func matchingBranchCount(
        for value: JSONValue,
        schemas: [JSONValue],
        path: String,
        valueLabel: String,
        missingLabel: String
    ) -> Int {
        schemas.reduce(into: 0) { count, branchSchema in
            guard let branchObject = branchSchema.objectValue else {
                return
            }
            if validationError(
                for: value,
                schemaObject: branchObject,
                path: path,
                valueLabel: valueLabel,
                missingLabel: missingLabel
            ) == nil {
                count += 1
            }
        }
    }

    private func templateValue(from schema: JSONValue) -> JSONValue {
        guard let schemaObject = schema.objectValue else {
            return .object([:])
        }

        if let defaultValue = schemaObject["default"] {
            return defaultValue
        }

        guard let type = primarySchemaType(from: schemaObject) else {
            return .object([:])
        }

        switch type {
        case "object":
            guard let properties = schemaObject["properties"]?.objectValue else {
                return .object([:])
            }
            let values = properties.reduce(into: [String: JSONValue]()) { result, property in
                result[property.key] = templateValue(from: property.value)
            }
            return .object(values)
        case "array":
            return .array([])
        case "boolean":
            return .bool(false)
        case "integer", "number":
            return .number(0)
        case "string":
            return .string("")
        default:
            return .null
        }
    }

    private func fallbackValue(for field: JSONSchemaFormField) -> JSONValue {
        if let defaultValue = field.defaultValue {
            return defaultValue
        }
        if let firstEnumValue = field.enumValues.first {
            return firstEnumValue
        }
        switch field.type {
        case .string:
            return .string("")
        case .number, .integer:
            return .number(0)
        case .boolean:
            return .bool(false)
        case .array:
            return .array([])
        case .object:
            return .object([:])
        case .unknown:
            return .null
        }
    }

    private func fieldType(from value: String?) -> JSONSchemaFormField.FieldType {
        guard let value else {
            return .unknown
        }
        return JSONSchemaFormField.FieldType(rawValue: value) ?? .unknown
    }

    private func requiredPropertyNames(from schemaObject: [String: JSONValue]) -> [String] {
        guard case .array(let values) = schemaObject["required"] else {
            return []
        }
        return values.compactMap(\.stringValue)
    }

    private func schemaTypes(from schemaObject: [String: JSONValue]) -> [String] {
        guard let typeValue = schemaObject["type"] else {
            return []
        }
        if let type = typeValue.stringValue {
            return [type]
        }
        return typeValue.arrayValue?.compactMap(\.stringValue) ?? []
    }

    private func primarySchemaType(from schemaObject: [String: JSONValue]) -> String? {
        let types = schemaTypes(from: schemaObject)
        return types.first { $0 != "null" } ?? types.first
    }

    private func humanReadableType(_ type: String) -> String {
        switch type {
        case "integer", "number":
            return "a number"
        case "string":
            return "a string"
        case "boolean":
            return "a boolean"
        case "array":
            return "an array"
        case "object":
            return "an object"
        default:
            return "a \(type)"
        }
    }

    private func humanReadableTypes(_ types: [String]) -> String {
        let readableTypes = types.map { type in
            type == "null" ? "null" : humanReadableType(type)
        }

        switch readableTypes.count {
        case 0:
            return "a supported JSON value"
        case 1:
            return readableTypes[0]
        case 2:
            return "\(readableTypes[0]) or \(readableTypes[1])"
        default:
            return "\(readableTypes.dropLast().joined(separator: ", ")), or \(readableTypes.last ?? "")"
        }
    }

    private func formatNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }
}

private extension JSONValue {
    var arrayValue: [JSONValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    var numberValue: Double? {
        if case .number(let value) = self {
            return value
        }
        return nil
    }

    var integerValue: Int? {
        guard let value = numberValue, value.rounded() == value else {
            return nil
        }
        return Int(value)
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    func matchesJSONSchemaType(_ type: String) -> Bool {
        switch (type, self) {
        case ("string", .string),
             ("number", .number),
             ("integer", .number),
             ("boolean", .bool),
             ("array", .array),
             ("object", .object),
             ("null", .null):
            return true
        default:
            return false
        }
    }

    var displayValue: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return String(value)
        case .object:
            return "object"
        case .array:
            return "array"
        case .null:
            return "null"
        }
    }
}

private extension String {
    func matchesJSONSchemaPattern(_ pattern: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return true
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        return expression.firstMatch(in: self, range: range) != nil
    }
}

private extension Double {
    func isMultiple(ofJSONSchemaValue divisor: Double) -> Bool {
        let quotient = self / divisor
        return abs(quotient - quotient.rounded()) < 0.000_000_001
    }
}

private extension Array where Element == JSONValue {
    var hasUniqueJSONItems: Bool {
        for (index, value) in enumerated() {
            if self[(index + 1)...].contains(value) {
                return false
            }
        }
        return true
    }
}
