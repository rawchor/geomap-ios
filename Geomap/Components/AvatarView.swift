import SwiftUI

/// Circular avatar with an initials fallback, used for both the user's own
/// marker and friend markers on the map and in the detail sheet.
struct AvatarView: View {
    let photoURL: String?
    let displayName: String
    var ringColor: Color?
    var diameter: CGFloat = 40

    var body: some View {
        Group {
            if let photoURL, let url = URL(string: photoURL) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay {
            if let ringColor {
                Circle().stroke(ringColor, lineWidth: max(3, diameter * 0.08))
            }
        }
        .padding(2)
        .background(Circle().fill(Color.white))
        .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
    }

    private var initialsView: some View {
        Circle()
            .fill(fallbackColor)
            .overlay {
                Text(initials)
                    .font(.system(size: diameter * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }

    // Stable across launches (String.hashValue is randomized per process).
    private var fallbackColor: Color {
        let palette: [Color] = [Palette.forest, Palette.olive, Palette.terracotta, Palette.blueGrey, Palette.rose, Palette.tan]
        let seed = displayName.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[seed % palette.count]
    }

    private var initials: String {
        displayName.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }
}
