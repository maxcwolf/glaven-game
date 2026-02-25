import SwiftUI

struct LogoView: View {
    let size: CGFloat
    var playable: Bool = true

    var body: some View {
        Group {
            if let image = ImageLoader.logo() {
                #if os(macOS)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                #else
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                #endif
            } else {
                Image(systemName: "gamecontroller.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }
        }
        .frame(height: size)
        .contentShape(Rectangle())
        .onTapGesture {
            if playable {
                SoundPlayer.playGlayvin()
            }
        }
    }
}
