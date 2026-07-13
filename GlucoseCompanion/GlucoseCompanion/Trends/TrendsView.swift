import SwiftUI

/// Container for the two trend views. `AGPView`/`DayBlockBreakdownView` set
/// their own in-content headline text rather than a `navigationTitle`, since
/// they're swapped in place here (not pushed), so this view's own title stays
/// the stable "Trends" regardless of which sub-view is selected.
struct TrendsView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case agp = "AGP"
        case dayBlocks = "Day Blocks"

        var id: String { rawValue }
    }

    @State private var selection: Tab = .agp

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selection) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            switch selection {
            case .agp:
                AGPView()
            case .dayBlocks:
                DayBlockBreakdownView()
            }
        }
        .navigationTitle("Trends")
    }
}

#Preview {
    NavigationStack {
        TrendsView()
    }
}
