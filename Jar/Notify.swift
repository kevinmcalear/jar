import UIKit
import UserNotifications

func postSpendNotice(person: String, sticker: String, category: String, amount: Int, left: Int) async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    if settings.authorizationStatus == .notDetermined {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }
    let content = UNMutableNotificationContent()
    content.title = person
    content.subtitle = category
    content.body = "\(formatCents(amount)) · \(formatCents(left)) left"
    content.sound = .default
    content.userInfo = ["open": "today"]
    if let image = UIImage(named: "sticker-\(sticker)"), let png = image.pngData() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sticker-\(sticker).png")
        try? png.write(to: url)
        if let attachment = try? UNNotificationAttachment(identifier: sticker, url: url) {
            content.attachments = [attachment]
        }
    }
    try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    UIApplication.shared.registerForRemoteNotifications()
}
