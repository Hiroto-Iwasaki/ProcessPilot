import SwiftUI
import AppKit

struct AsyncProcessIconView<Placeholder: View>: View {
    let executablePath: String?
    let imageSize: CGSize
    let cornerRadius: CGFloat
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: imageSize.width, height: imageSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                placeholder()
            }
        }
        .task(id: executablePath) {
            await loadIcon()
        }
    }

    private func loadIcon() async {
        icon = ProcessAppIconProvider.cachedIcon(forExecutablePath: executablePath)

        guard icon == nil else {
            return
        }

        let loadedIcon = await ProcessAppIconProvider.loadIcon(forExecutablePath: executablePath)
        guard !Task.isCancelled else { return }
        icon = loadedIcon
    }
}
