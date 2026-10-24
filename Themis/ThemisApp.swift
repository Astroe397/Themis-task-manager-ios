import SwiftUI
import SwiftData

@main
struct ThemisApp: App {
    private let container: ModelContainer
    @StateObject private var store: AppStore
    @StateObject private var tracking = TrackingManager()
    @StateObject private var meditation = MeditationModel()

    @MainActor
    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Schema(allModelTypes))
        } catch {
            fatalError("Could not open the Themis database: \(error)")
        }
        self.container = container
        _store = StateObject(wrappedValue: AppStore(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            ThemisRoot()
                .environmentObject(store)
                .environmentObject(tracking)
                .environmentObject(meditation)
                .modelContainer(container)
                .preferredColorScheme(store.darkTheme ? .dark : .light)
                .onAppear {
                    tracking.configure(context: container.mainContext)
                    tracking.onFinished = { [weak store] in store?.requestSync() }
                    meditation.configure(context: container.mainContext)
                }
        }
    }
}
