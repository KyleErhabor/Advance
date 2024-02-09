//
//  ImageCollection.swift
//  Advance
//
//  Created by Kyle Erhabor on 9/17/23.
//

import Foundation
import OrderedCollections
import OSLog
import SwiftUI
import VisionKit

extension URL {
  static let collectionDirectory = dataDirectory.appending(component: "Collections")

  static func collectionFile(for id: UUID) -> URL {
    .collectionDirectory
    .appending(component: id.uuidString)
    .appendingPathExtension(for: .binaryPropertyList)
  }
}

struct ImageCollectionDocumentSource<T> {
  let source: T
  let files: [T]
}

enum ImageCollectionSourceKind<T> {
  case file(T)
  case document(ImageCollectionDocumentSource<T>)

  var files: [T] {
    switch self {
      case .file(let file): [file]
      case .document(let document): document.files
    }
  }
}

struct ImageCollectionItemRoot {
  typealias ID = BookmarkStoreItem.ID

  let bookmark: BookmarkStoreItem.ID
  let bookmarked: Bool
}

extension ImageCollectionItemRoot: Equatable {
  static func ==(lhs: Self, rhs: Self) -> Bool {
    lhs.bookmark == rhs.bookmark
  }
}

extension ImageCollectionItemRoot: Codable {}

struct ImageCollectionItemImageAnalysisInput {
  let url: URL
  let interactions: ImageAnalysisOverlayView.InteractionTypes
  let downsample: Bool
  let isSuccessPhase: Bool
}

extension ImageCollectionItemImageAnalysisInput: Equatable {}

struct ImageCollectionItemImageAnalysis {
  let input: ImageCollectionItemImageAnalysisInput
  let output: ImageAnalysisResult

  var hasResults: Bool { output.analysis.hasOutput }
}

@Observable
class ImageCollectionItemImage {
  let bookmark: BookmarkStoreItem.ID

  let source: URLSource
  let relative: URLSource?

  var properties: ImageProperties
  var bookmarked: Bool

  var hasAnalysisResults = false
  var isAnalysisHighlighted = false

  init(bookmark: BookmarkStoreItem.ID, source: URLSource, relative: URLSource?, properties: ImageProperties, bookmarked: Bool) {
    self.bookmark = bookmark
    self.source = source
    self.relative = relative
    self.properties = properties
    self.bookmarked = bookmarked
  }

  func resolve() -> ImageProperties? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = source.properties() as? MapCF else {
      return nil
    }

    return .init(from: props)
  }
}

extension ImageCollectionItemImage: Identifiable {
  var id: BookmarkStoreItem.ID { bookmark }
}

extension ImageCollectionItemImage: Hashable {
  static func ==(lhs: ImageCollectionItemImage, rhs: ImageCollectionItemImage) -> Bool {
    lhs.url == rhs.url
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(url)
  }
}

extension ImageCollectionItemImage: URLScope {
  var url: URL { source.url }

  func startSecurityScope() -> Scope {
    .init(
      image: .init(source: source),
      relative: relative.map { .init(source: $0) }
    )
  }

  func endSecurityScope(scope: Scope) {
    if scope.image.accessing {
      scope.image.url.endSecurityScope()
    }

    if let relative = scope.relative,
       relative.accessing {
      relative.url.endSecurityScope()
    }
  }

  struct Scope {
    let image: URLSecurityScope
    let relative: URLSecurityScope?
  }
}

struct ImageCollectionItem {
  let root: ImageCollectionItemRoot
  let image: ImageCollectionItemImage?

  var bookmarked: Bool { image?.bookmarked ?? root.bookmarked }
}

extension ImageCollectionItem: Equatable {
  static func ==(lhs: Self, rhs: Self) -> Bool {
    lhs.root == rhs.root
  }
}

extension ImageCollectionItem: Codable {
  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    self.init(
      root: try container.decode(ImageCollectionItemRoot.self),
      image: nil
    )
  }

  func encode(to encoder: Encoder) throws {
    let root = ImageCollectionItemRoot(bookmark: root.bookmark, bookmarked: bookmarked)

    var container = encoder.singleValueContainer()
    try container.encode(root)
  }
}

@Observable
class ImageCollectionSidebar {
  typealias Selection = Set<ImageCollectionItemImage.ID>

  var images: [ImageCollectionItemImage]
  var selection: Selection
  @ObservationIgnored var current: ImageCollectionItemImage.ID?

  init(
    images: [ImageCollectionItemImage] = [],
    selection: Selection = [],
    current: ImageCollectionItemImage.ID? = nil
  ) {
    self.images = images
    self.selection = selection
    self.current = current
  }
}

