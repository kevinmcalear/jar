import CloudKit
import SwiftUI
import UIKit

struct AddSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step = JarLogStep.category
    @State private var typed = ""
    @State private var categoryID: String?
    @State private var showCamera = false
    @State private var naming = false
    @State private var newName = ""
    @State private var working = false
    @State private var saving = false
    @State private var note = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .category: categoryStep
                case .amount: amountStep
                case .photo: photoStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(20)
            .background(Flare.ground.ignoresSafeArea())
            .navigationTitle("Add something")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .category ? "Cancel" : "Back") {
                        if step == .category { dismiss() } else { back() }
                    }
                }
                if step == .amount {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Next") {
                            if let next = nextJarStep(.amount, tookPhoto: false) { step = next }
                        }
                        .disabled(cents(typed: typed) <= 0)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showCamera) {
            CameraPicker { data in
                guard let data else { return }
                working = true
                Task { @MainActor in
                    finish(photo: stickerPNG(data) ?? data)
                }
            }
        }
    }

    private var categoryStep: some View {
        VStack(spacing: 16) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                    ForEach(model.snapshot.categories.filter(\.enabled)) { category in
                        Button {
                            categoryID = category.id
                            if let next = nextJarStep(.category, tookPhoto: false) { step = next }
                        } label: {
                            VStack(spacing: 6) {
                                CategoryMark(builtIn: category.builtIn, name: category.name, size: 56)
                                Text(category.name)
                                    .font(.caption)
                                    .foregroundStyle(Flare.paper)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 96)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if naming {
                TextField("Name", text: $newName)
                    .font(.title3)
                    .foregroundStyle(Flare.paper)
                    .padding(12)
                    .background(Flare.surface, in: RoundedRectangle(cornerRadius: 12))
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit(addOwn)
                Button("Add", action: addOwn)
                    .font(.headline)
                    .foregroundStyle(Flare.ground)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Flare.flare, in: RoundedRectangle(cornerRadius: 16))
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Button("Add your own") {
                    naming = true
                    nameFocused = true
                }
                .font(.headline)
                .foregroundStyle(Flare.paper)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Flare.surface, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var amountStep: some View {
        VStack(spacing: 16) {
            Text(typed.isEmpty ? "$0" : "$\(typed)")
                .font(Flare.number(64))
                .foregroundStyle(Flare.paper)
                .frame(maxWidth: .infinity)
            MoneyPad(typed: $typed)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var photoStep: some View {
        VStack(spacing: 16) {
            TextField("Add a note", text: $note)
                .font(.title3)
                .foregroundStyle(Flare.paper)
                .padding(12)
                .background(Flare.surface, in: RoundedRectangle(cornerRadius: 12))
                .submitLabel(.done)
            Button {
                showCamera = UIImagePickerController.isSourceTypeAvailable(.camera)
            } label: {
                cameraGlass
            }
            .buttonStyle(.plain)
            .disabled(working || saving || !UIImagePickerController.isSourceTypeAvailable(.camera))
            Button(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Skip" : "Save") { finish(photo: nil) }
                .font(.headline)
                .foregroundStyle(Flare.muted)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(working || saving)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var cameraGlass: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Flare.surface)
            FinderCorners()
                .stroke(Flare.paper, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .padding(28)
            VStack(spacing: 18) {
                if working {
                    ProgressView().tint(Flare.paper)
                    Text("Cutting the sticker")
                        .font(.headline)
                        .foregroundStyle(Flare.paper)
                } else {
                    Text("Take a photo")
                        .font(.headline)
                        .foregroundStyle(Flare.paper)
                    ZStack {
                        Circle().stroke(Flare.paper, lineWidth: 4)
                        Circle().fill(Flare.flare).padding(7)
                    }
                    .frame(width: 78, height: 78)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Flare.line, lineWidth: 1))
        .accessibilityLabel("Take a photo")
    }

    private func back() {
        switch step {
        case .amount: step = .category
        case .photo: step = .amount
        case .category: break
        }
    }

    private func addOwn() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.addCategory(name: trimmed)
        newName = ""
        naming = false
    }

    private func finish(photo: Data?) {
        guard let categoryID, cents(typed: typed) > 0, !saving else { return }
        saving = true
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        model.logJar(amount: cents(typed: typed), categoryID: categoryID, photo: photo, note: trimmed.isEmpty ? nil : trimmed, day: model.addDay)
        dismiss()
    }
}

struct OutsideSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var chip = Chip.groceries
    @State private var typed = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
                    ForEach(Chip.allCases) { item in
                        Button(item.title) { chip = item }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(chip == item ? Flare.ground : Flare.paper)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(chip == item ? Flare.paper : Flare.surface, in: Capsule())
                    }
                }
                Text(typed.isEmpty ? "$0" : "$\(typed)")
                    .font(Flare.number(64))
                    .foregroundStyle(Flare.paper)
                    .frame(maxWidth: .infinity)
                MoneyPad(typed: $typed)
                Button("Done") {
                    model.logOutside(amount: cents(typed: typed), chip: chip, rhythm: chip.defaultRhythm, note: "", day: model.openDate)
                    dismiss()
                }
                .font(.headline)
                .foregroundStyle(Flare.ground)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Flare.paper, in: RoundedRectangle(cornerRadius: 16))
                .disabled(cents(typed: typed) <= 0)
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Flare.ground.ignoresSafeArea())
            .navigationTitle("Outside")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct SettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var capText = ""
    @State private var goalText = ""
    @State private var newCategory = ""
    @State private var zoneQuery = ""
    @State private var inviting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("This phone").font(.headline).foregroundStyle(Flare.muted)
                    HStack(spacing: 16) {
                        ForEach(model.snapshot.people) { person in
                            Button { model.setHolder(person.id) } label: {
                                VStack {
                                    PersonSticker(sticker: person.sticker, name: person.displayName, size: 72)
                                        .overlay(Circle().stroke(model.holder?.id == person.id ? Flare.flare : Color.clear, lineWidth: 3))
                                    Text(person.displayName).foregroundStyle(Flare.paper)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    field("Usual daily cap", text: $capText, hint: "Starts tomorrow. Today stays \(formatCents(model.todayCap)).") { text in
                        let amount = cents(typed: text)
                        if !text.isEmpty, amount >= 0 { model.setUsualCap(amount) }
                    }
                    field("Savings goal", text: $goalText, hint: "Shown on Year. Leave it empty for none.") { text in
                        model.setGoal(text.isEmpty ? nil : cents(typed: text))
                    }
                    Stepper("Ends at \(closeClock(model.snapshot.settings?.closeHour ?? 4))", value: closeHour, in: 0...23)
                        .foregroundStyle(Flare.paper)
                    NavigationLink("Home timezone") {
                        List(filteredZones, id: \.self) { zone in
                            Button(zone) { model.setTimezone(zone) }
                                .foregroundStyle(zone == model.snapshot.settings?.timezone ? Flare.flare : Flare.paper)
                        }
                        .searchable(text: $zoneQuery)
                        .navigationTitle("Timezone")
                    }
                    .foregroundStyle(Flare.paper)
                    Text(model.snapshot.settings?.timezone ?? "")
                        .font(.caption)
                        .foregroundStyle(Flare.muted)
                    Text("Today's jar").font(.headline).foregroundStyle(Flare.muted)
                    Text("These come off today's pile. Groceries stay outside.")
                        .font(.subheadline)
                        .foregroundStyle(Flare.muted)
                    ForEach(model.snapshot.categories) { category in
                        HStack {
                            CategoryMark(builtIn: category.builtIn, name: category.name)
                            Text(category.name).foregroundStyle(Flare.paper)
                            Spacer()
                            Toggle(category.name, isOn: enabled(category))
                                .labelsHidden()
                        }
                    }
                    HStack {
                        TextField("Add a category", text: $newCategory)
                            .foregroundStyle(Flare.paper)
                        Button("Add") {
                            model.addCategory(name: newCategory)
                            newCategory = ""
                        }
                        .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(12)
                    .background(Flare.surface, in: RoundedRectangle(cornerRadius: 12))
                    Button {
                        Task { await sendInvite() }
                    } label: {
                        Text(inviting ? "Creating the invite…" : "Invite the other phone")
                            .font(.headline)
                            .foregroundStyle(Flare.ground)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Flare.flare, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(inviting)
                    if let error = model.shareError {
                        Text(error).font(.caption).foregroundStyle(Flare.flare)
                    }
                }
                .padding(20)
            }
            .background(Flare.ground.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                capText = dollarText(model.snapshot.settings?.usualCap ?? 5000)
                goalText = model.snapshot.settings?.savingsGoal.map(dollarText) ?? ""
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var closeHour: Binding<Int> {
        Binding {
            model.snapshot.settings?.closeHour ?? 4
        } set: { model.setCloseHour($0) }
    }

    private var filteredZones: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers
        guard !zoneQuery.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(zoneQuery) }
    }

    private func sendInvite() async {
        inviting = true
        model.shareError = nil
        model.suspendLock = true
        defer { inviting = false }
        do {
            presentLink(try await model.sync.inviteLink())
        } catch {
            model.suspendLock = false
            model.shareError = inviteFailureText(error)
        }
    }

    private func presentLink(_ url: URL) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let root = scene?.keyWindow?.rootViewController else {
            model.suspendLock = false
            model.shareError = "Could not open the share sheet."
            return
        }
        var top = root
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in
                model.suspendLock = false
            }
        }
        top.present(sheet, animated: true)
    }

    private func enabled(_ category: JarCategory) -> Binding<Bool> {
        Binding {
            model.snapshot.categories.first { $0.id == category.id }?.enabled ?? false
        } set: { model.setCategory(category.id, enabled: $0) }
    }

    private func field(_ title: String, text: Binding<String>, hint: String, commit: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(Flare.muted)
            TextField("0", text: text)
                .font(Flare.number(40))
                .foregroundStyle(Flare.paper)
                .keyboardType(.decimalPad)
                .onChange(of: text.wrappedValue) { _, new in commit(new) }
            Text(hint).font(.subheadline).foregroundStyle(Flare.muted)
        }
    }

    private func dollarText(_ cents: Int) -> String {
        cents.isMultiple(of: 100) ? String(cents / 100) : formatCents(cents).replacingOccurrences(of: "$", with: "")
    }
}

