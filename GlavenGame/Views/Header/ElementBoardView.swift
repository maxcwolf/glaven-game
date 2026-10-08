import SwiftUI

struct ElementBoardView: View {
    @Environment(GameManager.self) private var gameManager
    /// Whether tapping an element changes its state. On the board, elements change only through
    /// abilities, so there they are display-only.
    var isEditable = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(gameManager.game.elementBoard) { element in
                ElementView(element: element, isEditable: isEditable)
            }
        }
    }
}
