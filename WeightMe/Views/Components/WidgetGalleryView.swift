#if DEBUG
import SwiftUI
import WidgetKit

/// Debug-only: renders every widget family at its real size with the app's current data,
/// so widget layout can be checked without adding widgets to the Home Screen.
struct WidgetGalleryView: View {
    @Environment(WeightStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let snapshot = WidgetSnapshotBuilder.make(series: store.series, unit: settings.unit, goalKg: settings.goalKg)
        let latest = snapshot.latestKg ?? 80
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Home Screen").font(.headline)
                    HStack(spacing: 20) {
                        homeTile(width: 170) { WidgetSmallView(snapshot: snapshot, latestKg: latest) }
                    }
                    homeTile(width: 364) { WidgetMediumView(snapshot: snapshot, latestKg: latest) }

                    Text("Lock Screen").font(.headline)
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 16) {
                            lockTile(width: 172, height: 76) { WidgetRectangularView(snapshot: snapshot, latestKg: latest) }
                            lockTile(width: 76, height: 76) { WidgetCircularView(snapshot: snapshot, latestKg: latest) }
                        }
                        WidgetInlineView(snapshot: snapshot, latestKg: latest)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: 24))
                    .environment(\.colorScheme, .dark)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Widget Gallery")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func homeTile(width: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(16)
            .frame(width: width, height: 170)
            .background(.background, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    private func lockTile(width: CGFloat, height: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(width: width, height: height)
            .foregroundStyle(.white)
    }
}
#endif
