import CloudKit
import SwiftUI
import UIKit
import UserNotifications

@main
struct JarApp: App {
    @UIApplicationDelegateAdaptor(JarDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        JarDelegate.held = model
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onAppear { delegate.model = model }
        }
    }
}

@MainActor
final class JarDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var held: AppModel?
    weak var model: AppModel?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        Task { await askNotifications(application) }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        (model ?? Self.held)?.tab = "today"
    }

    private func askNotifications(_ application: UIApplication) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        application.registerForRemoteNotifications()
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // SwiftUI is scene-based. The app-delegate share callback is not invoked; the scene delegate is.
        if let metadata = options.cloudKitShareMetadata {
            Self.accept(metadata)
        }
        for context in options.urlContexts where isCloudKitShareURL(context.url) {
            Self.accept(url: context.url)
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = JarSceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Self.accept(metadata)
    }

    static func accept(_ metadata: CKShare.Metadata) {
        let metadata = metadata
        Task { @MainActor in
            guard let model = JarDelegate.held else { return }
            await model.acceptShare(metadata)
        }
    }

    static func accept(url: URL) {
        guard isCloudKitShareURL(url) else { return }
        Task { @MainActor in
            guard let model = JarDelegate.held else { return }
            await model.acceptShare(url: url)
        }
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        // The push only says an entry changed. The amount is not in this payload.
        _ = userInfo.count
        let ready = await (model ?? Self.held)?.receiveRemoteChange() ?? false
        return ready ? .newData : .noData
    }
}

@MainActor
final class JarSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            JarDelegate.accept(metadata)
        }
        for context in connectionOptions.urlContexts where isCloudKitShareURL(context.url) {
            JarDelegate.accept(url: context.url)
        }
        for activity in connectionOptions.userActivities {
            guard let url = activity.webpageURL, isCloudKitShareURL(url) else { continue }
            JarDelegate.accept(url: url)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        JarDelegate.accept(cloudKitShareMetadata)
    }
}