struct ImageCollectionSidebars {
  let images = ImageCollectionSidebar()
  let bookmarks = ImageCollectionSidebar()
  let search = ImageCollectionSidebar()
}

struct ImageCollectionDetailItem {
  let image: ImageCollectionItemImage
  let edge: VerticalEdge?
}

extension ImageCollectionDetailItem: Identifiable {
  var id: ImageCollectionItemImage.ID { image.id }
}

extension ImageCollectionDetailItem: Equatable {}

struct ImageCollectionPathItem {
  let id: ImageCollectionItemImage.ID
  let url: URL
}

extension ImageCollectionPathItem: Identifiable {}

@Observable
class ImageCollectionPath: Codable {
  typealias Items = ImageCollectionSidebar.Selection

  @ObservationIgnored var items: Items
  @ObservationIgnored var item: ImageCollectionItemImage.ID?

  var back = [ImageCollectionPathItem]()
  var forward = [ImageCollectionPathItem]()

  init() {
    self.items = .init()
  }

  func update(images: [ImageCollectionItemImage]) {
    let images = images.filter { items.contains($0.id) }
    let index = item.flatMap { item in
      images.firstIndex { $0.id == item }
    } ?? images.startIndex

    let before = images[..<index]
    // We don't want the current item in the collection
    let after = images[min(images.endIndex, index.incremented())...]

    back = before.map { .init(id: $0.id, url: $0.url) }
    forward = after.map { .init(id: $0.id, url: $0.url) }
  }

  // MARK: - Codable conformance

  required init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()

    self.items = try container.decode(Items.self)
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()

    try container.encode(items)
  }
}

@Observable
class ImageCollection: Codable {
  typealias Order = OrderedSet<ImageCollectionItemRoot.ID>
  typealias Items = [ImageCollectionItemRoot.ID: ImageCollectionItem]

  // The source of truth for the collection.
  //
  // TODO: Remove unused bookmarks in store via items or order
  @ObservationIgnored var store: BookmarkStore
  @ObservationIgnored var items: Items
  @ObservationIgnored var order: Order

  // The materialized state for the UI.
  var images = [ImageCollectionItemImage]()
  var detail = [ImageCollectionDetailItem]()
  var sidebar: ImageCollectionSidebar { sidebars[keyPath: sidebarPage] }

  // Extra UI state.
  var sidebarPage = \ImageCollectionSidebars.images
  var sidebarSearch = ""
  @ObservationIgnored var sidebars = ImageCollectionSidebars()
  let path: ImageCollectionPath
  var bookmarks = Set<ImageCollectionItemRoot.ID>()

  init() {
    self.store = .init()
    self.items = .init()
    self.order = .init()
    self.path = .init()
  }

  init(store: BookmarkStore, items: Items, order: Order) {
    self.store = store
    self.items = items
    self.order = order
    self.path = .init()
  }

  typealias Kind = ImageCollectionSourceKind<URLSource>
  typealias Roots = [URL: ImageCollectionItemRoot]

  static func resolve(
    kinds: [Kind],
    in store: BookmarkStore
  ) async -> BookmarkStoreState<Roots> {
    await withThrowingTaskGroup(of: ImageCollectionSourceKind<URLBookmark>.self) { group in
      kinds.forEach { kind in
        group.addTask {
          switch kind {
            case .document(let document):
              return try await document.source.withSecurityScope {
                let item = try URLBookmark(
                  url: document.source.url,
                  options: document.source.options,
                  relativeTo: nil
                )

                let urbs = await withThrowingTaskGroup(of: URLBookmark.self) { group in
                  let files = document.files

                  files.forEach { source in
                    group.addTask {
                      try source.withSecurityScope {
                        try .init(
                          url: source.url,
                          options: source.options,
                          relativeTo: document.source.url
                        )
                      }
                    }
                  }

                  var urbs = [URLBookmark](minimumCapacity: files.count)

                  while let result = await group.nextResult() {
                    switch result {
                      case .success(let urb):
                        urbs.append(urb)
                      case .failure(let err):
                        Logger.model.error("Could not create bookmark for URL source of document: \(err)")
                    }
                  }

                  return urbs
                }

                return .document(.init(source: item, files: urbs))
              }
            case .file(let source):
              let item = try source.withSecurityScope {
                try URLBookmark(url: source.url, options: source.options, relativeTo: nil)
              }

              return .file(item)
          }
        }
      }

      var store = store
      var roots = Roots(minimumCapacity: kinds.map(\.files.count).sum())

      while let result = await group.nextResult() {
        switch result {
          case .success(let kind):
            switch kind {
              case .document(let document):
                // TODO: Extract the duplication.
                let bookmark = document.source.bookmark
                let hash = BookmarkStoreItem.hash(data: bookmark.data)
                let id = store.identify(hash: hash, bookmark: bookmark, relative: nil)

                store.urls[hash] = document.source.url

                document.files.forEach { source in
                  let bookmark = source.bookmark
                  let hash = BookmarkStoreItem.hash(data: bookmark.data)
                  let id = store.identify(hash: hash, bookmark: bookmark, relative: id)

                  store.urls[hash] = source.url
                  roots[source.url] = .init(bookmark: id, bookmarked: false)
                }
              case .file(let source):
                let bookmark = source.bookmark
                let hash = BookmarkStoreItem.hash(data: bookmark.data)
                let id = store.identify(hash: hash, bookmark: bookmark, relative: nil)

                store.urls[hash] = source.url
                roots[source.url] = .init(bookmark: id, bookmarked: false)
            }
          case .failure(let err):
            Logger.model.error("Could not create bookmark for URL source: \(err)")
        }
      }

      return .init(store: store, value: roots)
    }
  }

