//
//  UI+Core.swift
//  Advance
//
//  Created by Kyle Erhabor on 6/29/24.
//

import SwiftUI
import Combine
import Defaults

extension SchedulerTimeIntervalConvertible {
  static var imagesScrollInteraction: Self {
    .milliseconds(50)
  }

  static var imagesResizeInteraction: Self {
    .milliseconds(200)
  }

  static var imagesHoverInteraction: Self {
    .milliseconds(500)
  }
}

// MARK: - Defaults

enum DefaultColorScheme: Int {
  case system, light, dark

  var appearance: NSAppearance? {
    switch self {
      case .light: NSAppearance(named: .aqua)
      case .dark: NSAppearance(named: .darkAqua)
      default: nil
    }
  }
}

extension DefaultColorScheme: Defaults.Serializable {}

struct DefaultSearchEngine {
  typealias ID = UUID

  let id: UUID
  let name: String
  let string: String
}

extension DefaultSearchEngine: Codable, Defaults.Serializable {}

extension Defaults.Keys {
  static let colorScheme = Key("color-scheme", default: DefaultColorScheme.system)

  static let searchEngine = Key("search-engine", default: nil as DefaultSearchEngine.ID?)
  static let searchEngines = Key("search-engines", default: [DefaultSearchEngine]())
}

// MARK: - Storage

extension Visibility {
  init(_ value: Bool) {
    switch value {
      case true: self = .visible
      case false: self = .hidden
    }
  }
}

struct StorageVisibility {
  let visibility: Visibility
}

extension StorageVisibility {
  init(_ visibility: Visibility) {
    self.init(visibility: visibility)
  }
}

extension StorageVisibility: RawRepresentable {
  private static let automatic = 0
  private static let visible = 1
  private static let hidden = 2

  var rawValue: Int {
    switch visibility {
      case .automatic: Self.automatic
      case .visible: Self.visible
      case .hidden: Self.hidden
    }
  }

  init(rawValue: Int) {
    let visibility: Visibility = switch rawValue {
      case Self.automatic: .automatic
      case Self.visible: .visible
      case Self.hidden: .hidden
      default: fatalError()
    }

    self.init(visibility: visibility)
  }
}

struct StorageColumnVisibility {
  let columnVisibility: NavigationSplitViewVisibility
}

extension StorageColumnVisibility {
  init(_ columnVisibility: NavigationSplitViewVisibility) {
    self.init(columnVisibility: columnVisibility)
  }
}

extension StorageColumnVisibility: RawRepresentable {
  private static let unknown = -1
  private static let automatic = 0
  private static let all = 1
  private static let detailOnly = 2
  private static let doubleColumn = 3

  var rawValue: Int {
    switch columnVisibility {
      case .automatic: Self.automatic
      case .all: Self.all
      case .detailOnly: Self.detailOnly
      case .doubleColumn: Self.doubleColumn
      default: Self.unknown
    }
  }

  init?(rawValue: Int) {
    let columnVisibility: NavigationSplitViewVisibility

    switch rawValue {
      case Self.unknown:
        return nil
      case Self.automatic:
        columnVisibility = .automatic
      case Self.all:
        columnVisibility = .all
      case Self.detailOnly:
        columnVisibility = .detailOnly
      case Self.doubleColumn:
        columnVisibility = .doubleColumn
      default:
        fatalError()
    }

    self.init(columnVisibility: columnVisibility)
  }
}

enum StorageDirection: Int {
  case leftToRight, rightToLeft
}

enum StorageImagesLayoutStyle: Int {
  case paged, continuous
}

extension SetAlgebra {
  func value(_ value: Bool, for set: Self) -> Self {
    value ? self.union(set) : self.subtracting(set)
  }
}

struct StorageImagesLayoutContinuousStyleHidden: OptionSet {
  let rawValue: Int

  static let toolbar = Self(rawValue: 1 << 0)
  static let cursor = Self(rawValue: 1 << 1)
  static let scroll = Self(rawValue: 1 << 2)

  // Is there a better way to represent this?

  var toolbar: Bool {
    get {
      self.contains(.toolbar)
    }
    set {
      self = value(newValue, for: .toolbar)
    }
  }

