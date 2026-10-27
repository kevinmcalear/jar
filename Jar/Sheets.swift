import SwiftUI
import UIKit

struct AddSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var outside = false
    @State private var typed = ""
    @State private var categoryID: String?
    @State private var photo: Data?
    @State private var showCamera = false
    @State private var chip = Chip.groceries
    @State private var rhythm = PayRhythm.weekly
    @State private var note = ""
    @State private var outsideDay = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(loggingLine)
                        .font(.subheadline)
                        .foregroundStyle(Flare.muted)
                    kindPicker
                    if outside {
                        outsideBody
                    } else {
                        jarBody
                    }
                    Text(typed.isEmpty ? "$0" : "$\(typed)")
                        .font(Flare.number(64))
                        .foregroundStyle(Flare.paper)
                        .frame(maxWidth: .infinity)
                    MoneyPad(typed: $typed)
                    Text(outside ? "The jar stays at \(formatCents(model.settledScore.jar))." : "This counts against today.")
                        .font(.subheadline)
                        .foregroundStyle(Flare.muted)
                    Button("Log it") { commit() }
                        .font(.headline)
                        .foregroundStyle(Flare.ground)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Flare.flare, in: RoundedRectangle(cornerRadius: 16))
                        .disabled(cents(typed: typed) <= 0 || (!outside && categoryID == nil))
                }
                .padding(20)
            }
            .background(Flare.ground.ignoresSafeArea())
            .navigationTitle("Add something")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            categoryID = model.snapshot.categories.first { $0.enabled }?.id
            outsideDay = model.openDate
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { photo = $0 }
        }
    }

    private var loggingLine: String {
        let name = model.holder?.displayName ?? "Someone"
        let pronoun = model.holder?.sticker == "bridget" ? "hers" : "his"
        return "Logging as \(name). This phone is \(pronoun)."
    }

    private var kindPicker: some View {
        HStack(spacing: 8) {
            mode("Today's jar", on: !outside) { outside = false }
            mode("Outside", on: outside) { outside = true }
        }
    }

    private func mode(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(on ? Flare.ground : Flare.paper)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(on ? (outside && title == "Outside" ? Flare.paper : Flare.flare) : Flare.surface, in: Capsule())
    }

    private var jarBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                ForEach(model.snapshot.categories.filter(\.enabled)) { category in
                    Button { categoryID = category.id } label: {
                        VStack(spacing: 6) {
                            CategoryMark(builtIn: category.builtIn, size: 36)
                            Text(category.name)
                                .font(.caption)
                                .foregroundStyle(Flare.paper)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 78)
                        .background(Flare.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(categoryID == category.id ? Flare.flare : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            Button { showCamera = UIImagePickerController.isSourceTypeAvailable(.camera) } label: {
                HStack {
                    PhotoFrame()
                    VStack(alignment: .leading) {
                        Text("Photo").foregroundStyle(Flare.paper)
                        Text(photo == nil ? "Take one, or skip" : "One picture, ready")
                            .font(.caption)
                            .foregroundStyle(Flare.muted)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(UIImagePickerController.isSourceTypeAvailable(.camera) ? "Opens the camera" : "This phone has no camera")
        }
    }

    private var outsideBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ForEach(Chip.allCases) { item in
                    Button(item.title) {
                        chip = item
                        rhythm = item.defaultRhythm
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(chip == item ? Flare.ground : Flare.paper)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(chip == item ? Flare.paper : Flare.surface, in: Capsule())
                }
            }
            TextField("Note", text: $note)
                .padding(12)
                .background(Flare.surface, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Flare.paper)
            HStack {
                ForEach([PayRhythm.once, .weekly, .monthly], id: \.self) { item in
                    Button(rhythmTitle(item.rawValue)) { rhythm = item }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(rhythm == item ? Flare.ground : Flare.paper)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(rhythm == item ? Flare.paper : Flare.surface, in: Capsule())
                }
            }
            DatePicker("Day", selection: outsideDate, displayedComponents: .date)
                .foregroundStyle(Flare.paper)
        }
    }

    private var outsideDate: Binding<Date> {
        Binding {
            date(from: outsideDay.isEmpty ? model.openDate : outsideDay, timeZone: model.timeZone) ?? Date()
        } set: { outsideDay = formatDay($0, timeZone: model.timeZone) }
    }

    private func commit() {
        let amount = cents(typed: typed)
        if outside {
            model.logOutside(amount: amount, chip: chip, rhythm: rhythm, note: note, day: outsideDay.isEmpty ? model.openDate : outsideDay)
        } else if let categoryID {
            model.logJar(amount: amount, categoryID: categoryID, photo: photo)
        }
        dismiss()
    }
}

struct SettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var capText = ""
    @State private var goalText = ""
    @State private var newCategory = ""
    @State private var zoneQuery = ""
    @State private var share = false

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
                            CategoryMark(builtIn: category.builtIn)
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
                    Button("Invite the other phone") { share = true }
                        .font(.headline)
                        .foregroundStyle(Flare.ground)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Flare.flare, in: RoundedRectangle(cornerRadius: 16))
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
            .sheet(isPresented: $share) { ShareSheet() }
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

struct ShareSheet: UIViewControllerRepresentable {
    @Environment(AppModel.self) private var model

    func makeUIViewController(context: Context) -> UIViewController {
        context.coordinator.model = model
        let controller = UICloudSharingController { _, completion in
            Task { @MainActor in
                do {
                    guard let sync = context.coordinator.model?.sync else { return }
                    let share = try await sync.makeShare()
                    completion(share, sync.container, nil)
                } catch {
                    context.coordinator.model?.shareError = error.localizedDescription
                    completion(nil, nil, error)
                }
            }
        }
        controller.availablePermissions = [.allowReadWrite]
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var model: AppModel?
    }
}
