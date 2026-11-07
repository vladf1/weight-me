import SwiftUI

struct OnboardingView: View {
    @Environment(WeightStore.self) private var store
    @State private var isConnecting = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 40)
                Image(systemName: "scalemass.fill")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, value: isConnecting)
                VStack(spacing: 10) {
                    Text("Welcome to WeightMe")
                        .font(.largeTitle.bold())
                    Text("A simple, fast weight tracker built on Apple Health.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 18) {
                    feature("heart.text.square.fill", .pink, "Apple Health is the source of truth",
                            "Your full weight history, from every app and scale, in one place.")
                    feature("chart.xyaxis.line", .blue, "Graphs that tell the story",
                            "Rolling averages, a smoothed trend, goal projections, any time range.")
                    feature("lock.fill", .green, "Private",
                            "Data stays in Apple Health on your devices. Nothing is uploaded anywhere.")
                }
                .frame(maxWidth: 460)
                .padding(.horizontal)

                Button {
                    isConnecting = true
                    Task {
                        await store.connectHealth()
                        isConnecting = false
                    }
                } label: {
                    Label("Connect Apple Health", systemImage: "heart.fill")
                        .font(.headline)
                        .frame(maxWidth: 360)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isConnecting)

                VStack(spacing: 6) {
                    Text("WeightMe asks to read and write **Weight** only.")
                    Text("When asked how much data to share, choose **All Recorded Data** so your full history shows up.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                Spacer(minLength: 20)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }

    private func feature(_ symbol: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
