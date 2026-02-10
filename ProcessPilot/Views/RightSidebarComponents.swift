import SwiftUI

struct SidebarSectionCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    init(
        title: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.headline)
            }
            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

struct SidebarMetricRing: View {
    let title: String
    let icon: String
    let value: String
    let unit: String
    let progress: Double
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.14), lineWidth: 7)
                    .frame(width: 88, height: 88)

                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(
                        AngularGradient(
                            colors: [
                                color.opacity(0.55),
                                color.opacity(0.95)
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .frame(width: 88, height: 88)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 1) {
                    Text(value)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
