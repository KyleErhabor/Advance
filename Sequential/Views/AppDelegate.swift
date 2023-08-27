//
//  AppDelegate.swift
//  Sequential
//
//  Created by Kyle Erhabor on 7/30/23.
//

import AppKit
import OSLog

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
  // If we try to use @Environment(\.openWindow) in this delegate, we'll get a warning about it not being used in a
  // SwiftUI view (which will note that the value will not be updated). While it's not really a problem, we're better
  // off not worrying about what other side effects it may entail.
  var onOpenURL: (Seq) -> Void = { _ in }

  func application(_ application: NSApplication, open urls: [URL]) {
    do {
      onOpenURL(try .init(urls: urls))
    } catch {
      Logger.ui.error("\(error)")
    }
  }
}

func openFinder(selecting url: URL) {
  openFinder(selecting: [url])
}

func openFinder(selecting urls: [URL]) {
  NSWorkspace.shared.activateFileViewerSelecting(urls)
}

func openFinder(in url: URL) -> Bool {
  NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path())
}
