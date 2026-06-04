import SwiftUI

struct KnowledgeDocumentDetailView: View {
    var detail: KnowledgeDocumentDetail
    var focusedChunkID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if detail.chunks.isEmpty {
                            Text("No indexed text")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(18)
                        } else {
                            ForEach(detail.chunks.sorted { $0.index < $1.index }) { chunk in
                                KnowledgeChunkPreviewRow(
                                    chunk: chunk,
                                    isFocused: focusedChunkID == chunk.id
                                )
                                .id(chunk.id)
                            }
                        }
                    }
                    .padding(18)
                }
                .onAppear {
                    scrollToFocusedChunk(proxy)
                }
                .onChange(of: focusedChunkID) {
                    scrollToFocusedChunk(proxy)
                }
            }
        }
    }

    private func scrollToFocusedChunk(_ proxy: ScrollViewProxy) {
        guard let focusedChunkID else {
            return
        }
        withAnimation {
            proxy.scrollTo(focusedChunkID, anchor: .center)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(detail.document.fileName, systemImage: detail.document.contentType == "application/pdf" ? "doc.richtext" : "doc.text")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Text("#\(detail.collection.slug)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Text(detail.document.metadata.mimeTypeHint)
                Text(ByteCountFormatter.string(fromByteCount: Int64(detail.document.metadata.byteCount), countStyle: .file))
                Text("\(detail.chunks.count) chunks")
                Text(detail.document.metadata.lastIndexedAt, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text("Imported as \(detail.document.metadata.importedFileName)")
                Text(detail.document.metadata.sourceKind.displayName)
                Text(detail.document.createdAt, style: .relative)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

private struct KnowledgeChunkPreviewRow: View {
    var chunk: KnowledgeChunk
    var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Chunk \(chunk.index + 1)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isFocused ? Color.accentColor : Color.secondary)

            Text(chunk.text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(isFocused ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
        )
    }
}
