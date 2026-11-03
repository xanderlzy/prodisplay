import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var newWidth = ""

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "HiDPI scaling sizes")
                VStack(spacing: 2) {
                    ForEach(model.customSizes) { size in
                        HStack {
                            Text(size.label).monospacedDigit()
                            Spacer()
                            Button {
                                model.removeCustomSize(size)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(QuietButtonStyle())
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .background(Color.wash, in: RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))

                HStack(spacing: 8) {
                    TextField("Width in points", text: $newWidth)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    if let w = Int(newWidth), w >= 800 {
                        Text("× \(model.height(forWidth: w))")
                            .monospacedDigit()
                            .foregroundStyle(Color.muted)
                            .transition(.opacity)
                    }
                    Button("Add", action: add)
                        .buttonStyle(MonoButtonStyle(filled: true))
                        .frame(width: 70)
                }
                .font(.system(size: 12))
                .animation(Theme.quick, value: newWidth)
            }

            Hairline()

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
                SectionLabel(title: "Brightness keys")
                Toggle("Use ProDisplay for F1 / F2", isOn: $model.brightnessKeysBoost)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                if model.brightnessKeysBoost, !model.keyAccessGranted {
                    HStack(spacing: 8) {
                        Text("Needs Accessibility access to read the brightness keys.")
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
                Toggle("Show all modes", isOn: $model.showLowResolution)
                Toggle("Launch at login", isOn: $model.launchAtLogin)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .font(.system(size: 12))
        .padding(24)
        .frame(width: 380)
        .tint(.primary)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    private func add() {
        guard let w = Int(newWidth) else { return }
        model.addCustomSize(width: w)
        newWidth = ""
    }
}
