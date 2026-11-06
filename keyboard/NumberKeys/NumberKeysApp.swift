import SwiftUI

@main
struct NumberKeysApp: App {
    var body: some Scene {
        WindowGroup {
            SetupView()
        }
    }
}

struct SetupView: View {
    @State private var testText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("NumberKeys")
                    .font(.largeTitle.bold())

                Text("Turn it on")
                    .font(.title3.bold())
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Settings → General → Keyboard → Keyboards")
                    Text("2. Add New Keyboard → NumberKeys → add English, then do it again for Arabic")
                    Text("3. Tap each NumberKeys keyboard → turn on Allow Full Access (for key clicks and haptics)")
                    Text("4. Optional: remove Apple's English and Arabic keyboards so the globe only switches between these two")
                }
                .font(.body)

                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)

                Text("Try it")
                    .font(.title3.bold())
                TextField("Type here", text: $testText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
