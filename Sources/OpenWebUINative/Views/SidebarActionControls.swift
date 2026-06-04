import SwiftUI

enum SidebarActionLayoutPolicy {
    static let usesIconOnlyLabels = true
    static let buttonWidth: CGFloat = 28
    static let buttonHeight: CGFloat = 24
    static let spacing: CGFloat = 6
}

struct SidebarActionStrip<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: SidebarActionLayoutPolicy.spacing) {
            content
            Spacer(minLength: 0)
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SidebarActionButton: View {
    var title: String
    var systemImage: String
    var isDisabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .sidebarActionControl(title: title)
        .disabled(isDisabled)
    }
}

struct SidebarActionMenu<Content: View>: View {
    var title: String
    var systemImage: String
    var isDisabled = false
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            content
        } label: {
            Label(title, systemImage: systemImage)
        }
        .menuStyle(.borderlessButton)
        .sidebarActionControl(title: title)
        .disabled(isDisabled)
    }
}

extension View {
    func sidebarActionControl(title: String) -> some View {
        labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(
                width: SidebarActionLayoutPolicy.buttonWidth,
                height: SidebarActionLayoutPolicy.buttonHeight
            )
            .contentShape(Rectangle())
            .help(title)
    }
}
