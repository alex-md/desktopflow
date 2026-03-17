enum AppSection: String, CaseIterable, Identifiable {
    case home
    case recorder
    case editor
    case runner
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Overview"
        case .recorder: return "Recorder"
        case .editor: return "Flow Editor"
        case .runner: return "Runner"
        case .permissions: return "Permissions"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "rectangle.grid.2x2"
        case .recorder: return "record.circle"
        case .editor: return "slider.horizontal.3"
        case .runner: return "play.circle"
        case .permissions: return "checkmark.shield"
        }
    }
}
