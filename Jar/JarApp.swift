import CloudKit
import SwiftUI
import UIKit

@main
struct JarApp: App {
    @UIApplicationDelegateAdaptor(JarDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onAppear { delegate.model = model }
        }
    }
}

@MainActor
final class JarDelegate: NSObject, UIApplicationDelegate {
    weak var model: AppModel?

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
            } catch {
                model.shareError = error.localizedDescription
            }
        }
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        _ = userInfo.count
        await model?.sync.fetch()
        return .newData
    }
}
