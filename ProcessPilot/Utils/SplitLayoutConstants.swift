import CoreGraphics

enum SplitLayoutConstants {
    static let leftSidebarWidth: CGFloat = 200

    static let contentColumnMinWidth: CGFloat = 340
    static let contentColumnIdealWidth: CGFloat = 480

    static let detailColumnWidth: CGFloat = 320
    static let detailContentWidth: CGFloat = 296

    static let windowMinWidth: CGFloat = 920
    static let windowMinHeight: CGFloat = 600

    static var isConsistent: Bool {
        detailContentWidth <= detailColumnWidth
    }
}
