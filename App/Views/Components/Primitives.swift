import SwiftUI

// Reusable containers & controls — macOS HIG Native Redesign
// Materials, hairlines, continuous corners and system semantics.

/// Control Center style glass card for Menu Bar Popover
struct MiniCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(DS.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(TCTheme.separator.opacity(0.4), lineWidth: 0.5)
            )
    }
}

/// Dashboard section panel card
struct PanelCard<Content: View>: View {
    let title: String
    var symbol: String
    var tint: Color = TCTheme.fan
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: DS.Icon.chip, height: DS.Icon.chip)
                    .background(
                        tint.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    )
                Text(title)
                    .font(.headline)
                    .foregroundStyle(TCTheme.label)
                Spacer()
            }
            content()
        }
        .padding(DS.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            TCTheme.cardBackground,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(TCTheme.separator.opacity(0.5), lineWidth: 0.5)
        )
    }
}

/// Stat metric tile
struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = TCTheme.fan
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs + 2) {
            HStack(spacing: DS.Space.xs + 1) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(TCTheme.secondaryLabel)
            }
            Text(value)
                .font(.system(size: DS.Typography.metric, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(TCTheme.label)
            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(TCTheme.secondaryLabel)
                    .lineLimit(1)
            }
        }
        .padding(DS.Space.m + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            TCTheme.cardBackground,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(TCTheme.separator.opacity(0.5), lineWidth: 0.5)
        )
    }
}

/// Native Segmented-style Mode Tile
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
                    .font((compact ? Font.subheadline : Font.title3).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 7 : DS.Space.m)
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

/// Native capsule choice button
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
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.medium))
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

/// Helper connection indicator (native badge)
struct ConnectionDot: View {
    let connected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(connected ? TCTheme.battery : TCTheme.power)
                .frame(width: 7, height: 7)
            Text(connected ? L10n.t("online") : L10n.t("offline"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TCTheme.secondaryLabel)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(nsColor: .controlColor), in: Capsule())
    }
}

/// Native number row input
struct ConfigNumberRow: View {
    let title: String
    var unit: String = ""
    @Binding var value: Int
    var tint: Color = TCTheme.fan
    var enabled = true
    var onCommit: () -> Void = {}
    var onLive: () -> Void = {}

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Text(title)
                .font(.callout)
                .foregroundStyle(TCTheme.label)
            Spacer()
            SoftNumberField(
                value: $value,
                width: 68,
                enabled: enabled,
                onCommit: onCommit,
                onLive: onLive
            )
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TCTheme.secondaryLabel)
                    .frame(width: 32, alignment: .leading)
            }
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, 6)
        .background(
            Color(nsColor: .controlColor).opacity(0.7),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}
