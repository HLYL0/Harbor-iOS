import SwiftUI

enum HarborTheme {
    static let background = Color(red: 0.035, green: 0.045, blue: 0.065)
    static let raised = Color(red: 0.075, green: 0.09, blue: 0.12)
    static let card = Color(red: 0.105, green: 0.12, blue: 0.15)
    static let accent = Color(red: 0.24, green: 0.78, blue: 0.82)
    static let secondaryText = Color.white.opacity(0.68)
    static let border = Color.white.opacity(0.10)
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
