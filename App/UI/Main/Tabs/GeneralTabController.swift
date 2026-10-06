//
//  GeneralTabController.swift
//  tabTestStoryboards
//
//  Created by Noah Nübling on 23.07.21.
//

import Cocoa
import ReactiveSwift
import ReactiveCocoa
import Sparkle
import ServiceManagement
import UniformTypeIdentifiers

class GeneralTabController: NSViewController {
    
    /// Convenience
//    var enabled: MutableProperty<Bool> { MainAppState.shared.appIsEnabled }
    
    /// Config
    var showInMenuBar = ConfigValue<Bool>(configPath: "General.showMenuBarItem")
    var checkForUpdates = ConfigValue<Bool>(configPath: "General.checkForUpdates")
    var getBetaVersions = ConfigValue<Bool>(configPath: "General.checkForPrereleases")
    
    /// Outlets
    
    @IBOutlet var mainView: NSView!
    
    @IBOutlet weak var masterStack: CollapsingStackView!
    
    @IBOutlet weak var enableToggle: NSControl!
    
    @IBOutlet weak var menuBarToggle: NSButton!
    
    @IBOutlet weak var updatesToggle: NSButton!
    @IBOutlet weak var betaToggle: NSButton!
    
    @IBOutlet weak var mainHidableSection: CollapsingStackView!
    @IBOutlet weak var updatesExtraSection: NSView!
    
    
    @IBOutlet weak var enabledHint: NSTextField!
    @IBOutlet weak var updatesHint: NSTextField!
    @IBOutlet weak var menuBarHint: NSTextField!
    
    /// Init
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        /// Determine width for this tab
        applyHardcodedTabWidth("general", self, widthControllingTextFields: [enabledHint, updatesHint, menuBarHint]);
        
        /// Replace enable checkBox with NSSwitch on newer macOS versions
        var usingSwitch = false
        if #available(macOS 10.15, *) {
            
            usingSwitch = true

            let state = enableToggle.value(forKey: "state")

            let switchView = NSSwitcherino()
            
            let superView = enableToggle.superview as! NSStackView
            superView.replaceSubview(enableToggle, with: switchView)
            NSLayoutConstraint.activate(transferredSuperViewConstraints(fromView: enableToggle, toView: switchView, transferSizeConstraints: false)) /// Currently unnecessary because there are no constraints
            transferHuggingAndCompressionResistance(fromView: enableToggle, toView: switchView)
            
            self.enableToggle = switchView

