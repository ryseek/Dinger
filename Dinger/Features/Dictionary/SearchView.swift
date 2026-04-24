import SwiftUI

struct DictionaryRootView: View {
    @Bindable var env: AppEnvironment
    @State private var vm: DictionaryViewModel

    init(env: AppEnvironment) {
        self.env = env
        _vm = State(wrappedValue: DictionaryViewModel(
            service: env.searchService,
            historyService: env.historyService,
            pair: env.defaultPair
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                directionPicker
                content
            }
            .navigationTitle("Dictionary")
            .searchable(text: $vm.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search \(env.defaultPair.displayLabel)")
            .onChange(of: vm.query) { vm.onQueryChanged() }
            .onChange(of: vm.direction) { vm.onDirectionChanged() }
            .task { await vm.loadHistory() }
            .refreshable { await vm.loadHistory() }
        }
    }

    private var directionPicker: some View {
        Picker("Direction", selection: $vm.direction) {
            ForEach(LookupDirection.allCases, id: \.self) { dir in
                Text(dir.displayLabel).tag(dir)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var content: some View {
        if let err = vm.error {
            ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(err))
        } else if vm.query.trimmingCharacters(in: .whitespaces).isEmpty {
            historyContent
        } else if vm.results.isEmpty && !vm.isSearching {
            ContentUnavailableView.search(text: vm.query)
        } else {
            List(vm.results) { hit in
                NavigationLink {
                    EntryDetailView(env: env, hit: hit) {
                        await vm.loadHistory()
                    }
                } label: {
                    SenseRowView(hit: hit)
                }
            }
            .listStyle(.plain)
            .overlay(alignment: .top) {
                if vm.isSearching {
                    ProgressView().padding(.top, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if vm.recentSearches.isEmpty && vm.recentOpenedHits.isEmpty {
            ContentUnavailableView("Search the dictionary",
                                   systemImage: "magnifyingglass",
                                   description: Text("Type a word in German or English."))
        } else {
            List {
                if !vm.recentSearches.isEmpty {
                    Section("Recent Searches") {
                        ForEach(vm.recentSearches) { item in
                            Button {
                                vm.openSearch(item)
                            } label: {
                                HStack {
                                    Label(item.query, systemImage: "magnifyingglass")
                                    Spacer()
                                    Text(item.direction.displayLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !vm.recentOpenedHits.isEmpty {
                    Section("Opened Cards") {
                        ForEach(vm.recentOpenedHits) { hit in
                            NavigationLink {
                                EntryDetailView(env: env, hit: hit, recordHistory: false)
                            } label: {
                                SenseRowView(hit: hit)
                            }
                        }
                    }
                }

                if let err = vm.historyError {
                    Section {
                        Text(err).foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}
