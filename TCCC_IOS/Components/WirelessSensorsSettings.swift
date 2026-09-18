import SwiftUI

struct WirelessSensorsSettings: View {
    let state: AppState
    @Environment(\.palette) private var palette

    var body: some View {
        let session = state.wirelessSensors
        let transport = session.transport
        VStack(alignment: .leading, spacing: 10) {
            Text("Wireless sensors")
                .font(.system(size: 11, weight: .heavy)).tracking(1.8).textCase(.uppercase)
            Toggle("Automatically connect to pulse oximeter", isOn: Binding(
                get: { transport.autoConnectEnabled }, set: { state.setPulseOximeterAutoConnect($0) }))
                .frame(minHeight: 44)
            Text(transport.status.displayText)
                .font(.system(size: 13, weight: .semibold))
            if let device = transport.connectedDevice {
                Text(device.name).font(.system(size: 12, design: .monospaced))
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if session.previewIsFresh, let reading = session.preview {
                        Text("SpO₂ \(reading.spo2.map(String.init) ?? "—")% · Pulse \(reading.pulseRate.map(String.init) ?? "—") bpm")
                            .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    } else {
                        Text("No current valid reading").foregroundStyle(palette.fg2)
                    }
                }
                Text("Unvalidated consumer sensor · received time · signal quality unknown")
                    .font(.system(size: 11)).foregroundStyle(palette.fg2)
                if session.association != nil {
                    Text("Recording to \(state.casualtyId)").font(.system(size: 13, weight: .semibold))
                    HStack {
                        Button("Stop recording sensor") { state.invalidateWirelessSensorAssociation() }
                            .frame(minHeight: 44)
                        Spacer()
                        Button("Re-associate · resume sensor fields") {
                            Task { await state.associateConnectedSensorWithCurrentEncounter() }
                        }.frame(minHeight: 44).disabled(session.bindingInProgress)
                    }
                    Text("Operator corrections stay in control until you re-associate.")
                        .font(.system(size: 11)).foregroundStyle(palette.fg2)
                } else if session.resumableAssociation == nil {
                    Button(session.bindingInProgress ? "Associating…" : "Use this sensor for \(state.casualtyId)") {
                        Task { await state.associateConnectedSensorWithCurrentEncounter() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .buttonStyle(.bordered)
                    .disabled(session.bindingInProgress)
                    Text("Confirm the sensor is attached to this casualty before recording.")
                        .font(.system(size: 11)).foregroundStyle(palette.fg2)
                }
            }
            if session.association == nil, session.resumableAssociation != nil {
                Text("Recording paused · resumes for \(state.casualtyId) when this sensor reconnects")
                    .font(.system(size: 13, weight: .semibold))
                Button("Stop recording sensor") { state.invalidateWirelessSensorAssociation() }
                    .frame(minHeight: 44)
            }
            if case .selectionRequired = transport.status {
                Text("Choose the sensor attached to your casualty.").font(.system(size: 12))
                ForEach(transport.devices) { device in
                    Button(device.name) { transport.selectDevice(device.id) }
                        .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.bordered)
                }
            }
            if let message = session.message {
                Text(message).font(.system(size: 12)).foregroundStyle(palette.crit)
            }
            Text("First connection needs the app open. Reconnection uses the remembered sensor within iOS background limits. No vendor app or internet needed.")
                .font(.system(size: 11)).foregroundStyle(palette.fg2)
        }
        .foregroundStyle(palette.fg)
        .padding(16)
    }
}
