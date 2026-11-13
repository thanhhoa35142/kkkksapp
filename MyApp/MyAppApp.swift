import SwiftData
import SwiftUI

@main
struct MyAppApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    @State private var appState = AppState()

    /// One store for every scene; in-memory with seeded favorites in UI tests.
    private static let modelContainer: ModelContainer = {
        if let fixture = UITestFixtures.makeModelContainer() { return fixture }
        do {
            return try ModelContainer(for: FavoriteSpot.self)
        } catch {
            fatalError("SwiftData store failed to open: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .task { await appState.bootstrap() }
                #if os(macOS)
                // UI_SPEC §10.4: Mac window minimum 960×640.
                .frame(minWidth: 960, minHeight: 640)
                #endif
        }
        .modelContainer(Self.modelContainer)
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .commands { PickhourCommands(app: appState) }
        #endif

        #if os(macOS)
        Settings {
            NavigationStack { SettingsScreen() }
                .environment(appState)
                .frame(width: 520, height: 620)
        }
        .modelContainer(Self.modelContainer)
        #endif
    }
}

#if os(macOS)
/// Menu bar commands (UI_SPEC §10.4).
struct PickhourCommands: Commands {
    let app: AppState

    var body: some Commands {
        CommandMenu("Go") {
            Button("Now") { app.select(when: .now) }
                .keyboardShortcut("0", modifiers: .command)
            Button("Next Hour") { app.select(when: .at(app.when.resolved.addingTimeInterval(3600))) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Previous Hour") {
                let previous = app.when.resolved.addingTimeInterval(-3600)
                app.select(when: previous <= Date.now.startOfHour ? .now : .at(previous))
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
        }
    }
}
#endif
