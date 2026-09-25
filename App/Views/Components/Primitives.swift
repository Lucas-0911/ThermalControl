import SwiftUI

// MARK: - Apple HIG Modern Design Primitives (macOS Sonoma / Sequoia 2026 Edition)
// Materials, continuous corners, hairline borders, rich typography and native depth.

/// Control Center style Vibrancy Glass Card for Menu Bar Popover
struct MiniCard<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                    .strokeBorder(TCTheme.separator.opacity(0.35), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

/// Dashboard Section Panel Card
struct PanelCard<Content: View>: View {
    let title: String
    var symbol: String
    var tint: Color = TCTheme.fan
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(spacing: DS.Space.s + 2) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: DS.Icon.chip, height: DS.Icon.chip)
                    .background(
                        tint.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: DS.Radius.control + 1, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TCTheme.label)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(TCTheme.secondaryLabel)
                    }
                }
                Spacer()
            }
            content()
        }
        .padding(DS.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.85),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(TCTheme.separator.opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 2)
    }
}

/// Modern Big Metric Stat Tile
struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = TCTheme.fan
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs + 2) {
            HStack(spacing: DS.Space.xs + 2) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(TCTheme.secondaryLabel)
            }
            Text(value)
                .font(.system(size: DS.Typography.metric, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(TCTheme.label)
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(TCTheme.secondaryLabel)
                    .lineLimit(1)
            }
        }
        .padding(DS.Space.m + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.75),
            in: RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                .strokeBorder(TCTheme.separator.opacity(0.35), lineWidth: 0.5)
        )
    }
}

/// Native Segmented Mode Tile with smooth pill background
struct ModeTile: View {
    let title: String
    let symbol: String
    var selected = false
    var tint: Color = TCTheme.fan
    var enabled = true
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: compact ? 3 : 5) {
                Image(systemName: symbol)
                    .font((compact ? Font.system(size: 13, weight: .semibold) : Font.system(size: 16, weight: .semibold)))
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.system(size: compact ? 11 : 12, weight: selected ? .semibold : .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 6 : DS.Space.s + 2)
            .foregroundStyle(selected ? Color.white : TCTheme.label)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? AnyShapeStyle(tint) : AnyShapeStyle(Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// Choice Pill for Secondary Segmented Switchers
struct ChoicePill: View {
    let title: String
    let symbol: String
    var selected = false
    var tint: Color
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xs + 2) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? Color.white : TCTheme.label)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? AnyShapeStyle(tint) : AnyShapeStyle(Color.clear))
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// Helper connection indicator (subtle glowing dot badge)
struct ConnectionDot: View {
    let connected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(connected ? TCTheme.battery : TCTheme.power)
                .frame(width: 7, height: 7)
                .shadow(color: (connected ? TCTheme.battery : TCTheme.power).opacity(0.4), radius: 3, x: 0, y: 0)
            Text(connected ? L10n.t("online") : L10n.t("offline"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TCTheme.secondaryLabel)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Color(nsColor: .controlColor).opacity(0.8), in: Capsule())
        .overlay(
            Capsule().strokeBorder(TCTheme.separator.opacity(0.25), lineWidth: 0.5)
        )
    }
}

/// Modern Stepper & Direct Input Row
struct ConfigNumberRow: View {
    let title: String
    var unit: String = ""
    @Binding var value: Int
    var tint: Color = TCTheme.fan
    var step: Int = 100
    var minVal: Int = 0
    var maxVal: Int = 10000
    var enabled: Bool = true
    var onCommit: () -> Void = {}
    var onLive: () -> Void = {}

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TCTheme.label)
            Spacer()
            
            // Stepper buttons (- / +)
            HStack(spacing: 2) {
                Button(action: {
                    let next = max(minVal, value - step)
                    if next != value {
                        value = next
                        onLive()
                        onCommit()
                    }
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Color(nsColor: .controlColor), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!enabled || value <= minVal)

                SoftNumberField(
                    value: $value,
                    width: 62,
                    enabled: enabled,
                    onCommit: onCommit,
                    onLive: onLive
                )

                Button(action: {
                    let next = min(maxVal, value + step)
                    if next != value {
                        value = next
                        onLive()
                        onCommit()
                    }
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Color(nsColor: .controlColor), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!enabled || value >= maxVal)
            }

            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TCTheme.secondaryLabel)
                    .frame(width: 28, alignment: .leading)
            }
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, 6)
        .background(
            Color(nsColor: .controlColor).opacity(0.6),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}
