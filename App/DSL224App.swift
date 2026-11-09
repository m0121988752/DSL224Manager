import SwiftUI
import BackgroundTasks

@main
struct DSL224App: App {
    @StateObject private var service = RouterService.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: RouterService.bgTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                RouterService.shared.scheduleBackgroundRefresh()
                let ok = await RouterService.shared.loginAndRefresh()
                refreshTask.setTaskCompleted(success: ok)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(service: service)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    service.handleIncomingURL(url)
                }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                service.scheduleBackgroundRefresh()
                service.syncWidgetSnapshot()
            } else if newPhase == .active {
                service.syncWidgetSnapshot()
            }
        }
    }
}
