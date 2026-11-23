import Foundation
import TypstEngine

/// The Navigation settings that core decisions depend on; `standard` is the behaviour without any setting.
public struct NavigationSettings: Equatable, Sendable {
    public enum TabPinning: String, Sendable { case manually, automatically }
    public enum ClickAction: String, Sendable { case jump, quickHelp, none }
    public enum Destination: String, Sendable { case primary, focused }
    public enum Pane: Sendable { case first, second }

    /// Automatically: every opened file gets a permanent tab, never an italic preview tab.
    public var pinTabs = TabPinning.manually
    public var commandClick = ClickAction.jump
    public var optionClick = ClickAction.quickHelp
    public var destination = Destination.primary
    /// A double click in the file list opens a permanent tab; otherwise it acts as a single click.
    public var doubleClickOpensPermanent = true

    public init() {}
    public static let standard = NavigationSettings()

    /// The pane a navigation target opens in. `focusedSecond` is the second pane's file while that pane has focus
    /// (nil with the split closed or the first pane focused). A target the first pane already shows stays there:
    /// one file never sits in both panes.
    public func pane(for target: RelPath, first: RelPath?, focusedSecond: RelPath?) -> Pane {
        destination == .focused && focusedSecond != nil && target != first ? .second : .first
    }
}
