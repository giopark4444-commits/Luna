import SwiftUI

struct CalibrationView: View {
    @ObservedObject var controller: CalibrationController
    @ObservedObject var displayManager: DisplayManager

    @State private var presetName: String = ""
    @State private var selectedPreset: String = ""

    private var selected: DisplayInfo? {
        displayManager.displays.first { $0.id == controller.selectedDisplayID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: enabledBinding) {
                Text("Calibración activada").font(.system(size: 12, weight: .semibold))
            }
            .toggleStyle(.switch)
            Divider()
            patternPicker
            Divider()
            monitorPickers
            autoSection
            Divider()
            if let d = selected {
                controls(for: d)
            } else {
                Text("Conecta un monitor").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Divider()
            presetsSection
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 360)
    }

    // MARK: - Patrón

    private var patternPicker: some View {
        HStack {
            Text("Patrón").font(.system(size: 11)).frame(width: 70, alignment: .leading)
            Picker("", selection: $controller.pattern) {
                ForEach(CalibrationPattern.allCases) { p in Text(p.label).tag(p) }
            }
            .labelsHidden()
        }
    }

    // MARK: - Monitores

    private var monitorPickers: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Ajustar").font(.system(size: 11)).frame(width: 70, alignment: .leading)
                Picker("", selection: $controller.selectedDisplayID) {
                    ForEach(displayManager.displays) { d in Text(d.name).tag(Optional(d.id)) }
                }
                .labelsHidden()
            }
            HStack {
                Text("Referencia").font(.system(size: 11)).frame(width: 70, alignment: .leading)
                Picker("", selection: $controller.referenceDisplayID) {
                    ForEach(displayManager.displays) { d in Text(d.name).tag(Optional(d.id)) }
                }
                .labelsHidden()
            }
            Text("Pon un monitor como referencia y ajusta los demás hasta que coincidan al ojo.")
                .font(.system(size: 9)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Automático

    private var autoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                displayManager.autoCalibrate(referenceID: controller.referenceDisplayID)
            } label: {
                Label("Igualar automático a la referencia", systemImage: "wand.and.stars")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Text("Primer pase usando el perfil de color de cada monitor. Luego afina abajo.")
                .font(.system(size: 9)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    // MARK: - Controles del monitor seleccionado

    @ViewBuilder
    private func controls(for d: DisplayInfo) -> some View {
        let key = d.key
        let method = displayManager.calibration(for: key).method
        let enabled = displayManager.calibrationEnabled

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Método").font(.system(size: 11)).frame(width: 70, alignment: .leading)
                Picker("", selection: methodBinding(key)) {
                    Text("Software").tag(CalibrationMethod.gamma)
                    Text("Capa de color").tag(CalibrationMethod.overlay)
                    Text("Monitor").tag(CalibrationMethod.manual)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Text(methodHint(method))
                .font(.system(size: 9)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)

            Group {
                switch method {
                case .gamma:
                    caption("Ganancia (blancos)")
                    sliderRow("Rojo",  calBinding(key, \.rGain), 0.5...1.0)
                    sliderRow("Verde", calBinding(key, \.gGain), 0.5...1.0)
                    sliderRow("Azul",  calBinding(key, \.bGain), 0.5...1.0)
                    caption("Color de los medios (gamma)")
                    sliderRow("Rojo",  calBinding(key, \.rGamma), 0.5...2.0)
                    sliderRow("Verde", calBinding(key, \.gGamma), 0.5...2.0)
                    sliderRow("Azul",  calBinding(key, \.bGamma), 0.5...2.0)
                    sliderRow("Negros", calBinding(key, \.black), 0.0...0.2)
                case .overlay:
                    caption("Punto blanco (aproximado)")
                    sliderRow("Rojo",  calBinding(key, \.rGain), 0.5...1.0)
                    sliderRow("Verde", calBinding(key, \.gGain), 0.5...1.0)
                    sliderRow("Azul",  calBinding(key, \.bGain), 0.5...1.0)
                case .manual:
                    EmptyView()
                }
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.4)

            // El brillo es independiente de la calibración (siempre disponible).
            sliderRow("Brillo", brightnessBinding(d), 0.05...1.0)

            Toggle(isOn: fallbackBinding(key)) {
                Text("Night Shift: usar capa cálida si este monitor no calienta")
                    .font(.system(size: 10))
            }
            .toggleStyle(.checkbox)
            .padding(.top, 2)
        }
    }

    private func methodHint(_ method: CalibrationMethod) -> String {
        switch method {
        case .gamma:   return "Calibración real por software (lo normal en monitores que responden)."
        case .overlay: return "Aproximado por capa de color (para monitores que ignoran gamma, p. ej. 120Hz/HDMI)."
        case .manual:  return "Luna no toca el color: ajústalo en el menú físico del monitor mientras comparas los patrones."
        }
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            caption("Configuraciones guardadas")
            HStack(spacing: 8) {
                TextField("Nombre de la configuración…", text: $presetName)
                    .textFieldStyle(.roundedBorder)
                Button("Guardar") {
                    displayManager.savePreset(presetName)
                    selectedPreset = presetName.trimmingCharacters(in: .whitespaces)
                    presetName = ""
                }
                .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !displayManager.presetNames.isEmpty {
                HStack(spacing: 8) {
                    Picker("", selection: $selectedPreset) {
                        Text("Elegir…").tag("")
                        ForEach(displayManager.presetNames, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    Button("Cargar") { displayManager.loadPreset(selectedPreset) }
                        .disabled(selectedPreset.isEmpty)
                    Button("Borrar") {
                        displayManager.deletePreset(selectedPreset)
                        selectedPreset = ""
                    }
                    .disabled(selectedPreset.isEmpty)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("Restablecer este") {
                    if let d = selected { displayManager.resetCalibration(for: d.key) }
                }
                .fixedSize()
                Button("Restablecer todo") {
                    for d in displayManager.displays { displayManager.resetCalibration(for: d.key) }
                }
                .fixedSize()
                Spacer()
            }
            HStack {
                Spacer()
                Button("Listo") { controller.exit() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).padding(.top, 2)
    }

    private func sliderRow(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11)).frame(width: 50, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    // MARK: - Bindings

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { displayManager.calibrationEnabled },
            set: { displayManager.setCalibrationEnabled($0) }
        )
    }

    private func calBinding(_ key: String, _ keyPath: WritableKeyPath<DisplayCalibration, Double>) -> Binding<Double> {
        Binding(
            get: { displayManager.calibration(for: key)[keyPath: keyPath] },
            set: { newValue in
                var c = displayManager.calibration(for: key)
                c[keyPath: keyPath] = newValue
                displayManager.setCalibration(c, for: key)
            }
        )
    }

    private func fallbackBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { displayManager.calibration(for: key).nightShiftFallback },
            set: { v in
                var c = displayManager.calibration(for: key)
                c.nightShiftFallback = v
                displayManager.setCalibration(c, for: key)
            }
        )
    }

    private func methodBinding(_ key: String) -> Binding<CalibrationMethod> {
        Binding(
            get: { displayManager.calibration(for: key).method },
            set: { m in
                var c = displayManager.calibration(for: key)
                c.method = m
                displayManager.setCalibration(c, for: key)
            }
        )
    }

    private func brightnessBinding(_ d: DisplayInfo) -> Binding<Double> {
        Binding(
            get: { displayManager.displays.first { $0.id == d.id }?.brightness ?? d.brightness },
            set: { displayManager.setBrightness($0, for: d.id) }
        )
    }
}
