import SwiftUI

struct MenuView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var selection
    @State private var resolutionsExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            brightness
            Hairline()
            resolutions
            if model.refreshRates.count > 1 {
                Hairline()
                refreshRate
            }
            if let message = model.errorMessage {
                errorBanner(message)
            }
            Hairline()
            footer
        }
        .frame(width: Theme.panelWidth)
        .tint(Color.ink)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Built-in Display")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if let key = model.currentKey {
                // verbatim: no locale digit grouping ("2,298").
                Text(verbatim: "\(key.width) × \(key.height)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Color.muted)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, Theme.padding)
        .padding(.top, Theme.padding)
        .padding(.bottom, Theme.spacing)
    }

    private var brightness: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Brightness")
            BrightnessSlider(
                value: model.sliderValue,
                xdrAvailable: model.xdrAvailable,
                boostFactor: model.boostFactor(for:),
                onChange: model.setSlider,
                onEditingChanged: { model.isDraggingSlider = $0 }
            )
        }
        .padding(.horizontal, Theme.padding)
        .padding(.bottom, Theme.padding)
    }

    private var resolutions: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Resolution", expanded: $resolutionsExpanded)

            if resolutionsExpanded {
                VStack(spacing: 10) {
                    hiDPISwitch
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(model.resolutionEntries) { entry in
                                    ResolutionRow(
                                        title: "\(entry.key.width) × \(entry.key.height)",
                                        detail: detail(for: entry),
                                        badge: entry.hiDPI == nil ? "No HiDPI" : nil,
                                        selected: entry.contains(model.currentKey),
                                        namespace: selection
                                    ) { model.select(entry) }
                                    .id(entry.id)
                                }
                            }
                        }
                        // A ScrollView has no natural height, so the self-sizing menu window
                        // collapses it to zero unless the height is given explicitly.
                        .frame(height: listHeight)
                        .scrollIndicators(.never)
                        .onAppear {
                            if let id = model.currentEntry?.id { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .padding(Theme.padding)
    }

    private var listHeight: CGFloat {
        let rowHeight: CGFloat = 43 // ResolutionRow (41) + spacing (2)
        return min(CGFloat(model.resolutionEntries.count) * rowHeight, 220)
    }

    private var hiDPISwitch: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("HiDPI")
                    .font(.system(size: 12, weight: .medium))
                Text(hiDPICaption)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.muted)
                    .contentTransition(.opacity)
            }
            Spacer()
            Toggle("HiDPI", isOn: Binding(get: { model.isHiDPI }, set: model.setHiDPI))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!model.canToggleHiDPI)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.wash, in: RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
        .animation(Theme.spring, value: model.isHiDPI)
    }

    private var hiDPICaption: String {
        if !model.canToggleHiDPI {
            return model.isHiDPI ? "This size is HiDPI only" : "macOS has no HiDPI version of this size"
        }
        return model.isHiDPI ? "Sharp: 2 pixels per point" : "Lower resolution: 1 pixel per point"
    }

    private var refreshRate: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: "Refresh rate")
            RefreshPicker(
                rates: model.refreshRates,
                selected: model.currentRefresh,
                onSelect: model.selectRefresh
            )
        }
        .padding(Theme.padding)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
            Text(message).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                model.clearError()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(QuietButtonStyle())
        }
        .font(.system(size: 11))
        .padding(10)
        .background(Color.wash, in: RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
        .padding(.horizontal, Theme.padding)
        .padding(.bottom, Theme.spacing)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var footer: some View {
        HStack {
            SettingsLink {
                Text("Settings…")
            }
            .buttonStyle(QuietButtonStyle())
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(QuietButtonStyle())
        }
        .padding(.horizontal, Theme.padding)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, expanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(Theme.spring) { expanded.wrappedValue.toggle() }
        } label: {
            HStack {
                SectionLabel(title: title)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.muted)
                    .rotationEffect(.degrees(expanded.wrappedValue ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Pixel size of the version that is (or would be) used, given the HiDPI switch.
    private func detail(for entry: ResolutionEntry) -> String {
        let group = entry.variants.first { $0.key == model.currentKey } ?? entry.variant(hiDPI: model.isHiDPI)
        var parts = ["\(group.key.pixelWidth) × \(group.key.pixelHeight)"]
        if entry.isDefault { parts.append("Default") }
        return parts.joined(separator: " · ")
    }
}

/// A plain row; the selected row is inverted, and the highlight slides between rows.
struct ResolutionRow: View {
    let title: String
    let detail: String
    let badge: String?
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                    Text(detail)
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .opacity(0.6)
                }
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.4)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(.foreground.opacity(0.4)))
                        .opacity(0.8)
                }
            }
            .foregroundStyle(selected ? Color.inkInverse : Color.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                        .fill(Color.ink)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                        .fill(Color.wash)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Theme.quick) { hovering = h } }
        .animation(Theme.spring, value: selected)
    }
}

/// Monochrome segmented control for refresh rates.
struct RefreshPicker: View {
    let rates: [Double]
    let selected: Double
    let onSelect: (Double) -> Void

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(rates, id: \.self) { rate in
                let isSelected = abs(rate - selected) < 0.01
                Button {
                    onSelect(rate)
                } label: {
                    Text(label(for: rate))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Color.inkInverse : Color.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.ink)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.wash, in: Capsule())
        .animation(Theme.spring, value: selected)
    }

    private func label(for rate: Double) -> String {
        if rate == 0 { return "Auto" }
        return rate.rounded() == rate ? "\(Int(rate)) Hz" : String(format: "%.2f Hz", rate)
    }
}
