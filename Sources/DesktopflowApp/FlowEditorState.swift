import DesktopflowCore
import Foundation

@MainActor
extension AppModel {
    func createNewFlowDraft() {
        let flow = Flow(
            name: "Untitled Flow",
            description: "New editable automation flow.",
            targetHint: selectedFlow?.targetHint ?? TargetHint(),
            steps: []
        )
        selectedFlowID = nil
        editorDraft = flow
        editorSavedSnapshot = nil
        selectedEditorStepID = nil
        editorStatus = "New unsaved flow."
    }

    func duplicateSelectedFlowIntoDraft() {
        guard let baseFlow = editorDraft ?? selectedFlow else {
            createNewFlowDraft()
            return
        }

        var duplicate = baseFlow
        duplicate.id = UUID()
        duplicate.name = "\(baseFlow.name) Copy"
        duplicate.createdAt = .now
        duplicate.updatedAt = .now
        duplicate.steps = baseFlow.steps.enumerated().map { index, step in
            var copy = step
            copy.id = UUID()
            copy.ordinal = index
            return copy
        }

        selectedFlowID = nil
        editorDraft = duplicate
        editorSavedSnapshot = nil
        selectedEditorStepID = duplicate.steps.first?.id
        editorStatus = "Duplicated into a new unsaved draft."
    }

    func saveEditorDraft() async {
        guard var draft = editorDraft else {
            editorStatus = "Nothing to save."
            return
        }

        draft.updatedAt = .now
        draft.steps = normalizedSteps(draft.steps)

        do {
            try await flowRepository.saveFlow(draft)
            editorDraft = draft
            editorSavedSnapshot = draft
            editorStatus = "Saved '\(draft.name)'."
            await load()
            selectedFlowID = draft.id
            editorDraft = draft
            editorSavedSnapshot = draft
            selectedEditorStepID = draft.steps.first(where: { $0.id == selectedEditorStepID })?.id ?? draft.steps.first?.id
        } catch {
            editorStatus = error.localizedDescription
        }
    }

    func revertEditorDraft() {
        if let saved = editorSavedSnapshot {
            editorDraft = saved
            selectedEditorStepID = saved.steps.first(where: { $0.id == selectedEditorStepID })?.id ?? saved.steps.first?.id
            editorStatus = "Reverted changes."
            return
        }

        if let selectedFlow {
            editorDraft = selectedFlow
            editorSavedSnapshot = selectedFlow
            selectedEditorStepID = selectedFlow.steps.first?.id
            editorStatus = "Reverted changes."
            return
        }

        createNewFlowDraft()
    }

    func deleteSelectedFlow() async {
        if let saved = editorSavedSnapshot {
            do {
                try await flowRepository.deleteFlow(id: saved.id)
                editorDraft = nil
                editorSavedSnapshot = nil
                selectedEditorStepID = nil
                selectedFlowID = nil
                editorStatus = "Deleted '\(saved.name)'."
                await load()
            } catch {
                editorStatus = error.localizedDescription
            }
            return
        }

        createNewFlowDraft()
    }

    func selectEditorStep(_ id: UUID?) {
        selectedEditorStepID = id ?? editorDraft?.steps.first?.id
    }

    func insertEditorStep(after index: Int?, type: StepType) {
        ensureEditorDraft()
        guard var draft = editorDraft else { return }

        let insertionIndex = min(max((index ?? -1) + 1, 0), draft.steps.count)
        let newStep = defaultStep(for: type)
        draft.steps.insert(newStep, at: insertionIndex)
        draft.steps = normalizedSteps(draft.steps)
        editorDraft = draft
        selectedEditorStepID = newStep.id
        editorStatus = "Inserted \(type.rawValue)."
    }

    func duplicateEditorStep(_ id: UUID) {
        guard var draft = editorDraft, let index = draft.steps.firstIndex(where: { $0.id == id }) else { return }

        var copy = draft.steps[index]
        copy.id = UUID()
        draft.steps.insert(copy, at: index + 1)
        draft.steps = normalizedSteps(draft.steps)
        editorDraft = draft
        selectedEditorStepID = copy.id
        editorStatus = "Duplicated step."
    }

    func removeEditorStep(_ id: UUID) {
        guard var draft = editorDraft, let index = draft.steps.firstIndex(where: { $0.id == id }) else { return }
        draft.steps.remove(at: index)
        draft.steps = normalizedSteps(draft.steps)
        editorDraft = draft
        selectedEditorStepID = draft.steps.indices.contains(index) ? draft.steps[index].id : draft.steps.last?.id
        editorStatus = "Removed step."
    }

