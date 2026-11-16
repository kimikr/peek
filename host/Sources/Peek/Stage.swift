import SwiftUI
import UIKit

/// Shows the preview as the root of its own window, the way the previewed app would run.
///
/// Inside Peek's own view hierarchy a preview is not a window root, and UIKit then omits
/// root-only features (e.g. a tab bar's bottom accessory). Peek's controls live in a second,
/// handle-sized window.
@MainActor
final class Stage {
    private var window: UIWindow?
    private var handle: HandleWindow?
    private weak var errorSheet: UIViewController?
    /// Overrides Peek put on the preview's root. Only those are removed again: SwiftUI stores the
    /// app's own `.preferredColorScheme` there too.
    private var overridesStyle = false
    private var overridesSize = false

    private var scene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    /// Puts `controller` on stage, or clears the stage when it is nil.
    func show(_ controller: UIViewController?, session: Session) {
        guard let controller, let scene else {
            window?.rootViewController?.dismiss(animated: false)
            window?.isHidden = true
            window?.rootViewController = nil
            handle?.isHidden = true
            return
        }
        let window = self.window ?? UIWindow(windowScene: scene)
        window.windowLevel = .normal + 1
        if window.rootViewController !== controller {
            window.rootViewController?.dismiss(animated: false)
            window.rootViewController = controller
            overridesStyle = false  // a fresh controller carries none of ours
            overridesSize = false
        }
        window.makeKeyAndVisible()
        self.window = window
        applyDisplay(session)

        let handle = self.handle ?? HandleWindow(windowScene: scene)
        handle.onTap = { [weak self, weak session] in
            guard let self, let session else { return }
            self.present(UIHostingController(rootView: MenuView().environment(session)))
        }
        handle.isHidden = false
        self.handle = handle
    }

    /// Light or dark appearance and text size chosen in the menu, applied to the preview only.
    ///
    /// Overrides go on the root controller, not the window, so system pop-up menus keep the
    /// phone's settings. Peek's own sheets reset them in `present`.
    func applyDisplay(_ session: Session, report: Bool = false) {
        guard let window, let controller = window.rootViewController else { return }
        if session.appearance != .system {
            controller.traitOverrides.userInterfaceStyle = session.appearance.style
            overridesStyle = true
        } else if overridesStyle {
            controller.traitOverrides.remove(UITraitUserInterfaceStyle.self)
            overridesStyle = false
        }
        if let category = session.textSize.category {
            controller.traitOverrides.preferredContentSizeCategory = category
            overridesSize = true
        } else if overridesSize {
            controller.traitOverrides.remove(UITraitPreferredContentSizeCategory.self)
            overridesSize = false
        }
        // Trait changes reach the preview on the next layout pass, so read them back after it.
        if report { DispatchQueue.main.async { [weak window, weak session] in
            guard let window, let session else { return }
            let now = window.rootViewController?.traitCollection
            session.log("display: \(session.appearance.rawValue), text \(session.textSize.rawValue) → preview sees "
                        + "style \(now?.userInterfaceStyle.rawValue ?? -1), size \(now?.preferredContentSizeCategory.rawValue ?? "?")")
        } }
    }

    /// What the preview window shows (with any sheet on it), as a PNG.
    func snapshot() -> Data? {
        guard let window, !window.isHidden else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.pngData { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    func setHealthy(_ healthy: Bool) {
        handle?.dot.backgroundColor = healthy ? .systemGreen : .systemOrange
    }

    /// Shows the compiler output (or why a build did not load) over the preview, or takes it
    /// down once the problem is gone.
    func showError(_ text: String?, title: String = "Build failed") {
        errorSheet?.dismiss(animated: true)
        errorSheet = nil
        guard let text, window?.isHidden == false else { return }
        let sheet = UIHostingController(rootView: BuildErrorView(text: text, title: title) { [weak self] in
            self?.errorSheet?.dismiss(animated: true)
        })
        sheet.sheetPresentationController?.detents = [.medium(), .large()]
        present(sheet)
        errorSheet = sheet
    }

    /// Presents Peek's own UI over the preview, with the phone's real text size and appearance
    /// rather than the preview's overrides.
    private func present(_ controller: UIViewController) {
        guard var top = window?.rootViewController else { return }
        controller.traitOverrides.preferredContentSizeCategory = UIApplication.shared.preferredContentSizeCategory
        if let style = scene?.traitCollection.userInterfaceStyle, style != .unspecified {
            controller.traitOverrides.userInterfaceStyle = style
        }
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        top.present(controller, animated: true)
    }
}

/// A small draggable dot that opens the menu without covering much of the preview.
private final class HandleWindow: UIWindow {
    let dot = UIView()
    var onTap: (() -> Void)?
    private static let side: CGFloat = 44

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        windowLevel = .normal + 2
        backgroundColor = .clear
        let host = UIViewController()
        host.view.backgroundColor = .clear
        rootViewController = host

        let side = Self.side
        let bounds = windowScene.screen.bounds
        let saved = UserDefaults.standard
        let x = saved.object(forKey: "handleCenterX") as? Double ?? Double(bounds.maxX - 16 - side / 2)
        let y = saved.object(forKey: "handleCenterY") as? Double ?? Double(bounds.maxY - 120)
        frame = CGRect(x: 0, y: 0, width: side, height: side)
        center = clamp(CGPoint(x: x, y: y), in: bounds)

        let backdrop = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        backdrop.frame = CGRect(x: 6, y: 6, width: side - 12, height: side - 12)
        backdrop.layer.cornerRadius = (side - 12) / 2
        backdrop.clipsToBounds = true
        backdrop.isUserInteractionEnabled = false
        host.view.addSubview(backdrop)

        dot.frame = CGRect(x: side / 2 - 6, y: side / 2 - 6, width: 12, height: 12)
        dot.layer.cornerRadius = 6
        dot.backgroundColor = .systemGreen
        dot.isUserInteractionEnabled = false
        host.view.addSubview(dot)

        host.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        host.view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragged)))
        host.view.isAccessibilityElement = true
        host.view.accessibilityLabel = "Peek menu"
        host.view.accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private func clamp(_ point: CGPoint, in bounds: CGRect) -> CGPoint {
        let inset = Self.side / 2
        return CGPoint(x: min(max(point.x, bounds.minX + inset), bounds.maxX - inset),
                       y: min(max(point.y, bounds.minY + inset), bounds.maxY - inset))
    }

    @objc private func tapped() { onTap?() }

    @objc private func dragged(_ pan: UIPanGestureRecognizer) {
        guard let screen = windowScene?.screen else { return }
        let move = pan.translation(in: nil)
        pan.setTranslation(.zero, in: nil)
        center = clamp(CGPoint(x: center.x + move.x, y: center.y + move.y), in: screen.bounds)
        if pan.state == .ended {
            UserDefaults.standard.set(Double(center.x), forKey: "handleCenterX")
            UserDefaults.standard.set(Double(center.y), forKey: "handleCenterY")
        }
    }
}

struct BuildErrorView: View {
    let text: String
    var title = "Build failed"
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(title, systemImage: "xmark.octagon.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Spacer()
                Button("Hide", action: dismiss)
            }
            .padding()
            Divider()
            ScrollView([.vertical, .horizontal]) {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
            }
        }
        .background(.regularMaterial)
    }
}
