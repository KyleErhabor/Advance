//
//  View.swift
//  Advance
//
//  Created by Kyle Erhabor on 7/31/23.
//

import OSLog
import SwiftUI
import UniformTypeIdentifiers

extension EdgeInsets {
  // Normally, NSTableView's style can just be set to .plain to take up the full size of the container. List, for some
  // reason, doesn't want to do that, so I have to do this little dance. I have no idea if this will transfer well to
  // other devices.
  static let listRow = Self(top: 0, leading: -8, bottom: 0, trailing: -9)

  init(_ insets: Double) {
    self.init(top: insets, leading: insets, bottom: insets, trailing: insets)
  }

  init(vertical: Double, horizontal: Double) {
    self.init(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
  }

  init(horizontal: Double, top: Double, bottom: Double) {
    self.init(top: top, leading: horizontal, bottom: bottom, trailing: horizontal)
  }
}

struct FileDialogOpenViewModifier: ViewModifier {
  static let id = "open"

  func body(content: Content) -> some View {
    content.fileDialogCustomizationID(Self.id)
  }
}

struct FileDialogCopyViewModifier: ViewModifier {
  static let id = "copy"

  func body(content: Content) -> some View {
    content
      .fileDialogCustomizationID(Self.id)
      .fileDialogConfirmationLabel("Copy")
  }
}

struct FileDialogCopyingViewModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .fileDialogCustomizationID(FileDialogCopyViewModifier.id)
      .fileDialogConfirmationLabel("Add")
  }
}

extension View {
  func fileDialogOpen() -> some View {
    self.modifier(FileDialogOpenViewModifier())
  }

  func fileDialogCopy() -> some View {
    self.modifier(FileDialogCopyViewModifier())
  }

  func fileDialogCopying() -> some View {
    self.modifier(FileDialogCopyingViewModifier())
  }
}

extension FileManager {
  func contents(at url: URL, options: DirectoryEnumerationOptions) -> [URL] {
    self
      .enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: options)?
      .contents() ?? []
  }
}

extension FileManager.DirectoryEnumerationOptions {
  init(includingHiddenFiles hidden: Bool, includingSubdirectories subdirectories: Bool) {
    // Packages are directories presented as files in Finder (e.g. an app). Generally, there is no reason to descend
    // into them, as their structures are usually distinct.
    self = .skipsPackageDescendants

    if !hidden {
      self.insert(.skipsHiddenFiles)
    }

    if !subdirectories {
      self.insert(.skipsSubdirectoryDescendants)
    }
  }
}

struct ImageTransferable: Transferable {
  let url: URL
  let type: UTType
  let original: Bool

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(importedContentType: .image, shouldAttemptToOpenInPlace: true) { received in
      try .init(received: received, type: .image)
    }

    FileRepresentation(importedContentType: .folder, shouldAttemptToOpenInPlace: true) { received in
      try .init(received: received, type: .folder)
    }
  }
}

extension URL {
  static let temporaryImagesDirectory = Self.temporaryDirectory.appending(components: Bundle.appID, "Images")
}

extension ImageTransferable {
  init(received: ReceivedTransferredFile, type: UTType) throws {
    guard URL.cachesDirectory.contains(url: received.file) else {
      self.init(url: received.file, type: type, original: received.isOriginalFile)

      return
    }

    let destination = URL.temporaryImagesDirectory.appending(component: received.file.lastPathComponent)

    Logger.sandbox.info("Dropped image at URL \"\(received.file.path)\" is a promise; moving to \"\(destination.path)\"...")

    let manager = FileManager.default

    try manager.creatingDirectories(at: destination.deletingLastPathComponent(), code: .fileNoSuchFile) {
      try manager.moveItem(at: received.file, to: destination)
    }

    self.init(url: destination, type: type, original: false)
  }
}

enum Navigator {
  case images
  case bookmarks
}

extension Navigator: Equatable {}
