import DesktopflowCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedSection: AppSection = .home

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1180, minHeight: 820)
    }

    private var sidebar: some View {
        List {
            Section("Workspace") {
                ForEach(AppSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        Label(section.title, systemImage: section.systemImage)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selectedSection == section ? Color.accentColor.opacity(0.14) : Color.clear)
                }
            }

            Section("Flows") {
                ForEach(model.flows) { flow in
                    Button {
                        model.selectFlow(flow.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(flow.name)
                                .font(.headline)
                            Text(flow.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(model.selectedFlowID == flow.id ? Color.secondary.opacity(0.10) : Color.clear)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Desktopflow")
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .home:
            home
        case .recorder:
            recorder
        case .editor:
            flowEditor
        case .runner:
            runnerConsole
        case .permissions:
            permissions
        }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(
                    title: "Overview",
                    subtitle: "Library status, selected flow summary, and current runner state."
                )

                statsRow

                GroupBox("Selected Flow") {
                    VStack(alignment: .leading, spacing: 16) {
                        if let flow = model.selectedFlow {
                            Text(flow.name)
                                .font(.title2.weight(.semibold))
                            Text(flow.description)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 20) {
                                keyValue("Steps", "\(flow.steps.count)")
                                keyValue("Default Timeout", "\(flow.defaultTimeoutMs) ms")
                                keyValue("Bundle ID", flow.targetHint.bundleID ?? "Unset")
                            }

                            PreviewSurface(flow: flow)
                                .frame(height: 300)
                        } else {
                            Text("Select a flow from the sidebar.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let error = model.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            statPanel(title: "Flows", value: "\(model.flows.count)")
            statPanel(title: "Anchors", value: "\(model.anchors.count)")
            statPanel(title: "Runner", value: model.lastRunReport?.status.rawValue.capitalized ?? "Idle")
        }
    }

    private var recorder: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(
                title: "Recorder",
                subtitle: "Capture clicks, drags, scrolls, and keys into a new flow."
            )

            Form {
                Section("Target") {
                    Picker("Target Window", selection: $model.selectedWindowID) {
                        ForEach(model.availableWindows) { window in
                            Text("\(window.appName) · \(window.title)")
                                .tag(Optional(window.id))
                        }
                    }

                    TextField("Saved Flow Name", text: $model.recorderFlowName)
                }

                Section("Controls") {
                    HStack(spacing: 10) {
                        Button("Refresh Windows") {
                            Task {
                                do {
                                    try await model.refreshWindows()
                                } catch {
                                    model.recorderStatus = error.localizedDescription
                                }
                            }
                        }

                        Button(model.isRecording ? "Recording…" : "Start Recording") {
                            Task {
                                await model.startRecording()
                            }
                        }
                        .buttonStyle(.borderedProminent)
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
                }

                Section("Status") {
                    Text(model.recorderStatus)
                        .foregroundStyle(model.isRecording ? .red : .secondary)
                    keyValue("Selected Window", model.selectedWindow?.title ?? "None")
                    keyValue("Captured Steps", "\(model.recordedSteps.count)")
                }
            }
            .formStyle(.grouped)

            GroupBox("Captured Actions") {
                if model.recordedSteps.isEmpty {
                    ContentUnavailableView("No Recorded Steps Yet", systemImage: "record.circle")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    List(model.recordedSteps) { step in
                        stepRow(step)
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 220)
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
    }

    private var flowEditor: some View {
        FlowEditorView()
    }

    private var runnerConsole: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(
                title: "Runner",
                subtitle: "Replay the selected flow and inspect step-level results."
            )

            HStack(spacing: 10) {
                Button("Run Selected Flow") {
                    Task {
                        await model.runSelectedFlow()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedFlow == nil || model.isRunningFlow)

                Button("Abort") {
                    Task {
                        await model.abortRunningFlow()
                    }
                }
                .disabled(!model.isRunningFlow)
            }
            .padding(.horizontal, 24)

            Form {
                Section("Status") {
                    Text(model.runnerStatus)
                        .foregroundStyle(model.isRunningFlow ? .red : .secondary)
                    if let flow = model.selectedFlow {
                        keyValue("Flow", flow.name)
                        keyValue("Steps", "\(flow.steps.count)")
                    }
                }

                if let report = model.lastRunReport {
                    Section("Last Run") {
                        keyValue("Status", report.status.rawValue.capitalized)
                        keyValue("Started", report.startedAt.formatted(date: .abbreviated, time: .standard))
                        keyValue("Finished", report.finishedAt.formatted(date: .omitted, time: .standard))
                        if let reason = report.stopReason {
                            Text(reason)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HSplitView {
                GroupBox("Flow Steps") {
                    if let flow = model.selectedFlow {
                        List(flow.steps) { step in
                            stepRow(step)
                        }
                        .listStyle(.inset)
                    } else {
                        ContentUnavailableView("No Runnable Flow", systemImage: "play.slash")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                GroupBox("Step Results") {
                    if let report = model.lastRunReport {
                        List(report.stepResults) { result in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.status.rawValue.capitalized)
                                    .font(.headline)
                                Text(result.reason ?? "Completed")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .listStyle(.inset)
                    } else {
                        ContentUnavailableView("No Run Results", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(
                title: "Permissions",
                subtitle: "Grant the system access needed for reliable recording and playback."
            )

            Form {
                Section("Required") {
                    permissionRow("Screen Recording", "Needed for live preview, anchor creation, and visual waits.")
                    permissionRow("Accessibility", "Needed for focusing windows and replaying synthesized input.")
                    permissionRow("Input Monitoring", "Needed for broader keyboard and mouse capture during recording.")
                }

                Section("Recommended Order") {
                    Text("1. Accessibility")
                    Text("2. Input Monitoring")
                    Text("3. Screen Recording")
                }
            }
            .formStyle(.grouped)

            Spacer(minLength: 0)
        }
    }

    private func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.weight(.semibold))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private func statPanel(title: String, value: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func permissionRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
        }
    }

    private func stepRow(_ step: FlowStep) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(step.type.rawValue)
                    .font(.headline)
                Spacer()
                Text("Step \(step.ordinal + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(stepSummary(step))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func keyValue(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
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
        case .scrollAt:
            let point = step.params.point ?? NormalizedPoint(x: 0, y: 0)
            return String(format: "Scroll at %.3f, %.3f with dx %d and dy %d.", point.x, point.y, step.params.deltaX ?? 0, step.params.deltaY ?? 0)
        case .dragTo:
            let start = step.params.point ?? NormalizedPoint(x: 0, y: 0)
            let end = step.params.endPoint ?? NormalizedPoint(x: 0, y: 0)
            return String(format: "Drag from %.3f, %.3f to %.3f, %.3f.", start.x, start.y, end.x, end.y)
        case .pressKey:
            let modifiers = step.params.modifiers.isEmpty ? "" : "\(step.params.modifiers.joined(separator: "+"))+"
            return "Press key \(modifiers)\(step.params.keyCode ?? "unknown")."
        case .checkpointScreenshot:
            return "Capture checkpoint '\(step.params.label ?? "checkpoint")'."
        }
    }
}

private struct PreviewSurface: View {
    let flow: Flow

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let insetX = size.width * 0.08
            let insetY = size.height * 0.10
            let rectWidth = size.width - (insetX * 2)
            let rectHeight = size.height - (insetY * 2)

            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor))
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.10))
                    .frame(width: rectWidth, height: rectHeight)
                    .overlay(alignment: .topLeading) {
                        ForEach(flow.steps.filter { $0.type == .clickAt }) { step in
                            if let point = step.params.point {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 12, height: 12)
                                    .offset(x: (rectWidth * point.x) - 6, y: (rectHeight * point.y) - 6)
                            }
                        }
                    }
            }
        }
    }
}
