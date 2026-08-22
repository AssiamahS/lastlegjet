import SwiftUI

// MARK: - Typography helpers

extension Font {
    static var displayTitle: Font { .system(.title, design: .serif).weight(.semibold) }
    static var displayLarge: Font { .system(.largeTitle, design: .serif).weight(.semibold) }
    static var displayHeadline: Font { .system(.title3, design: .serif).weight(.semibold) }
}

// MARK: - Surfaces

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Brand.inkCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Brand.inkLine)
            )
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardBackground(padding: padding))
    }

    func screenBackground() -> some View {
        background(Brand.ink.ignoresSafeArea())
    }
}

#if compiler(>=6.2)
extension View {
    /// Liquid Glass where available; plain view elsewhere. Used sparingly (banners only).
    @ViewBuilder
    func lightGlass() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect()
        } else {
            self
        }
    }
}
#else
extension View {
    func lightGlass() -> some View { self }
}
#endif

// MARK: - Small pieces

struct SectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.displayHeadline)
            .foregroundStyle(Brand.cream)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Pill: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = Brand.gold

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage = systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

struct VerifiedPill: View {
    var body: some View {
        Pill(text: "Verified Operator", systemImage: "checkmark.seal.fill", tint: Brand.gold)
    }
}

struct StatusBadge: View {
    let status: String

    private var tint: Color {
        switch BookingStatus(rawValue: status) {
        case .confirmed: return Brand.success
        case .held: return Brand.gold
        case .expired, .cancelled: return Brand.muted
        case .refunded: return Color.blue
        case .none: return Brand.muted
        }
    }

    var body: some View {
        Text(BookingStatus(rawValue: status)?.label.uppercased() ?? status)
            .font(.caption2.weight(.bold))
            .tracking(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.15), in: Capsule())
    }
}

struct Chip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? Brand.ink : Brand.cream)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Brand.gold : Brand.inkCard, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? Brand.gold : Brand.inkLine))
        }
        .buttonStyle(.plain)
    }
}

struct SampleDataBanner: View {
    var text: String = "Sample data — server unreachable or sample mode on"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Brand.gold)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Brand.gold.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(Brand.gold.opacity(0.4)))
        .lightGlass()
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Brand.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Brand.gold.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Brand.cream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Brand.inkCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Brand.inkLine))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct BrandField: View {
    let title: String
    @Binding var text: String
    var secure: Bool = false
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .never

    var body: some View {
        Group {
            if secure {
                SecureField(title, text: $text)
            } else {
                TextField(title, text: $text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled()
            }
        }
        .foregroundStyle(Brand.cream)
        .padding(12)
        .background(Brand.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Brand.inkLine))
    }
}

struct LabeledRow: View {
    let label: String
    let value: String
    var emphasize: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(Brand.muted)
            Spacer()
            Text(value)
                .foregroundStyle(emphasize ? Brand.gold : Brand.cream)
                .fontWeight(emphasize ? .bold : .regular)
        }
        .font(emphasize ? .headline : .subheadline)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(Brand.gold)
            Text(title)
                .font(.displayHeadline)
                .foregroundStyle(Brand.cream)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}

/// Copies `text` to the pasteboard and flashes a checkmark for a moment.
struct CopyButton: View {
    let text: String
    var label: String = "Copy"

    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(copied ? Brand.success : Brand.cream)
                .frame(width: 40, height: 40)
                .background(Brand.inkCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Brand.inkLine))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Copied" : label)
    }
}

/// Monospace value (wallet address, 2FA secret) with a copy button beside it.
struct CopyableValue: View {
    let value: String
    var copyLabel: String = "Copy"

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(value)
                .font(.footnote.monospaced())
                .foregroundStyle(Brand.cream)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Brand.ink, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Brand.inkLine))
            CopyButton(text: value, label: copyLabel)
        }
    }
}

/// Navigation route for the confirmation screen (distinct from pushing a `Booking`, which opens payment).
struct BookingConfirmationRoute: Hashable {
    let booking: Booking
}
