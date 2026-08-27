import SwiftUI

enum HarborTheme {
    // Harbor desktop palette: layered dark blues + amber accent (oklch 0.78 0.13 60)
    static let background = Color(red: 21 / 255, green: 22 / 255, blue: 26 / 255)
    static let raised = Color(red: 29 / 255, green: 30 / 255, blue: 36 / 255)
    static let card = Color(red: 37 / 255, green: 38 / 255, blue: 46 / 255)
    static let accent = Color(red: 233 / 255, green: 197 / 255, blue: 94 / 255)
    static let accentSoft = Color(red: 233 / 255, green: 197 / 255, blue: 94 / 255).opacity(0.18)
    static let success = Color(red: 76 / 255, green: 195 / 255, blue: 138 / 255)
    static let danger = Color(red: 229 / 255, green: 72 / 255, blue: 77 / 255)
    static let ink = Color.white
    static let secondaryText = Color.white.opacity(0.72)
    static let subtleText = Color.white.opacity(0.54)
    static let border = Color.white.opacity(0.12)
    static let onAccent = Color(red: 26 / 255, green: 21 / 255, blue: 3 / 255)
    static let cornerRadius: CGFloat = 18
}

struct HarborCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(HarborTheme.card, in: RoundedRectangle(cornerRadius: HarborTheme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: HarborTheme.cornerRadius)
                    .stroke(HarborTheme.border, lineWidth: 1)
            }
    }
}

struct HarborAsyncImage: View {
    let urlString: String?
    let contentMode: ContentMode

    init(_ urlString: String?, contentMode: ContentMode = .fill) {
        self.urlString = urlString
        self.contentMode = contentMode
    }

    var body: some View {
        AsyncImage(url: urlString.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .empty:
                ZStack {
                    HarborTheme.raised
                    ProgressView().tint(HarborTheme.accent)
                }
            case .failure:
                ZStack {
                    HarborTheme.raised
                    Image(systemName: "film.stack").foregroundStyle(HarborTheme.secondaryText)
                }
            @unknown default:
                HarborTheme.raised
            }
        }
    }
}

extension View {
    func harborBackground() -> some View {
        background(
            ZStack {
                HarborTheme.background
                RadialGradient(
                    colors: [HarborTheme.accent.opacity(0.08), .clear],
                    center: .init(x: 0.2, y: -0.1),
                    startRadius: 0,
                    endRadius: 420
                )
            }
            .ignoresSafeArea()
        )
    }
}
