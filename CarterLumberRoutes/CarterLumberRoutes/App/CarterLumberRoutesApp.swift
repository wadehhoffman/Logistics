import SwiftUI

@main
struct CarterLumberRoutesApp: App {
    @State private var locationStore = LocationDataStore()
    @State private var appConfig = AppConfiguration()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(locationStore)
                .environment(appConfig)
                .task {
                    // Background refresh of Mills/Yards from server on launch.
                    // Cache from previous session has already loaded synchronously,
                    // so the UI is up before this completes.
                    await locationStore.refresh(serverBaseURL: appConfig.intelliShiftBaseURL)
                }
        }
    }
}