  typealias Bookmarks = Set<BookmarkStoreItem.ID>

  static func resolve(
    bookmarks: [BookmarkStoreItem],
    in store: BookmarkStore
  ) async -> BookmarkStoreState<Bookmarks> {
    await withThrowingTaskGroup(of: Pair<BookmarkStoreItem.ID, BookmarkResolution>?.self) { group in
      let relatives = bookmarks
        .compactMap(\.relative)
        .uniqued()
        .compactMap { id -> URLSecurityScope? in
          guard let bookmark = store.bookmarks[id],
                let url = store.urls[bookmark.hash] else {
            return nil
          }

          return URLSecurityScope(source: .init(url: url, options: bookmark.bookmark.options))
        }

      bookmarks.forEach { item in
        group.addTask {
          let resolved: BookmarkResolution
          let bookmark = item.bookmark

          if let url = store.urls[item.hash] {
            resolved = .init(data: bookmark.data, url: url)
          } else {
            let relative: URL?

            if let id = item.relative {
              guard let bookmark = store.bookmarks[id],
                    let url = store.urls[bookmark.hash] else {
                return nil
              }

              relative = url
            } else {
              relative = nil
            }

            resolved = try BookmarkStoreItem.resolve(
              data: bookmark.data,
              options: bookmark.options,
              relativeTo: relative
            )
          }

          return .init(left: item.id, right: resolved)
        }
      }

      var store = store
      var ids = Bookmarks(minimumCapacity: bookmarks.count)

      while let result = await group.nextResult() {
        switch result {
          case .success(let pair):
            guard let pair else {
              continue
            }

            let id = pair.left
            let resolved = pair.right

            ids.insert(id)

            let item = store.bookmarks[id]!
            let bookmark = BookmarkStoreItem(
              id: id,
              bookmark: .init(
                data: resolved.data,
                options: item.bookmark.options
              ),
              relative: item.relative
            )

            store.register(item: bookmark)
            store.urls[bookmark.hash] = resolved.url
          case .failure(let err):
            Logger.model.error("Could not resolve bookmark: \(err)")
        }
      }

      relatives.filter(\.accessing).forEach { $0.url.endSecurityScope() }

      return .init(store: store, value: ids)
    }
  }

  typealias Images = [ImageCollectionItemRoot.ID: ImageCollectionItemImage]

  static func resolve(roots: [ImageCollectionItemRoot], in store: BookmarkStore) async -> Images {
    await withTaskGroup(of: ImageCollectionItemImage?.self) { group in
      let relatives = roots
        .compactMap { store.bookmarks[$0.bookmark]?.relative }
        .uniqued()
        .compactMap { id -> URLSecurityScope? in
          guard let bookmark = store.bookmarks[id],
                let url = store.urls[bookmark.hash] else {
            return nil
          }

          return URLSecurityScope(source: .init(url: url, options: bookmark.bookmark.options))
        }

      roots.forEach { root in
        group.addTask {
          guard let bookmark = store.bookmarks[root.bookmark],
                let url = store.urls[bookmark.hash] else {
            return nil
          }

          let source = URLSource(url: url, options: bookmark.bookmark.options)
          let relative: URLSource?

          if let id = bookmark.relative {
            guard let bookmark = store.bookmarks[id],
                  let url = store.urls[bookmark.hash] else {
              return nil
            }

            relative = .init(url: url, options: bookmark.bookmark.options)
          } else {
            relative = nil
          }

          let image = ImageCollectionItemImage(
            bookmark: bookmark.id,
            source: source,
            relative: relative,
            properties: .init(size: .init(width: 0, height: 0), orientation: .up),
            bookmarked: root.bookmarked
          )

          // We don't need to scope the whole image since the relative is already scoped.
          guard let properties = image.source.withSecurityScope({ image.resolve() }) else {
            return nil
          }

          image.properties = properties

          return image
        }
      }

      let images = await group.reduce(into: Images(minimumCapacity: roots.count)) { images, image in
        guard let image else {
          return
        }

        images[image.bookmark] = image
      }

      relatives.filter(\.accessing).forEach { $0.url.endSecurityScope() }

      return images
    }
  }

