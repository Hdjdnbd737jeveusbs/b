import SwiftUI

// MARK: - Cast Card View (Circular Actor Portrait)

struct CastCardView: View {
    let member: TMDBCastMember

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 10) {
                // Circular profile image
                if let path = member.profilePath,
                   let url = TMDBService.shared.imageURL(path: path, size: "w185") {
                    AuraCachedImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 152, height: 152)
                            .clipShape(Circle())
                    } placeholder: {
                        castPlaceholder
                    }
                } else {
                    castPlaceholder
                }

                // Actor Name
                Text(member.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: 168)

                // Character Name
                if let character = member.character, !character.isEmpty {
                    Text(character)
                        .font(.system(size: 17))
                        .foregroundStyle(Color.auraSecondaryText)
                        .lineLimit(1)
                        .frame(width: 168)
                }
            }
            .padding(6)
            .overlay(
                Circle()
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.12), lineWidth: isFocused ? 2.5 : 1)
                    .frame(width: 154, height: 154)
                    .offset(y: -24)
            )
            .scaleEffect(isFocused ? 1.07 : 1.0)
            .animation(.easeOut(duration: 0.18), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
    }

    private var castPlaceholder: some View {
        Circle()
            .fill(Color.auraSurface)
            .frame(width: 152, height: 152)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.25))
            }
    }
}
