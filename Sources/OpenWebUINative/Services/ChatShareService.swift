import AppKit

@MainActor
protocol ChatSharing {
    func share(text: String, title: String)
    func share(fileURL: URL, title: String)
}

extension ChatSharing {
    func share(fileURL: URL, title: String) {
        share(text: fileURL.path, title: title)
    }
}

@MainActor
final class ChatShareService: ChatSharing {
    private var activeDelegate: ChatSharePickerDelegate?
    private var activeSharedFileURLs: [URL] = []

    func share(text: String, title: String) {
        let picker = NSSharingServicePicker(items: [text])
        let delegate = ChatSharePickerDelegate(title: title)
        activeDelegate = delegate
        picker.delegate = delegate

        guard let view = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView else {
            return
        }

        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }

    func share(fileURL: URL, title: String) {
        activeSharedFileURLs = [fileURL]
        let picker = NSSharingServicePicker(items: [fileURL])
        let delegate = ChatSharePickerDelegate(title: title)
        activeDelegate = delegate
        picker.delegate = delegate

        guard let view = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView else {
            return
        }

        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }
}

private final class ChatSharePickerDelegate: NSObject, NSSharingServicePickerDelegate {
    let title: String

    init(title: String) {
        self.title = title
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        sharingServicesForItems items: [Any],
        proposedSharingServices proposedServices: [NSSharingService]
    ) -> [NSSharingService] {
        for service in proposedServices {
            service.subject = title
        }
        return proposedServices
    }
}