  var cursor: Bool {
    get {
      self.contains(.cursor)
    }
    set {
      self = value(newValue, for: .cursor)
    }
  }

  var scroll: Bool {
    get {
      self.contains(.scroll)
    }
    set {
      self = value(newValue, for: .scroll)
    }
  }
}

struct StorageCopyingSeparatorItem {
  let forward: Character
  let back: Character

  func separator(direction: StorageDirection) -> Character {
    switch direction {
      case .leftToRight: forward
      case .rightToLeft: back
    }
  }
}

enum StorageCopyingSeparator: Int {
  case inequalitySign,
       singlePointingAngleQuotationMark,
       blackPointingTriangle,
       blackPointingSmallTriangle

  var separator: StorageCopyingSeparatorItem {
    switch self {
      case .inequalitySign: StorageCopyingSeparatorItem(forward: ">", back: "<")
      case .singlePointingAngleQuotationMark: StorageCopyingSeparatorItem(
        forward: "\u{203A}", // ›
        back: "\u{2039}" // ‹
      )
      case .blackPointingTriangle: StorageCopyingSeparatorItem(
        forward: "\u{25B6}", // ▶
        back: "\u{25C0}" // ◀
      )
      case .blackPointingSmallTriangle: StorageCopyingSeparatorItem(
        forward: "\u{25B8}", // ▸
        back: "\u{25C2}" // ◂
      )
    }
  }
}

struct StorageKey<Value> {
  let name: String
  let defaultValue: Value
}

extension StorageKey {
  init(_ name: String, defaultValue: Value) {
    self.init(name: name, defaultValue: defaultValue)
  }
}

extension StorageKey: Sendable where Value: Sendable {}

enum StorageKeys {
  static let columnVisibility = StorageKey("column-visibility", defaultValue: StorageColumnVisibility(.all))

  static let restoreLastImage = StorageKey("restore-last-image", defaultValue: true)

  static let layoutStyle = StorageKey("layout-style", defaultValue: StorageImagesLayoutStyle.continuous)
  static let layoutContinuousStyleHidden = StorageKey(
    "layout-continuous-style-hidden",
    defaultValue: StorageImagesLayoutContinuousStyleHidden.cursor
  )

  static let importHiddenFiles = StorageKey("import-hidden-files", defaultValue: false)
  static let importSubdirectories = StorageKey("import-subdirectories", defaultValue: true)

  static let liveTextEnabled = StorageKey("live-text-is-enabled", defaultValue: true)
  static let liveTextIcon = StorageKey("live-text-is-icon-visible", defaultValue: false)
  static let liveTextIconVisibility = StorageKey("live-text-icon-visibility", defaultValue: StorageVisibility(.automatic))
  static let liveTextSubject = StorageKey("live-text-is-subject-highlighted", defaultValue: false)

  static let searchUseSystemDefault = StorageKey("search-use-system-default", defaultValue: false)

  static let copyingResolveConflicts = StorageKey("copying-resolve-conflicts", defaultValue: true)
  static let copyingConflictFormat = StorageKey(
    "copying-conflict-format",
    defaultValue: "\(CopyingSettingsModel.nameKeyword) [\(CopyingSettingsModel.pathKeyword)]"
  )
  static let copyingConflictSeparator = StorageKey("copying-conflict-separator", defaultValue: StorageCopyingSeparator.singlePointingAngleQuotationMark)
  static let copyingConflictDirection = StorageKey("copying-conflict-direction", defaultValue: StorageDirection.rightToLeft)
}

extension AppStorage {
  init(_ key: StorageKey<Value>) where Value == Bool {
    self.init(wrappedValue: key.defaultValue, key.name)
  }

  init(_ key: StorageKey<Value>) where Value == String {
    self.init(wrappedValue: key.defaultValue, key.name)
  }

  init(_ key: StorageKey<Value>) where Value: RawRepresentable,
                                       Value.RawValue == Int {
    self.init(wrappedValue: key.defaultValue, key.name)
  }
}

extension SceneStorage {
  init(_ key: StorageKey<Value>) where Value: RawRepresentable,
                                       Value.RawValue == Int {
    self.init(wrappedValue: key.defaultValue, key.name)
  }
}
