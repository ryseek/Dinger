import SwiftUI

struct ContentView: View {
    @State private var bootstrap = AppBootstrap()

    var body: some View {
        Group {
            switch bootstrap.state {
            case .loading:
                VStack(spacing: 12) {
                    if let fraction = bootstrap.progress.fractionCompleted {
                        ProgressView(value: fraction)
                            .frame(maxWidth: 220)
                    } else {
                        ProgressView()
                    }
                    Text(bootstrap.progress.title)
                        .font(.headline)
                    if let detail = bootstrap.progress.detail {
                        Text(detail)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
                .padding()
            case .ready(let env):
                RootTabView(env: env)
            case .failed(let msg):
                ContentUnavailableView("Couldn't open database",
                                       systemImage: "xmark.octagon",
                                       description: Text(msg))
            }
        }
        .task {
            if case .loading = bootstrap.state {
                await bootstrap.load()
            }
        }
    }
}

#Preview {
    ContentView()
}
