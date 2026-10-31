import AppIntents

// These run inside the app process (LiveActivityIntent), not the widget.
// The widget target only needs the types so Button(intent:) compiles.

struct VolumeUpIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Volume Up"

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await VolumeController.shared.step(VolumeController.stepSize)
        #endif
        return .result()
    }
}

struct VolumeDownIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Volume Down"

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await VolumeController.shared.step(-VolumeController.stepSize)
        #endif
        return .result()
    }
}

struct MuteToggleIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mute"

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await VolumeController.shared.toggleMute()
        #endif
        return .result()
    }
}
