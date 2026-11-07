import SwiftUI

struct OnboardingView: View {
    @Environment(WeightStore.self) private var store
    @State private var isConnecting = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 60)
                Image(systemName: "scalemass.fill")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, value: isConnecting)
                VStack(spacing: 10) {
                    Text("WeightMe")
                        .font(.largeTitle.bold())
                    Text("Log your weight and see where it's heading. Your data stays in Apple Health.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

                Button {
                    isConnecting = true
                    Task {
                        await store.connectHealth()
                        isConnecting = false
                    }
                } label: {
                    Text("Connect Apple Health")
                        .font(.headline)
                        .frame(maxWidth: 360)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isConnecting)

                Text("Next, Apple asks for access. Turn on **Weight**, and if asked, choose **All Recorded Data** to see your full history.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                Spacer(minLength: 20)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }
}
