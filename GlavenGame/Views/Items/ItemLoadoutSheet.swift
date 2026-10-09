import SwiftUI

/// What a character brings to the next scenario (GH p.9): every item they own, each brought or
/// left at home, within one head, body and legs item, two hands and half their level (rounded up)
/// in small items. In the board's look: the items as tiles that say what each does.
struct ItemLoadoutSheet: View {
    @Environment(GameManager.self) private var gameManager
    let character: GameCharacter
    /// Off for snapshots: ImageRenderer doesn't draw scroll views.
    var scrolls = true
    var onDone: () -> Void = {}

    private var store: EditionDataStore { gameManager.editionStore }
    private var name: String { GameText.characterName(character, labels: store) }

    private var owned: [ItemData] {
        character.items.compactMap { store.itemData(key: $0) }
            .sorted { (ItemSlot.allCases.firstIndex(of: $0.slot) ?? 0, $0.id) < (ItemSlot.allCases.firstIndex(of: $1.slot) ?? 0, $1.id) }
    }

    var body: some View {
        TownDialog(title: "\(name)'s Items", subtitle: "What the \(name) brings to the next scenario",
                   portrait: (ImageLoader.characterThumbnail(edition: character.edition, name: character.name),
                              Color(hex: character.color) ?? BoardTheme.border),
                   size: CGSize(width: 860, height: 640), onDone: onDone) {
            Text("Brings \(character.carriedItems.count) of \(character.items.count)")
                .font(BoardTheme.font(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(BoardTheme.sheet)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(BoardTheme.brass, in: Capsule())
                .fixedSize()
                .accessibilityLabel(Self.limitsLine(for: character, store: store))
        } content: {
            if scrolls { ScrollView { content } } else { content }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Self.rulesLine(for: character))
                .font(BoardTheme.font(size: 13))
                .foregroundStyle(BoardTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if owned.isEmpty {
                Text("No items yet. Buy some in the shop.")
                    .font(BoardTheme.font(size: 14))
                    .foregroundStyle(BoardTheme.secondaryText)
                    .padding(.top, 20)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(owned) { tile($0) }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tile(_ item: ItemData) -> some View {
        let bringing = !character.itemsLeftBehind.contains(item.itemKey)
        let problem = bringing ? nil : gameManager.itemManager.bringingProblem(item.itemKey, for: character)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: item.slot.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(bringing ? BoardTheme.brass : BoardTheme.secondaryText)
                    .accessibilityHidden(true)
                TownSmallCaps(text: item.slot.displayName)
                Spacer()
                TownSwitch(label: "Bring \(item.name)", isOn: Binding(
                    get: { bringing },
                    set: { gameManager.itemManager.setBringing(item.itemKey, $0, for: character) }))
                    .disabled(problem != nil)
            }
            Text(item.name)
                .font(BoardTheme.display(18))
                .foregroundStyle(BoardTheme.text)
                .lineLimit(1)
            Text(bringing ? GameText.itemRule(item, labels: store) : Self.atHome(problem?.text))
                .font(BoardTheme.font(size: 12))
                .foregroundStyle(bringing ? BoardTheme.text.opacity(0.85) : BoardTheme.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 118, maxHeight: 118, alignment: .topLeading)
        .background(BoardTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(bringing ? BoardTheme.brass.opacity(0.6) : BoardTheme.border.opacity(0.45), lineWidth: 1))
        .opacity(bringing ? 1 : 0.6)
    }

    /// "At home · already bringing 1 small item".
    static func atHome(_ problem: String?) -> String {
        guard let problem else { return "At home" }
        return "At home \u{00B7} " + problem.prefix(1).lowercased() + problem.dropFirst()
    }

    /// "One head, body and legs item, two hands' worth, and 1 small item at level 2. …"
    static func rulesLine(for character: GameCharacter) -> String {
        let small = ItemLoadout.smallItemLimit(level: character.level, carrying: character.carriedItems)
        return "One head, body and legs item, two hands' worth, and \(small) small item\(small == 1 ? "" : "s") at level \(character.level). Items left at home stay yours."
    }

    /// "Bringing 3 of 4 items · up to 1 small item at level 2".
    static func limitsLine(for character: GameCharacter, store: EditionDataStore) -> String {
        let small = ItemLoadout.smallItemLimit(level: character.level, carrying: character.carriedItems)
        let brought = character.carriedItems.count
        return "Bringing \(brought) of \(character.items.count) item\(character.items.count == 1 ? "" : "s")"
            + " · up to \(small) small item\(small == 1 ? "" : "s") at level \(character.level)"
    }
}
