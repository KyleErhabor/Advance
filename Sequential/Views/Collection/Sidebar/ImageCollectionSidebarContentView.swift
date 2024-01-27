//
//  ImageCollectionSidebarContentView.swift
//  Sequential
//
//  Created by Kyle Erhabor on 10/11/23.
//

import Defaults
import Combine
import QuickLook
import OSLog
import SwiftUI

struct ImageCollectionSidebarBookmarkButtonView: View {
  let title: LocalizedStringKey
  @Binding var showing: Bool

  var body: some View {
    Toggle(title, systemImage: "bookmark", isOn: $showing)
      .labelStyle(.iconOnly)
      .buttonStyle(.plain)
      .toggleStyle(.button)
      .symbolVariant(showing ? .fill : .none)
      .foregroundStyle(Color(showing ? .controlAccentColor : .secondaryLabelColor))
  }
}

struct ImageCollectionSidebarFilterView: View {
  @Environment(ImageCollection.self) private var collection
  @Environment(\.id) private var id
  @Environment(\.navigationColumns) @Binding private var columns
  @FocusState private var isSearchFocused
  private var isSearching: Bool {
    !collection.sidebarSearch.isEmpty
  }

  var body: some View {
    HStack(alignment: .top, spacing: 4) {
      Button("Search.Interaction", systemImage: "magnifyingglass") {
        // The reason we're doing it like this is because search may already be focused but not reflected in the sidebar.
        // In other words, this button performs a search. We don't always need to, since isSearchFocused changing its
        // state also triggers a search.
        if isSearchFocused {
          search()
        } else {
          isSearchFocused = true
        }
      }
      .buttonStyle(.borderless)
      .labelStyle(.iconOnly)
      .help("Search.Interaction")

      @Bindable var collect = collection

      // TODO: Figure out how to disallow tabbing when the user is not searching
      TextField("Search", text: $collect.sidebarSearch, prompt: Text(isSearchFocused ? "Search" : ""))
        .textFieldStyle(.plain)
        .font(.subheadline)
        .focused($isSearchFocused)
        .focusedSceneValue(\.searchSidebar, .init(identity: id) {
          withAnimation {
            columns = .all
          } completion: {
            isSearchFocused = true
          }
        })
        .onSubmit {
          search()
        }.onChange(of: isSearchFocused) { focusedPrior, _ in
          guard focusedPrior else {
            return
          }

          search()
        }

      let showingBookmarks = collection.sidebarPage == \.bookmarks
      let showing = Binding {
        showingBookmarks
      } set: { show in
        collection.sidebarPage = show ? \.bookmarks : \.images

        collection.updateBookmarks()
      }

      let title: LocalizedStringKey = showingBookmarks ? "Images.Bookmarks.Hide" : "Images.Bookmarks.Show"

      ImageCollectionSidebarBookmarkButtonView(title: title, showing: showing)
        .help(title)
        .visible(!isSearching)
        .disabled(isSearching)
        .overlay {
          Button("Clear", systemImage: "xmark.circle.fill", role: .cancel) {
            collection.sidebarSearch = ""

            search()
          }
          .buttonStyle(.borderless)
          .labelStyle(.iconOnly)
          .imageScale(.small)
          .visible(isSearching)
          .disabled(!isSearching)
        }
    }
  }

  func search() {
    collection.sidebarPage = \.search

    collection.updateBookmarks()
  }
}

struct ImageCollectionSidebarItemView: View {
  let image: ImageCollectionItemImage

  var body: some View {
    VStack {
      ImageCollectionItemView(image: image)
        .aspectRatio(image.properties.sized.aspectRatio, contentMode: .fit)
        .overlay(alignment: .topTrailing) {
          Image(systemName: "bookmark")
            .symbolVariant(.fill)
            .symbolRenderingMode(.multicolor)
            .opacity(0.8)
            .imageScale(.large)
            .shadow(radius: 0.5)
            .padding(4)
            .visible(image.bookmarked)
        }

      // Interestingly, this can be slightly expensive.
      let path = image.url.lastPathComponent

      Text(path)
        .font(.subheadline)
        .padding(.init(vertical: 4, horizontal: 8))
        .background(.fill.tertiary, in: .rect(cornerRadius: 4))
        // TODO: Replace this for an expansion tooltip (like how NSTableView has it)
        //
        // I tried this before, but couldn't get sizing or the trailing ellipsis to work properly.
        .help(path)
    }
    // This is not an image editor, but I don't mind some functionality that's associated with image editors. Being
    // able to drag images out of the app and drop them elsewhere just feels natural.
    .draggable(image.url) {
      ImageCollectionItemView(image: image)
    }
  }
}

