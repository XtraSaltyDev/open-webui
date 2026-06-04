import Foundation

struct AudioHistoryExportService: Sendable {
    func jsonData(for items: [AppAudioHistoryItem], exportedAt: Date = Date()) throws -> Data {
        let bundle = AudioHistoryExportBundle(exportedAt: exportedAt, items: items)
        return try JSONEncoder.openWebUIEncoder.encode(bundle)
    }

    func items(fromJSONData data: Data) throws -> [AppAudioHistoryItem] {
        let decoder = JSONDecoder.openWebUIDecoder
        if let bundle = try? decoder.decode(AudioHistoryExportBundle.self, from: data) {
            return bundle.items.sorted { $0.createdAt > $1.createdAt }
        }

        let items = try decoder.decode([AppAudioHistoryItem].self, from: data)
        return items.sorted { $0.createdAt > $1.createdAt }
    }
}

private struct AudioHistoryExportBundle: Codable {
    var format: String
    var version: Int
    var exportedAt: Date
    var items: [AppAudioHistoryItem]

    init(
        format: String = "open-webui-native-audio-history",
        version: Int = 1,
        exportedAt: Date,
        items: [AppAudioHistoryItem]
    ) {
        self.format = format
        self.version = version
        self.exportedAt = exportedAt
        self.items = items
    }
}
