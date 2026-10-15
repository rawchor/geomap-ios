import SwiftUI

/// "Uncovers" a combined map bubble — lists the people it was standing in
/// for, letting the user pick one to open their real detail view.
struct ClusterMembersView: View {
    let members: [MapPerson]
    let onSelect: (MapPerson) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(members) { person in
                Button {
                    onSelect(person)
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(
                            photoURL: person.photoURL,
                            displayName: person.displayName,
                            ringColor: person.ringColor,
                            diameter: 44
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.isSelf ? "\(person.displayName) (You)" : person.displayName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            if let statusText = person.statusText {
                                Text(statusText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Nearby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
