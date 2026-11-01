import Combine

/// Editor selection with appearance preferences shared between editing sessions.
final class MarkupSession: ObservableObject {
    @Published var tool: AnnotationTool?
    @Published var color: AnnotationColor
    @Published var weight: LineWeight
    @Published var canUndo = false
    private var preferenceUpdates = Set<AnyCancellable>()

    init(settings: AppSettings = .shared) {
        color = settings.annotationColor
        weight = settings.lineWeight
        $color.dropFirst().removeDuplicates().sink { value in
            settings.annotationColor = value
        }.store(in: &preferenceUpdates)
        $weight.dropFirst().removeDuplicates().sink { value in
            settings.lineWeight = value
        }.store(in: &preferenceUpdates)
    }

    var style: MarkAppearance {
        MarkAppearance(color: color.nsColor, lineWidth: weight.lineWidth, fontSize: weight.fontSize)
    }
}
