import SwiftUI

public struct RootTabView: View {
    @Bindable var env: AppEnvironment

    public init(env: AppEnvironment) {
        self.env = env
    }

    public var body: some View {
        TabView {
            DictionaryRootView(env: env)
                .tabItem { Label("Dictionary", systemImage: "book") }

            CardsRootView(env: env)
                .tabItem { Label("Cards", systemImage: "rectangle.stack") }

            QuizRootView(env: env)
                .tabItem { Label("Quiz", systemImage: "graduationcap") }
        }
    }
}
