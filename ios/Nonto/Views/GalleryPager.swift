import SwiftUI
import UIKit

/// Keep page controllers alive throughout the interactive transition. SwiftUI only
/// receives the selected index after UIKit has finished (or cancelled) the swipe.
struct GalleryPager: UIViewControllerRepresentable {
    let images: [String]
    let index: Int
    var animated = true
    var onSelect: (Int) -> Void
    var onTransition: (Bool) -> Void
    var onTap: () -> Void
    var onLoaded: (UIImage) -> Void
    var onDismiss: () -> Void
    func makeUIViewController(context: Context) -> GalleryPagerController {
        GalleryPagerController(images: images, initial: index)
    }
    func updateUIViewController(_ controller: GalleryPagerController, context: Context) {
        controller.onSelect = onSelect; controller.onTransition = onTransition
        controller.onTap = onTap; controller.onLoaded = onLoaded; controller.onDismiss = onDismiss
        controller.show(images: images, index: index, animated: animated)
    }
}

@MainActor final class GalleryPagerController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
    private(set) var images: [String]
    private(set) var visibleIndex: Int
    private(set) var transitioning = false
    private var pages: [Int: GalleryImagePage] = [:]
    private var pendingImages: (images: [String], index: Int)?
    private var zoomed = false
    var onSelect: (Int) -> Void = { _ in }
    var onTransition: (Bool) -> Void = { _ in }
    var onTap: () -> Void = {}
    var onLoaded: (UIImage) -> Void = { _ in }
    var onDismiss: () -> Void = {}
    init(images: [String], initial: Int) {
        self.images = images; visibleIndex = GalleryPosition.clamped(initial, count: images.count)
        super.init(transitionStyle: .scroll, navigationOrientation: .horizontal, options: [.interPageSpacing: 16])
        dataSource = self; delegate = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        if let page = page(at: visibleIndex) { setViewControllers([page], direction: .forward, animated: false) }
        let dismissPan = UIPanGestureRecognizer(target: self, action: #selector(draggedDown(_:)))
        dismissPan.delegate = self; view.addGestureRecognizer(dismissPan)
    }
    private func page(at index: Int) -> GalleryImagePage? {
        guard images.indices.contains(index) else { return nil }
        if let page = pages[index] { return page }
        let page = GalleryImagePage(index: index, url: images[index], onTap: { [weak self] in self?.onTap() },
            onZoom: { [weak self] expanded in
                guard let self, self.visibleIndex == index else { return }
                self.zoomed = expanded; self.pagingScrollView?.isScrollEnabled = !expanded
            }, onLoaded: { [weak self] image in
                guard let self, self.visibleIndex == index else { return }
                self.onLoaded(image)
            })
        pages[index] = page; return page
    }
    private var pagingScrollView: UIScrollView? { view.subviews.compactMap { $0 as? UIScrollView }.first }
    func show(images: [String], index: Int, animated: Bool) {
        loadViewIfNeeded()
        if images != self.images {
            if transitioning { pendingImages = (images, index); return }
            self.images = images; pages.removeAll()
            visibleIndex = GalleryPosition.clamped(index, count: images.count)
            zoomed = false; pagingScrollView?.isScrollEnabled = true
            if let page = page(at: visibleIndex) { setViewControllers([page], direction: .forward, animated: false) }
            return
        }
        let target = GalleryPosition.clamped(index, count: images.count)
        // Rendering chrome during a drag must never reset UIKit's in-flight pages.
        guard target != visibleIndex, !transitioning, let page = page(at: target) else { return }
        (viewControllers?.first as? GalleryImagePage)?.resetZoom()
        zoomed = false; pagingScrollView?.isScrollEnabled = true
        let direction: UIPageViewController.NavigationDirection = target > visibleIndex ? .forward : .reverse
        setTransitioning(true)
        setViewControllers([page], direction: direction, animated: animated) { [weak self] _ in self?.finishTransition() }
    }
    private func setTransitioning(_ value: Bool) {
        transitioning = value
        DispatchQueue.main.async { [weak self] in
            guard let self, self.transitioning == value else { return }; self.onTransition(value)
        }
    }
    private func finishTransition() {
        if let page = viewControllers?.first as? GalleryImagePage { visibleIndex = page.index }
        zoomed = false; pagingScrollView?.isScrollEnabled = true
        pages = pages.filter { abs($0.key - visibleIndex) <= 1 }
        setTransitioning(false)
        let selected = visibleIndex
        DispatchQueue.main.async { [weak self] in
            guard let self, self.visibleIndex == selected else { return }; self.onSelect(selected)
        }
        if let pendingImages {
            self.pendingImages = nil; show(images: pendingImages.images, index: pendingImages.index, animated: false)
        }
    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? GalleryImagePage else { return nil }; return self.page(at: page.index - 1)
    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? GalleryImagePage else { return nil }; return self.page(at: page.index + 1)
    }
    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) { setTransitioning(true) }
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        finishTransition()
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, !zoomed, !transitioning else { return false }
        let velocity = pan.velocity(in: view)
        return velocity.y > 0 && velocity.y > abs(velocity.x) * 1.5
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    @objc private func draggedDown(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        if gesture.state == .ended && !zoomed && translation.y > 130 && translation.y > abs(translation.x) * 1.5 { onDismiss() }
    }
}

private final class GalleryImagePage: UIHostingController<ZoomImage> {
    let index: Int
    init(index: Int, url: String, onTap: @escaping () -> Void, onZoom: @escaping (Bool) -> Void, onLoaded: @escaping (UIImage) -> Void) {
        self.index = index
        super.init(rootView: ZoomImage(url: url, onTap: onTap, onZoom: onZoom, onLoaded: onLoaded))
        safeAreaRegions = []
    }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() { super.viewDidLoad(); view.backgroundColor = .black }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); resetZoom() }
    func resetZoom() {
        func reset(_ view: UIView) {
            if let surface = view as? ImageScrollView { surface.setZoomScale(surface.minimumZoomScale, animated: false) }
            else { for child in view.subviews { reset(child) } }
        }
        if isViewLoaded { reset(view) }
    }
}
