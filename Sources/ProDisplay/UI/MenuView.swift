import SwiftUI

struct MenuView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var selection
    @State private var resolutionsExpanded = true
    @State private var scalingExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            brightness
            Hairline()
            resolutions
            Hairline()
            scaling
            if let message = model.errorMessage {
                errorBanner(message)
            }
            Hairline()
            footer
        }
        .frame(width: Theme.panelWidth)
        .tint(.primary)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Built-in Display")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if let key = model.currentKey {
                Text("\(key.pixelWidth) × \(key.pixelHeight)")
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
            if model.activeCustom != nil, !model.xdrAvailable {
                Text("XDR boost is paused while custom scaling is on.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.muted)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.padding)
        .padding(.bottom, Theme.padding)
    }

    private var resolutions: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Resolution", expanded: $resolutionsExpanded)

            if resolutionsExpanded {
                VStack(spacing: 8) {
                    ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(model.visibleGroups) { group in
                                ResolutionRow(
                                    title: "\(group.key.width) × \(group.key.height)",
                                    detail: detail(for: group),
                                    badge: group.isHiDPI ? "HiDPI" : nil,
                                    selected: model.activeCustom == nil && group.key == model.currentKey,
                                    namespace: selection,
                                    matchID: "resolution"
                                ) { model.select(group) }
                                .id(group.key)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .scrollIndicators(.never)
                    .onAppear {
                        if let key = model.currentKey { proxy.scrollTo(key, anchor: .center) }
                    }
                    }

                    if model.refreshRates.count > 1, model.activeCustom == nil {
                        RefreshPicker(
                            rates: model.refreshRates,
                            selected: model.currentRefresh,
                            onSelect: model.selectRefresh
                        )
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .padding(Theme.padding)
    }

    private var scaling: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("HiDPI Scaling", expanded: $scalingExpanded)

            if scalingExpanded {
                VStack(spacing: 2) {
                    ResolutionRow(
                        title: "Off",
                        detail: "Use the resolutions above",
                        badge: nil,
                        selected: model.activeCustom == nil && model.applyingCustom == nil,
                        namespace: selection,
                        matchID: "scaling"
                    ) {
                        Task { await model.disableCustom() }
                    }
                    ForEach(model.customSizes) { size in
                        ResolutionRow(
                            title: size.label,
                            detail: "\(size.width * 2) × \(size.height * 2) rendered",
                            badge: "HiDPI",
                            selected: model.activeCustom == size,
                            namespace: selection,
                            matchID: "scaling",
                            busy: model.applyingCustom == size
                        ) { model.applyCustom(size) }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
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

    private func detail(for group: DisplayModeGroup) -> String {
        var parts = ["\(group.key.pixelWidth) × \(group.key.pixelHeight)"]
        if group.isDefault { parts.append("Default") }
        if !group.isHiDPI { parts.append("Low resolution") }
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
    let matchID: String
    var busy = false
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
                if busy {
                    ProgressView().controlSize(.mini)
                } else if let badge {
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
                        .matchedGeometryEffect(id: matchID, in: namespace)
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
