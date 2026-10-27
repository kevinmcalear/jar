import UIKit
import UserNotifications

struct SpendNotice {
    var person: String
    var sticker: String?
    var category: String
    var amount: Int
    var left: Int
    var note: String?
    var photo: Data?
    var removed: Bool = false
}

func postSpendNotice(_ notice: SpendNotice) async {
    let content = UNMutableNotificationContent()
    content.title = notice.person
    content.subtitle = notice.category
    content.body = spendNoticeBody(amount: notice.amount, note: notice.note, left: notice.left, removed: notice.removed)
    content.sound = .default
    content.userInfo = ["open": "today"]
    if let photo = notice.photo, let attachment = noticeAttachment(photo, name: "spend") {
        content.attachments = [attachment]
    } else if let sticker = notice.sticker, let image = UIImage(named: "sticker-\(sticker)"), let png = image.pngData(), let attachment = noticeAttachment(png, name: sticker) {
        content.attachments = [attachment]
    }
    try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
}

private func noticeAttachment(_ data: Data, name: String) -> UNNotificationAttachment? {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).png")
    guard (try? data.write(to: url)) != nil else { return nil }
    return try? UNNotificationAttachment(identifier: name, url: url)
}
