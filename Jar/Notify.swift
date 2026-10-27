import UIKit
import UserNotifications

struct SpendNotice {
    var person: String
    var sticker: String
    var category: String
    var amount: Int
    var left: Int
}

func postSpendNotice(_ notice: SpendNotice) async {
    let content = UNMutableNotificationContent()
    content.title = notice.person
    content.subtitle = notice.category
    content.body = "\(formatCents(notice.amount)) · \(formatCents(notice.left)) left"
    content.sound = .default
    content.userInfo = ["open": "today"]
    if let image = UIImage(named: "sticker-\(notice.sticker)"), let png = image.pngData() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sticker-\(notice.sticker)-\(UUID().uuidString).png")
        try? png.write(to: url)
        if let attachment = try? UNNotificationAttachment(identifier: notice.sticker, url: url) {
            content.attachments = [attachment]
        }
    }
    try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
}
