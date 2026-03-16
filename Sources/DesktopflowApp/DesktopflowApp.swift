import DesktopflowStorage
import SwiftUI

@main
struct DesktopflowApp: App {
    @StateObject private var model = AppModel(
        flowRepository: FileFlowRepository(directoryURL: WorkspacePaths.flowsDirectory()),
        anchorRepository: FileAnchorRepository(directoryURL: WorkspacePaths.anchorsDirectory())
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .task {
                    await model.load()
                }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
