import SwiftUI

// MARK: - Shared rail components (Harbor parity: home/rooms rails, ranked rows, CW cards).

struct PosterCard: View {
    let item: StremioMeta
    var width: CGFloat = 108

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottomLeading) {
                HarborAsyncImage(item.poster)
                    .frame(width: width, height: width * 1.48)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                if let rating = item.imdbRating {
                    Text("★ \(rating)")
                        .font(.system(size: 9.5, weight: .heavy))
                        .foregroundStyle(HarborTheme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 7))
                        .padding(6)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(HarborTheme.border, lineWidth: 1))
            Text(item.name)
                .font(.caption)
                .foregroundStyle(HarborTheme.secondaryText)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
        .frame(width: width)
    }
}

struct PosterRail: View {
    let title: String
    let items: [StremioMeta]
    var width: CGFloat = 108

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(HarborTheme.ink)
                Text("\(items.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HarborTheme.subtleText)
            }
            .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 13) {
                    ForEach(items) { item in
                        NavigationLink(value: item) { PosterCard(item: item, width: width) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

/// Harbor's Top-10 style ranked row (big number + poster).
struct RankedRail: View {
    let title: String
    let items: [StremioMeta]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(HarborTheme.ink)
            }
            .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(items.prefix(10).enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: item) {
                            HStack(alignment: .bottom, spacing: -14) {
                                Text("\(index + 1)")
                                    .font(.system(size: 88, weight: .black))
                                    .foregroundStyle(HarborTheme.ink.opacity(0.9))
                                    .frame(width: 44, alignment: .trailing)
                                PosterCard(item: item, width: 96)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

/// Continue-watching card with progress bar (resume semantics from ResumeStore).
struct ContinueWatchingCard: View {
    let item: StremioMeta
    let progress: Double   // 0...1

    var body: some View {
        NavigationLink(value: item) {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .bottom) {
                    HarborAsyncImage(item.poster)
                        .frame(width: 160, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            HarborTheme.raised.opacity(0.6)
                            HarborTheme.accent
                                .frame(width: geo.size.width * min(max(progress, 0), 1))
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 5)
                }
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(HarborTheme.border, lineWidth: 1))
                Text(item.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HarborTheme.ink)
                    .lineLimit(1)
                    .frame(width: 160, alignment: .leading)
                Text("\(Int(progress * 100))% watched")
                    .font(.caption2)
                    .foregroundStyle(HarborTheme.subtleText)
            }
            .frame(width: 160)
        }
        .buttonStyle(.plain)
    }
}

struct HeroCarousel: View {
    let items: [StremioMeta]
    @State private var index = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TabView(selection: $index) {
                ForEach(Array(items.prefix(4).enumerated()), id: \.element.id) { position, item in
                    HeroSlide(item: item, rank: position + 1)
                        .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 352)

            HStack(spacing: 6) {
                ForEach(0..<min(items.count, 4), id: \.self) { dot in
                    Capsule()
                        .fill(dot == index ? HarborTheme.accent : HarborTheme.border)
                        .frame(width: dot == index ? 18 : 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.2), value: index)
        }
    }
}

struct HeroSlide: View {
    let item: StremioMeta
    let rank: Int

    var body: some View {
        NavigationLink(value: item) {
            ZStack(alignment: .bottomLeading) {
                HarborAsyncImage(item.background ?? item.poster)
                    .frame(height: 352)
                    .clipped()
                LinearGradient(
                    colors: [.clear, HarborTheme.background.opacity(0.55), HarborTheme.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Text("#\(rank) TRENDING")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(HarborTheme.onAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(HarborTheme.accent, in: RoundedRectangle(cornerRadius: 8))
                        if let rating = item.imdbRating {
                            Label(rating, systemImage: "star.fill")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(HarborTheme.accent)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(HarborTheme.accentSoft, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    Text(item.name)
                        .font(.system(size: 25, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 10) {
                        if let release = item.releaseInfo {
                            Text(release.prefix(4))
                        }
                        if let genres = item.genres {
                            Text(genres.prefix(2).joined(separator: " · "))
                        }
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HarborTheme.secondaryText)
                }
                .padding(16)
            }
            .frame(height: 352)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(HarborTheme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}
