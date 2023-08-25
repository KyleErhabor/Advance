//
//  LiveTextView.swift
//  Sequential
//
//  Created by Kyle Erhabor on 8/19/23.
//

import OSLog
import SwiftUI
import VisionKit

struct LiveTextView: NSViewRepresentable {
  typealias NSViewType = ImageAnalysisOverlayView

  private let analyzer = ImageAnalyzer()

  let url: URL
  @Binding var highlight: Bool
  private var supplementaryInterfaceHidden: Bool

  var hidden: Bool { !highlight && supplementaryInterfaceHidden }

  init(url: URL, highlight: Binding<Bool>) {
    self.url = url
    self._highlight = highlight
    self.supplementaryInterfaceHidden = false
  }

  func makeNSView(context: Context) -> NSViewType {
    let overlayView = ImageAnalysisOverlayView()
    overlayView.delegate = context.coordinator
    // .imageSubject seems to be very unreliable, so I'm limiting it to text only.
    overlayView.preferredInteractionTypes = .automaticTextOnly
    overlayView.setSupplementaryInterfaceHidden(hidden, animated: false)
    overlayView.selectableItemsHighlighted = highlight

    analyze(view: overlayView, coordinator: context.coordinator)

    return overlayView
  }

  func updateNSView(_ nsView: NSViewType, context: Context) {
    let coord = context.coordinator
    coord.parent = self

    nsView.selectableItemsHighlighted = highlight
    nsView.setSupplementaryInterfaceHidden(hidden, animated: true)

    guard coord.url != url || nsView.analysis == nil else {
      return
    }

    coord.url = url

    analyze(view: nsView, coordinator: coord)
  }

  static func dismantleNSView(_ nsView: ImageAnalysisOverlayView, coordinator: Coordinator) {
    coordinator.task?.cancel()
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  @MainActor
  func analyze(view: NSViewType, coordinator: Coordinator) {
    guard coordinator.task == nil else {
      return
    }

    coordinator.task = .init {
      view.analysis = await analyze()
      coordinator.task = nil
    }
  }

  func analyze() async -> ImageAnalysis? {
    // FIXME: VisionKit complains about analyzing over 10 images at times.
    //
    // The analyze method doesn't seem to check for cancellation itself. If we wanted to fix this, we'd need a handle
    // from users, but it would be difficult to schedule, given we'd need to know when a slot becomes available and
    // which view on-screen is most relevant to be given the priority (assuming we don't want to leave the user in a
    // weird state).
    guard !Task.isCancelled else {
      return nil
    }

    do {
      let exec = try await time {
        // I presume it's possible the image's orientation is not up (e.g. some images in Photos have are labeled right),
        // so it may be necessary to provide an orientation with this view. It would be simple, I just haven't tested it.
        try await analyzer.analyze(imageAt: url, orientation: .up, configuration: .init(.text))
      }

      Logger.ui.info("Took \(exec.duration) to analyze image at \"\(url.string)\"")

      return exec.value
    } catch {
      Logger.ui.error("Could not analyze image at \"\(url.string)\": \(error)")

      return nil
    }
  }

  class Coordinator: NSObject, ImageAnalysisOverlayViewDelegate {
    typealias Tag = ImageAnalysisOverlayView.MenuTag

    var parent: LiveTextView
    var url: URL
    var task: Task<Void, Never>?

    init(_ parent: LiveTextView) {
      self.parent = parent
      self.url = parent.url
      self.task = nil
    }

    func overlayView(_ overlayView: ImageAnalysisOverlayView, updatedMenuFor menu: NSMenu, for event: NSEvent, at point: CGPoint) -> NSMenu {
      // There better be a simpler way to do this.
      guard let vMenu = overlayView.superview?.superview?.superview?.menu else {
        return menu
      }

      let removal = [
        // Already implemented.
        menu.item(withTag: Tag.copyImage),
        // Too unstable (and slow).
        menu.item(withTag: Tag.shareImage),
        // This always opens in Safari, which is annoying.
        //
        // I wonder if other search engines are considered. How about other languages?
        menu.item(withTitle: "Search With Google")
      ].compactMap { $0 }

      removal.forEach(menu.removeItem)

      let items = menu.items

      if !items.isEmpty {
        // ... and this as well.
        vMenu.addItem(.separator())
        items.forEach { item in
          menu.removeItem(item)
          vMenu.addItem(item)
        }
      }

      return vMenu
    }

    func overlayView(_ overlayView: ImageAnalysisOverlayView, highlightSelectedItemsDidChange highlightSelectedItems: Bool) {
      parent.highlight = highlightSelectedItems
    }
  }
}

// View modifiers.
extension LiveTextView {
  func supplementaryInterfaceHidden(_ hidden: Bool) -> Self {
    var this = self
    this.supplementaryInterfaceHidden = hidden

    return this
  }
}