            self.enableToggle.setValue(state, forKey: "state")
        }
        
        /// Add accessibility identifier for NSSwitch
        ///     Note: We use this from the XCUI tests to take localization screenshots.
        self.enableToggle.setAccessibilityIdentifier("axEnableToggle")
        
        /// 
        /// Sync enabledToggle with Helper enabledState
        ///
        
        let enableTimeout = 7.0
        var enableTimeoutDisposable: Disposable? = nil
        var enableTimeoutTimer: DispatchSourceTimer? = nil
        
        let onToggle = { (doEnable: Bool) in
            
            /// Prevent the enable toggle from toggling when it is clicked
            self.enableToggle.intValue = self.enableToggle.intValue == 0 ? 1 : 0
            
            if doEnable {
                
                let userClickTS = CACurrentMediaTime()
                
                EnabledState.shared.enable(onComplete: { error in
                    
                    if error == nil {
                        
                        if #available(macOS 15.0, *) {
                            
                            /// [Jul 2025] The strange issues with enabling have been fixed by Apple since macOS 15.0 Sequoia. (Source: Enabling Guide: https://redirect.macmousefix.com/?target=mmf-ventura-enabling-guide)
                            ///     Due to this, the instructions on the `enable-timeout-toast` and the `is-strange-helper-alert` are outdated.
                            ///     We didn't get around to disabling those alerts during macOS 15's lifecycle, but now we're finally doing it during the macOS 26 Tahoe Beta.
                            ///
                            ///     Reasons for disabling the alerts:
                            ///         - The alerts' instructions were outdated.
                            ///         - The `enable-timeout-toast` would show still show up in weird situations.
                            ///             - Specifically, the `enable-timeout-toast` would show when enabling the helper for the first time, which sometimes took macOS a while. When macOS eventually did enable the helper, the accessibility sheet would show up, but then the  `enable-timeout-toast` would show up *behind* the accessibility sheet, which is janky.
                            ///     On keeping the alerts:
                            ///         - There are still rare situations where the app won't enable
                            ///             - But simply restarting the app always fixes this in my experience.
                            ///             - (I assume this is some quirk of LaunchServices, not a bug in MMF which we can fix.)
                            ///         - The guide that `enable-timeout-toast` linked to had a comment section (https://redirect.macmousefix.com/?target=mmf-ventura-enabling-guide)
                            ///             - But this had no comments In 2025 so far [Jul 2025]
                            ///         - If we ever wanna re-install `enable-timeout-toast` we need to fix the jank first! I added an `if window.attachedSheet == nil` check below to help but it's still kinda janky [Jul 2025]
                        }
                        else if #available(macOS 13.0, *) {
                        
                            /// Notes:
                            /// - Unfortunately there's a whole class of errors with enabling MMF under macOS 13 Ventura and later using the SMAppService API, where the error that the API returns is nil and there seems to be no direct way of finding out that things failed. None of these issues seem to have been fixed currently under macOS 14.2
                            ///     To help the user in these cases:
                            ///     - In the case that the system launches a 'strange' instance of MMF Helper which comes from another version of Mac Mouse Fix. We use `MessagePortUtility.checkHelperStrangenessReact()` to detect that and provide solution steps to the user.
                            ///     - For cases where the system doesn't seem to launch any instance of MMF Helper at all, we set a timout here and then show a toast that refers users to a help page.
                            
                            
                            /// Clean up
                            enableTimeoutDisposable?.dispose()
                            enableTimeoutTimer?.cancel()
                            
                            /// Create a signal that fires when either the app is enabled or a strange helper is detected.
                            let mergedSignal: Signal<Void, Never> = Signal.merge(
                                EnabledState.shared.signal.filter({ $0 == true }).map({ _ in () }),
                                MessagePortUtility.shared.strangeHelperDetected.map({ _ in () })
                            )
                            
                            /// Observe the signal
                            enableTimeoutDisposable = mergedSignal.observeValues({ _ in
                                
                                ///
                                /// Enabling __has not__ timed out
                                ///
                                
                                /// Clean up
                                enableTimeoutDisposable?.dispose()
                                enableTimeoutTimer?.cancel()
                            })
                            
                            /// Set up a timer that fires `enableTimeout` seconds after the user clicked
                            let timeSinceUserClick = CACurrentMediaTime() - userClickTS
                            var timerFireTime = DispatchTime.now() + enableTimeout - timeSinceUserClick
                            enableTimeoutTimer = DispatchSource.makeTimerSource(flags: [], queue: .main) /// Using main queue here since we're drawing UI from the callback
                            enableTimeoutTimer?.schedule(deadline: timerFireTime, repeating: .never, leeway: .nanoseconds(0))
                            enableTimeoutTimer?.setEventHandler(qos: .userInitiated, flags: [], handler: {
      
                                ///
                                /// Enabling __has__ timed out
                                ///
                                
                                /// Extend the enable timeout if the CPU is busy.
                                /// Notes:
                                /// -  We added this so the enableTimeout isn't triggered when the computer is starting up. I think what we really wanna be doing here is wait for all the login items to start before starting the enableTimeout. The login items are only started after most of the windows are restored. The CPU usage is an okay way to detect this startup sequence but far from perfect. The CPU usage will continute to be high during startup after the login items have been started. Also CPU can be high in other circumstances. CPU usage will be high in more cases than the ones we want to detect. But I think it's better to show enable-timeout-toast too little than too much since I don't want to confuse/clutter up normal users with it and users that actually can't enable Mac Mouse Fix are gonna find the toast, even if it doesn't show up 100% consistently.
                                /// - It's conceivable that on weaker machines the CPU usage never goes below our thrwshold and therefore the enable-timeout-message is never shown.
                                
                                if let cpuUsage = Utility_App.cpuUsage(includingNice: false) {
                                    
                                    var mightBeStartingUp = false
                                    
                                    for coreUsage in cpuUsage {
                                        if coreUsage.floatValue >= 0.5 {
                                            mightBeStartingUp = true
                                            break
                                        }
                                    }
                                    
                                    if mightBeStartingUp {
                                        timerFireTime = timerFireTime + enableTimeout
                                        enableTimeoutTimer?.schedule(deadline: timerFireTime)
                                        
                                        DDLogDebug("GeneralTabController - might be starting up - extending enable timeout. CPU usage: \(cpuUsage)")
                                        return
                                    }
                                }
                                
                                /// Clean up
                                enableTimeoutDisposable?.dispose()
                                
                                /// Show user feedback
                                if let window = MainAppState.shared.window {
                                    if window.attachedSheet == nil { /// [Jul 2025] Prevent the toast from showing up behind the accessibility sheet. This is still kinda jank but since this code only runs on macOS 13 and 14 (as of [Jul 2025]), it's not worth fixing. A better way would be to have the `mergedSignal` listen to anything that indicates the user no longer waiting for the helper being enabled: window resigning key, sheet being attached, tab being switched, helper sending mainApp any message, perhaps more I can't think of rn. Probably using NSNotificationCenter for this would be good.
                                        Toasts.showSimpleToast(name: "k-enable-timeout-toast")
                                    }
                                }
                            })
                            enableTimeoutTimer?.resume()
                        }
                        
                    } else { /// error != nil
                        
                        guard let error = error else { assert(false); return }
                        
                        
                        if #available(macOS 13.0, *), error.domain == "SMAppServiceErrorDomain", error.code == 1 {
                            
                            Toasts.showSimpleToast(name: "k-is-disabled-toast")
                        }
                        else { assert(false) }
                    }
                })
                
            } else { /// !doEnabled
                EnabledState.shared.disable()
            }
        }
        
        if usingSwitch, #available(macOS 10.15, *) {
            (enableToggle as? NSSwitcherino)?.reactive.boolValues.skip(first: 1).startWithValues(onToggle)
        } else {
            enableToggle.reactive.boolValues.observeValues(onToggle) /// Why are we using observe here and startWithValues above?
        }
        
        /// Declare signals
        
        /// UI <-> data bindings
        
        showInMenuBar <~ menuBarToggle.reactive.boolValues
        checkForUpdates <~ updatesToggle.reactive.boolValues
        getBetaVersions <~ betaToggle.reactive.boolValues
        
        if usingSwitch, #available(macOS 10.15, *) {
            (enableToggle as? NSSwitcherino)?.reactive.boolValue <~ EnabledState.shared
        } else {
            enableToggle.reactive.boolValue <~ EnabledState.shared
        }
        menuBarToggle.reactive.boolValue <~ showInMenuBar
        updatesToggle.reactive.boolValue <~ checkForUpdates
        betaToggle.reactive.boolValue <~ getBetaVersions
        
        /// Add 'Excluded Apps...' button
        ///     Created in code instead of in the storyboard so we don't have to edit the storyboard by hand.
        let excludedAppsButton = NSButton(title: MFLocalizedString("excluded-apps.open-button", comment: "Button in the General tab that opens the per-app exclusion sheet"), target: self, action: #selector(openExcludedApps))
        excludedAppsButton.bezelStyle = .rounded
        excludedAppsButton.setAccessibilityIdentifier("axExcludedAppsButton")
        mainHidableSection.addArrangedSubview(excludedAppsButton)
        if let previous = mainHidableSection.arrangedSubviews.dropLast().last {
            mainHidableSection.setCustomSpacing(12, after: previous)
        }
        
        mainHidableSection.reactive.isCollapsed <~ EnabledState.shared.producer.negate()
        updatesExtraSection.reactive.isCollapsed <~ checkForUpdates.producer.negate()
        
        /// Alert on betaToggle
        /// Notes:
        ///     - Disabling this now, because it's kind of unnecessary, and I don't know how this alert will interact, when a beta Version is acutally available and Sparkle wants to present a sheet as well. Ideally, we would want to present this sheet **before** we toggle the betaToggle, but right now we're just toggling it back if the user doesn't want to toggle it, so Sparkle still gets the message that it's been enabled.
        ///     - The alertStyle should maybe be .warning or sth instead of .informational.
        ///     - We could also put this info into a toas instead of an alert
        ///
        
//        betaToggle.reactive.boolValues.observeValues { betaGotEnabled in
//
//            if betaGotEnabled {
//
//                /// Create alert
//
//                let alert = NSAlert()
//                alert.alertStyle = .informational
//                alert.messageText = MFLocalizedString("beta-alert.title", comment: "")
//                alert.informativeText = MFLocalizedString("beta-alert.body", comment: "")
//                alert.addButton(withTitle: MFLocalizedString("beta-alert.confirm", comment: ""))
//                alert.addButton(withTitle: MFLocalizedString("beta-alert.back", comment: ""))
//
//                /// Display alert
//                guard let window = MainAppState.shared.window else { return }
//                alert.beginSheetModal(for: window) { response in
//                    if response != .alertFirstButtonReturn {
//                        /// Toggle back off
//                        self.betaToggle.state = .off
//                    }
//                }
//            }
//        }
        
        /// Side effects: Sparkle
        ///     See `applicationDidFinishLaunching` for context
        
        checkForUpdates.producer.skip(first: 1).startWithValues { doCheckUpdates in
            SparkleUpdaterController.resetSkippedVersions()
            if doCheckUpdates {
                SUUpdater.shared().checkForUpdatesInBackground()
            }
        }
        getBetaVersions.producer.skip(first: 1).startWithValues { doCheckBetas in
            SparkleUpdaterController.resetSkippedVersions()
            SparkleUpdaterController.enablePrereleaseChannel(doCheckBetas)
            if doCheckBetas {
                SUUpdater.shared().checkForUpdatesInBackground()
            }
        }
    }
}

