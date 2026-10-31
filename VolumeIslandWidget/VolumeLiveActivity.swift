import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private func speakerIcon(_ state: VolumeAttributes.ContentState) -> String {
    state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
}

struct VolumeBar: View {
    let value: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule()
                    .fill(.white)
                    .frame(width: geo.size.width * CGFloat(min(max(value, 0), 1)))
            }
        }
        .frame(height: 4)
    }
}

struct VolumeControlsView: View {
    let state: VolumeAttributes.ContentState

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 28) {
                Button(intent: VolumeDownIntent()) {
                    Image(systemName: "minus").font(.title2)
                }
                Button(intent: MuteToggleIntent()) {
                    Image(systemName: speakerIcon(state)).font(.title2)
                }
                Button(intent: VolumeUpIntent()) {
                    Image(systemName: "plus").font(.title2)
                }
            }
            .buttonStyle(.plain)
            VolumeBar(value: state.isMuted ? 0 : state.volume)
        }
        .foregroundStyle(.white)
    }
}

struct VolumeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VolumeAttributes.self) { context in
            VolumeControlsView(state: context.state)
                .padding()
                .activityBackgroundTint(.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    VolumeControlsView(state: context.state)
                }
            } compactLeading: {
                Image(systemName: speakerIcon(context.state))
            } compactTrailing: {
                Text(context.state.isMuted ? "0%" : "\(Int(context.state.volume * 100))%")
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: speakerIcon(context.state))
            }
        }
    }
}
