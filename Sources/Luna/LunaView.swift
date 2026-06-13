import SwiftUI

struct LunaView: View {
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject var nightShift: NightShiftManager = .shared
    @ObservedObject var loginItem: LoginItem = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            masterRow
            if !displayManager.displays.isEmpty {
                Divider()
                ForEach(displayManager.displays) { display in
                    DisplayRow(
                        display: display,
                        brightness: Binding(
                            get: { displayManager.displays.first(where: { $0.id == display.id })?.brightness ?? display.brightness },
                            set: { displayManager.setBrightness($0, for: display.id) }
                        )
                    )
                    if displayManager.displays.last?.id != display.id {
                        Divider().padding(.horizontal, 16)
                    }
                }
            }
            if nightShift.isAvailable {
                Divider()
                nightShiftSection
            }
            Divider()
            loginRow
            Divider()
            footer
        }
        .frame(width: 290)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.fill")
                .font(.system(size: 13, weight: .medium))
            Text("Luna")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 10)
    }

    private var masterRow: some View {
        BrightnessRow(
            label: "Todos los monitores",
            icon: "square.3.layers.3d",
            brightness: Binding(
                get: { displayManager.masterBrightness },
                set: { displayManager.setAllBrightness($0) }
            ),
            available: true
        )
    }

    private var nightShiftSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toggle row
            HStack(spacing: 8) {
                Image(systemName: "sun.haze.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text("Night Shift")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { nightShift.isEnabled },
                    set: { nightShift.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.75)
                .frame(width: 38)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, nightShift.isEnabled ? 4 : 10)

            // Intensity slider — only when Night Shift is on
            if nightShift.isEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "thermometer.low")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Slider(
                        value: Binding(
                            get: { nightShift.strength },
                            set: { nightShift.setStrength($0) }
                        ),
                        in: 0.0...1.0
                    )
                    .tint(nightShiftTint)
                    Image(systemName: "thermometer.high")
                        .font(.system(size: 10))
                        .foregroundStyle(nightShiftTint)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: nightShift.isEnabled)
    }

    /// Color de la barra de Night Shift: ámbar suave en baja intensidad →
    /// amarillo dorado intenso a medida que sube la potencia.
    private var nightShiftTint: Color {
        let s = max(0, min(1, nightShift.strength))
        let hue = 0.090 + 0.050 * s        // 0.09 (naranja-ámbar) → 0.14 (amarillo)
        let saturation = 0.62 + 0.38 * s   // más saturado cuanto más potente
        return Color(hue: hue, saturation: saturation, brightness: 1.0)
    }

    private var loginRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "power")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Abrir al iniciar sesión")
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Toggle("", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.set($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .scaleEffect(0.75)
            .frame(width: 38)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Button("Salir de Luna") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

// MARK: - Display Row

struct DisplayRow: View {
    let display: DisplayInfo
    @Binding var brightness: Double

    var body: some View {
        BrightnessRow(
            label: display.name,
            icon: "display",
            brightness: $brightness,
            available: true
        )
    }
}

// MARK: - Reusable brightness row

struct BrightnessRow: View {
    let label: String
    let icon: String
    @Binding var brightness: Double
    let available: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(brightness * 100))%")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            HStack(spacing: 6) {
                Image(systemName: "sun.min.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Slider(value: $brightness, in: 0.05...1.0)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
