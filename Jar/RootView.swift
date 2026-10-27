import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        Group {
            if !model.booted {
                ProgressView().tint(Flare.paper)
            } else if model.snapshot.settings == nil {
                SetupView()
            } else if !model.unlocked {
                UnlockView()
            } else {
                main
            }
        }
        .background(Flare.ground.ignoresSafeArea())
        .preferredColorScheme(model.picture.climbs ? .light : .dark)
        .task { model.boot(); await model.wake() }
        .onOpenURL { url in
            guard url.scheme == PileBoard.add.scheme, url.host == PileBoard.add.host else { return }
            model.openAdd()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.lock() }
            if phase == .active { Task { await model.wake() } }
        }
    }

    private var main: some View {
        @Bindable var model = model
        return ZStack {
            TabView(selection: $model.tab) {
                Tab("Today", systemImage: "sun.max", value: "today") {
                    NavigationStack { TodayView() }
                }
                Tab("Month", systemImage: "calendar", value: "month") {
                    NavigationStack { MonthView() }
                }
                Tab("Year", systemImage: "clock", value: "year") {
                    NavigationStack { YearView() }
                }
            }
            .toolbarVisibility(model.coversTabs ? .hidden : .visible, for: .tabBar)
            .tint(Flare.paper)
            if let shove = model.shove {
                ShoveView(shove: shove)
            }
        }
        .sheet(item: $model.addToken) { _ in AddSheet() }
        .sheet(item: $model.outsideToken) { _ in OutsideSheet() }
        .sheet(item: $model.settingsToken) { _ in SettingsSheet() }
        .sheet(item: $model.yesterdayToken) { _ in YesterdaySheet() }
        .sheet(item: editToken) { _ in EditAmountSheet() }
    }

    private var editToken: Binding<EditID?> {
        Binding {
            model.editEntryID.map(EditID.init)
        } set: { model.editEntryID = $0?.id }
    }
}

struct EditID: Identifiable {
    var id: String
}

struct ShoveView: View {
    var shove: ShoveShow
    @Environment(AppModel.self) private var model
    @State private var token = 0

    var body: some View {
        let start = min(1, Double(shove.plan.beforeJar) / 30000)
        let end = min(1, Double(shove.plan.afterJar) / 30000)
        VStack(spacing: 22) {
            KeyframeAnimator(initialValue: Motion(fill: start), trigger: token) { value in
                VStack(spacing: 18) {
                    ScoreJar(fill: value.fill, stroke: Flare.paper, gaps: value.fill == 0 ? 1 : 0, width: 180)
                    if shove.plan.billCents > 0 {
                        BillPile(cents: shove.plan.billCents)
                            .offset(y: value.drop)
                            .opacity(value.alpha)
                    }
                }
            } keyframes: { _ in
                KeyframeTrack(\.drop) {
                    LinearKeyframe(0, duration: 0.15)
                    SpringKeyframe(120, duration: 0.75, spring: .smooth)
                }
                KeyframeTrack(\.fill) {
                    LinearKeyframe(start, duration: 0.35)
                    SpringKeyframe(end, duration: 0.8, spring: .smooth)
                }
                KeyframeTrack(\.alpha) {
                    LinearKeyframe(1, duration: 0.45)
                    LinearKeyframe(shove.plan.billCents > 0 ? 0 : 1, duration: 0.4)
                }
            }
            if shove.plan.tappable {
                Button(shove.plan.text) { model.yesterdayToken = SheetToken() }
                    .font(Flare.number(22))
                    .foregroundStyle(Flare.flare)
                    .multilineTextAlignment(.center)
                Button("Continue") { model.finishShove() }
                    .foregroundStyle(Flare.paper)
            } else {
                Text(shove.plan.text)
                    .font(Flare.number(22))
                    .foregroundStyle(Flare.flare)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Flare.ground.ignoresSafeArea())
        .onAppear {
            token += 1
            guard !shove.plan.tappable else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.8))
                if model.shove?.id == shove.id { model.finishShove() }
            }
        }
    }
}

nonisolated struct Motion: Animatable {
    var drop: CGFloat = 0
    var fill: Double
    var alpha: Double = 1
    var animatableData: AnimatablePair<CGFloat, AnimatablePair<Double, Double>> {
        get { AnimatablePair(drop, AnimatablePair(fill, alpha)) }
        set {
            drop = newValue.first
            fill = newValue.second.first
            alpha = newValue.second.second
        }
    }
}

