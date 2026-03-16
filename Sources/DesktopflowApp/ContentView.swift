import DesktopflowCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            home
                .tabItem { Label("Home", systemImage: "square.grid.2x2") }

            recorder
                .tabItem { Label("Recorder", systemImage: "record.circle") }

            flowEditor
                .tabItem { Label("Flow Editor", systemImage: "list.bullet.rectangle") }

            runnerConsole
                .tabItem { Label("Runner", systemImage: "play.circle") }

            permissions
                .tabItem { Label("Permissions", systemImage: "checkmark.shield") }
        }
        .frame(minWidth: 1100, minHeight: 760)
    }

    private var home: some View {
        NavigationSplitView {
            List(selection: $model.selectedFlowID) {
                ForEach(model.flows) { flow in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(flow.name)
                            .font(.headline)
                        Text(flow.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                    .tag(flow.id)
                }
            }
            .navigationTitle("Flows")
        } detail: {
            VStack(alignment: .leading, spacing: 20) {
                if let flow = model.selectedFlow {
                    Text(flow.name)
                        .font(.largeTitle.bold())
                    Text(flow.description)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        StatCard(title: "Steps", value: "\(flow.steps.count)")
                        StatCard(title: "Anchors", value: "\(model.anchors.count)")
                        StatCard(title: "Default Timeout", value: "\(flow.defaultTimeoutMs) ms")
                    }

                    PreviewSurface(flow: flow)
                } else {
                    ContentUnavailableView("No flows yet", systemImage: "square.dashed")
                }

                if let lastError = model.lastError {
                    Text(lastError)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
    }

    private var flowEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Semantic Step List")
                .font(.title2.bold())

            if let flow = model.selectedFlow {
                List(flow.steps) { step in
                    HStack {
                        Text(String(format: "%02d", step.ordinal))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.type.rawValue)
                                .font(.headline)
                            Text(stepSummary(step))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                ContentUnavailableView("Select a flow", systemImage: "cursorarrow.click")
            }
        }
        .padding(24)
    }

    private var recorder: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Recorder")
                    .font(.title2.bold())
                Spacer()
                Button("Refresh Windows") {
                    Task {
                        do {
                            try await model.refreshWindows()
                        } catch {
                            model.recorderStatus = error.localizedDescription
                        }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Target Window")
                        .font(.headline)
                    Picker("Target Window", selection: $model.selectedWindowID) {
                        ForEach(model.availableWindows) { window in
                            Text("\(window.appName) · \(window.title)")
                                .tag(Optional(window.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 380, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Saved Flow Name")
                        .font(.headline)
                    TextField("Recorded Flow", text: $model.recorderFlowName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }
            }

            HStack(spacing: 12) {
                Button(model.isRecording ? "Recording…" : "Start Recording") {
                    Task {
                        await model.startRecording()
                    }
                }
                .disabled(model.isRecording || model.selectedWindow == nil)

                Button("Stop") {
                    model.stopRecording()
                }
                .disabled(!model.isRecording)

                Button("Save Recording") {
                    Task {
                        await model.saveRecording()
                    }
                }
                .disabled(model.recordedSteps.isEmpty)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Mouse clicks are captured only when the pointer is inside the selected window.", systemImage: "cursorarrow.click")
                    Label("Keyboard events are captured while the selected app is frontmost.", systemImage: "keyboard")
                    Label("For global key capture outside this app, macOS Input Monitoring permission is typically required.", systemImage: "hand.raised")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(model.recorderStatus)
                .foregroundStyle(model.isRecording ? .red : .secondary)

            if model.recordedSteps.isEmpty {
                ContentUnavailableView("No Recorded Steps Yet", systemImage: "record.circle")
            } else {
                List(model.recordedSteps) { step in
                    HStack {
                        Text(String(format: "%02d", step.ordinal))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.type.rawValue)
                                .font(.headline)
                            Text(stepSummary(step))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(24)
    }

    private var runnerConsole: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Runner Console")
                    .font(.title2.bold())
                Spacer()
                Button("Run Selected Flow") {
                    Task {
                        await model.runSelectedFlow()
                    }
                }
                .disabled(model.selectedFlow == nil || model.isRunningFlow)

                Button("Abort") {
                    Task {
                        await model.abortRunningFlow()
                    }
                }
                .disabled(!model.isRunningFlow)
            }

            if let flow = model.selectedFlow {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Targeting uses the window content rect as the canonical coordinate space.", systemImage: "scope")
                        Label("Anchor waits are the default synchronization mechanism; blind sleeps are secondary.", systemImage: "eye")
                        Label("Recorded click/key flows can be replayed now; anchor-based waits still need the capture/vision stack.", systemImage: "wrench.and.screwdriver")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(model.runnerStatus)
                    .foregroundStyle(model.isRunningFlow ? .red : .secondary)

                if let report = model.lastRunReport {
                    GroupBox("Last Run") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Status: \(report.status.rawValue)")
                            Text("Started: \(report.startedAt.formatted(date: .abbreviated, time: .standard))")
                            Text("Finished: \(report.finishedAt.formatted(date: .omitted, time: .standard))")
                            if let reason = report.stopReason {
                                Text("Reason: \(reason)")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                List {
                    Section("Steps") {
                        ForEach(flow.steps) { step in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.type.rawValue)
                                    .font(.headline)
                                Text(stepSummary(step))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    if let report = model.lastRunReport {
                        Section("Step Results") {
                            ForEach(report.stepResults) { result in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.status.rawValue.capitalized)
                                        .font(.headline)
                                    Text(result.reason ?? "Completed")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("No runnable flow", systemImage: "play.slash")
            }
        }
        .padding(24)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Permissions")
                .font(.title2.bold())

            PermissionRow(title: "Screen Recording", detail: "Required for live preview, anchor creation, and visual waits.")
            PermissionRow(title: "Accessibility", detail: "Required for focusing the game window and dispatching synthesized input.")
            PermissionRow(title: "Input Monitoring", detail: "Required for capturing global keyboard and mouse events during recording.")

            Spacer()
        }
        .padding(24)
    }

    private func stepSummary(_ step: FlowStep) -> String {
        switch step.type {
        case .attachWindow:
            return "Reacquire the configured target window."
        case .focusWindow:
            return "Bring the target window to the foreground."
        case .wait:
            return "\(step.params.durationMs ?? 0) ms fixed wait."
        case .waitForAnchor:
            return "Wait for anchor \(step.params.anchorID?.uuidString.prefix(8) ?? "unknown") with poll interval \(step.params.pollIntervalMs ?? 120) ms."
        case .clickAt:
            let point = step.params.point ?? NormalizedPoint(x: 0, y: 0)
            return String(format: "Click %.3f, %.3f in normalized content space.", point.x, point.y)
        case .pressKey:
            let modifiers = step.params.modifiers.isEmpty ? "" : "\(step.params.modifiers.joined(separator: "+"))+"
            return "Press key \(modifiers)\(step.params.keyCode ?? "unknown")."
        case .checkpointScreenshot:
            return "Capture checkpoint '\(step.params.label ?? "checkpoint")'."
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct PreviewSurface: View {
    let flow: Flow

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let horizontalInset = size.width * 0.1
            let verticalInset = size.height * 0.12
            let rectWidth = size.width - (horizontalInset * 2)
            let rectHeight = size.height - (verticalInset * 2)

            ZStack {
                LinearGradient(colors: [.indigo.opacity(0.9), .teal.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)

                RoundedRectangle(cornerRadius: 20)
                    .fill(.black.opacity(0.32))
                    .frame(width: rectWidth, height: rectHeight)
                    .overlay(alignment: .topLeading) {
                        ForEach(flow.steps.filter { $0.type == .clickAt }) { step in
                            if let point = step.params.point {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                                    .offset(x: (rectWidth * point.x) - 7, y: (rectHeight * point.y) - 7)
                            }
                        }
                    }

                VStack {
                    Text("Live Preview Contract")
                        .font(.headline)
                    Text("Click targets are projected into the window content rect, not the frame.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, rectHeight / 2 + 36)
            }
        }
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
