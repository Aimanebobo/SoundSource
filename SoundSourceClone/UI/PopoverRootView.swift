import SwiftUI

/// The whole panel: header, scrollable System + Applications sections, bottom bar.
/// Its ideal height reaches the window through NSHostingController.preferredContentSize.
struct PopoverRootView: View {
    @Environment(AudioEngine.self) private var engine
    @Environment(PanelState.self) private var panel
    @State private var scrollContentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Hairline()
            sections
            Hairline()
            BottomBarView()
        }
        .frame(width: Theme.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var sections: some View {
        let content = VStack(spacing: 0) {
            SystemSectionView()
            Hairline().padding(.horizontal, 12)
            ApplicationsSectionView()
        }
        .padding(.vertical, 4)

        if panel.isSnapshot {
            content   // ImageRenderer can't draw an NSScrollView
        } else {
            ScrollView(.vertical) {
                content.onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    scrollContentHeight = height
                }
            }
            .scrollIndicators(.automatic)
            .frame(height: min(max(scrollContentHeight, 1), panel.maxScrollHeight))
        }
    }
}

#Preview {
    PopoverRootView()
        .environment(AudioEngine(preview: true))
        .environment(PanelState())
        .background(Theme.snapshotBackground)
}
