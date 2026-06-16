import SwiftUI

struct EditTabPicker: View {
    @Binding var selectedTab: EditTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(EditTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    Image(systemName: tab.iconName)
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            selectedTab == tab
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear
                        )
                        .cornerRadius(6)
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(tab.label)
            }
        }
        .padding(3)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
    }
}
