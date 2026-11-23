import SwiftUI
import TypoKit

extension SettingsKey {
    static let pinTabs = "navigationPinTabs"
    static let commandClick = "navigationCommandClick"
    static let optionClick = "navigationOptionClick"
    static let navigationDestination = "navigationDestination"
    static let doubleClickOpensPermanent = "navigationDoubleClickPermanent"
}

extension NavigationSettings {
    /// The settings as stored; an unset or unknown value keeps the default.
    static var current: NavigationSettings {
        let d = UserDefaults.standard
        var s = NavigationSettings.standard
        s.pinTabs = (d.string(forKey: SettingsKey.pinTabs).flatMap(TabPinning.init)) ?? s.pinTabs
        s.commandClick = (d.string(forKey: SettingsKey.commandClick).flatMap(ClickAction.init)) ?? s.commandClick
        s.optionClick = (d.string(forKey: SettingsKey.optionClick).flatMap(ClickAction.init)) ?? s.optionClick
        s.destination = (d.string(forKey: SettingsKey.navigationDestination).flatMap(Destination.init)) ?? s.destination
        s.doubleClickOpensPermanent = d.object(forKey: SettingsKey.doubleClickOpensPermanent) as? Bool ?? s.doubleClickOpensPermanent
        return s
    }
}

struct NavigationSettingsView: View {
    @AppStorage(SettingsKey.pinTabs) private var pinTabs = NavigationSettings.TabPinning.manually.rawValue
    @AppStorage(SettingsKey.commandClick) private var commandClick = NavigationSettings.ClickAction.jump.rawValue
    @AppStorage(SettingsKey.optionClick) private var optionClick = NavigationSettings.ClickAction.quickHelp.rawValue
    @AppStorage(SettingsKey.navigationDestination) private var destination = NavigationSettings.Destination.primary.rawValue
    @AppStorage(SettingsKey.doubleClickOpensPermanent) private var doubleClick = true

    var body: some View {
        Form {
            Section {
                Picker("Pin editor tabs", selection: $pinTabs) {
                    Text("Manually").tag("manually")
                    Text("Automatically").tag("automatically")
                }
                Text("Manually: a file opened by a single click replaces the italic preview tab. Automatically: every opened file gets its own tab.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Click on Code") {
                Picker("With Command", selection: $commandClick) { clickChoices }
                Picker("With Option", selection: $optionClick) { clickChoices }
            }
            Section("Navigation") {
                Picker("Destination", selection: $destination) {
                    Text("Primary Editor Pane").tag("primary")
                    Text("Focused Editor Pane").tag("focused")
                }
                Text("Where jumps, search results, problems, reference results and Quick Open open a file when the split editor is showing.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("With double-click", selection: $doubleClick) {
                    Text("Opens Permanent Tab").tag(true)
                    Text("Same as Click").tag(false)
                }
            }
        }
        .pane()
    }

    @ViewBuilder private var clickChoices: some View {
        Text("Jumps to Definition").tag("jump")
        Text("Shows Quick Help").tag("quickHelp")
        Text("Does Nothing").tag("none")
    }
}
