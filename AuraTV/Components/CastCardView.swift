import SwiftUI

// MARK: - Cast Card View (Circular Actor Portrait)

struct CastCardView: View, Equatable {
    let member: TMDBCastMember
    var imageSize: CGFloat = 112

    @FocusState private var isFocused: Bool

    static func == (lhs: CastCardView, rhs: CastCardView) -> Bool {
        lhs.member.id == rhs.member.id &&
        lhs.member.profilePath == rhs.member.profilePath &&
        lhs.imageSize == rhs.imageSize
    }

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 10) {
                // Circular profile image
                Group {
                    if let path = member.profilePath,
                       let url = TMDBService.shared.imageURL(path: path, size: imageSize > 120 ? "w342" : "w185") {
                        AuraCachedImage(url: url, targetSize: CGSize(width: imageSize, height: imageSize)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: imageSize, height: imageSize)
                                .clipShape(Circle())
                        } placeholder: {
                            castPlaceholder
                        }
                    } else {
                        castPlaceholder
                    }
                }
                .overlay(
                    Circle()
                        .stroke(isFocused ? Color.white : Color.white.opacity(0.14), lineWidth: isFocused ? 3.5 : 1)
                )

                // Actor Name
                Text(member.name)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: max(imageSize, 148))

                // Character Name
                if let character = member.character, !character.isEmpty {
                    Text(character)
                        .font(.system(size: 18))
                        .foregroundStyle(Color.auraSecondaryText)
                        .lineLimit(1)
                        .frame(width: max(imageSize, 148))
                }
            }
            .padding(6)
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.85), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
    }

    private var castPlaceholder: some View {
        Circle()
            .fill(Color.auraSurface)
            .frame(width: imageSize, height: imageSize)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: imageSize * 0.32))
                    .foregroundStyle(.white.opacity(0.25))
            }
    }
}
