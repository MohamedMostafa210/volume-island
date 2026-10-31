import SwiftUI

struct ContentView: View {
    @ObservedObject private var controller = VolumeController.shared

    var body: some View {
        VStack(spacing: 20) {
            Text("VolumeIsland")
                .font(.largeTitle.bold())

            Text(controller.isMuted ? "Muted" : "Volume \(Int(controller.volume * 100))%")
                .font(.title2)

            Button("Start") {
                Task { await controller.startActivity() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Stop") {
                Task { await controller.stopActivity() }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if !controller.lastError.isEmpty {
                Text(controller.lastError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { controller.prepare() }
    }
}
