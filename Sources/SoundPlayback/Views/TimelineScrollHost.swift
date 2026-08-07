import AppKit
import SwiftUI

struct TimelineScrollRequest: Equatable {
    let id: UUID
    let origin: CGPoint

    static func to(_ origin: CGPoint) -> TimelineScrollRequest {
        TimelineScrollRequest(id: UUID(), origin: origin)
    }
}

fileprivate final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// Scroll view that won't steal keyboard focus (avoids system beep on Delete, etc.).
fileprivate final class PassiveScrollView: NSScrollView {
    override var acceptsFirstResponder: Bool { false }
}

/// Dual scroll panes: headers scroll vertically only; timeline scrolls both axes.
/// Vertical origins stay locked together so rows never misalign.
struct AlignedTimelineHost<Header: View, Timeline: View>: NSViewRepresentable {
    var headerWidth: CGFloat
    var timelineWidth: CGFloat
    var contentHeight: CGFloat
    var scrollRequest: TimelineScrollRequest?
    var onOffsetChange: (CGFloat, CGFloat) -> Void
    @ViewBuilder var header: () -> Header
    @ViewBuilder var timeline: () -> Timeline

    func makeCoordinator() -> Coordinator {
        Coordinator(onOffsetChange: onOffsetChange)
    }

    func makeNSView(context: Context) -> NSView {
        let root = NSView()
        root.wantsLayer = true

        let headerScroll = makeScrollView(horizontal: false)
        headerScroll.hasVerticalScroller = false
        let timelineScroll = makeScrollView(horizontal: true)

        let headerDoc = FlippedDocumentView(frame: NSRect(x: 0, y: 0, width: headerWidth, height: contentHeight))
        let headerHosting = NSHostingView(rootView: header())
        headerHosting.frame = headerDoc.bounds
        headerHosting.autoresizingMask = [.width, .height]
        headerDoc.addSubview(headerHosting)
        headerScroll.documentView = headerDoc

        let timelineDoc = FlippedDocumentView(frame: NSRect(x: 0, y: 0, width: timelineWidth, height: contentHeight))
        let timelineHosting = NSHostingView(rootView: timeline())
        timelineHosting.frame = timelineDoc.bounds
        timelineHosting.autoresizingMask = [.width, .height]
        timelineDoc.addSubview(timelineHosting)
        timelineScroll.documentView = timelineDoc

        root.addSubview(headerScroll)
        root.addSubview(timelineScroll)

        context.coordinator.rootView = root
        context.coordinator.headerScroll = headerScroll
        context.coordinator.timelineScroll = timelineScroll
        context.coordinator.headerDocument = headerDoc
        context.coordinator.timelineDocument = timelineDoc
        context.coordinator.headerHosting = headerHosting
        context.coordinator.timelineHosting = timelineHosting
        context.coordinator.observe()

        return root
    }

