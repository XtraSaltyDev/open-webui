import SwiftUI

struct ValvesSchemaFieldEditor: View {
    let fields: [JSONSchemaFormField]
    @Binding var jsonBody: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(fields) { field in
                ValvesSchemaFieldRow(field: field, jsonBody: $jsonBody)
                if field.id != fields.last?.id {
                    Divider()
                }
            }
        }
        .padding(10)
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(.quaternary)
        }
    }
}

private struct ValvesSchemaFieldRow: View {
    let field: JSONSchemaFormField
    @Binding var jsonBody: String
    private let templateService = ToolArgumentTemplateService()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: field.type.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(field.title)
                        .font(.caption.weight(.semibold))
                    Text(field.name)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    if field.isRequired {
                        Text("Required")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }

                if let description = field.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    FieldAttribute(label: "Type", value: field.type.label)
                    if let defaultValue = field.defaultValue {
                        FieldAttribute(label: "Default", value: defaultValue.fieldDisplayValue)
                    }
                    if !field.enumValues.isEmpty {
                        FieldAttribute(
                            label: "Options",
                            value: field.enumValues.map(\.fieldDisplayValue).joined(separator: ", ")
                        )
                    }
                    if let range = field.rangeLabel {
                        FieldAttribute(label: "Range", value: range)
                    }
                    if let length = field.lengthLabel {
                        FieldAttribute(label: "Length", value: length)
                    }
                }
            }

            Spacer(minLength: 0)

            fieldControl
        }
    }

    @ViewBuilder
    private var fieldControl: some View {
        if !field.enumValues.isEmpty {
            Menu {
                ForEach(Array(field.enumValues.enumerated()), id: \.offset) { _, value in
                    Button(value.fieldDisplayValue) {
                        setFieldValue(value)
                    }
                }
            } label: {
                Text(currentValue.fieldDisplayValue)
                    .frame(minWidth: 96, alignment: .trailing)
            }
            .menuStyle(.borderlessButton)
        } else {
            switch field.type {
            case .boolean:
                Toggle("", isOn: Binding(
                    get: { currentValue.fieldBoolValue },
                    set: { setFieldValue(.bool($0)) }
                ))
                .labelsHidden()
            case .string:
                TextField("", text: Binding(
                    get: { currentValue.fieldStringValue },
                    set: { setFieldValue(.string($0)) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
            case .integer:
                TextField("", text: Binding(
                    get: { currentValue.fieldNumberText },
                    set: { text in
                        if let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            setFieldValue(.number(Double(value)))
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 96)
            case .number:
                TextField("", text: Binding(
                    get: { currentValue.fieldNumberText },
                    set: { text in
                        if let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            setFieldValue(.number(value))
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 96)
            case .array, .object, .unknown:
                Text("Edit JSON")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var currentValue: JSONValue {
        templateService.fieldValue(for: field, in: jsonBody)
    }

    private func setFieldValue(_ value: JSONValue) {
        if let updated = try? templateService.jsonBody(jsonBody, settingField: field, to: value) {
            jsonBody = updated
        }
    }
}

private struct FieldAttribute: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(.tertiary)
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.caption2)
    }
}

private extension JSONSchemaFormField {
    var rangeLabel: String? {
        switch (minimum, maximum) {
        case (.some(let minimum), .some(let maximum)):
            return "\(minimum.formattedSchemaNumber)-\(maximum.formattedSchemaNumber)"
        case (.some(let minimum), nil):
            return ">= \(minimum.formattedSchemaNumber)"
        case (nil, .some(let maximum)):
            return "<= \(maximum.formattedSchemaNumber)"
        case (nil, nil):
            return nil
        }
    }

    var lengthLabel: String? {
        switch (minLength, maxLength) {
        case (.some(let minLength), .some(let maxLength)):
            return "\(minLength)-\(maxLength)"
        case (.some(let minLength), nil):
            return ">= \(minLength)"
        case (nil, .some(let maxLength)):
            return "<= \(maxLength)"
        case (nil, nil):
            return nil
        }
    }
}

private extension JSONSchemaFormField.FieldType {
    var label: String {
        switch self {
        case .string:
            return "String"
        case .number:
            return "Number"
        case .integer:
            return "Integer"
        case .boolean:
            return "Boolean"
        case .array:
            return "Array"
        case .object:
            return "Object"
        case .unknown:
            return "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .boolean:
            return "switch.2"
        case .integer, .number:
            return "number"
        case .array:
            return "list.bullet"
        case .object:
            return "curlybraces"
        case .string:
            return "textformat"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

private extension JSONValue {
    var fieldDisplayValue: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value.formattedSchemaNumber
        case .bool(let value):
            return String(value)
        case .array:
            return "array"
        case .object:
            return "object"
        case .null:
            return "null"
        }
    }

    var fieldStringValue: String {
        if case .string(let value) = self {
            return value
        }
        return fieldDisplayValue
    }

    var fieldBoolValue: Bool {
        if case .bool(let value) = self {
            return value
        }
        return false
    }

    var fieldNumberText: String {
        if case .number(let value) = self {
            return value.formattedSchemaNumber
        }
        return "0"
    }
}

private extension Double {
    var formattedSchemaNumber: String {
        if rounded() == self {
            return String(Int(self))
        }
        return String(self)
    }
}
