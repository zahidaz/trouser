import AppKit
import SwiftUI

extension BrowserWindowController {
    func setBackground(_ background: Bool) {
        if background, stage == nil {
            let size = viewportSize ?? (webView.bounds.size == .zero ? CGSize(width: 1280, height: 860) : webView.bounds.size)
            webView.removeFromSuperview()
            webView.translatesAutoresizingMaskIntoConstraints = true
            stage = StageWindow(hosting: webView, size: size)
        } else if !background, let stage {
            self.stage = nil
            stage.contentView = nil
            stage.close()
            attachWebView()
        }
    }

    func makeSplitViewController() -> NSSplitViewController {
        let sidebarController = NSHostingController(rootView: SidebarView(session: session))
        sidebarController.sizingOptions = []
        let sidebar = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebar.minimumThickness = 220
        sidebar.maximumThickness = 340

        let page = NSViewController()
        page.view = makePageView()
        let content = NSSplitViewItem(viewController: page)

        let inspectorController = NSHostingController(rootView: AutomationView(
            profile: session.name,
            supervisor: session.supervisor,
            setPaused: session.setPaused
        ))
        inspectorController.sizingOptions = []
        let inspector = NSSplitViewItem(inspectorWithViewController: inspectorController)
        inspector.minimumThickness = 280
        inspector.maximumThickness = 420
        inspector.isCollapsed = true

        let split = NSSplitViewController()
        split.splitViewItems = [sidebar, content, inspector]
        split.splitView.autosaveName = "trouser.browser"
        return split
    }

    private func makePageView() -> NSView {
        let approval = NSHostingView(rootView: ApprovalCard(supervisor: session.supervisor))
        marker.wantsLayer = true

        for view in [startPage, marker, approval] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            pageView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            approval.centerXAnchor.constraint(equalTo: pageView.centerXAnchor),
            approval.bottomAnchor.constraint(equalTo: pageView.bottomAnchor)
        ] + [startPage, marker].flatMap(pinToPage))
        attachWebView()
        return pageView
    }

    private func attachWebView() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        pageView.addSubview(webView, positioned: .below, relativeTo: startPage)
        layoutWebView()
    }

    private var viewportSize: CGSize? {
        session.settings.settings.viewport.map { viewport in
            let range = ProfileSettings.Viewport.range
            let clamp = { (value: Int) in CGFloat(min(max(value, range.lowerBound), range.upperBound)) }
            return CGSize(width: clamp(viewport.width), height: clamp(viewport.height))
        }
    }

    func layoutWebView() {
        if let stage {
            viewportSize.map(stage.setContentSize)
            return
        }
        guard webView.superview === pageView else { return }
        NSLayoutConstraint.deactivate(webViewConstraints)
        webViewConstraints = viewportSize.map { size in
            [
                webView.topAnchor.constraint(equalTo: pageView.safeAreaLayoutGuide.topAnchor),
                webView.leadingAnchor.constraint(equalTo: pageView.leadingAnchor),
                webView.widthAnchor.constraint(equalToConstant: size.width),
                webView.heightAnchor.constraint(equalToConstant: size.height)
            ]
        } ?? pinToPage(webView)
        NSLayoutConstraint.activate(webViewConstraints)
    }

    private func pinToPage(_ view: NSView) -> [NSLayoutConstraint] {
        [
            view.topAnchor.constraint(equalTo: pageView.safeAreaLayoutGuide.topAnchor),
            view.leadingAnchor.constraint(equalTo: pageView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: pageView.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: pageView.bottomAnchor)
        ]
    }
}
