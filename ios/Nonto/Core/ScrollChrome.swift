import UIKit

/// Scope UIKit's native swipe behavior to the visible timeline. Never mutate a
/// SwiftUI toolbar preference from scroll geometry: bar/inset layout can feed
/// back into the observer (the navigation update in build 21.1's iOS 27 watchdog).
@MainActor
final class ScrollChrome: UIViewController {
    private static let owners = NSMapTable<UINavigationController, ScrollChrome>.weakToWeakObjects()
    private weak var controlledNavigation: UINavigationController?
    private var previousSwipeBehavior = false

    override func loadView() {
        let marker = UIView()
        marker.isUserInteractionEnabled = false
        marker.backgroundColor = .clear
        view = marker
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let navigationController { enableSwipe(in: navigationController) }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        restoreNavigationBar()
    }
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil { restoreNavigationBar() }
    }

    func enableSwipe(in navigation: UINavigationController) {
        guard controlledNavigation !== navigation else { return }
        restoreNavigationBar()
        // A filter change can replace the list before its old marker is
        // dismantled. Transfer ownership so old cleanup cannot undo the new list.
        Self.owners.object(forKey: navigation)?.restoreNavigationBar()
        previousSwipeBehavior = navigation.hidesBarsOnSwipe
        controlledNavigation = navigation
        Self.owners.setObject(self, forKey: navigation)
        navigation.hidesBarsOnSwipe = true
    }
    func restoreNavigationBar() {
        guard let navigation = controlledNavigation else { return }
        controlledNavigation = nil
        guard Self.owners.object(forKey: navigation) === self else { return }
        Self.owners.removeObject(forKey: navigation)
        navigation.hidesBarsOnSwipe = previousSwipeBehavior
        // Restore once when leaving the page, never during scroll/layout updates.
        if navigation.isNavigationBarHidden {
            navigation.setNavigationBarHidden(false, animated: false)
        }
    }
}
