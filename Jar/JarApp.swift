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

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        let metadata = metadata
        Task { @MainActor in
            guard let model else { return }
            do {
                _ = try await model.sync.container.accept(metadata)
                var settings = model.snapshot.settings ?? HouseholdSettings(
                    timezone: TimeZone.current.identifier, closeHour: 4, usualCap: 5000, usualCapChangedAt: stamp(),
                    usualCapSetBy: nil, savingsGoal: nil, kdfSalt: nil, kdfIterations: nil, verifier: nil, holderID: nil,
                    isOwner: false, zoneOwner: metadata.share.recordID.zoneID.ownerName
                )
                settings.isOwner = false
                settings.zoneOwner = metadata.share.recordID.zoneID.ownerName
                try model.store?.insertSettings(settings)
                model.reload()
                model.sync.start()
                await model.sync.fetch()
                await model.flushNotices()
                model.markNoticesLive()
            } catch {
                model.shareError = error.localizedDescription
            }
        }
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        // The push only says an entry changed. The amount is not in this payload.
        _ = userInfo.count
        let appModel = model ?? Self.held
        let ready = await appModel?.receiveRemoteChange() ?? false
        if application.applicationState != .active { appModel?.lock() }
        return ready ? .newData : .noData
    }
}
