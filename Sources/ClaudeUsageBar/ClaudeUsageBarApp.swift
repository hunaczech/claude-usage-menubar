import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            DropdownView()
                .environmentObject(model)
        } label: {
            Text(model.titleString)
                .foregroundStyle(model.titleColor)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: scenePhaseProxy) { _ in }
    }

    // Placeholder to keep `model` referenced from the scene; the real work is
    // kicked off when the dropdown first appears (see DropdownView.onAppear).
    private var scenePhaseProxy: Int { 0 }
}

/// The popover shown when the menu-bar item is clicked.
struct DropdownView: View {
    @EnvironmentObject private var model: AppModel
    @State private var started = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Claude Usage")
                .font(.headline)

            usageRow(label: "5-hour", pct: model.usage?.fiveHourPct)
            usageRow(label: "Weekly", pct: model.usage?.weeklyPct)

            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let fetchedAt = model.usage?.fetchedAt {
                Text("Updated \(fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button(action: { Task { await model.refresh() } }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshing)
                Spacer()
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }

            Toggle("Launch at login", isOn: Binding(
                get: { model.launchAtLoginEnabled },
                set: { model.setLaunchAtLogin($0) }
            ))

            Toggle("Notify at 90%", isOn: $model.notifyAt90)

            HStack {
                Text("Refresh every")
                Picker("", selection: $model.pollIntervalMinutes) {
                    Text("1 min").tag(1)
                    Text("5 min").tag(5)
                    Text("10 min").tag(10)
                    Text("30 min").tag(30)
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Divider()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 240)
        .onAppear {
            if !started {
                started = true
                model.start()
            }
        }
    }

    @ViewBuilder
    private func usageRow(label: String, pct: Double?) -> some View {
        HStack {
            Text(label)
            Spacer()
            if let pct {
                Text("\(Int(pct.rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(color(for: pct))
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
    }

    private func color(for pct: Double) -> Color {
        switch pct {
        case ..<70: return .green
        case ..<90: return .orange
        default: return .red
        }
    }
}
