import SwiftUI

struct CalibrationView: View {
    @ObservedObject var controller: CalibrationController
    @ObservedObject var displayManager: DisplayManager

    private var selected: DisplayInfo? {
        displayManager.displays.first { $0.id == controller.selectedDisplayID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            patternPicker
            Divider()
            monitorPickers
            Divider()
            if let d = selected {
                controls(for: d)
            } else {
                Text("Conecta un monitor").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 330)
    }

    // MARK: - Secciones

    private var patternPicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Patrón de prueba").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Picker("", selection: $controller.pattern) {
                ForEach(CalibrationPattern.allCases) { p in Text(p.label).tag(p) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

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

    @ViewBuilder
    private func controls(for d: DisplayInfo) -> some View {
        let name = d.name
        let isOverlay = displayManager.calibration(for: name).method == .overlay

        VStack(alignment: .leading, spacing: 7) {
            sliderRow("Rojo",  calBinding(name, \.rGain), 0.5...1.0)
            sliderRow("Verde", calBinding(name, \.gGain), 0.5...1.0)
            sliderRow("Azul",  calBinding(name, \.bGain), 0.5...1.0)

            if isOverlay {
                Text("Gamma y negros no aplican en este monitor (capa de color, aproximado).")
                    .font(.system(size: 9)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            } else {
                sliderRow("Gamma",  calBinding(name, \.gamma), 0.5...2.0)
                sliderRow("Negros", calBinding(name, \.black), 0.0...0.2)
            }

            sliderRow("Brillo", brightnessBinding(d), 0.05...1.0)

            Toggle(isOn: methodBinding(name)) {
                Text("Este monitor no responde a gamma → usar capa de color")
                    .font(.system(size: 10))
            }
            .toggleStyle(.checkbox)
            .padding(.top, 2)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Restablecer este") {
                if let d = selected { displayManager.resetCalibration(for: d.name) }
            }
            .font(.system(size: 11))
            Button("Restablecer todo") {
                for d in displayManager.displays { displayManager.resetCalibration(for: d.name) }
            }
            .font(.system(size: 11))
            Spacer()
            Button("Listo") { controller.exit() }
                .keyboardShortcut(.defaultAction)
        }
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

    private func calBinding(_ name: String, _ keyPath: WritableKeyPath<DisplayCalibration, Double>) -> Binding<Double> {
        Binding(
            get: { displayManager.calibration(for: name)[keyPath: keyPath] },
            set: { newValue in
                var c = displayManager.calibration(for: name)
                c[keyPath: keyPath] = newValue
                displayManager.setCalibration(c, for: name)
            }
        )
    }

    private func methodBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { displayManager.calibration(for: name).method == .overlay },
            set: { useOverlay in
                var c = displayManager.calibration(for: name)
                c.method = useOverlay ? .overlay : .gamma
                displayManager.setCalibration(c, for: name)
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
