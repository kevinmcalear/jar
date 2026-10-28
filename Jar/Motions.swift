import SwiftUI

private struct PlayClock: Animatable {
    var time: Double
    var animatableData: Double {
        get { time }
        set { time = newValue }
    }
}

struct FacePlayView: View {
    var play: FacePlay
    var done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var token = 0

    var body: some View {
        Group {
            if reduce {
                Color.clear
            } else {
                KeyframeAnimator(initialValue: PlayClock(time: 0), trigger: token) { clock in
                    stage(facePose(at: clock.time))
                } keyframes: { _ in
                    KeyframeTrack(\.time) { LinearKeyframe(1, duration: 2.2) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Flare.ground.ignoresSafeArea())
        .onAppear {
            if reduce {
                done()
                return
            }
            token += 1
            Task {
                try? await Task.sleep(for: .seconds(2.35))
                done()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(play.jarCents > 0 ? "\(play.name) took from the jar" : "\(play.name) spent")
    }

    private func stage(_ pose: FacePose) -> some View {
        ZStack {
            if play.jarCents > 0 {
                ScoreJar(fill: max(0, 0.72 - 0.4 * pose.fly), stroke: Flare.paper, gaps: 0, width: 140)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 36)
                    .padding(.bottom, 120)
                flying(play.jarCents, pose: pose, x: -30, y: 90)
            }
            if play.pileCents > 0 {
                flying(play.pileCents, pose: pose, x: -10, y: -30)
            }
            PersonSticker(sticker: play.sticker, name: play.name, size: 132)
                .scaleEffect(pose.headScale)
                .rotationEffect(.degrees(pose.wiggle))
                .offset(y: pose.headY)
                .opacity(pose.headAlpha)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 64)
                .padding(.trailing, 20)
        }
    }

    private func flying(_ cents: Int, pose: FacePose, x: CGFloat, y: CGFloat) -> some View {
        BillPile(cents: cents)
            .frame(width: 220)
            .offset(x: x + pose.fly * 120, y: y + pose.fly * -300)
            .opacity(pose.billAlpha)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct ShoveView: View {
    var shove: ShoveShow
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var token = 0

    var body: some View {
        VStack(spacing: 22) {
            if reduce {
                glass(shovePose(at: 1, beforeJar: shove.plan.beforeJar, afterJar: shove.plan.afterJar))
            } else {
                KeyframeAnimator(initialValue: PlayClock(time: 0), trigger: token) { clock in
                    glass(shovePose(at: clock.time, beforeJar: shove.plan.beforeJar, afterJar: shove.plan.afterJar))
                } keyframes: { _ in
                    KeyframeTrack(\.time) { LinearKeyframe(1, duration: 2.2) }
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
            let wait: Double = reduce ? 0.4 : 2.5
            Task {
                try? await Task.sleep(for: .seconds(wait))
                if model.shove?.id == shove.id { model.finishShove() }
            }
        }
    }

    private func glass(_ pose: ShovePose) -> some View {
        VStack(spacing: 18) {
            ScoreJar(fill: pose.fill, stroke: Flare.paper, gaps: pose.fill == 0 ? 1 : 0, width: 180 * pose.scale)
            if pose.upgraded {
                Text("Jar upgraded!")
                    .font(Flare.number(28))
                    .foregroundStyle(Flare.flare)
            } else {
                Text(nextJarLine(cents: pose.goal))
                    .font(.subheadline)
                    .foregroundStyle(Flare.muted)
            }
            Text(jarSizeLine(cents: pose.goal))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Flare.paper)
            if shove.plan.billCents > 0 {
                BillPile(cents: shove.plan.billCents)
                    .offset(y: pose.billY)
                    .opacity(pose.billAlpha)
            }
        }
    }
}
