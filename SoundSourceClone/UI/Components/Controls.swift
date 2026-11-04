import SwiftUI

/// Small square icon button used in the header and in row accessories.
struct IconButton: View {
    let systemName: String
    var isOn = false
    /// Tints the glyph without the "pressed" background, e.g. EQ active while collapsed.
    var isActive = false
    var tint: Color = Theme.accent
    var size: CGFloat = 22
    var help: String = ""
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn || isActive ? tint : Color.white.opacity(isHovering ? 0.9 : 0.6))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isOn ? tint.opacity(0.2) : (isHovering ? Color.white.opacity(0.08) : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
    }
}

struct ChevronButton: View {
    let isOpen: Bool
    var help: String = "Details"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isOpen ? Theme.primaryText : Theme.tertiaryText)
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .frame(width: 18, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct StarButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "star.fill" : "star")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? Theme.favorite : Theme.tertiaryText)
                .frame(width: 16, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Remove from Favorites" : "Add to Favorites")
    }
}

/// System row glyph (speaker / mic / bell) that doubles as a mute toggle.
struct SymbolButton: View {
    let systemName: String
    var tint: Color?
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint ?? Theme.primaryText.opacity(0.85))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// App icon that toggles mute when clicked.
struct AppIconButton: View {
    let icon: NSImage
    let isMuted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
                .opacity(isMuted ? 0.45 : 1)
                .overlay(alignment: .bottomTrailing) {
                    if isMuted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(2)
                            .background(Circle().fill(Theme.danger))
                            .offset(x: 3, y: 3)
                    }
                }
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isMuted ? "Unmute" : "Mute")
    }
}

struct PillToggle: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Theme.accent : Color.white.opacity(0.18))
                    .frame(width: 28, height: 16)
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.3), radius: 1)
                    .padding(2)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: isOn)
    }
}

struct CapsuleButton: View {
    let title: String
    var symbol: String?
    var isProminent = false
    let action: () -> Void

    init(_ title: String, symbol: String? = nil, isProminent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.isProminent = isProminent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            CapsuleLabel(title: title, symbol: symbol, isProminent: isProminent)
        }
        .buttonStyle(.plain)
    }
}

struct CapsuleLabel: View {
    let title: String
    var symbol: String?
    var showsChevron = false
    var isProminent = false

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold))
            }
            Text(title).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down").font(.system(size: 7.5, weight: .bold)).opacity(0.6)
            }
        }
        .foregroundStyle(isProminent ? Color.white : Theme.primaryText.opacity(0.85))
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule().fill(isProminent ? Theme.accent : Theme.controlFill))
        .overlay(Capsule().strokeBorder(isProminent ? Color.clear : Theme.controlStroke, lineWidth: 0.5))
        .contentShape(Capsule())
    }
}

struct DevicePickerButton: View {
    let title: String
    let symbol: String
    var isMissing = false
    var width: CGFloat = Theme.deviceColumn
    let items: () -> [MenuItemSpec]

    var body: some View {
        PopUpMenuButton(items: items) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isMissing ? Theme.warning : Theme.secondaryText)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(isMissing ? Theme.warning : Theme.primaryText.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(.horizontal, 8)
            .frame(width: width, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.controlFill))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.controlStroke, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .help("Output device")
    }
}

struct SectionHeader: View {
    let title: String
    var detail: String?
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 10)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.tertiaryText)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Fixed-column row shared by the System and Applications sections so sliders line up.
struct MixerRow<Leading: View, Icon: View, Trailing: View>: View {
    let title: String
    var isDimmed = false
    let percentText: String
    let slider: VolumeSlider
    let leading: Leading
    let icon: Icon
    let trailing: Trailing

    init(title: String,
         isDimmed: Bool = false,
         percentText: String,
         slider: VolumeSlider,
         @ViewBuilder leading: () -> Leading,
         @ViewBuilder icon: () -> Icon,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.isDimmed = isDimmed
        self.percentText = percentText
        self.slider = slider
        self.leading = leading()
        self.icon = icon()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            leading.frame(width: 16)
            icon.frame(width: 22, height: 22)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isDimmed ? Theme.secondaryText : Theme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: Theme.nameColumn, alignment: .leading)
            slider
            Text(percentText)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .frame(width: Theme.percentColumn, alignment: .trailing)
            trailing
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.rowHeight)
    }
}

/// Container for the inline EQ and detail panels that open under a row.
struct DetailCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.separator, lineWidth: 0.5))
            .padding(.leading, 36)
            .padding(.trailing, 12)
            .padding(.bottom, 8)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.separator).frame(height: 1)
    }
}

/// Keeps column alignment where a row has no control in that slot.
struct ColumnSpacer: View {
    let width: CGFloat
    var body: some View { Color.clear.frame(width: width, height: 1) }
}
