import XCTest
@testable import OpenWebUINative

final class ToolArgumentTemplateServiceTests: XCTestCase {
    func testFormEditingUpdatesFieldValueInJSONBody() throws {
        let service = ToolArgumentTemplateService()
        let field = JSONSchemaFormField(
            name: "enabled",
            title: "Enabled",
            description: nil,
            type: .boolean,
            isRequired: false,
            defaultValue: .bool(false),
            enumValues: [],
            minimum: nil,
            maximum: nil,
            minLength: nil,
            maxLength: nil
        )

        let updated = try service.jsonBody(
            """
            {
              "mode" : "fast",
              "enabled" : false
            }
            """,
            settingField: field,
            to: .bool(true)
        )

        XCTAssertEqual(
            updated,
            """
            {
              "enabled" : true,
              "mode" : "fast"
            }
            """
        )
    }

    func testFormEditingReadsDefaultsAndTypeFallbacksForMissingFields() {
        let service = ToolArgumentTemplateService()

        XCTAssertEqual(
            service.fieldValue(
                for: JSONSchemaFormField(
                    name: "mode",
                    title: "Mode",
                    description: nil,
                    type: .string,
                    isRequired: false,
                    defaultValue: .string("fast"),
                    enumValues: [.string("fast"), .string("deep")],
                    minimum: nil,
                    maximum: nil,
                    minLength: nil,
                    maxLength: nil
                ),
                in: "{}"
            ),
            .string("fast")
        )

        XCTAssertEqual(
            service.fieldValue(
                for: JSONSchemaFormField(
                    name: "limit",
                    title: "Limit",
                    description: nil,
                    type: .integer,
                    isRequired: false,
                    defaultValue: nil,
                    enumValues: [],
                    minimum: nil,
                    maximum: nil,
                    minLength: nil,
                    maxLength: nil
                ),
                in: "{}"
            ),
            .number(0)
        )
    }

    func testFormEditingRejectsInvalidOrNonObjectJSONBodies() {
        let service = ToolArgumentTemplateService()
        let field = JSONSchemaFormField(
            name: "enabled",
            title: "Enabled",
            description: nil,
            type: .boolean,
            isRequired: false,
            defaultValue: nil,
            enumValues: [],
            minimum: nil,
            maximum: nil,
            minLength: nil,
            maxLength: nil
        )

        XCTAssertThrowsError(try service.jsonBody("{", settingField: field, to: .bool(true))) { error in
            XCTAssertEqual(error as? JSONSchemaFormEditingError, .invalidJSON)
        }
        XCTAssertThrowsError(try service.jsonBody("[]", settingField: field, to: .bool(true))) { error in
            XCTAssertEqual(error as? JSONSchemaFormEditingError, .nonObjectRoot)
        }
    }

