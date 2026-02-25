import SwiftUI

struct WelcomeView: View {
    @Environment(GameManager.self) private var gameManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                LogoView(size: 220)

                Text("Glaven")
                    .font(GlavenFont.title(size: 64))
                    .foregroundStyle(GlavenTheme.primaryText)
                    .padding(.top, -12)

                Text("Select an Edition")
                    .font(.title2)
                    .foregroundStyle(GlavenTheme.secondaryText)

                VStack(spacing: 12) {
                    ForEach(gameManager.editionStore.editions) { edition in
                        Button {
                            gameManager.setEdition(edition.edition)
                        } label: {
                            HStack {
                                Text(edition.displayName)
                                    .font(GlavenFont.title(size: 22))
                                    .foregroundStyle(GlavenTheme.primaryText)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(GlavenTheme.secondaryText)
                            }
                            .padding()
                            .background(GlavenTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 40)
            .background(GlavenTheme.background)
            .navigationTitle("New Game")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}