  func update() {
    images = order.compactMap { items[$0]?.image }
    detail = images.enumerated().map { (offset, image) in
      let edge: VerticalEdge? = switch offset {
        case images.startIndex: .top
        case images.endIndex - 1: .bottom
        default: nil
      }

      return .init(image: image, edge: edge)
    }

    updateBookmarks()

    path.update(images: images)
  }

  func updateBookmarks() {
    let bookmarks = images.filter(\.bookmarked)
    let bookmarked: [ImageCollectionItemImage]
    let page = sidebarPage

    switch page {
      case \.images,
           // An empty string never passes the later filter
           \.search where sidebarSearch.isEmpty:
        bookmarked = images
      case \.search:
        // Eventually, we want to expand search to analyze images for their transcripts.
        bookmarked = images.filter { $0.url.lastPath.localizedCaseInsensitiveContains(sidebarSearch) }
      case \.bookmarks:
        bookmarked = bookmarks
      default:
        Logger.model.error("Unknown sidebar page \"\(page.debugDescription)\"; defaulting to all")

        bookmarked = images
    }

    sidebars[keyPath: page].images = bookmarked

    self.bookmarks = .init(bookmarks.map(\.bookmark))
  }

  func persist(to url: URL) throws {
    let encoder = PropertyListEncoder()
    let encoded = try encoder.encode(self)

    try FileManager.default.creatingDirectories(at: url.deletingLastPathComponent(), code: .fileNoSuchFile) {
      try encoded.write(to: url)
    }
  }

  // MARK: - Codable conformance

  required init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let roots = try container.decode([ImageCollectionItem].self, forKey: .items)

    self.store = try container.decode(BookmarkStore.self, forKey: .store)
    self.items = .init(uniqueKeysWithValues: roots.map { ($0.root.bookmark, $0) })
    self.order = try container.decode(Order.self, forKey: .order)
    self.path = try container.decode(ImageCollectionPath.self, forKey: .path)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(store, forKey: .store)
    try container.encode(Array(items.values), forKey: .items)
    try container.encode(order, forKey: .order)
    try container.encode(path, forKey: .path)
  }

  enum CodingKeys: CodingKey {
    case store, items, order
    case path
  }
}

extension ImageCollection {
  // MARK: - Convenience
  static func prepare(
    url: URL,
    includingHiddenFiles importHidden: Bool,
    includingSubdirectories importSubdirectories: Bool
  ) -> ImageCollection.Kind {
    let source = URLSource(url: url, options: [.withReadOnlySecurityScope, .withoutImplicitSecurityScope])

    if url.isDirectory() {
      return .document(.init(
        source: source,
        files: url.withSecurityScope {
          FileManager.default
            .contents(at: url, options: .init(includingHiddenFiles: importHidden, includingSubdirectories: importSubdirectories))
            .finderSort()
            .map { .init(url: $0, options: .withoutImplicitSecurityScope) }
        }
      ))
    }

    return .file(source)
  }

  static func resolving(
    bookmarks: [BookmarkStoreItem],
    in store: BookmarkStore
  ) async -> BookmarkStoreState<Bookmarks> {
    let relatives = bookmarks
      .compactMap(\.relative)
      .uniqued()
      .compactMap { store.bookmarks[$0] }

    let rels = await Self.resolve(bookmarks: relatives, in: store)
    let books = bookmarks.filter { bookmark in
      guard let id = bookmark.relative else {
        return true
      }

      return rels.value.contains(id)
    }

    return await Self.resolve(bookmarks: books, in: rels.store)
  }

  func persist(id: UUID) async throws {
    try self.persist(to: URL.collectionFile(for: id))
  }
}

extension ImageCollection: Hashable {
  static func ==(lhs: ImageCollection, rhs: ImageCollection) -> Bool {
    lhs.order == rhs.order
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(order)
  }
}
