import Foundation

/// A random dungeon (rulebook pp. 50–51): three rooms, each a room card's map with a monster
/// card's figures, traps, terrain and treasure on its twelve numbered hexes. The next room is
/// set up only when its door is opened, through an exit of the type (A or B) the next room's
/// entrance has: room cards whose entrance doesn't match are discarded from the top of the deck.
///
/// The game draws the whole dungeon as the scenario starts — a room behind every exit, since
/// the party may leave a room by either of two exits — and keeps the draws, so the same map is
/// built again from a save. Only the rooms the party reaches are ever revealed.
struct RandomDungeon: Codable, Equatable {
    /// A drawn room: its room card, its monster card, and the room behind each of its exits.
    struct Room: Codable, Equatable {
        /// The room card's name ("Trail").
        var room: String
        /// The monster card's index ("554").
        var monsters: String
        /// The room behind each exit of the room card, in the card's order; empty in the last room.
        var next: [Room]
        /// Which of the room card's entrances the party comes in by (or starts at).
        var entrance: Int
    }

    var first: Room
    /// How many rooms deep the dungeon goes (three).
    var depth: Int = 3

    /// The rooms on the way from the first, by the exits taken.
    func room(at path: [Int]) -> Room? {
        var room = first
        for index in path {
            guard index < room.next.count else { return nil }
            room = room.next[index]
        }
        return room
    }

    // MARK: - Drawing

    /// Draws a dungeon from shuffled decks. `roomCards` and `monsterCards` limit the decks
    /// (#55 Foggy Thicket uses six of each); nil is the whole deck.
    static func draw(rooms allRooms: [DungeonRoomCard], monsterCards allMonsters: [String],
                     roomCards: [String]? = nil, monsterCardsUsed: [String]? = nil,
                     random: inout GameRandom) -> RandomDungeon? {
        var roomDeck = allRooms.filter { card in roomCards.map { $0.contains(card.name) } ?? true }
        var monsterDeck = allMonsters.filter { monsterCardsUsed?.contains($0) ?? true }
        roomDeck.shuffle(using: &random)
        monsterDeck.shuffle(using: &random)
        guard !roomDeck.isEmpty, !monsterDeck.isEmpty else { return nil }
        var monsterDiscard: [String] = []

        func nextMonsters() -> String {
            if monsterDeck.isEmpty {
                monsterDeck = monsterDiscard.shuffled(using: &random)
                monsterDiscard = []
            }
            let card = monsterDeck.removeFirst()
            monsterDiscard.append(card)
            return card
        }

        // Every exit leads somewhere: the rooms behind both exits come from the one deck, so a
        // room card is never in the dungeon twice.
        func build(_ card: DungeonRoomCard, entrance: Int, depth: Int) -> Room {
            var room = Room(room: card.name, monsters: nextMonsters(), next: [], entrance: entrance)
            guard depth > 1 else { return room }
            for exit in card.exits {
                guard let index = roomDeck.firstIndex(where: { $0.entranceTypes.contains(exit.type) }) else { continue }
                // The cards above it don't match the exit: they are discarded.
                let next = roomDeck[index]
                roomDeck.removeFirst(index + 1)
                let way = next.entrances.firstIndex { $0.type == exit.type } ?? 0
                room.next.append(build(next, entrance: way, depth: depth - 1))
            }
            return room
        }

        let first = roomDeck.removeFirst()
        return RandomDungeon(first: build(first, entrance: 0, depth: 3))
    }
}

// MARK: - The scenario a dungeon is played as

extension RandomDungeon {
    /// Every room with its path of exits from the first, first to last.
    var allRooms: [(path: [Int], room: Room)] {
        var result: [(path: [Int], room: Room)] = []
        func walk(_ room: Room, _ path: [Int]) {
            result.append((path, room))
            for (index, next) in room.next.enumerated() { walk(next, path + [index]) }
        }
        walk(first, [])
        return result
    }

    /// The scenario data of the dungeon: `base` (the Random Dungeon, or #55 Foggy Thicket, with
    /// its rules) with the monsters of every monster card drawn and a room for each drawn room —
    /// its tile, its monsters by number, the rooms behind its exits — so the board sets up and
    /// reveals it like any scenario.
    func scenarioData(base: ScenarioData, rooms cards: [DungeonRoomCard], monsterCards: [ScenarioData]) -> ScenarioData {
        var data = base
        let drawn = allRooms
        var numbers: [[Int]: Int] = [:]
        for (number, entry) in drawn.enumerated() { numbers[entry.path] = number + 1 }
        var monsters: [String] = []
        var rooms: [RoomData] = []
        for (path, room) in drawn {
            let card = cards.first { $0.name == room.room }
            let monsterCard = monsterCards.first { $0.index == room.monsters }
            for name in monsterCard?.monsters ?? [] where !monsters.contains(name) { monsters.append(name) }
            let entranceTile = card.flatMap { $0.entrances.indices.contains(room.entrance) ? $0.entrances[room.entrance].tile : $0.tiles.first?.ref }
            rooms.append(RoomData(
                roomNumber: numbers[path] ?? 0, ref: entranceTile, initial: path.isEmpty ? true : nil, marker: nil,
                rooms: room.next.indices.compactMap { numbers[path + [$0]] }, treasures: nil,
                monster: monsterCard?.rooms?.first?.monster, allies: nil, objectives: nil))
        }
        data.monsters = monsters
        data.rooms = rooms
        return data
    }
}
