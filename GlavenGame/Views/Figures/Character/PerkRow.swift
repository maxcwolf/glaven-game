import SwiftUI

struct PerkRow: View {
    let perk: PerkModel
    let selected: Int
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 10) {
                checkboxes
                Text(perkDescription)
                    .font(.subheadline)
                    .foregroundStyle(GlavenTheme.primaryText)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(selected > 0 ? GlavenTheme.primaryText.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var checkboxes: some View {
        HStack(spacing: 4) {
            ForEach(0..<perk.count, id: \.self) { i in
                Image(systemName: i < selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(i < selected ? Color.accentColor : GlavenTheme.secondaryText)
            }
        }
    }

    private var perkDescription: String { GameText.perkText(perk) }
}
