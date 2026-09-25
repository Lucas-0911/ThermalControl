import CoreGraphics

/// Layout tokens replacing the scattered magic numbers (corner radii
/// 8/12/14/16/18/20 and opacities 0.05–0.18 of the old AppChrome).
/// The scale follows macOS HIG grouping: cards 10, controls 6–8.
enum DS {
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
    }

    enum Radius {
        static let control: CGFloat = 6
        static let field: CGFloat = 8
        static let card: CGFloat = 10
        static let panel: CGFloat = 12
    }

    enum Icon {
        /// Small tinted icon chip in card headers.
        static let chip: CGFloat = 26
        /// Circular icon button in the menu-bar header.
        static let button: CGFloat = 26
    }

    enum Typography {
        /// Big rounded numerals (RPM, percent, watts).
        static let metric: CGFloat = 24
        static let metricLarge: CGFloat = 30
    }
}