    func moveEditorStep(_ id: UUID, direction: Int) {
        guard
            var draft = editorDraft,
            let index = draft.steps.firstIndex(where: { $0.id == id })
        else { return }

        let targetIndex = index + direction
        guard draft.steps.indices.contains(targetIndex) else { return }
        draft.steps.swapAt(index, targetIndex)
        draft.steps = normalizedSteps(draft.steps)
        editorDraft = draft
        selectedEditorStepID = id
        editorStatus = direction < 0 ? "Moved step up." : "Moved step down."
    }

    func mutateEditorDraft(_ mutate: (inout Flow) -> Void) {
        ensureEditorDraft()
        guard var draft = editorDraft else { return }
        mutate(&draft)
        draft.steps = normalizedSteps(draft.steps)
        editorDraft = draft
    }

    func mutateSelectedEditorStep(_ mutate: (inout FlowStep) -> Void) {
        guard var draft = editorDraft else { return }
        let targetID = selectedEditorStepID ?? draft.steps.first?.id
        guard let targetID, let index = draft.steps.firstIndex(where: { $0.id == targetID }) else { return }
        mutate(&draft.steps[index])
        draft.steps = normalizedSteps(draft.steps)
        editorDraft = draft
        selectedEditorStepID = draft.steps[index].id
    }

    func replaceSelectedEditorStepType(_ type: StepType) {
        mutateSelectedEditorStep { step in
            step.type = type
            step.params = defaultParameters(for: type)
            if type != .waitForAnchor {
                step.preconditions = []
                step.postconditions = []
            }
            if type != .wait {
                step.timeoutMs = type == .waitForAnchor ? (step.timeoutMs ?? editorDraft?.defaultTimeoutMs) : step.timeoutMs
            }
        }
    }

    func toggleSelectedModifier(_ modifier: String) {
        mutateSelectedEditorStep { step in
            if step.params.modifiers.contains(modifier) {
                step.params.modifiers.removeAll(where: { $0 == modifier })
            } else {
                step.params.modifiers.append(modifier)
            }
            step.params.modifiers.sort()
        }
    }

    private func ensureEditorDraft() {
        if editorDraft == nil {
            createNewFlowDraft()
        }
    }

    private func normalizedSteps(_ steps: [FlowStep]) -> [FlowStep] {
        steps.enumerated().map { index, step in
            var normalized = step
            normalized.ordinal = index
            return normalized
        }
    }

    private func defaultStep(for type: StepType) -> FlowStep {
        switch type {
        case .attachWindow:
            return FlowStep.attachWindow(ordinal: 0)
        case .focusWindow:
            return FlowStep.focusWindow(ordinal: 0)
        case .wait:
            return FlowStep.wait(ordinal: 0, durationMs: 500)
        case .waitForAnchor:
            return FlowStep(
                ordinal: 0,
                type: .waitForAnchor,
                params: StepParameters(anchorID: anchors.first?.id, pollIntervalMs: 120),
                timeoutMs: 5_000
            )
        case .clickAt:
            return FlowStep.clickAt(ordinal: 0, point: NormalizedPoint(x: 0.5, y: 0.5))
        case .scrollAt:
            return FlowStep.scrollAt(ordinal: 0, point: NormalizedPoint(x: 0.5, y: 0.5), deltaY: -6)
        case .dragTo:
            return FlowStep.dragTo(
                ordinal: 0,
                from: NormalizedPoint(x: 0.35, y: 0.5),
                to: NormalizedPoint(x: 0.7, y: 0.5)
            )
        case .pressKey:
            return FlowStep.pressKey(ordinal: 0, keyCode: "SPACE", durationMs: 0)
        case .checkpointScreenshot:
            return FlowStep.checkpointScreenshot(ordinal: 0, label: "checkpoint")
        }
    }

    private func defaultParameters(for type: StepType) -> StepParameters {
        switch type {
        case .attachWindow, .focusWindow:
            return StepParameters()
        case .wait:
            return StepParameters(durationMs: 500)
        case .waitForAnchor:
            return StepParameters(anchorID: anchors.first?.id, pollIntervalMs: 120)
        case .clickAt:
            return StepParameters(point: NormalizedPoint(x: 0.5, y: 0.5), button: .left)
        case .scrollAt:
            return StepParameters(point: NormalizedPoint(x: 0.5, y: 0.5), deltaX: 0, deltaY: -6)
        case .dragTo:
            return StepParameters(
                point: NormalizedPoint(x: 0.35, y: 0.5),
                endPoint: NormalizedPoint(x: 0.7, y: 0.5),
                button: .left,
                durationMs: 350
            )
        case .pressKey:
            return StepParameters(keyCode: "SPACE", modifiers: [], durationMs: 0)
        case .checkpointScreenshot:
            return StepParameters(label: "checkpoint")
        }
    }
}