    func testFormFieldsBuildsMetadataFromObjectProperties() {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "required": .array([.string("query"), .string("mode")]),
            "properties": .object([
                "includeArchived": .object([
                    "type": .string("boolean"),
                    "title": .string("Include archived"),
                    "description": .string("Search archived documents too."),
                    "default": .bool(false)
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "minimum": .number(1),
                    "maximum": .number(25)
                ]),
                "mode": .object([
                    "type": .string("string"),
                    "enum": .array([.string("fast"), .string("deep")]),
                    "default": .string("fast")
                ]),
                "query": .object([
                    "type": .string("string"),
                    "title": .string("Search query"),
                    "description": .string("Text to look up."),
                    "minLength": .number(3)
                ])
            ])
        ])
        let service = ToolArgumentTemplateService()

        let fields = service.formFields(forSchema: schema)

        XCTAssertEqual(fields.map(\.name), ["includeArchived", "limit", "mode", "query"])
        XCTAssertEqual(fields[0].title, "Include archived")
        XCTAssertEqual(fields[0].description, "Search archived documents too.")
        XCTAssertEqual(fields[0].type, .boolean)
        XCTAssertFalse(fields[0].isRequired)
        XCTAssertEqual(fields[0].defaultValue, .bool(false))
        XCTAssertEqual(fields[1].type, .integer)
        XCTAssertEqual(fields[1].minimum, 1)
        XCTAssertEqual(fields[1].maximum, 25)
        XCTAssertEqual(fields[2].enumValues, [.string("fast"), .string("deep")])
        XCTAssertTrue(fields[2].isRequired)
        XCTAssertEqual(fields[3].title, "Search query")
        XCTAssertEqual(fields[3].minLength, 3)
        XCTAssertTrue(fields[3].isRequired)
    }

    func testFormFieldsReturnsEmptyForNonObjectSchemas() {
        let service = ToolArgumentTemplateService()

        XCTAssertEqual(service.formFields(forSchema: .object(["type": .string("string")])), [])
        XCTAssertEqual(service.formFields(forSchema: .object(["type": .string("object")])), [])
    }

    func testFormFieldsMapsUnsupportedTypesToUnknown() {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "custom": .object(["type": .string("date-time")])
            ])
        ])
        let service = ToolArgumentTemplateService()

        let fields = service.formFields(forSchema: schema)

        XCTAssertEqual(fields.map(\.type), [.unknown])
    }

    func testFormFieldsAndTemplateUseFirstNonNullTypeFromUnionSchemas() throws {
        let schema: JSONValue = .object([
            "type": .array([.string("object"), .string("null")]),
            "properties": .object([
                "limit": .object([
                    "type": .array([.string("integer"), .string("null")]),
                    "minimum": .number(1)
                ]),
                "query": .object([
                    "type": .array([.string("string"), .string("null")]),
                    "minLength": .number(3)
                ])
            ])
        ])
        let service = ToolArgumentTemplateService()

        let fields = service.formFields(forSchema: schema)
        let template = try service.jsonTemplate(forSchema: schema)

        XCTAssertEqual(fields.map(\.name), ["limit", "query"])
        XCTAssertEqual(fields.map(\.type), [.integer, .string])
        XCTAssertEqual(
            template,
            """
            {
              "limit" : 0,
              "query" : ""
            }
            """
        )
    }

    func testTemplateBuildsEditableJSONFromObjectProperties() throws {
        let tool = AppToolServerTool(
            name: "search_docs",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object(["type": .string("string")]),
                    "limit": .object(["type": .string("integer")]),
                    "includeArchived": .object(["type": .string("boolean")]),
                    "tags": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")])
                    ]),
                    "filters": .object(["type": .string("object")])
                ])
            ])
        )
        let service = ToolArgumentTemplateService()

        let template = try service.argumentsTemplate(for: tool)

        XCTAssertEqual(
            template,
            """
            {
              "filters" : {

              },
              "includeArchived" : false,
              "limit" : 0,
              "query" : "",
              "tags" : [

              ]
            }
            """
        )
    }

    func testTemplateUsesSchemaDefaultValuesWhenPresent() throws {
        let tool = AppToolServerTool(
            name: "search_docs",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "default": .string("release notes")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "default": .number(5)
                    ])
                ])
            ])
        )
        let service = ToolArgumentTemplateService()

        let template = try service.argumentsTemplate(for: tool)

        XCTAssertEqual(
            template,
            """
            {
              "limit" : 5,
              "query" : "release notes"
            }
            """
        )
    }

    func testTemplateFallsBackToEmptyObjectForUnknownSchema() throws {
        let tool = AppToolServerTool(name: "ping")
        let service = ToolArgumentTemplateService()

        let template = try service.argumentsTemplate(for: tool)

        XCTAssertEqual(
            template,
            """
            {

            }
            """
        )
    }

    func testValidateRejectsMissingRequiredArgument() {
        let tool = AppToolServerTool(
            name: "search_docs",
            inputSchema: .object([
                "type": .string("object"),
                "required": .array([.string("query")]),
                "properties": .object([
                    "query": .object(["type": .string("string")])
                ])
            ])
        )
        let service = ToolArgumentTemplateService()

        let message = service.validationError(
            for: .object([:]),
            tool: tool
        )

        XCTAssertEqual(message, "Missing required tool argument: query.")
    }

    func testValidateRejectsBasicTypeMismatch() {
        let tool = AppToolServerTool(
            name: "search_docs",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object(["type": .string("string")]),
                    "limit": .object(["type": .string("integer")]),
                    "includeArchived": .object(["type": .string("boolean")]),
                    "tags": .object(["type": .string("array")])
                ])
            ])
        )
        let service = ToolArgumentTemplateService()

        let message = service.validationError(
            for: .object([
                "query": .string("SwiftUI"),
                "limit": .string("ten"),
                "includeArchived": .bool(false),
                "tags": .array([])
            ]),
            tool: tool
        )

        XCTAssertEqual(message, "Tool argument 'limit' must be a number.")
    }

    func testValidateRejectsEnumStringLengthAndNumericBounds() {
        let tool = AppToolServerTool(
            name: "search_docs",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "minLength": .number(3)
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "minimum": .number(1),
                        "maximum": .number(20)
                    ]),
                    "mode": .object([
                        "type": .string("string"),
                        "enum": .array([.string("fast"), .string("deep")])
                    ])
                ])
            ])
        )
        let service = ToolArgumentTemplateService()

        XCTAssertEqual(
            service.validationError(
                for: .object([
                    "query": .string("go"),
                    "limit": .number(10),
                    "mode": .string("fast")
                ]),
                tool: tool
            ),
            "Tool argument 'query' must be at least 3 characters."
        )
        XCTAssertEqual(
            service.validationError(
                for: .object([
                    "query": .string("SwiftUI"),
                    "limit": .number(25),
                    "mode": .string("fast")
                ]),
                tool: tool
            ),
            "Tool argument 'limit' must be at most 20."
        )
        XCTAssertEqual(
            service.validationError(
                for: .object([
                    "query": .string("SwiftUI"),
                    "limit": .number(5),
                    "mode": .string("balanced")
                ]),
                tool: tool
            ),
            "Tool argument 'mode' must be one of: fast, deep."
        )
    }

    func testValidateRejectsNestedRequiredArgumentsAndArrayItemTypes() {
        let tool = AppToolServerTool(
            name: "search_docs",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "filters": .object([
                        "type": .string("object"),
                        "required": .array([.string("owner")]),
                        "properties": .object([
                            "owner": .object(["type": .string("string")])
                        ])
                    ]),
                    "tags": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")])
                    ])
                ])
            ])
        )
        let service = ToolArgumentTemplateService()

        XCTAssertEqual(
            service.validationError(
                for: .object([
                    "filters": .object([:]),
                    "tags": .array([.string("docs")])
                ]),
                tool: tool
            ),
            "Missing required tool argument: filters.owner."
        )
        XCTAssertEqual(
            service.validationError(
                for: .object([
                    "filters": .object(["owner": .string("devrel")]),
                    "tags": .array([.string("docs"), .number(3)])
                ]),
                tool: tool
            ),
            "Tool argument 'tags[1]' must be a string."
        )
    }

    func testValidateRejectsPatternMultipleOfExclusiveBoundsAndUniqueArrayItems() {
        let tool = AppToolServerTool(
            name: "run_report",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "slug": .object([
                        "type": .string("string"),
                        "pattern": .string("^[a-z0-9-]+$")
                    ]),
                    "topK": .object([
                        "type": .string("integer"),
                        "exclusiveMinimum": .number(0),
                        "exclusiveMaximum": .number(10),
                        "multipleOf": .number(2)
                    ]),
                    "tags": .object([
                        "type": .string("array"),
                        "uniqueItems": .bool(true),
                        "items": .object(["type": .string("string")])
                    ])
                ])
            ])
        )
        let service = ToolArgumentTemplateService()

        XCTAssertEqual(
            service.validationError(
                for: .object([
                    "slug": .string("Bad Slug"),
                    "topK": .number(4),
                    "tags": .array([.string("docs"), .string("swift")])
                ]),
                tool: tool
            ),
            "Tool argument 'slug' must match pattern ^[a-z0-9-]+$."
        )
        XCTAssertEqual(
            service.validationError(
                for: .object([
                    "slug": .string("daily-report"),
                    "topK": .number(10),
                    "tags": .array([.string("docs"), .string("swift")])
                ]),
                tool: tool
            ),
            "Tool argument 'topK' must be less than 10."
        )
        XCTAssertEqual(
            service.validationError(
                for: .object([
                    "slug": .string("daily-report"),
                    "topK": .number(3),
                    "tags": .array([.string("docs"), .string("swift")])
                ]),
                tool: tool
            ),
            "Tool argument 'topK' must be a multiple of 2."
        )
        XCTAssertEqual(
            service.validationError(
                for: .object([
                    "slug": .string("daily-report"),
                    "topK": .number(4),
                    "tags": .array([.string("docs"), .string("docs")])
                ]),
                tool: tool
            ),
            "Tool argument 'tags' must include unique items."
        )
    }

    func testValidateRejectsUnexpectedObjectPropertiesWhenAdditionalPropertiesIsFalse() {
        let tool = AppToolServerTool(
            name: "search_docs",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "query": .object(["type": .string("string")]),
                    "filters": .object([
                        "type": .string("object"),
                        "additionalProperties": .bool(false),
                        "properties": .object([
                            "owner": .object(["type": .string("string")])
                        ])
                    ])
                ])
            ])
        )
        let service = ToolArgumentTemplateService()

        XCTAssertEqual(
            service.validationError(
                for: .object([
                    "query": .string("SwiftUI"),
                    "extra": .string("unexpected")
                ]),
                tool: tool
            ),
            "Tool argument 'extra' is not allowed."
        )
        XCTAssertEqual(
            service.validationError(
                for: .object([
                    "query": .string("SwiftUI"),
                    "filters": .object([
                        "owner": .string("devrel"),
                        "status": .string("draft")
                    ])
                ]),
                tool: tool
            ),
            "Tool argument 'filters.status' is not allowed."
        )
    }

    func testValidateAcceptsNullableUnionTypesAndStillEnforcesNonNullConstraints() {
        let tool = AppToolServerTool(
            name: "search_docs",
            inputSchema: .object([
                "type": .array([.string("object"), .string("null")]),
                "properties": .object([
                    "filters": .object([
                        "type": .array([.string("object"), .string("null")]),
                        "additionalProperties": .bool(false),
                        "properties": .object([
                            "owner": .object(["type": .string("string")])
                        ])
                    ]),
                    "query": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "minLength": .number(3)
                    ])
                ])
            ])
        )
        let service = ToolArgumentTemplateService()

        XCTAssertNil(
            service.validationError(
                for: .object([
                    "filters": .null,
                    "query": .null
                ]),
                tool: tool
            )
        )
        XCTAssertEqual(
            service.validationError(
                for: .object([
                    "filters": .object(["owner": .string("devrel")]),
                    "query": .number(42)
                ]),
                tool: tool
            ),
            "Tool argument 'query' must be a string or null."
        )
        XCTAssertEqual(
            service.validationError(
                for: .object([
                    "filters": .object(["owner": .string("devrel")]),
                    "query": .string("go")
                ]),
                tool: tool
            ),
            "Tool argument 'query' must be at least 3 characters."
        )
        XCTAssertEqual(
            service.validationError(
                for: .object([
                    "filters": .object([
                        "owner": .string("devrel"),
                        "status": .string("draft")
                    ]),
                    "query": .string("SwiftUI")
                ]),
                tool: tool
            ),
            "Tool argument 'filters.status' is not allowed."
        )
    }

    func testValidateArrayItemsWithNullableUnionTypes() {
        let tool = AppToolServerTool(
            name: "tag_docs",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "tags": .object([
                        "type": .string("array"),
                        "items": .object([
                            "type": .array([.string("string"), .string("null")])
                        ])
                    ])
                ])
            ])
        )
        let service = ToolArgumentTemplateService()

        XCTAssertNil(
            service.validationError(
                for: .object([
                    "tags": .array([.string("docs"), .null])
                ]),
                tool: tool
            )
        )
        XCTAssertEqual(
            service.validationError(
                for: .object([
                    "tags": .array([.string("docs"), .number(3)])
                ]),
                tool: tool
            ),
            "Tool argument 'tags[1]' must be a string or null."
        )
    }

    func testValidateRejectsValuesThatDoNotMatchConstSchemas() {
        let tool = AppToolServerTool(
            name: "run_mode",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "kind": .object([
                        "type": .string("string"),
                        "const": .string("search")
                    ])
                ])
            ])
        )
        let service = ToolArgumentTemplateService()

        XCTAssertNil(
            service.validationError(
                for: .object(["kind": .string("search")]),
                tool: tool
            )
        )
        XCTAssertEqual(
            service.validationError(
                for: .object(["kind": .string("summarize")]),
                tool: tool
            ),
            "Tool argument 'kind' must be search."
        )
    }

    func testValidateAcceptsValuesMatchingAnyOfSchemas() {
        let tool = AppToolServerTool(
            name: "lookup",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "target": .object([
                        "anyOf": .array([
                            .object([
                                "type": .string("string"),
                                "minLength": .number(3)
                            ]),
                            .object([
                                "type": .string("integer"),
                                "minimum": .number(1)
                            ])
                        ])
                    ])
                ])
            ])
        )
        let service = ToolArgumentTemplateService()

        XCTAssertNil(
            service.validationError(
                for: .object(["target": .string("docs")]),
                tool: tool
            )
        )
        XCTAssertNil(
            service.validationError(
                for: .object(["target": .number(3)]),
                tool: tool
            )
        )
        XCTAssertEqual(
            service.validationError(
                for: .object(["target": .bool(false)]),
                tool: tool
            ),
            "Tool argument 'target' must match one of the allowed schemas."
        )
        XCTAssertEqual(
            service.validationError(
                for: .object(["target": .string("go")]),
                tool: tool
            ),
            "Tool argument 'target' must match one of the allowed schemas."
        )
    }

    func testValidateRequiresValuesToMatchAllOfSchemas() {
        let tool = AppToolServerTool(
            name: "search",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "allOf": .array([
                            .object([
                                "type": .string("string"),
                                "minLength": .number(3)
                            ]),
                            .object([
                                "type": .string("string"),
                                "pattern": .string("^[a-z]+$")
                            ])
                        ])
                    ])
                ])
            ])
        )
        let service = ToolArgumentTemplateService()

        XCTAssertNil(
            service.validationError(
                for: .object(["query": .string("docs")]),
                tool: tool
            )
        )
        XCTAssertEqual(
            service.validationError(
                for: .object(["query": .string("go")]),
                tool: tool
            ),
            "Tool argument 'query' must match all required schemas."
        )
        XCTAssertEqual(
            service.validationError(
                for: .object(["query": .string("Docs")]),
                tool: tool
            ),
            "Tool argument 'query' must match all required schemas."
        )
    }

    func testValidateRequiresValuesToMatchExactlyOneOneOfSchema() {
        let tool = AppToolServerTool(
            name: "lookup",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "target": .object([
                        "oneOf": .array([
                            .object([
                                "type": .string("string"),
                                "pattern": .string("^[a-z]+$")
                            ]),
                            .object([
                                "type": .string("string"),
                                "minLength": .number(3)
                            ])
                        ])
                    ])
                ])
            ])
        )
        let service = ToolArgumentTemplateService()

        XCTAssertNil(
            service.validationError(
                for: .object(["target": .string("go")]),
                tool: tool
            )
        )
        XCTAssertEqual(
            service.validationError(
                for: .object(["target": .number(3)]),
                tool: tool
            ),
            "Tool argument 'target' must match exactly one allowed schema."
        )
        XCTAssertEqual(
            service.validationError(
                for: .object(["target": .string("docs")]),
                tool: tool
            ),
            "Tool argument 'target' must match exactly one allowed schema."
        )
    }

    func testValidateAcceptsMatchingObjectArguments() {
        let tool = AppToolServerTool(
            name: "search_docs",
            inputSchema: .object([
                "type": .string("object"),
                "required": .array([.string("query")]),
                "properties": .object([
                    "query": .object(["type": .string("string")]),
                    "limit": .object(["type": .string("integer")])
                ])
            ])
        )
        let service = ToolArgumentTemplateService()

        let message = service.validationError(
            for: .object([
                "query": .string("SwiftUI"),
                "limit": .number(10)
            ]),
            tool: tool
        )

        XCTAssertNil(message)
    }
}
