import SwiftUI

struct AddSummonSheet: View {
    let character: GameCharacter
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedColor: SummonColor = .blue

    private var availableSummons: [SummonDataModel] {
        guard let summons = character.characterData?.availableSummons else { return [] }
        return summons.filter { data in
            data.level == nil || (data.level ?? 0) <= character.level
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Color picker
                VStack(spacing: 6) {
                    Text("Summon Color")
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.secondaryText)
                    HStack(spacing: 8) {
                        ForEach(playerColors, id: \.self) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                Circle()
                                    .fill(swiftColor(for: color))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: selectedColor == color ? 2.5 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal)
                .background(GlavenTheme.cardBackground)

                // Summon list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(availableSummons.enumerated()), id: \.element.name) { idx, data in
                            summonRow(data)
                            if idx < availableSummons.count - 1 {
                                Divider().background(GlavenTheme.primaryText.opacity(0.1))
                            }
                        }

                        if availableSummons.isEmpty {
                            Text("No summons available at this level")
                                .font(.subheadline)
                                .foregroundStyle(GlavenTheme.secondaryText)
                                .padding(.top, 40)
                        }
                    }
                }
            }
            .background(GlavenTheme.background)
            .navigationTitle("Add Summon")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 400)
    }

    @ViewBuilder
    private func summonRow(_ data: SummonDataModel) -> some View {
        Button {
            addSummon(data)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(swiftColor(for: selectedColor))
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(data.name.replacingOccurrences(of: "-", with: " ").capitalized)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(GlavenTheme.primaryText)
                    HStack(spacing: 8) {
                        let hp = evaluateEntityValue(data.health, level: character.level)
                        HStack(spacing: 2) {
                            GameIcon(image: ImageLoader.statusIcon("health"), fallbackSystemName: "heart.fill", size: 12, color: .red)
                            Text("\(hp)")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                        if let atk = data.attack {
                            HStack(spacing: 2) {
                                GameIcon(image: ImageLoader.actionIcon("attack"), fallbackSystemName: "burst.fill", size: 12, color: .white)
                                Text("\(atk.intValue)")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        if let mov = data.movement, mov.intValue > 0 {
                            HStack(spacing: 2) {
                                GameIcon(image: ImageLoader.actionIcon(data.flying == true ? "fly" : "move"), fallbackSystemName: "figure.walk", size: 12, color: .white)
                                Text("\(mov.intValue)")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        if let rng = data.range, rng.intValue > 0 {
                            HStack(spacing: 2) {
                                GameIcon(image: ImageLoader.actionIcon("range"), fallbackSystemName: "scope", size: 12, color: .white)
                                Text("\(rng.intValue)")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        if let level = data.level {
                            Text("Lv \(level)")
                                .font(.caption)
                                .foregroundStyle(GlavenTheme.secondaryText)
                        }
                    }
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.title3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addSummon(_ data: SummonDataModel) {
        gameManager.characterManager.addSummon(from: data, for: character)
        if let last = character.summons.last {
            last.color = selectedColor
        }
        dismiss()
    }

    private var playerColors: [SummonColor] {
        [.blue, .green, .yellow, .orange, .white, .purple, .pink, .red]
    }

    private func swiftColor(for color: SummonColor) -> Color {
        switch color {
        case .blue: return .blue
        case .green: return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .white: return .white
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        default: return .gray
        }
    }
}
