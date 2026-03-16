import Foundation

public enum SampleData {
    public static let inventoryAsset = Asset(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        kind: "anchor-template",
        filePath: "WorkspaceData/assets/inventory_open.png",
        pixelSize: ScreenSize(width: 180, height: 120)
    )

    public static let inventoryAnchor = Anchor(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        assetID: inventoryAsset.id,
        name: "inventory_open",
        region: NormalizedRect(x: 0.72, y: 0.08, width: 0.20, height: 0.25),
        threshold: 0.93,
        matchMode: .grayscaleTemplate,
        notes: "Top-right inventory panel for the practice target."
    )

    public static let practiceFlow = Flow(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        name: "Practice Window Loop",
        description: "A starter flow for the first implementation spike: attach, wait on a visual anchor, click a point, press a key, and store a checkpoint.",
        targetHint: TargetHint(
            bundleID: "com.example.GameLauncher",
            appName: "Practice Java Window",
            windowTitleContains: "Practice Arena"
        ),
        defaultTimeoutMs: 5_000,
        steps: [
            .attachWindow(ordinal: 0),
            .focusWindow(ordinal: 1),
            .waitForAnchor(ordinal: 2, anchorID: inventoryAnchor.id, timeoutMs: 5_000),
            .clickAt(ordinal: 3, point: NormalizedPoint(x: 0.64, y: 0.38)),
            .pressKey(ordinal: 4, keyCode: "SPACE"),
            .checkpointScreenshot(ordinal: 5, label: "after_action")
        ]
    )
}
