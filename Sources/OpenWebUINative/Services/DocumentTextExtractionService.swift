import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers
#if canImport(Vision)
import Vision
#endif

protocol DocumentTextExtracting: Sendable {
    func extractedText(from data: Data, contentType: String, fileName: String) throws -> String?
}

struct DocumentTextExtractionService: DocumentTextExtracting {
    func extractedText(from data: Data, contentType: String, fileName: String) throws -> String? {
        let fileType = UTType(filenameExtension: URL(fileURLWithPath: fileName).pathExtension)
        let mimeType = UTType(mimeType: contentType)
        if fileType == .pdf || mimeType == .pdf || contentType.lowercased() == "application/pdf" {
            return selectablePDFText(from: data) ?? ocrPDFText(from: data)
        }

        guard isTextType(fileType) || isTextType(mimeType) || contentType.lowercased().hasPrefix("text/") else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func isTextType(_ type: UTType?) -> Bool {
        type?.conforms(to: .text) == true || type?.conforms(to: .sourceCode) == true
    }

    private func selectablePDFText(from data: Data) -> String? {
        guard let document = PDFDocument(data: data) else {
            return nil
        }

        let pageText = (0..<document.pageCount).compactMap { pageIndex in
            document.page(at: pageIndex)?.string
        }
        let text = pageText.joined(separator: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    private func ocrPDFText(from data: Data) -> String? {
        #if canImport(Vision)
        guard let document = PDFDocument(data: data) else {
            return nil
        }

        let pageText = (0..<document.pageCount).compactMap { pageIndex -> String? in
            guard let page = document.page(at: pageIndex),
                  let image = renderedImage(from: page) else {
                return nil
            }
            return recognizedText(from: image)
        }
        let text = pageText.joined(separator: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        #else
        return nil
        #endif
    }

    private func renderedImage(from page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let scale: CGFloat = 2
        let width = Int((bounds.width * scale).rounded(.up))
        let height = Int((bounds.height * scale).rounded(.up))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
        return context.makeImage()
    }

    private func recognizedText(from image: CGImage) -> String? {
        #if canImport(Vision)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        let text = request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n") ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        #else
        return nil
        #endif
    }
}
