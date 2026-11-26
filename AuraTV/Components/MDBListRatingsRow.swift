import SwiftUI

// MARK: - MDBList Multi-Source Ratings Badges

struct MDBListRatingsRow: View {
    let ratings: MDBListRatingsSummary

    var body: some View {
        if !ratings.isEmpty {
            HStack(spacing: 10) {
                if let imdb = ratings.imdb {
                    ratingPill(
                        label: "IMDb",
                        value: String(format: "%.1f", imdb),
                        accent: Color(red: 245 / 255, green: 197 / 255, blue: 24 / 255)
                    )
                }

                if let rt = ratings.rottenTomatoes {
                    ratingPill(
                        label: "RT",
                        value: "\(rt)%",
                        accent: Color(red: 250 / 255, green: 50 / 255, blue: 58 / 255)
                    )
                }

                if let mc = ratings.metacritic {
                    ratingPill(
                        label: "MC",
                        value: "\(mc)",
                        accent: Color(red: 102 / 255, green: 204 / 255, blue: 51 / 255)
                    )
                }

                if let lb = ratings.letterboxd {
                    ratingPill(
                        label: "LB",
                        value: String(format: "%.1f", lb),
                        accent: Color(red: 0 / 255, green: 224 / 255, blue: 84 / 255)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func ratingPill(label: String, value: String, accent: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11.5, weight: .heavy))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(accent, in: RoundedRectangle(cornerRadius: 4))

            Text(value)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .padding(.leading, 3)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}
