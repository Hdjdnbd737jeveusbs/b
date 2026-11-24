import SwiftUI

// MARK: - Cast Card View

struct CastCardView: View {
    let member: TMDBCastMember

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 8) {
                // Profile image
                if let path = member.profilePath,
                   let url = TMDBService.shared.imageURL(path: path, size: "w185") {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 120, height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        case .failure, .empty:
                            castPlaceholder
                        @unknown default:
                            castPlaceholder
                        }
                    }
                } else {
                    castPlaceholder
                }

                // Actor Name
                Text(member.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: 120)

                // Character Name
                if let character = member.character, !character.isEmpty {
                    Text(character)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.auraSecondaryText)
                        .lineLimit(1)
                        .frame(width: 120)
                }
            }
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .shadow(color: isFocused ? Color.auraAccent.opacity(0.4) : .clear, radius: 14, y: 6)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
    }

    private var castPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.auraSurface)
            .frame(width: 120, height: 160)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.25))
            }
    }
}
