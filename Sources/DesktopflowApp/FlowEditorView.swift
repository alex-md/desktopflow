import DesktopflowCore
import SwiftUI

struct FlowEditorView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if model.editorDraft != nil {
                HSplitView {
                    stepListPane
                    inspectorPane
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            } else {
                ContentUnavailableView("No Flow Draft", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Flow Editor")
                    .font(.largeTitle.weight(.semibold))
                Text("Edit actions, targeting, and timing without leaving the selected flow.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("New Flow") {
                    model.createNewFlowDraft()
                }
                Button("Duplicate") {
                    model.duplicateSelectedFlowIntoDraft()
                }
                Button("Revert") {
                    model.revertEditorDraft()
                }
                .disabled(model.editorDraft == nil || !model.editorIsDirty)
                Button("Save") {
                    Task {
                        await model.saveEditorDraft()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.editorDraft == nil)
                Button("Delete") {
                    Task {
                        await model.deleteSelectedFlow()
                    }
                }
                .disabled(model.editorDraft == nil)

                Spacer()

                Text(model.editorStatus)
                    .foregroundStyle(model.editorIsDirty ? .orange : .secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private var stepListPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Section("Flow") {
                    TextField("Flow name", text: Binding(
                        get: { model.editorDraft?.name ?? "" },
                        set: { newValue in
                            model.mutateEditorDraft { draft in
                                draft.name = newValue
                            }
                        }
                    ))

                    TextField("Description", text: Binding(
                        get: { model.editorDraft?.description ?? "" },
                        set: { newValue in
                            model.mutateEditorDraft { draft in
                                draft.description = newValue
                            }
                        }
                    ))

                    TextField("Default Timeout", text: Binding(
                        get: { String(model.editorDraft?.defaultTimeoutMs ?? 5_000) },
                        set: { newValue in
                            model.mutateEditorDraft { draft in
                                draft.defaultTimeoutMs = max(0, Int(newValue) ?? 0)
                            }
                        }
                    ))
                }

                Section("Targeting") {
                    TextField("Bundle ID", text: Binding(
                        get: { model.editorDraft?.targetHint.bundleID ?? "" },
                        set: { newValue in
                            model.mutateEditorDraft { draft in
                                draft.targetHint.bundleID = normalizedOptionalString(newValue)
                            }
                        }
                    ))
                    TextField("App Name", text: Binding(
                        get: { model.editorDraft?.targetHint.appName ?? "" },
                        set: { newValue in
                            model.mutateEditorDraft { draft in
                                draft.targetHint.appName = normalizedOptionalString(newValue)
                            }
                        }
                    ))
                    TextField("Window Title Contains", text: Binding(
                        get: { model.editorDraft?.targetHint.windowTitleContains ?? "" },
                        set: { newValue in
                            model.mutateEditorDraft { draft in
                                draft.targetHint.windowTitleContains = normalizedOptionalString(newValue)
                            }
                        }
                    ))
                }
            }
            .formStyle(.grouped)
            .frame(height: 260)

            HStack {
                Text("Actions")
                    .font(.headline)
                Spacer()
                Menu("Add Action") {
                    ForEach(StepType.allCases, id: \.self) { type in
                        Button(type.rawValue) {
                            let lastIndex = (model.editorDraft?.steps.count ?? 0) - 1
                            model.insertEditorStep(after: lastIndex >= 0 ? lastIndex : nil, type: type)
                        }
                    }
                }
            }

            List(selection: Binding(
                get: { model.selectedEditorStepID },
                set: { model.selectEditorStep($0) }
            )) {
                if let steps = model.editorDraft?.steps {
                    ForEach(steps) { step in
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
                        .tag(Optional(step.id))
                        .contextMenu {
                            Button("Move Up") {
                                model.moveEditorStep(step.id, direction: -1)
                            }
                            Button("Move Down") {
                                model.moveEditorStep(step.id, direction: 1)
                            }
                            Button("Duplicate") {
                                model.duplicateEditorStep(step.id)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                model.removeEditorStep(step.id)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 460)
    }

    private var inspectorPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inspector")
                .font(.headline)

            if let step = model.selectedEditorStep {
                Form {
                    Section("Action") {
                        Picker("Type", selection: Binding(
                            get: { model.selectedEditorStep?.type ?? .clickAt },
                            set: { model.replaceSelectedEditorStepType($0) }
                        )) {
                            ForEach(StepType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }

                        Toggle("Enabled", isOn: Binding(
                            get: { model.selectedEditorStep?.enabled ?? true },
                            set: { newValue in
                                model.mutateSelectedEditorStep { step in
                                    step.enabled = newValue
                                }
                            }
                        ))
                    }

                    Section("Step Settings") {
                        TextField("Timeout Override", text: Binding(
                            get: {
                                guard let timeout = model.selectedEditorStep?.timeoutMs else { return "" }
                                return String(timeout)
                            },
                            set: { newValue in
                                model.mutateSelectedEditorStep { step in
                                    step.timeoutMs = newValue.isEmpty ? nil : max(0, Int(newValue) ?? 0)
                                }
                            }
                        ))

                        TextField("Retry Attempts", text: Binding(
                            get: { String(model.selectedEditorStep?.retryPolicy?.maxAttempts ?? 1) },
                            set: { newValue in
                                model.mutateSelectedEditorStep { step in
                                    let attempts = max(1, Int(newValue) ?? 1)
                                    let backoff = step.retryPolicy?.backoffMs ?? 0
                                    step.retryPolicy = RetryPolicy(maxAttempts: attempts, backoffMs: backoff)
                                }
                            }
                        ))

                        TextField("Retry Backoff", text: Binding(
                            get: { String(model.selectedEditorStep?.retryPolicy?.backoffMs ?? 0) },
                            set: { newValue in
                                model.mutateSelectedEditorStep { step in
                                    let attempts = step.retryPolicy?.maxAttempts ?? 1
                                    let backoff = max(0, Int(newValue) ?? 0)
                                    step.retryPolicy = RetryPolicy(maxAttempts: attempts, backoffMs: backoff)
                                }
                            }
                        ))

                        TextField("Debug Note", text: Binding(
                            get: { model.selectedEditorStep?.debugNote ?? "" },
                            set: { newValue in
                                model.mutateSelectedEditorStep { step in
                                    step.debugNote = normalizedOptionalString(newValue)
                                }
                            }
                        ))
                    }

                    Section("Parameters") {
                        parametersView(for: step)
                    }

                    Section("Step Commands") {
                        HStack(spacing: 10) {
                            Button("Move Up") {
                                model.moveEditorStep(step.id, direction: -1)
                            }
                            Button("Move Down") {
                                model.moveEditorStep(step.id, direction: 1)
                            }
                            Button("Duplicate") {
                                model.duplicateEditorStep(step.id)
                            }
                            Button("Delete", role: .destructive) {
                                model.removeEditorStep(step.id)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView("Select a Step", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 420)
    }

    @ViewBuilder
    private func parametersView(for step: FlowStep) -> some View {
        switch step.type {
        case .attachWindow, .focusWindow:
            Text("This action has no editable parameters.")
                .foregroundStyle(.secondary)

        case .wait:
            TextField("Duration (ms)", text: Binding(
                get: { String(model.selectedEditorStep?.params.durationMs ?? 500) },
                set: { newValue in
                    model.mutateSelectedEditorStep { step in
                        step.params.durationMs = max(0, Int(newValue) ?? 0)
                    }
                }
            ))

        case .waitForAnchor:
            Picker("Anchor", selection: Binding(
                get: { model.selectedEditorStep?.params.anchorID },
                set: { newValue in
                    model.mutateSelectedEditorStep { step in
                        step.params.anchorID = newValue
                    }
                }
            )) {
                Text("None").tag(Optional<UUID>.none)
                ForEach(model.anchors) { anchor in
                    Text(anchor.name).tag(Optional(anchor.id))
                }
            }

            TextField("Poll Interval (ms)", text: Binding(
                get: { String(model.selectedEditorStep?.params.pollIntervalMs ?? 120) },
                set: { newValue in
                    model.mutateSelectedEditorStep { step in
                        step.params.pollIntervalMs = max(1, Int(newValue) ?? 120)
                    }
                }
            ))

        case .clickAt:
            HStack {
                Text("X")
                Slider(value: Binding(
                    get: { model.selectedEditorStep?.params.point?.x ?? 0.5 },
                    set: { newValue in
                        model.mutateSelectedEditorStep { step in
                            let current = step.params.point ?? NormalizedPoint(x: 0.5, y: 0.5)
                            step.params.point = NormalizedPoint(x: newValue, y: current.y)
                        }
                    }
                ), in: 0...1)
                Text(String(format: "%.3f", model.selectedEditorStep?.params.point?.x ?? 0.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Y")
                Slider(value: Binding(
                    get: { model.selectedEditorStep?.params.point?.y ?? 0.5 },
                    set: { newValue in
                        model.mutateSelectedEditorStep { step in
                            let current = step.params.point ?? NormalizedPoint(x: 0.5, y: 0.5)
                            step.params.point = NormalizedPoint(x: current.x, y: newValue)
                        }
                    }
                ), in: 0...1)
                Text(String(format: "%.3f", model.selectedEditorStep?.params.point?.y ?? 0.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Picker("Button", selection: Binding(
                get: { model.selectedEditorStep?.params.button ?? .left },
                set: { newValue in
                    model.mutateSelectedEditorStep { step in
                        step.params.button = newValue
                    }
                }
            )) {
                ForEach(MouseButton.allCases, id: \.self) { button in
                    Text(button.rawValue).tag(button)
                }
            }

        case .scrollAt:
            HStack {
                Text("X")
                Slider(value: Binding(
                    get: { model.selectedEditorStep?.params.point?.x ?? 0.5 },
                    set: { newValue in
                        model.mutateSelectedEditorStep { step in
                            let current = step.params.point ?? NormalizedPoint(x: 0.5, y: 0.5)
                            step.params.point = NormalizedPoint(x: newValue, y: current.y)
                        }
                    }
                ), in: 0...1)
                Text(String(format: "%.3f", model.selectedEditorStep?.params.point?.x ?? 0.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Y")
                Slider(value: Binding(
                    get: { model.selectedEditorStep?.params.point?.y ?? 0.5 },
                    set: { newValue in
                        model.mutateSelectedEditorStep { step in
                            let current = step.params.point ?? NormalizedPoint(x: 0.5, y: 0.5)
                            step.params.point = NormalizedPoint(x: current.x, y: newValue)
                        }
                    }
                ), in: 0...1)
                Text(String(format: "%.3f", model.selectedEditorStep?.params.point?.y ?? 0.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            TextField("Delta X", text: Binding(
                get: { String(model.selectedEditorStep?.params.deltaX ?? 0) },
                set: { newValue in
                    model.mutateSelectedEditorStep { step in
                        step.params.deltaX = Int(newValue) ?? 0
                    }
                }
            ))

            TextField("Delta Y", text: Binding(
                get: { String(model.selectedEditorStep?.params.deltaY ?? 0) },
                set: { newValue in
                    model.mutateSelectedEditorStep { step in
                        step.params.deltaY = Int(newValue) ?? 0
                    }
                }
            ))

        case .dragTo:
            Group {
                TextField("Start X", text: Binding(
                    get: { String(format: "%.3f", model.selectedEditorStep?.params.point?.x ?? 0.35) },
                    set: { newValue in
                        model.mutateSelectedEditorStep { step in
                            let current = step.params.point ?? NormalizedPoint(x: 0.35, y: 0.5)
                            step.params.point = NormalizedPoint(x: min(1, max(0, Double(newValue) ?? current.x)), y: current.y)
                        }
                    }
                ))

                TextField("Start Y", text: Binding(
                    get: { String(format: "%.3f", model.selectedEditorStep?.params.point?.y ?? 0.5) },
                    set: { newValue in
                        model.mutateSelectedEditorStep { step in
                            let current = step.params.point ?? NormalizedPoint(x: 0.35, y: 0.5)
                            step.params.point = NormalizedPoint(x: current.x, y: min(1, max(0, Double(newValue) ?? current.y)))
                        }
                    }
                ))

                TextField("End X", text: Binding(
                    get: { String(format: "%.3f", model.selectedEditorStep?.params.endPoint?.x ?? 0.7) },
                    set: { newValue in
                        model.mutateSelectedEditorStep { step in
                            let current = step.params.endPoint ?? NormalizedPoint(x: 0.7, y: 0.5)
                            step.params.endPoint = NormalizedPoint(x: min(1, max(0, Double(newValue) ?? current.x)), y: current.y)
                        }
                    }
                ))

                TextField("End Y", text: Binding(
                    get: { String(format: "%.3f", model.selectedEditorStep?.params.endPoint?.y ?? 0.5) },
                    set: { newValue in
                        model.mutateSelectedEditorStep { step in
                            let current = step.params.endPoint ?? NormalizedPoint(x: 0.7, y: 0.5)
                            step.params.endPoint = NormalizedPoint(x: current.x, y: min(1, max(0, Double(newValue) ?? current.y)))
                        }
                    }
                ))

                Picker("Button", selection: Binding(
                    get: { model.selectedEditorStep?.params.button ?? .left },
                    set: { newValue in
                        model.mutateSelectedEditorStep { step in
                            step.params.button = newValue
                        }
                    }
                )) {
                    ForEach(MouseButton.allCases, id: \.self) { button in
                        Text(button.rawValue).tag(button)
                    }
                }

                TextField("Duration (ms)", text: Binding(
                    get: { String(model.selectedEditorStep?.params.durationMs ?? 350) },
                    set: { newValue in
                        model.mutateSelectedEditorStep { step in
                            step.params.durationMs = max(0, Int(newValue) ?? 350)
                        }
                    }
                ))
            }

        case .pressKey:
            TextField("Key Code", text: Binding(
                get: { model.selectedEditorStep?.params.keyCode ?? "" },
                set: { newValue in
                    model.mutateSelectedEditorStep { step in
                        step.params.keyCode = newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    }
                }
            ))

            HStack(spacing: 8) {
                modifierToggle("command")
                modifierToggle("shift")
                modifierToggle("control")
                modifierToggle("option")
            }

            TextField("Hold Duration (ms)", text: Binding(
                get: { String(model.selectedEditorStep?.params.durationMs ?? 0) },
                set: { newValue in
                    model.mutateSelectedEditorStep { step in
                        step.params.durationMs = max(0, Int(newValue) ?? 0)
                    }
                }
            ))

        case .checkpointScreenshot:
            TextField("Label", text: Binding(
                get: { model.selectedEditorStep?.params.label ?? "" },
                set: { newValue in
                    model.mutateSelectedEditorStep { step in
                        step.params.label = normalizedOptionalString(newValue)
                    }
                }
            ))
        }
    }

    private func modifierToggle(_ modifier: String) -> some View {
        Toggle(modifier.capitalized, isOn: Binding(
            get: { model.selectedEditorStep?.params.modifiers.contains(modifier) ?? false },
            set: { newValue in
                let contains = model.selectedEditorStep?.params.modifiers.contains(modifier) ?? false
                if newValue != contains {
                    model.toggleSelectedModifier(modifier)
                }
            }
        ))
        .toggleStyle(.button)
    }

    private func stepSummary(_ step: FlowStep) -> String {
        switch step.type {
        case .attachWindow:
            return "Bind the configured target window."
        case .focusWindow:
            return "Bring the target window to the foreground."
        case .wait:
            return "\(step.params.durationMs ?? 0) ms wait."
        case .waitForAnchor:
            if let anchorID = step.params.anchorID,
               let anchor = model.anchors.first(where: { $0.id == anchorID }) {
                return "Wait for anchor \(anchor.name)."
            }
            return "Wait for an anchor."
        case .clickAt:
            let point = step.params.point ?? NormalizedPoint(x: 0.5, y: 0.5)
            return String(format: "Click %.3f, %.3f with %@ button.", point.x, point.y, (step.params.button ?? .left).rawValue)
        case .scrollAt:
            let point = step.params.point ?? NormalizedPoint(x: 0.5, y: 0.5)
            return String(format: "Scroll at %.3f, %.3f with dx %d and dy %d.", point.x, point.y, step.params.deltaX ?? 0, step.params.deltaY ?? 0)
        case .dragTo:
            let start = step.params.point ?? NormalizedPoint(x: 0.35, y: 0.5)
            let end = step.params.endPoint ?? NormalizedPoint(x: 0.7, y: 0.5)
            return String(format: "Drag from %.3f, %.3f to %.3f, %.3f with %@ button.", start.x, start.y, end.x, end.y, (step.params.button ?? .left).rawValue)
        case .pressKey:
            let modifiers = step.params.modifiers.isEmpty ? "" : "\(step.params.modifiers.joined(separator: "+"))+"
            if let durationMs = step.params.durationMs, durationMs > 0 {
                return "Press \(modifiers)\(step.params.keyCode ?? "UNKNOWN") for \(durationMs) ms."
            }
            return "Press \(modifiers)\(step.params.keyCode ?? "UNKNOWN")."
        case .checkpointScreenshot:
            return "Capture screenshot '\(step.params.label ?? "checkpoint")'."
        }
    }

    private func normalizedOptionalString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
