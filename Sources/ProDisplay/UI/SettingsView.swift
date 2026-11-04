import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "XDR boost limit")
                HStack {
                    Slider(value: $model.maxBoostSetting, in: 1.2...2.0, step: 0.05)
                    Text("\(Int((model.maxBoostSetting * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                Text("Higher values are brighter but use more power and run warmer. The boost turns off on its own when the Mac runs hot or the battery is low.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Hairline()

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "Keyboard")
                Toggle("Use ProDisplay for brightness (F1 / F2)", isOn: $model.brightnessKeysBoost)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Toggle("Use ProDisplay for volume (F10–F12)", isOn: $model.volumeKeys)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                if model.brightnessKeysBoost || model.volumeKeys, !model.keyAccessGranted {
                    HStack(spacing: 8) {
                        Text("Needs Accessibility access to read the brightness and volume keys.")
                            .foregroundStyle(Color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Allow…", action: model.openAccessibilitySettings)
                            .buttonStyle(MonoButtonStyle(filled: true))
                            .frame(width: 80)
                    }
                    .font(.system(size: 11))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(Theme.spring, value: model.keyAccessGranted)

            Hairline()

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show below-notch sizes", isOn: $model.showLowResolution)
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                Toggle("Automatically check for updates", isOn: $model.automaticallyChecksForUpdates)
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Button("Show Welcome Again", action: model.showOnboarding)
                .buttonStyle(QuietButtonStyle())
        }
        .font(.system(size: 12))
        .padding(24)
        .frame(width: 380)
        .tint(Color.ink)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}
