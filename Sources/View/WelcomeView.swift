import SwiftUI

struct WelcomeView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 60)

                // Mark
                Image(systemName: "camera.aperture")
                    .font(.system(size: 48, weight: .thin))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)

                Text("Picshurs")
                    .font(.custom("Comic Sans MS", size: 34).weight(.semibold))
                    .padding(.bottom, 6)

                Text("Local-first photo organizer")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 36)

                // Philosophy
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(
                        icon: "externaldrive.fill",
                        title: "Your files stay yours",
                        detail: "No cloud sync, no hidden database. Picshurs reads your folders in place."
                    )
                    FeatureRow(
                        icon: "pin.fill",
                        title: "The Tray",
                        detail: "Pin, reorder, and batch-export a curated set. Your staging area."
                    )
                    FeatureRow(
                        icon: "slider.horizontal.3",
                        title: "Non-destructive editing",
                        detail: "Adjust, crop, straighten \u{2014} originals are never touched unless you do so."
                    )
                }
                .padding(20)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: 420)
                .padding(.bottom, 32)

                // CTA
                Button {
                    viewModel.openFolder()
                } label: {
                    Label("Open Folder", systemImage: "folder.badge.plus")
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("or drag a folder onto the sidebar")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
                    .padding(.top, 8)

                Spacer(minLength: 60)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: — Subviews

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
    }
}


#Preview {
    WelcomeView()
        .environment(AppViewModel(settings: AppSettings()))
}