// MARK: Excluded apps

extension GeneralTabController {
    @objc func openExcludedApps() {
        self.presentAsSheet(ExcludedAppsViewController())
    }
}

class ExcludedAppsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    
    /// Lets the user choose apps in which some features of Mac Mouse Fix are turned off.
    /// Stored at `General.excludedApps` as `{ bundleID: { buttons: Bool, scroll: Bool } }`. The Helper reads this in `SwitchMaster`.
    
    private struct Entry {
        var bundleID: String
        var buttons: Bool
        var scroll: Bool
    }
    
    private var entries: [Entry] = []
    private let tableView = NSTableView()
    private let removeButton = NSButton()
    
    private static let colApp = NSUserInterfaceItemIdentifier("app")
    private static let colButtons = NSUserInterfaceItemIdentifier("buttons")
    private static let colScroll = NSUserInterfaceItemIdentifier("scroll")
    
    // MARK: Load & store
    
    private func loadEntries() {
        entries = []
        guard let dict = config("General.excludedApps") as? NSDictionary else { return }
        for (key, value) in dict {
            guard let bundleID = key as? String, let value = value as? NSDictionary else { continue }
            entries.append(Entry(bundleID: bundleID,
                                 buttons: value.object(forKey: "buttons") as? Bool ?? false,
                                 scroll: value.object(forKey: "scroll") as? Bool ?? false))
        }
        entries.sort { Self.displayName($0.bundleID).localizedCaseInsensitiveCompare(Self.displayName($1.bundleID)) == .orderedAscending }
    }
    
    private func storeEntries() {
        let dict = NSMutableDictionary()
        for e in entries {
            dict[e.bundleID] = NSMutableDictionary(dictionary: ["buttons": e.buttons, "scroll": e.scroll])
        }
        setConfig("General.excludedApps", dict)
        commitConfig()
    }
    
    // MARK: App info
    
    private static func appURL(_ bundleID: String) -> URL? {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
    private static func displayName(_ bundleID: String) -> String {
        guard let url = appURL(bundleID) else { return bundleID } /// App is not installed anymore
        return FileManager.default.displayName(atPath: url.path)
    }
    private static func icon(_ bundleID: String) -> NSImage? {
        guard let url = appURL(bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
    
    // MARK: View
    
    override func loadView() {
        
        let title = NSTextField(labelWithString: MFLocalizedString("excluded-apps.title", comment: "Title of the per-app exclusion sheet"))
        title.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        
        let body = NSTextField(wrappingLabelWithString: MFLocalizedString("excluded-apps.body", comment: "Explanation at the top of the per-app exclusion sheet"))
        body.textColor = .secondaryLabelColor
        body.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        
        /// Table
        let appColumn = NSTableColumn(identifier: Self.colApp)
        appColumn.title = MFLocalizedString("excluded-apps.column.app", comment: "Column header: the app")
        appColumn.width = 220
        let buttonsColumn = NSTableColumn(identifier: Self.colButtons)
        buttonsColumn.title = MFLocalizedString("excluded-apps.column.buttons", comment: "Column header: checkbox to turn off button remapping (incl. Click and Drag) in this app")
        buttonsColumn.width = 70
        let scrollColumn = NSTableColumn(identifier: Self.colScroll)
        scrollColumn.title = MFLocalizedString("excluded-apps.column.scroll", comment: "Column header: checkbox to turn off scroll enhancements in this app")
        scrollColumn.width = 70
        for c in [appColumn, buttonsColumn, scrollColumn] { tableView.addTableColumn(c) }
        tableView.rowHeight = 24
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.dataSource = self
        tableView.delegate = self
        
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 200).isActive = true
        
        /// + / - buttons
        let addButton = NSButton(image: NSImage(named: NSImage.addTemplateName)!, target: self, action: #selector(addApps))
        addButton.bezelStyle = .smallSquare
        removeButton.image = NSImage(named: NSImage.removeTemplateName)
        removeButton.bezelStyle = .smallSquare
        removeButton.target = self
        removeButton.action = #selector(removeApps)
        removeButton.isEnabled = false
        let plusMinus = NSStackView(views: [addButton, removeButton])
        plusMinus.spacing = 0
        
        /// Done
        let doneButton = NSButton(title: MFLocalizedString("excluded-apps.done", comment: "Button that closes the per-app exclusion sheet"), target: self, action: #selector(done))
        doneButton.keyEquivalent = "\r"
        
        let bottomRow = NSStackView(views: [plusMinus, NSView(), doneButton])
        bottomRow.distribution = .fill
        
        let stack = NSStackView(views: [title, body, scrollView, bottomRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        for v in [body, scrollView, bottomRow] {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        }
        stack.widthAnchor.constraint(equalToConstant: 440).isActive = true
        
        self.view = stack
        
        loadEntries()
        tableView.reloadData()
    }
    
    // MARK: Actions
    
    @objc private func addApps() {
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [UTType.application]
        } else {
            panel.allowedFileTypes = ["com.apple.application"]
        }
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        guard let window = self.view.window else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            for url in panel.urls {
                guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue } /// Apps without bundleID can't be excluded
                if self.entries.contains(where: { $0.bundleID == bundleID }) { continue }
                self.entries.append(Entry(bundleID: bundleID, buttons: true, scroll: true)) /// Turn off everything by default
            }
            self.storeEntries()
            self.tableView.reloadData()
        }
    }
    
    @objc private func removeApps() {
        let rows = tableView.selectedRowIndexes
        guard !rows.isEmpty else { return }
        for i in rows.reversed() { entries.remove(at: i) }
        storeEntries()
        tableView.reloadData()
    }
    
    @objc private func toggleFeature(_ sender: NSButton) {
        let row = tableView.row(for: sender)
        guard row >= 0 && row < entries.count else { return }
        let on = sender.state == .on
        if sender.identifier == Self.colButtons {
            entries[row].buttons = on
        } else {
            entries[row].scroll = on
        }
        storeEntries()
    }
    
    @objc private func done() {
        self.dismiss(nil)
    }
    
    // MARK: Table
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return entries.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        
        guard let column = tableColumn?.identifier else { return nil }
        let entry = entries[row]
        
        if column == Self.colApp {
            let imageView = NSImageView(image: Self.icon(entry.bundleID) ?? NSImage())
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.widthAnchor.constraint(equalToConstant: 18).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 18).isActive = true
            let label = NSTextField(labelWithString: Self.displayName(entry.bundleID))
            label.lineBreakMode = .byTruncatingTail
            label.toolTip = entry.bundleID
            let cell = NSStackView(views: [imageView, label])
            cell.spacing = 6
            return cell
        } else {
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleFeature(_:)))
            checkbox.identifier = column
            checkbox.state = (column == Self.colButtons ? entry.buttons : entry.scroll) ? .on : .off
            return checkbox
        }
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        removeButton.isEnabled = !tableView.selectedRowIndexes.isEmpty
    }
}

