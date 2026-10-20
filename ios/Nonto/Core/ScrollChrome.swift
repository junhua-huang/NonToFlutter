import UIKit

/// Scope UIKit's native swipe behavior to the visible timeline. Never mutate a
/// SwiftUI toolbar preference from scroll geometry: bar/inset layout can feed
/// back into the observer (the navigation update in build 21.1's iOS 27 watchdog).
@MainActor
final class ScrollChrome: UIView {
    private static let owners = NSMapTable<UINavigationController, ScrollChrome>.weakToWeakObjects()
    private weak var controlledNavigation: UINavigationController?
    private var previousSwipeBehavior = false

    var isAttached: Bool { controlledNavigation?.hidesBarsOnSwipe == true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        isUserInteractionEnabled = false
        if window == nil { restoreNavigationBar(); return }
        attachIfNeeded()
        // SwiftUI can attach the marker before the NavigationStack's hosting
        // controller has its final parent, particularly inside a TabView.
        DispatchQueue.main.async { [weak self] in self?.attachIfNeeded() }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        attachIfNeeded()
    }
    private func attachIfNeeded() {
        guard window != nil, controlledNavigation == nil else { return }
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController,
               let navigation = (controller as? UINavigationController) ?? controller.navigationController {
                enableSwipe(in: navigation)
                return
            }
            responder = current.next
        }
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
