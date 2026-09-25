import SwiftUI

// Reusable containers & controls — macOS-native restyle (Phase 5).
// Surfaces use system control background + separator hairlines instead of
// per-card colored gradients; tint survives only as a small accent.

/// Neutral surface card for the menu-bar panel.
struct MiniCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(DS.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                TCTheme.cardBackground,
                in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(TCTheme.separator, lineWidth: 1)
            )
    }
}

/// Dashboard section card: tinted icon chip + headline title.
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
            in: RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                .strokeBorder(TCTheme.separator, lineWidth: 1)
        )
    }
}

/// Dashboard stat tile: small-caps title, big rounded numeral, footnote.
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
            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(TCTheme.separator, lineWidth: 1)
        )
    }
}

/// Selectable fan-mode tile.
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
                    .font((compact ? Font.body : Font.title3).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? DS.Space.s : DS.Space.m)
            .foregroundStyle(selected ? Color.white : tint)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.field, style: .continuous)
                    .fill(selected ? AnyShapeStyle(tint) : AnyShapeStyle(TCTheme.controlFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.field, style: .continuous)
                    .strokeBorder(
                        selected ? Color.clear : TCTheme.separator.opacity(0.6),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// Selectable capsule (charge mode).
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
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.s)
            .foregroundStyle(selected ? Color.white : tint)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? AnyShapeStyle(tint) : AnyShapeStyle(TCTheme.controlFill))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(selected ? Color.clear : TCTheme.separator.opacity(0.6), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// Helper connection indicator.
struct ConnectionDot: View {
    let connected: Bool

    var body: some View {
        HStack(spacing: DS.Space.xs + 2) {
            Circle()
                .fill(connected ? TCTheme.battery : TCTheme.power)
                .frame(width: 7, height: 7)
            Text(connected ? L10n.t("online") : L10n.t("offline"))
                .font(.caption.weight(.medium))
                .foregroundStyle(TCTheme.secondaryLabel)
        }
        .padding(.horizontal, DS.Space.s + 2)
        .padding(.vertical, DS.Space.xs)
        .background(.regularMaterial, in: Capsule())
    }
}

/// Labeled numeric input row (RPM / charge %).
struct ConfigNumberRow: View {
    let title: String
    var unit: String = ""
    @Binding var value: Int
    var tint: Color = TCTheme.fan
    var enabled = true
    var onCommit: () -> Void = {}
    var onLive: () -> Void = {}

    var body: some View {
        HStack(spacing: DS.Space.s + 2) {
            Text(title)
                .font(.callout)
                .foregroundStyle(TCTheme.secondaryLabel)
            Spacer()
            SoftNumberField(
                value: $value,
                width: 76,
                enabled: enabled,
                onCommit: onCommit,
                onLive: onLive
            )
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TCTheme.tertiaryLabel)
                    .frame(width: 32, alignment: .leading)
            }
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.s)
        .background(
            TCTheme.controlFill,
            in: RoundedRectangle(cornerRadius: DS.Radius.field, style: .continuous)
        )
    }
}