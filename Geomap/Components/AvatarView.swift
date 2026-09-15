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
                Circle().stroke(ringColor, lineWidth: max(2, diameter * 0.06))
            }
        }
    }

    private var initialsView: some View {
        Circle()
            .fill(Color.gray.opacity(0.5))
            .overlay {
                Text(initials)
                    .font(.system(size: diameter * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }

    private var initials: String {
        displayName.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }
}
