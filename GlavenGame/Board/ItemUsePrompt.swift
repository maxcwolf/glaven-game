import SwiftUI

/// "Bandit Guard attacks the Brute: use Leather Armor?" — a defence item offered mid-attack.
struct ItemUsePrompt: View {
    let pending: BoardCoordinator.PendingItemUse
    let coordinator: BoardCoordinator

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Text("\(pending.attacker) attacks \(coordinator.characterName(pending.characterID))")
                    .font(.subheadline)
                    .foregroundStyle(BoardTheme.secondaryText)
                Label("Use \(pending.itemName)?", systemImage: "shield.lefthalf.filled")
                    .font(BoardTheme.display(26))
                    .foregroundStyle(BoardTheme.text)
                Text(pending.question)
                    .font(.body)
                    .foregroundStyle(BoardTheme.text)
                HStack(spacing: 12) {
                    Button("Not Now") { coordinator.resolvePendingItemUse(false) }
                        .buttonStyle(.bordered)
                        .tint(BoardTheme.text)
                    Button("Use \(pending.itemName)") { coordinator.resolvePendingItemUse(true) }
                        .buttonStyle(.borderedProminent)
                        .tint(BoardTheme.brass)
                }
                .controlSize(.large)
            }
            .padding(20)
            .frame(maxWidth: 460, alignment: .leading)
            .boardPanel()
            .padding(.bottom, 40)
        }
    }
}
