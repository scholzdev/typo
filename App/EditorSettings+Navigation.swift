import AppKit
import TypoKit

extension EditorView.Coordinator {
    // Runs on every defaults change, so it must be idempotent and cheap.
    func applyNavigationSettings(_ tv: NSTextView) {
        let s = NavigationSettings.current
        project?.navigation = s
        (tv as? EditorTextView)?.clickActions = (s.commandClick, s.optionClick)
    }
}
