import SwiftUI

struct ElementBoardView: View {
    @Environment(GameManager.self) private var gameManager

    var body: some View {
        HStack(spacing: 8) {
            ForEach(gameManager.game.elementBoard) { element in
                ElementView(element: element)
            }
        }
    }
}
