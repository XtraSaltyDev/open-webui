import Foundation
import XCTest
@testable import OpenWebUINative

final class FileExportServiceTests: XCTestCase {
    func testNativeJSONRoundTripsOriginalFileData() throws {
        let originalData = Data([0x23, 0x20, 0x42, 0x72, 0x69, 0x65, 0x66])
        let file = AppFile(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            fileName: "brief.md",
            contentType: "text/markdown",
            byteCount: originalData.count,
            textContent: "# Brief",
            originalData: originalData,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_300)
        )

        let data = try FileExportService().jsonData(for: [file])
        let files = try FileExportService().files(fromJSONData: data)

        XCTAssertEqual(files.first?.originalData, originalData)
    }

    func testOpenWebUIJSONDataBuildsFileRecordsWithContentAndMetadata() throws {
        let file = AppFile(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            fileName: "brief.md",
            contentType: "text/markdown",
            byteCount: 12,
            textContent: "# Brief",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_300)
        )

        let data = try FileExportService().openWebUIJSONData(for: [file], userID: "user-1")
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let record = try XCTUnwrap(records.first)

        XCTAssertEqual(record["id"] as? String, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(record["user_id"] as? String, "user-1")
        XCTAssertEqual(record["filename"] as? String, "brief.md")
        XCTAssertEqual(record["created_at"] as? Int, 1_700_000_000)
        XCTAssertEqual(record["updated_at"] as? Int, 1_700_000_300)
        let dataObject = try XCTUnwrap(record["data"] as? [String: Any])
        XCTAssertEqual(dataObject["content"] as? String, "# Brief")
        XCTAssertEqual(dataObject["status"] as? String, "completed")
        let metaObject = try XCTUnwrap(record["meta"] as? [String: Any])
        XCTAssertEqual(metaObject["name"] as? String, "brief.md")
        XCTAssertEqual(metaObject["content_type"] as? String, "text/markdown")
        XCTAssertEqual(metaObject["size"] as? Int, 12)
    }

    func testFilesFromJSONDataAcceptsOpenWebUIFileListResponse() throws {
        let json = """
        {
          "items": [
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "user_id": "user-1",
              "filename": "raw-upload-name.md",
              "data": {
                "content": "# Imported\\nUse this source.",
                "status": "completed"
              },
              "meta": {
                "name": "imported-source.md",
                "content_type": "text/markdown",
                "size": 27
              },
              "created_at": 1700001000,
              "updated_at": 1700001300
            }
          ],
          "total": 1
        }
        """

        let files = try FileExportService().files(fromJSONData: Data(json.utf8))

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.id.uuidString, "22222222-2222-2222-2222-222222222222")
        XCTAssertEqual(files.first?.fileName, "imported-source.md")
        XCTAssertEqual(files.first?.contentType, "text/markdown")
        XCTAssertEqual(files.first?.byteCount, 27)
        XCTAssertEqual(files.first?.textContent, "# Imported\nUse this source.")
        XCTAssertEqual(files.first?.createdAt, Date(timeIntervalSince1970: 1_700_001_000))
        XCTAssertEqual(files.first?.updatedAt, Date(timeIntervalSince1970: 1_700_001_300))
    }
}
