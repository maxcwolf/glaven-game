import SwiftUI

struct StandeePickerView: View {
    let label: String
    let type: MonsterType
    let monster: GameMonster
    let color: Color
    @Environment(GameManager.self) private var gameManager
    @Environment(\.uiScale) private var scale

    private var count: Int {
        monster.entities.filter { $0.type == type && !$0.dead }.count
    }

    private var availableNumbers: [Int] {
        gameManager.monsterManager.availableStandeeNumbers(for: monster)
    }

    var body: some View {
        Menu {
            ForEach(availableNumbers, id: \.self) { number in
                Button("Standee #\(number)") {
                    gameManager.monsterManager.addEntity(type: type, to: monster, number: number)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12 * scale))
                    .fontWeight(.medium)
                Text("\(count)")
                    .font(.system(size: 12 * scale))
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12 * scale))
            }
            .padding(.horizontal, 10 * scale)
            .padding(.vertical, 6 * scale)
            .background(GlavenTheme.primaryText.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(availableNumbers.isEmpty)
    }
}
