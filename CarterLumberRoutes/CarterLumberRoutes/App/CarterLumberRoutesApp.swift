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
        }
    }
}