struct ImageCollectionSidebarContentView: View {
  @Environment(ImageCollection.self) private var collection
  @Environment(ImageCollectionSidebar.self) private var sidebar
  @Environment(\.prerendering) private var prerendering
  @Environment(\.id) private var id
  @Environment(\.loaded) private var loaded
  @Environment(\.detailScroller) private var detailScroller
  @Default(.importHiddenFiles) private var importHidden
  @Default(.importSubdirectories) private var importSubdirectories
  @Default(.resolveCopyingConflicts) private var resolveCopyingConflicts
  @State private var quickLookItems = [URL]()
  @State private var selectedQuickLookItem: URL?
  @State private var quickLookScopes = [ImageCollectionItemImage: ImageCollectionItemImage.Scope]()
  @State private var isPresentingCopyFilePicker = false
  @State private var selectedCopyFiles = ImageCollectionSidebar.Selection()
  @State private var error: String?
  private var selection: ImageCollectionSidebar.Selection { sidebar.selection }
  private var selected: Binding<ImageCollectionSidebar.Selection> {
    .init {
      sidebar.selection
    } set: { selection in
      let id = images(from: selection.subtracting(sidebar.selection)).last?.id

      if let id {
        detailScroller.scroll(id)
      }

      sidebar.selection = selection
    }
  }
  private var isPresentingErrorAlert: Binding<Bool> {
    .init {
      error != nil
    } set: { present in
      if !present {
        error = nil
      }
    }
  }

