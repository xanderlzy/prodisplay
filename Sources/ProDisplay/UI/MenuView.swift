import SwiftUI

struct MenuView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var selection
    @State private var resolutionsExpanded = true
    @State private var customWidth = ""
    @State private var customHiDPI = true
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if model.displays.count > 1 {
                DisplayPicker(
                    displays: model.displays,
                    selected: model.selectedDisplayID,
                    onSelect: model.selectDisplay
                )
                .padding(.horizontal, Theme.padding)
                .padding(.bottom, Theme.padding)
            }
            if model.builtinID != nil {
                brightness
                Hairline()
            }
            resolutions
            if model.refreshRates.count > 1, model.activeCustom == nil {
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
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .background(PanelAnchor(height: contentHeight))
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text(model.selectedDisplay?.name ?? "No Display")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .contentTransition(.opacity)
            Spacer()
            if let size = model.currentSize {
                // verbatim: no locale digit grouping ("2,298").
                Text(verbatim: "\(size.width) × \(size.height)")
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
            // The slider always drives the built-in panel; say so when another display is selected.
            SectionLabel(title: model.selectedDisplay?.isBuiltin == false ? "Built-in brightness" : "Brightness")
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
                                        selected: entry.contains(model.currentKey) && model.activeCustom == nil,
                                        namespace: selection,
                                        isDefault: model.isDefault(entry),
                                        onToggleDefault: { model.toggleDefault(entry) }
                                    ) { model.select(entry) }
                                    .id(entry.id)
                                }
                            }
                        }
                        // A ScrollView has no natural height, so the self-sizing menu window
                        // collapses it to zero unless the height is given explicitly.
                        .frame(height: listHeight)
                        .scrollIndicators(.never)
                        .onAppear { scrollToCurrent(proxy) }
                        // A fresh list for each display, so it opens at that display's current size.
                        .id(model.selectedDisplayID)
                    }
                    customSection
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .padding(Theme.padding)
    }

    /// Centres the current size, or shows the top of the list when it isn't listed (a custom size is on).
    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        let entries = model.resolutionEntries
        if let current = entries.first(where: { $0.contains(model.currentKey) }) {
            proxy.scrollTo(current.id, anchor: .center)
        } else if let first = entries.first {
            proxy.scrollTo(first.id, anchor: .top)
        }
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
        if model.activeCustom != nil { return "Custom size: set when it was added" }
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

    // MARK: - Custom resolutions

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(title: "Custom")
                Spacer()
                if model.isApplyingCustom {
                    ProgressView().controlSize(.mini)
                        .transition(.opacity)
                }
            }
            .padding(.top, 4)

            if !model.customResolutions.isEmpty {
                VStack(spacing: 2) {
                    ForEach(model.customResolutions) { resolution in
                        ResolutionRow(
                            title: "\(resolution.width) × \(resolution.height)",
                            detail: "\(resolution.pixelWidth) × \(resolution.pixelHeight)"
                                + (model.isDefault(resolution) ? " · Default" : ""),
                            badge: resolution.hiDPI ? "HiDPI" : nil,
                            selected: model.activeCustom == resolution,
                            namespace: selection,
                            isDefault: model.isDefault(resolution),
                            onToggleDefault: { model.toggleDefault(resolution) },
                            onRemove: { model.removeCustom(resolution) }
                        ) { model.selectCustom(resolution) }
                    }
                }
            }

            addCustomRow

            if model.selectedDisplay?.isBuiltin == true {
                Text("On the built-in screen a custom size covers the notch area with a black bar and turns off XDR brightness while it's on.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(Theme.spring, value: model.isApplyingCustom)
        .animation(Theme.spring, value: model.customResolutions)
    }

    private var addCustomRow: some View {
        let width = Int(customWidth)
        let valid = width.map { model.customWidthRange(hiDPI: customHiDPI).contains($0) } ?? false

        return HStack(spacing: 6) {
            TextField("Width", text: $customWidth)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .frame(width: 44)
                .onSubmit(addCustom)
                .onChange(of: customWidth) { _, new in
                    let digits = String(new.filter(\.isNumber).prefix(4))
                    if digits != new { customWidth = digits }
                }
            Text(verbatim: "× \(width.map { String(model.customHeight(forWidth: $0)) } ?? "–")")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Color.muted)
                .contentTransition(.numericText())
            Spacer(minLength: 4)
            Button {
                withAnimation(Theme.quick) { customHiDPI.toggle() }
            } label: {
                Text("HiDPI")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(customHiDPI ? Color.inkInverse : Color.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background {
                        Capsule().fill(customHiDPI ? Color.ink : Color.clear)
                        Capsule().strokeBorder(customHiDPI ? Color.clear : Color.hairline)
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(customHiDPI ? "Sharp: 2 pixels per point" : "Lower resolution: 1 pixel per point")
            Button("Add", action: addCustom)
                .buttonStyle(MonoButtonStyle(filled: valid))
                .frame(width: 58)
                .disabled(!valid || model.isApplyingCustom)
        }
        .padding(.leading, 10)
        .padding(.vertical, 3)
        .padding(.trailing, 3)
        .background(Color.wash, in: RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
        .help("Type a width from \(model.customWidthRange(hiDPI: customHiDPI).lowerBound) to \(model.customWidthRange(hiDPI: customHiDPI).upperBound); the height follows the display's shape.")
    }

    private func addCustom() {
        guard let width = Int(customWidth), model.customWidthRange(hiDPI: customHiDPI).contains(width) else { return }
        model.addCustom(width: width, hiDPI: customHiDPI)
        customWidth = ""
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
        // "Default" is the user's pinned size; macOS's own pick is named as such.
        if model.isDefault(entry) {
            parts.append("Default")
        } else if entry.isDefault {
            parts.append("macOS default")
        }
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
    var isDefault = false
    var onToggleDefault: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil
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
                // The pin stays on the default row and appears on others while hovered.
                if let onToggleDefault, isDefault || hovering {
                    Button(action: onToggleDefault) {
                        Image(systemName: isDefault ? "pin.fill" : "pin")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(45))
                            .opacity(isDefault ? 1 : 0.6)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .help(isDefault ? "Remove as default" : "Set as default: used when ProDisplay opens or this display reconnects")
                    .transition(.opacity)
                }
                if let onRemove, hovering {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Remove")
                    .transition(.opacity)
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
        .animation(Theme.spring, value: isDefault)
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

/// Monochrome segmented control for choosing which display the resolution controls act on.
struct DisplayPicker: View {
    let displays: [DisplayInfo]
    let selected: CGDirectDisplayID?
    let onSelect: (CGDirectDisplayID) -> Void

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(displays) { display in
                let isSelected = display.id == selected
                Button {
                    onSelect(display.id)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                            .font(.system(size: 10, weight: .medium))
                        Text(display.isBuiltin ? "Built-in" : display.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? Color.inkInverse : Color.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
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
                .help(display.name)
            }
        }
        .padding(2)
        .background(Color.wash, in: Capsule())
        .animation(Theme.spring, value: selected)
    }
}