struct SetupView: View {
    @Environment(AppModel.self) private var model
    @State private var kevin = "Kevin"
    @State private var bridget = "Bridget"
    @State private var holder = "kevin"
    @State private var passphrase = ""
    @State private var confirm = ""
    @State private var cap = "50"
    @State private var goal = ""
    @State private var closeHour = 4
    @State private var timezone = TimeZone.current.identifier

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Jar")
                        .font(Flare.number(56))
                        .foregroundStyle(Flare.paper)
                    Text("Two names, one passphrase, and whose phone this is.")
                        .foregroundStyle(Flare.muted)
                    labeled("First person", text: $kevin)
                    labeled("Second person", text: $bridget)
                    HStack {
                        personChoice("kevin", kevin)
                        personChoice("bridget", bridget)
                    }
                    labeled("Usual daily cap", text: $cap)
                    labeled("Savings goal", text: $goal)
                    Stepper("Ends at \(closeClock(closeHour))", value: $closeHour, in: 0...23)
                        .foregroundStyle(Flare.paper)
                    Text(timezone).font(.caption).foregroundStyle(Flare.muted)
                    SecureField("Household passphrase", text: $passphrase)
                        .padding(12)
                        .background(Flare.surface, in: RoundedRectangle(cornerRadius: 12))
                    SecureField("Type it again", text: $confirm)
                        .padding(12)
                        .background(Flare.surface, in: RoundedRectangle(cornerRadius: 12))
                    Button("Start the jar") { start() }
                        .font(.headline)
                        .foregroundStyle(Flare.ground)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Flare.flare, in: RoundedRectangle(cornerRadius: 16))
                        .disabled(!ready)
                }
                .padding(20)
            }
            .background(Flare.ground.ignoresSafeArea())
        }
    }

    private var ready: Bool {
        !kevin.trimmingCharacters(in: .whitespaces).isEmpty && !bridget.trimmingCharacters(in: .whitespaces).isEmpty && !passphrase.isEmpty && passphrase == confirm && cents(typed: cap) >= 0
    }

    private func labeled(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(Flare.muted)
            TextField(title, text: text)
                .padding(12)
                .background(Flare.surface, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Flare.paper)
        }
    }

    private func personChoice(_ sticker: String, _ name: String) -> some View {
        Button { holder = sticker } label: {
            VStack {
                PersonSticker(sticker: sticker, name: name, size: 72)
                    .overlay(Circle().stroke(holder == sticker ? Flare.flare : Color.clear, lineWidth: 3))
                Text("This phone is \(name)").font(.caption).foregroundStyle(Flare.paper)
            }
        }
        .buttonStyle(.plain)
    }

    private func start() {
        model.start(
            kevin: kevin, bridget: bridget, holderSticker: holder, timezone: timezone, closeHour: closeHour,
            cap: cents(typed: cap), goal: goal.isEmpty ? nil : cents(typed: goal), passphrase: passphrase
        )
    }
}

struct UnlockView: View {
    @Environment(AppModel.self) private var model
    @State private var passphrase = ""
    @State private var failed = false

    var body: some View {
        VStack(spacing: 18) {
            Text("Jar").font(Flare.number(56)).foregroundStyle(Flare.paper)
            SecureField("Household passphrase", text: $passphrase)
                .padding(12)
                .background(Flare.surface, in: RoundedRectangle(cornerRadius: 12))
            if UserDefaults.standard.bool(forKey: "jar.passphraseReset") {
                Text("Use the passphrase from the phone that set the jar up.")
                    .font(.subheadline)
                    .foregroundStyle(Flare.muted)
                    .multilineTextAlignment(.center)
            }
            if failed {
                Text("That passphrase does not open the jar.")
                    .foregroundStyle(Flare.flare)
            }
            if let error = model.shareError {
                Text(error).font(.caption).foregroundStyle(Flare.flare).multilineTextAlignment(.center)
            }
            Button("Unlock") {
                failed = !model.unlock(passphrase: passphrase)
            }
            .font(.headline)
            .foregroundStyle(Flare.ground)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Flare.flare, in: RoundedRectangle(cornerRadius: 16))
            Button("Try Face ID") { Task { await model.wake() } }
                .foregroundStyle(Flare.paper)
        }
        .padding(24)
    }
}