    func updateNSView(_ root: NSView, context: Context) {
        context.coordinator.onOffsetChange = onOffsetChange
        layout(root: root, context: context)

        // Avoid animated transitions while the playhead drives ~30 updates/sec.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let headerHosting = context.coordinator.headerHosting {
                headerHosting.rootView = header()
            }
            if let timelineHosting = context.coordinator.timelineHosting {
                timelineHosting.rootView = timeline()
            }
        }

        resizeDocuments(context: context)

        guard let scrollRequest,
              scrollRequest.id != context.coordinator.lastAppliedRequestID else { return }
        context.coordinator.lastAppliedRequestID = scrollRequest.id
        context.coordinator.apply(origin: scrollRequest.origin)
    }

    private func makeScrollView(horizontal: Bool) -> NSScrollView {
        let scroll = PassiveScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = horizontal
        scroll.autohidesScrollers = false
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.allowsMagnification = false
        scroll.horizontalScrollElasticity = horizontal ? .allowed : .none
        scroll.verticalScrollElasticity = .allowed
        return scroll
    }

    private func layout(root: NSView, context: Context) {
        guard let headerScroll = context.coordinator.headerScroll,
              let timelineScroll = context.coordinator.timelineScroll else { return }
        let bounds = root.bounds
        headerScroll.frame = NSRect(x: 0, y: 0, width: headerWidth, height: bounds.height)
        timelineScroll.frame = NSRect(
            x: headerWidth,
            y: 0,
            width: max(0, bounds.width - headerWidth),
            height: bounds.height
        )
    }

    private func resizeDocuments(context: Context) {
        guard let headerScroll = context.coordinator.headerScroll,
              let timelineScroll = context.coordinator.timelineScroll,
              let headerDoc = context.coordinator.headerDocument,
              let timelineDoc = context.coordinator.timelineDocument,
              let headerHosting = context.coordinator.headerHosting,
              let timelineHosting = context.coordinator.timelineHosting
        else { return }

        let headerSize = NSSize(
            width: headerWidth,
            height: max(contentHeight, headerScroll.contentView.bounds.height)
        )
        let timelineSize = NSSize(
            width: max(timelineWidth, timelineScroll.contentView.bounds.width),
            height: max(contentHeight, timelineScroll.contentView.bounds.height)
        )

        let origin = timelineScroll.contentView.bounds.origin
        var changed = false
        if headerDoc.frame.size != headerSize {
            headerDoc.frame = NSRect(origin: .zero, size: headerSize)
            headerHosting.frame = headerDoc.bounds
            changed = true
        }
        if timelineDoc.frame.size != timelineSize {
            timelineDoc.frame = NSRect(origin: .zero, size: timelineSize)
            timelineHosting.frame = timelineDoc.bounds
            changed = true
        }
        if changed {
            context.coordinator.apply(origin: origin, notify: false)
        }
    }

    final class Coordinator {
        var rootView: NSView?
        var headerScroll: NSScrollView?
        var timelineScroll: NSScrollView?
        fileprivate var headerDocument: FlippedDocumentView?
        fileprivate var timelineDocument: FlippedDocumentView?
        var headerHosting: NSHostingView<Header>?
        var timelineHosting: NSHostingView<Timeline>?
        var onOffsetChange: (CGFloat, CGFloat) -> Void
        var isProgrammatic = false
        var lastAppliedRequestID: UUID?
        private var observations: [NSObjectProtocol] = []

        init(onOffsetChange: @escaping (CGFloat, CGFloat) -> Void) {
            self.onOffsetChange = onOffsetChange
        }

        func observe() {
            for observation in observations {
                NotificationCenter.default.removeObserver(observation)
            }
            observations.removeAll()

            guard let headerScroll, let timelineScroll else { return }
            headerScroll.contentView.postsBoundsChangedNotifications = true
            timelineScroll.contentView.postsBoundsChangedNotifications = true

            observations.append(
                NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: headerScroll.contentView,
                    queue: .main
                ) { [weak self] _ in
                    self?.headerScrolled()
                }
            )
            observations.append(
                NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: timelineScroll.contentView,
                    queue: .main
                ) { [weak self] _ in
                    self?.timelineScrolled()
                }
            )
        }

        private func headerScrolled() {
            guard !isProgrammatic,
                  let headerScroll,
                  let timelineScroll else { return }
            let y = headerScroll.contentView.bounds.origin.y
            var origin = timelineScroll.contentView.bounds.origin
            guard abs(origin.y - y) > 0.5 else { return }
            isProgrammatic = true
            origin.y = y
            timelineScroll.contentView.setBoundsOrigin(origin)
            timelineScroll.reflectScrolledClipView(timelineScroll.contentView)
            isProgrammatic = false
            onOffsetChange(origin.x, origin.y)
        }

        private func timelineScrolled() {
            guard !isProgrammatic,
                  let headerScroll,
                  let timelineScroll else { return }
            let origin = timelineScroll.contentView.bounds.origin
            var headerOrigin = headerScroll.contentView.bounds.origin
            if abs(headerOrigin.y - origin.y) > 0.5 {
                isProgrammatic = true
                headerOrigin.y = origin.y
                headerScroll.contentView.setBoundsOrigin(headerOrigin)
                headerScroll.reflectScrolledClipView(headerScroll.contentView)
                isProgrammatic = false
            }
            onOffsetChange(origin.x, origin.y)
        }

        func apply(origin: CGPoint, notify: Bool = true) {
            guard let headerScroll, let timelineScroll else { return }
            isProgrammatic = true
            let x = max(0, origin.x)
            let y = max(0, origin.y)
            timelineScroll.contentView.setBoundsOrigin(NSPoint(x: x, y: y))
            timelineScroll.reflectScrolledClipView(timelineScroll.contentView)
            headerScroll.contentView.setBoundsOrigin(NSPoint(x: 0, y: y))
            headerScroll.reflectScrolledClipView(headerScroll.contentView)
            isProgrammatic = false
            if notify {
                onOffsetChange(x, y)
            }
        }

        deinit {
            for observation in observations {
                NotificationCenter.default.removeObserver(observation)
            }
        }
    }
}