  var body: some View {
    ScrollViewReader { proxy in
      List(selection: selected) {
        ForEach(sidebar.images) { image in
          ImageCollectionSidebarItemView(image: image)
            .anchorPreference(key: VisiblePreferenceKey<ImageCollectionItemImage.ID>.self, value: .bounds) {
              [.init(item: image.id, anchor: $0)]
            }
        }.onMove { from, to in
          collection.order.elements.move(fromOffsets: from, toOffset: to)
          collection.update()

          Task(priority: .medium) {
            do {
              try await collection.persist(id: id)
            } catch {
              Logger.model.error("Could not persist image collection \"\(id)\" (via sidebar image move): \(error)")
            }
          }
        }
        // This adds a "Delete" menu item under Edit.
        .onDelete { offsets in
          collection.order.elements.remove(atOffsets: offsets)
          collection.update()

          Task(priority: .medium) {
            do {
              try await collection.persist(id: id)
            } catch {
              Logger.model.error("Could not persist image collection \"\(id)\" (via menu bar delete): \(error)")
            }
          }
        }
      }.backgroundPreferenceValue(VisiblePreferenceKey<ImageCollectionItemImage.ID>.self) { items in
        GeometryReader { proxy in
          let local = proxy.frame(in: .local)
          let id = items
            .filter { local.contains(proxy[$0.anchor]) }
            .middle?.item

          Color.clear.onChange(of: id) {
            sidebar.current = id
          }
        }
      }.onDeleteCommand {
        collection.order.subtract(sidebar.selection)
        collection.update()

        Task(priority: .medium) {
          do {
            try await collection.persist(id: id)
          } catch {
            Logger.model.error("Could not persist image collection \"\(id)\" (via delete key): \(error)")
          }
        }
      }.onChange(of: collection.sidebarPage) {
        guard let id = sidebar.current else {
          return
        }

        proxy.scrollTo(id, anchor: .center)
      }
    }.safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 0) {
        Divider()

        ImageCollectionSidebarFilterView()
          .padding(8)
      }
    }
    .copyable(urls(from: sidebar.selection))
    // TODO: Figure out how to extract this.
    //
    // I tried moving this into a ViewModifier and View, but the passed binding for the selected item wouldn't always
    // be reflected.
    .quickLookPreview($selectedQuickLookItem, in: quickLookItems)
    .contextMenu { ids in
      let bookmarked = Binding {
        !ids.isEmpty && isBookmarked(selection: ids)
      } set: { bookmarked in
        bookmark(images: images(from: ids), value: bookmarked)
      }

      Section {
        Button("Finder.Show") {
          openFinder(selecting: urls(from: ids))
        }

        Button("Quick Look") {
          guard selectedQuickLookItem == nil else {
            selectedQuickLookItem = nil

            return
          }

          quicklook(images: images(from: ids))
        }
      }

      Section {
        Button("Copy") {
          let urls = urls(from: ids)

          if !NSPasteboard.general.write(items: urls as [NSURL]) {
            Logger.ui.error("Failed to write URLs \"\(urls.map(\.string))\" to pasteboard")
          }
        }

        let isPresented = Binding {
          isPresentingCopyFilePicker
        } set: { isPresenting in
          isPresentingCopyFilePicker = isPresenting
          selectedCopyFiles = ids
        }

        ImageCollectionCopyingView(isPresented: isPresented) { destination in
          Task(priority: .medium) {
            do {
              try await copy(images: images(from: ids), to: destination)
            } catch {
              self.error = error.localizedDescription
            }
          }
        }
      }

      Section {
        ImageCollectionBookmarkView(showing: bookmarked)
      }
    }.fileImporter(isPresented: $isPresentingCopyFilePicker, allowedContentTypes: [.folder]) { result in
      switch result {
        case .success(let url):
          Task(priority: .medium) {
            do {
              try await copy(images: images(from: selectedCopyFiles), to: url)
            } catch {
              self.error = error.localizedDescription
            }
          }
        case .failure(let err):
          Logger.ui.info("\(err)")
      }
    }
    .fileDialogCopy()
    .alert(self.error ?? "", isPresented: isPresentingErrorAlert) {}
    .focusedValue(\.openFinder, .init(enabled: !sidebar.selection.isEmpty, state: true, menu: .init(identity: sidebar.selection) {
      openFinder(selecting: urls(from: sidebar.selection))
    }))
    .focusedValue(\.sidebarQuicklook, .init(enabled: !sidebar.selection.isEmpty, state: true, menu: .init(identity: quickLookItems) {
      guard selectedQuickLookItem == nil else {
        selectedQuickLookItem = nil

        return
      }

      quicklook(images: images(from: sidebar.selection))
    }))
    .onDisappear {
      clearQuickLookItems()
    }.onKeyPress(.space, phases: .down) { _ in
      quicklook(images: images(from: sidebar.selection))

      return .handled
    }
  }

  func images(from selection: ImageCollectionSidebar.Selection) -> [ImageCollectionItemImage] {
    collection.images.filter(in: selection, by: \.id)
  }

  func urls(from selection: ImageCollectionSidebar.Selection) -> [URL] {
    images(from: selection).map(\.url)
  }

  func clearQuickLookItems() {
    quickLookScopes.forEach { (image, scope) in
      image.endSecurityScope(scope: scope)
    }

    quickLookScopes = [:]
  }

  func quicklook(images: [ImageCollectionItemImage]) {
    clearQuickLookItems()

    images.forEach { image in
      // If we hooked into Quick Look directly, we could likely avoid this lifetime juggling taking place here.
      quickLookScopes[image] = image.startSecurityScope()
    }

    quickLookItems = images.map(\.url)
    selectedQuickLookItem = quickLookItems.first
  }

  func isBookmarked(selection: ImageCollectionSidebar.Selection) -> Bool {
    return selection.isSubset(of: collection.bookmarks)
  }

  func bookmark(images: some Sequence<ImageCollectionItemImage>, value: Bool) {
    images.forEach(setter(value: value, on: \.bookmarked))
    
    collection.updateBookmarks()

    Task(priority: .medium) {
      do {
        try await collection.persist(id: id)
      } catch {
        Logger.model.error("Could not persist image collection \"\(id)\" (via sidebar bookmark): \(error)")
      }
    }
  }

  func copy(images: [ImageCollectionItemImage], to destination: URL) async throws {
    try ImageCollectionCopyingView.saving {
      try destination.withSecurityScope {
        try images.forEach { image in
          try ImageCollectionCopyingView.saving(url: image, to: destination) { url in
            try image.withSecurityScope {
              try ImageCollectionCopyingView.save(url: url, to: destination, resolvingConflicts: resolveCopyingConflicts)
            }
          }
        }
      }
    }
  }
}
