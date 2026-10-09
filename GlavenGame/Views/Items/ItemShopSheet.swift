import SwiftUI

/// The shop, in the board's look: the city's items as tiles that say what each does and what it
/// costs, filtered by slot or name, with what the buyer already carries beside them. Any party
/// member can shop from here; selling pays half the price.
struct ItemShopSheet: View {
    let onDone: () -> Void
    @Environment(GameManager.self) private var gameManager
    @State private var buyer: GameCharacter
    @State private var searchText = ""
    @State private var selectedSlot: ItemSlot?
    /// An owned item the player tapped Sell on, waiting for them to confirm on its tile.
    @State private var pendingSale: ItemData?

    init(character: GameCharacter, onDone: @escaping () -> Void = {}) {
        _buyer = State(initialValue: character)
        self.onDone = onDone
    }

    private var edition: String { gameManager.game.edition ?? "gh" }
    private var items: ItemManager { gameManager.itemManager }
    private var party: [GameCharacter] { gameManager.game.characters.filter { !$0.absent } }

    /// The city's supply, plus anything the buyer owns so it can be sold back.
    private var shown: [ItemData] {
        var list = items.availableItems()
        let supply = Set(list.map(\.itemKey))
        list += gameManager.editionStore.items(for: edition).filter {
            buyer.items.contains($0.itemKey) && !supply.contains($0.itemKey)
        }
        if let slot = selectedSlot { list = list.filter { $0.slot == slot } }
        if !searchText.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(searchText) } }
        return list.sorted { $0.id < $1.id }
    }

    var body: some View {
        TownDialog(title: "Shop", subtitle: subtitle, onDone: onDone) {
            buyerChip
        } content: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    slotFilter
                    Spacer(minLength: 8)
                    searchField
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                HStack(alignment: .top, spacing: 14) {
                    ScrollView {
                        if shown.isEmpty {
                            Text("Nothing here. Try another slot or name.")
                                .font(BoardTheme.font(size: 14))
                                .foregroundStyle(BoardTheme.secondaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                            ForEach(shown) { tile($0) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)   // room for the Owned tag
                    }
                    ScrollView { carries }
                        .frame(width: 250)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Words

    /// What a tile offers the buyer.
    enum Offer: Equatable {
        case buy
        /// Owned: sell it back for this much.
        case sell(Int)
        /// This much more gold is needed.
        case short(Int)
        case soldOut
    }

    static func offer(_ item: ItemData, for character: GameCharacter, items: ItemManager) -> Offer {
        switch items.purchaseProblem(item, for: character) {
        case .alreadyOwned: return .sell(items.salePrice(item))
        case .soldOut: return .soldOut
        case .tooExpensive: return .short(items.price(item) - character.loot)
        case nil: return .buy
        }
    }

    /// "Prosperity 2 · reputation 5, prices 1 gold lower".
    static func subtitle(prosperity: Int, reputation: Int) -> String {
        let modifier = ItemManager.reputationPriceModifier(reputation)
        let prices = modifier == 0 ? "prices as printed"
            : "prices \(abs(modifier)) gold \(modifier < 0 ? "lower" : "higher")"
        return "Prosperity \(prosperity) \u{00B7} reputation \(reputation), \(prices)"
    }

    private var subtitle: String {
        Self.subtitle(prosperity: gameManager.game.prosperityLevel, reputation: gameManager.game.partyReputation)
    }

    // MARK: - Header and filters

    private func name(_ character: GameCharacter) -> String {
        GameText.characterName(character, labels: gameManager.editionStore)
    }

    @ViewBuilder
    private var buyerChip: some View {
        let chip = HStack(spacing: 10) {
            Group {
                if let image = ImageLoader.characterThumbnail(edition: buyer.edition, name: buyer.name) {
                    #if os(macOS)
                    Image(nsImage: image).resizable().scaledToFill()
                    #else
                    Image(uiImage: image).resizable().scaledToFill()
                    #endif
                } else {
                    BoardTheme.raised
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color(hex: buyer.color) ?? BoardTheme.border, lineWidth: 2))
            Text(name(buyer))
                .font(BoardTheme.font(size: 15, weight: .semibold))
                .foregroundStyle(BoardTheme.text)
                .lineLimit(1)
            TownGold(amount: buyer.loot)
            if party.count > 1 {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BoardTheme.secondaryText)
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, 14)
        .frame(height: 40)
        .background(BoardTheme.raised, in: Capsule())
        .overlay(Capsule().stroke(BoardTheme.border.opacity(0.6), lineWidth: 1))
        .fixedSize()

        if party.count > 1 {
            Menu {
                ForEach(party) { character in
                    Button("\(name(character)) \u{00B7} \(character.loot) gold") { buyer = character }
                }
            } label: {
                chip
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("Buying for \(name(buyer)), \(buyer.loot) gold")
            .accessibilityHint("Choose who's shopping")
        } else {
            chip.accessibilityElement(children: .combine)
        }
    }

    private var slotFilter: some View {
        let choices: [(ItemSlot?, String)] = [(nil, "All")] + ItemSlot.allCases.map { ($0, $0 == .small ? "Small" : $0.displayName) }
        return HStack(spacing: 0) {
            ForEach(choices, id: \.1) { slot, label in
                let isSelected = selectedSlot == slot
                Button { selectedSlot = slot } label: {
                    Text(label)
                        .font(BoardTheme.font(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? BoardTheme.sheet : BoardTheme.text)
                        .padding(.horizontal, 13)
                        .frame(minHeight: 34)
                        .background(isSelected ? BoardTheme.brass : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(BoardTheme.raised, in: Capsule())
        .fixedSize()
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(BoardTheme.secondaryText)
                .accessibilityHidden(true)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(BoardTheme.font(size: 14))
                .foregroundStyle(BoardTheme.text)
                .accessibilityLabel("Search items")
        }
        .padding(.horizontal, 14)
        .frame(minWidth: 140, maxWidth: 220, minHeight: 40)
        .background(BoardTheme.raised, in: Capsule())
    }

    // MARK: - Tiles

    private func tile(_ item: ItemData) -> some View {
        let offer = Self.offer(item, for: buyer, items: items)
        let owned = buyer.items.contains(item.itemKey)
        let dimmed = offer == .soldOut || { if case .short = offer { return true } else { return false } }()
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: item.slot.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BoardTheme.brass)
                    .accessibilityHidden(true)
                TownSmallCaps(text: item.slot.displayName)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 4)
                if item.spent { badge("arrow.uturn.right", "Spent") }
                if item.consumed { badge("xmark", "Lost") }
            }
            Text(item.name)
                .font(BoardTheme.display(19))
                .foregroundStyle(BoardTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(GameText.itemRule(item, labels: gameManager.editionStore))
                .font(BoardTheme.font(size: 13))
                .foregroundStyle(BoardTheme.text.opacity(0.85))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: .infinity, alignment: .top)
            HStack {
                if pendingSale?.itemKey != item.itemKey { TownGold(amount: items.price(item), size: 14) }
                Spacer(minLength: 0)
                switch offer {
                case .sell(let amount) where pendingSale?.itemKey == item.itemKey:
                    // Selling asks first, here on the tile: Buy and Sell share a spot, so a
                    // double tap would otherwise sell what was just bought at half price.
                    Text("Sell for \(amount) gold?")
                        .font(BoardTheme.font(size: 12, weight: .semibold))
                        .foregroundStyle(BoardTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 4)
                    Button("Keep") { pendingSale = nil }
                        .buttonStyle(.boardQuietCompact)
                    Button("Sell") {
                        if items.sell(item, for: buyer) { BoardSoundPlayer.play(.loot) }
                        pendingSale = nil
                    }
                    .buttonStyle(.boardPrimaryCompact)
                    .accessibilityLabel("Sell \(item.name) for \(amount) gold")
                case .sell(let amount):
                    Button("Sell for \(amount)") { pendingSale = item }
                        .buttonStyle(.boardQuietCompact)
                case .soldOut:
                    TownSmallCaps(text: "Sold out")
                case .short(let gold):
                    Text("\(gold) more gold")
                        .font(BoardTheme.font(size: 12, weight: .medium))
                        .foregroundStyle(BoardTheme.secondaryText)
                case .buy:
                    Button("Buy") {
                        if items.buy(item, for: buyer) { BoardSoundPlayer.play(.loot) }
                    }
                    .buttonStyle(.boardPrimaryCompact)
                    .accessibilityLabel("Buy \(item.name) for \(items.price(item)) gold")
                }
            }
        }
        .padding(12)
        .frame(height: 182)
        .background(BoardTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(owned ? BoardTheme.brass : BoardTheme.border.opacity(0.45),
                                                           lineWidth: owned ? 1.5 : 1))
        .overlay(alignment: .top) {
            if owned {
                Text("OWNED")
                    .font(BoardTheme.font(size: 11, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(BoardTheme.sheet)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(BoardTheme.brass, in: Capsule())
                    .offset(y: -9)
            }
        }
        .opacity(dimmed ? 0.55 : 1)
        .accessibilityElement(children: .contain)
    }

    private func badge(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(BoardTheme.font(size: 11, weight: .semibold))
            .foregroundStyle(BoardTheme.secondaryText)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .fixedSize()
            .overlay(Capsule().stroke(BoardTheme.border, lineWidth: 1))
    }

    // MARK: - What the buyer carries

    private var carries: some View {
        let owned = buyer.items.compactMap { gameManager.editionStore.itemData(key: $0) }
        let small = ItemLoadout.smallItemLimit(level: buyer.level, carrying: buyer.carriedItems)
        let rows: [(String, [ItemSlot])] = [("Head", [.head]), ("Body", [.body]), ("Legs", [.legs]),
                                            ("Hands", [.onehand, .twohand]), ("Small", [.small])]
        return TownSection(title: "\(name(buyer)) Owns", detail: "Level \(buyer.level)") {
            ForEach(rows, id: \.0) { label, slots in
                let names = owned.filter { slots.contains($0.slot) }.map(\.name)
                HStack(alignment: .firstTextBaseline) {
                    TownSmallCaps(text: label)
                    Spacer(minLength: 8)
                    Text(names.isEmpty ? "\u{2014}" : names.joined(separator: ", "))
                        .font(BoardTheme.font(size: 13, weight: names.isEmpty ? .regular : .semibold))
                        .foregroundStyle(names.isEmpty ? BoardTheme.secondaryText : BoardTheme.text)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
            Rectangle().fill(BoardTheme.border.opacity(0.35)).frame(height: 1)
            Text("A scenario takes one head, body and legs item, two hands' worth and \(small) small item\(small == 1 ? "" : "s") at level \(buyer.level).")
                .font(BoardTheme.font(size: 12))
                .foregroundStyle(BoardTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Selling pays half the price.")
                .font(BoardTheme.font(size: 12))
                .foregroundStyle(BoardTheme.secondaryText)
        }
    }
}
