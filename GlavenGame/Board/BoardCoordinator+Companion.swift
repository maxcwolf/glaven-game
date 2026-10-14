import Foundation

/// A class's companion: a summon it starts every scenario with (the Beast Tyrant's bear, the
/// class data's summon marked `special`). It is set up beside the character once the party is
/// placed, acts as a summon each round, can't be summoned again once it is gone, and performs
/// the character's Command halves (`PlayerTurnController.commandedFigure`).
extension BoardCoordinator {

    func companionData(of character: GameCharacter) -> SummonDataModel? {
        character.characterData?.availableSummons?.first { $0.special == true }
    }

    /// The companion this scenario, alive or dead.
    func companion(of character: GameCharacter) -> GameSummon? {
        guard let data = companionData(of: character) else { return nil }
        return character.summons.first { $0.cardId == (data.cardId ?? "") }
    }

    /// The companion's piece, while it is on the board.
    func companionPiece(of character: GameCharacter) -> PieceID? {
        guard let bear = companion(of: character), !bear.dead else { return nil }
        let piece = PieceID.summon(id: bear.id)
        return boardState.piecePositions[piece] != nil ? piece : nil
    }

    /// Set up each companion not yet made this scenario beside its character — the player
    /// tapping the hex, or, headless, the first free one — then go on.
    func setUpCompanions(then go: @escaping () -> Void) {
        guard let gameManager,
              let character = gameManager.game.characters.first(where: { character in
                  !character.absent && !character.exhausted && companionData(of: character) != nil && companion(of: character) == nil
                      && boardState.piecePositions[.character(character.id)] != nil
              }),
              let data = companionData(of: character), let here = boardState.piecePositions[.character(character.id)] else {
            go()
            return
        }
        var options = boardState.neighbors(of: here).filter(isEmptyHex).sorted()
        if options.isEmpty, let near = nearestEmptyHex(to: here) { options = [near] }
        func place(_ hex: HexCoord?) {
            gameManager.characterManager.addSummon(from: data, for: character)
            guard let bear = character.summons.last else { return go() }
            bear.name = "bear"
            bear.state = .active   // it acts from the first round
            if let hex {
                let piece = PieceID.summon(id: bear.id)
                boardState.placePiece(piece, at: hex)
                boardScene?.addPieceSprite(id: piece, at: hex, offsetCol: offsetCol, offsetRow: offsetRow)
                log("\(characterName(character.id))\u{2019}s \(name(piece)) is set up", category: .setup, trace: "at \(hex)")
            }
            setUpCompanions(then: go)
        }
        guard options.count > 1, !autoResolvePrompts else { return place(options.first) }
        let generation = boardGeneration
        Task { @MainActor in
            let hex = await self.chooseHex(options, for: .character(character.id), title: "The bear",
                                           detail: "Tap the hex beside \(self.characterName(character.id)) where the bear starts")
            guard self.isCurrentBoard(generation) else { return }
            place(hex ?? options.first)
        }
    }
}
