import CoreGraphics

/// Shared layout values used across dashboard and menu-bar components.
enum DS {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
    }

    enum Radius {
        static let control: CGFloat = 6
        static let panel: CGFloat = 12
    }

    enum Icon {
        static let chip: CGFloat = 26
    }

    enum Typography {
        static let metric: CGFloat = 24
    }
}