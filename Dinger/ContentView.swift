import SwiftUI

struct ContentView: View {
    @State private var bootstrap = AppBootstrap()

    var body: some View {
        Group {
            switch bootstrap.state {
            case .loading:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Preparing dictionary…")
                        .foregroundStyle(.secondary)
                }
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