struct EditAmountSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(typed.isEmpty ? "$0" : "$\(typed)")
                    .font(Flare.number(64))
                    .foregroundStyle(Flare.paper)
                MoneyPad(typed: $typed)
                Button("Save") {
                    if let id = model.editEntryID { model.changeAmount(id, amount: cents(typed: typed)) }
                    model.editEntryID = nil
                    dismiss()
                }
                .font(.headline)
                .foregroundStyle(Flare.ground)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Flare.flare, in: RoundedRectangle(cornerRadius: 16))
                .disabled(cents(typed: typed) <= 0)
            }
            .padding(20)
            .background(Flare.ground.ignoresSafeArea())
            .navigationTitle("Amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.editEntryID = nil; dismiss() } } }
            .onAppear {
                if let id = model.editEntryID, let amount = model.snapshot.entries.first(where: { $0.id == id })?.amount {
                    typed = amount.isMultiple(of: 100) ? String(amount / 100) : formatCents(amount).replacingOccurrences(of: "$", with: "")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct YesterdaySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var categoryID: String?

    var body: some View {
        let day = addDays(model.openDate, -1, timeZone: model.timeZone)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Yesterday").font(.headline).foregroundStyle(Flare.paper)
                    ForEach(model.snapshot.entries.filter { $0.day == day && $0.kind == "jar" }) { entry in
                        HStack {
                            Text(model.snapshot.categories.first { $0.id == entry.categoryID }?.name ?? "Jar")
                                .foregroundStyle(Flare.paper)
                            Spacer()
                            Text(formatCents(entry.amount)).foregroundStyle(Flare.paper)
                        }
                        .swipeActions { Button("Delete", role: .destructive) { model.deleteEntry(entry.id) } }
                    }
                    Text(typed.isEmpty ? "$0" : "$\(typed)").font(Flare.number(48)).foregroundStyle(Flare.paper)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))], spacing: 8) {
                        ForEach(model.snapshot.categories.filter(\.enabled)) { category in
                            Button(category.name) { categoryID = category.id }
                                .font(.caption)
                                .foregroundStyle(categoryID == category.id ? Flare.ground : Flare.paper)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(categoryID == category.id ? Flare.flare : Flare.surface, in: Capsule())
                        }
                    }
                    MoneyPad(typed: $typed)
                    Button("Add it") {
                        if let categoryID { model.logJar(amount: cents(typed: typed), categoryID: categoryID, photo: nil, day: day) }
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundStyle(Flare.ground)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Flare.flare, in: RoundedRectangle(cornerRadius: 16))
                    .disabled(cents(typed: typed) <= 0 || categoryID == nil)
                }
                .padding(20)
            }
            .background(Flare.ground.ignoresSafeArea())
            .navigationTitle("Fix yesterday")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Leave it") { model.finishShove(); dismiss() } } }
            .onAppear { categoryID = model.snapshot.categories.first { $0.enabled }?.id }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private nonisolated struct FinderCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let arm: CGFloat = 28
        var path = Path()
        let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (rect.minX, rect.minY, 1, 1),
            (rect.maxX, rect.minY, -1, 1),
            (rect.minX, rect.maxY, 1, -1),
            (rect.maxX, rect.maxY, -1, -1),
        ]
        for (x, y, dx, dy) in corners {
            path.move(to: CGPoint(x: x, y: y + dy * arm))
            path.addLine(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + dx * arm, y: y))
        }
        return path
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onPick: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (Data?) -> Void
        init(onPick: @escaping (Data?) -> Void) { self.onPick = onPick }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            onPick(image.flatMap(jpegData))
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

private func inviteFailureText(_ error: Error) -> String {
    if let invite = error as? InviteShareError, let text = invite.errorDescription { return text }
    let raw = error.localizedDescription
    if raw.contains("production schema") { return "iCloud is not ready for invites yet." }
    if let ck = error as? CKError {
        switch ck.code {
        case .notAuthenticated:
            return "Sign in to iCloud to invite the other phone."
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return "iCloud is temporarily unavailable. Try again."
        default:
            return "iCloud could not make the invite link."
        }
    }
    if raw.contains("CKRecordID") || raw.hasPrefix("Error saving record") {
        return "iCloud could not make the invite link."
    }
    return raw
}

private func jpegData(_ image: UIImage) -> Data? {
    let maxSide: CGFloat = 1600
    let scale = min(1, maxSide / max(image.size.width, image.size.height))
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
        image.draw(in: CGRect(origin: .zero, size: size))
    }
    return rendered.jpegData(compressionQuality: 0.7)
}