// MARK: NSSwitcherino

@available(macOS 10.15, *)
extension Reactive where Base: NSSwitcherino {
    
    var boolValue: BindingTarget<Bool> {
        /// Difference to default implementation
        /// - This animates the state change
        
        return BindingTarget(lifetime: base.reactive.lifetime) { newValue in
            if (base.state == .on) != newValue {
                base.performClick(nil)
            }
        }
    }
    var boolValues: SignalProducer<Bool, Never> {
        /// Difference to default implementation
        /// - Doesn't animate when the user clicks
        return base.signal.producer.prefix(value: base.state == .on)
    }
}
@available(macOS 10.15, *)
@objc fileprivate class NSSwitcherino: NSSwitch {
    
    var signal: Signal<Bool, Never>
    var observer: Signal<Bool, Never>.Observer
    var eventMonitor: Any?
    
    required init() {
        let (o, i) = Signal<Bool, Never>.pipe()
        signal = o
        observer = i
        eventMonitor = nil
        super.init(frame: NSZeroRect)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseDown(with event: NSEvent) {
        self.isHighlighted = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .leftMouseDragged]) { event in
            if event.type == .leftMouseUp {
                self.isHighlighted = false
                if self == self.window?.contentView?.hitTest(event.locationInWindow) {
                    self.state = self.state == .on ? .off : .on
                    self.observer.send(value: (self.state == .on))
                }
                if let monitor = self.eventMonitor {
                    NSEvent.removeMonitor(monitor)
                    self.eventMonitor = nil
                } else { assert(false) }
            } else { /// mouseDragged event
                if self == self.window?.contentView?.hitTest(event.locationInWindow) {
                    self.isHighlighted = true
                } else {
                    self.isHighlighted = false
                }
            }
            return event
        } as AnyObject?
    }
}
