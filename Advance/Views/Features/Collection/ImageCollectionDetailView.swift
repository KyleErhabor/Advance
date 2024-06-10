//
//  ImageCollectionDetailView.swift
//  Advance
//
//  Created by Kyle Erhabor on 9/13/23.
//

import Combine
import Defaults
import ImageIO
import OSLog
import SwiftUI
import VisionKit

struct ImageCollectionVisiblePreferenceKey: PreferenceKey {
  typealias Value = [ImageCollectionItemImage]

  static var defaultValue = Value(minimumCapacity: VisiblePreferenceKey<Value>.defaultMinimumCapacity)

  static func reduce(value: inout Value, nextValue: () -> Value) {
    value = nextValue()
  }
}

struct ImageCollectionDetailItemBookmarkView: View {
  @Environment(ImageCollection.self) private var collection
  @Environment(\.id) private var id

  @Binding var bookmarked: Bool
  var bookmark: Binding<Bool> {
    .init {
      bookmarked
    } set: { bookmarked in
      self.bookmarked = bookmarked

      collection.updateBookmarks()

      Task(priority: .medium) {
        do {
          try await collection.persist(id: id)
        } catch {
          Logger.model.error("Could not persist image collection \"\(id)\" (via detail bookmark): \(error)")
        }
      }
    }
  }

  var body: some View {
    ImageCollectionBookmarkView(isOn: bookmark)
  }
}

struct ImageCollectionDetailItemSidebarView: View {
  @Environment(ImageCollectionSidebar.self) private var sidebar
  @Environment(\.sidebarScroller) private var sidebarScroller

  let id: ImageCollectionItemImage.ID

  var body: some View {
    Button("Sidebar.Item.Show") {
      sidebarScroller.scroll(.init(id: id) {
        Task {
          sidebar.selection = [id]
        }
      })
    }
  }
}

struct ImageCollectionDetailItemInteractionView: View {
  @Environment(\.supplementaryInterfaceHidden) private var liveTextIcon
  @Default(.liveText) private var liveText
  @Default(.liveTextSearchWith) private var liveTextSearchWith
  @Default(.liveTextDownsample) private var liveTextDownsample
  @State private var analysis: ImageCollectionItemImageAnalysis?
  private let invalid = 0

  @Bindable var image: ImageCollectionItemImage
  let resample: ImageResample?

  private var interactions: ImageAnalysisOverlayView.InteractionTypes {
    var interactions = ImageAnalysisOverlayView.InteractionTypes()

    guard liveText && resample != nil else {
      return interactions
    }

    interactions.insert([.textSelection, .dataDetectors])

    return interactions
  }

  private var length: Int {
    guard let size = resample?.size else {
      return invalid
    }

    return .init(size.length.rounded(.up))
  }

  private var input: ImageCollectionItemImageAnalysisInput {
    .init(
      url: image.url,
      interactions: interactions,
      downsample: liveTextDownsample && length != invalid,
      isSuccessPhase: resample != nil
    )
  }

  var body: some View {
    LiveTextView(
      interactions: interactions,
      analysis: analysis?.analysis,
      isHighlighted: $image.isAnalysisHighlighted
    )
    .supplementaryInterfaceHidden(!liveTextIcon)
    .searchEngineHidden(!liveTextSearchWith)
    .task(id: Pair(left: liveText, right: input)) {
      guard liveText else {
        return
      }

      let input = input

      guard analysis?.input != input && input.isSuccessPhase else {
        return
      }

      let analysis = await image.withSecurityScope {
        await Self.analyze(
          url: input.url,
          orientation: image.properties.orientation,
          interactions: input.interactions,
          resample: input.downsample,
          resampleSize: min(length, ImageAnalyzer.maxSize)
        )
      }

      guard let analysis else {
        return
      }

      self.analysis = .init(analysis, input: input)
    }.onChange(of: analysis?.analysis.hasOutput) {
      image.hasAnalysisResults = analysis?.analysis.hasOutput ?? false
    }
  }

  static nonisolated func analyze(
    url: URL,
    orientation: CGImagePropertyOrientation,
    interactions: ImageAnalysisOverlayView.InteractionTypes,
    resample: Bool,
    resampleSize: Int
  ) async -> ImageAnalysis? {
    let analyzer = ImageAnalyzer()
    let maxSize = ImageAnalyzer.maxSize
    let configuration = ImageAnalyzer.Configuration(.init(interactions))

    do {
      return try await Self.analyze(analyzer: analyzer, imageAt: url, orientation: orientation, configuration: configuration)
    } catch let err as NSError where err.domain == ImageAnalyzer.errorDomain && err.code == ImageAnalyzer.errorMaxSizeCode {
      guard resample else {
        Logger.ui.error("Could not analyze image at URL \"\(url.string)\" as its size is too large: \(err)")

        return nil
      }

      let size = min(resampleSize, maxSize.decremented())

      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let type = CGImageSourceGetType(source),
            let image = source.resample(to: size) else {
        return nil
      }

      let directory = URL.temporaryLiveTextImagesDirectory
      let url = directory.appending(component: UUID().uuidString)
      let count = 1
      let destination: CGImageDestination

      do {
        let manager = FileManager.default
        let dest: CGImageDestination? = try manager.creatingDirectories(at: directory, code: .fileNoSuchFile) {
          guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, count, nil) else {
            if manager.fileExists(atPath: url.string) {
              return nil
            }

            throw CocoaError(.fileNoSuchFile)
          }

          return destination
        }

        guard let dest else {
          return nil
        }

        destination = dest
      } catch {
        Logger.ui.error("Could not create destination for image analyzer replacement image: \(error)")

        return nil
      }

      CGImageDestinationAddImage(destination, image, nil)

      guard CGImageDestinationFinalize(destination) else {
        Logger.ui.error("Could not finalize destination for image analyzer replacement image")

        return nil
      }

      do {
        return try await Self.analyze(analyzer: analyzer, imageAt: url, orientation: orientation, configuration: configuration)
      } catch {
        Logger.ui.error("Could not analyze image at URL \"\(url.string)\": \(error)")

        return nil
      }
    } catch {
      Logger.ui.error("Could not analyze image at URL \"\(url.string)\": \(error)")

      return nil
    }
  }

  // For reference, I know VisionKit logs the analysis time in Console; this is just useful for always displaying the
  // time in *our own logs*.
  static nonisolated func analyze(
    analyzer: ImageAnalyzer,
    imageAt url: URL,
    orientation: CGImagePropertyOrientation,
    configuration: ImageAnalyzer.Configuration
  ) async throws -> ImageAnalysis {
    let exec = try await time {
      try await analyzer.analyze(imageAt: url, orientation: orientation, configuration: configuration)
    }

    Logger.ui.info("Took \(exec.duration) to analyze image at URL \"\(url.string)\"")

    return exec.value
  }
}

struct ImageCollectionDetailItemPhaseView: View {
  @State private var phase = ImageResamplePhase.empty

  let image: ImageCollectionItemImage

  var body: some View {
    ImageCollectionItemView(image: image, phase: $phase) {
      ImageCollectionItemPhaseView(phase: phase)
        .overlay {
          ImageCollectionDetailItemInteractionView(image: image, resample: phase.success)
        }
    }.aspectRatio(image.properties.sized.aspectRatio, contentMode: .fit)
  }
}

struct ImageCollectionDetailItemView: View {
  @Default(.resolveCopyingConflicts) private var resolveCopyingConflicts
  @State private var isCopyingFileImporterPresented = false
  @State private var error: String?
  private var isErrorPresented: Binding<Bool> {
    .init {
      self.error != nil
    } set: { present in
      if !present {
        self.error = nil
      }
    }
  }

  let image: ImageCollectionItemImage

  var body: some View {
    // For some reason, ImageCollectionItemView needs to be wrapped in a VStack for animations to apply.
    VStack {
      // For some reason, we need to isolate the phase state to its own view for SwiftUI to automatically discard the
      // view and its memory.
      ImageCollectionDetailItemPhaseView(image: image)
    }.contextMenu {
      @Bindable var image = image

      Section {
        Button("Finder.Show") {
          openFinder(selecting: image.url)
        }

        ImageCollectionDetailItemSidebarView(id: image.id)
      }

      Section {
        Button("Copy") {
          if !NSPasteboard.general.write(items: [image.url as NSURL]) {
            Logger.ui.error("Failed to write URL \"\(image.url.string)\" to pasteboard")
          }
        }

        ImageCollectionCopyingView(isPresented: $isCopyingFileImporterPresented) { destination in
          Task(priority: .medium) {
            do {
              try await copy(image: image, to: destination)
            } catch {
              self.error = error.localizedDescription
            }
          }
        }
      }

      Section {
        ImageCollectionDetailItemBookmarkView(bookmarked: $image.bookmarked)
      }
    }.fileImporter(isPresented: $isCopyingFileImporterPresented, allowedContentTypes: [.folder]) { result in
      switch result {
        case .success(let url):
          Task(priority: .medium) {
            do {
              try await copy(image: image, to: url)
            } catch {
              self.error = error.localizedDescription
            }
          }
        case .failure(let err):
          Logger.ui.info("Could not import copy destination from file picker: \(err)")
      }
    }
    .fileDialogCopy()
    // TODO: Create a view modifier to automatically specify an empty actions
    .alert(error ?? "", isPresented: isErrorPresented) {}
  }

  nonisolated func copy(image: ImageCollectionItemImage, to destination: URL) async throws {
    try await Self.copy(image: image, to: destination, resolvingConflicts: resolveCopyingConflicts)
  }

  static nonisolated func copy(
    image: ImageCollectionItemImage,
    to destination: URL,
    resolvingConflicts resolveConflicts: Bool
  ) async throws {
    try ImageCollectionCopyingView.saving {
      try destination.withSecurityScope {
        try ImageCollectionCopyingView.saving(url: image, to: destination) { url in
          try image.withSecurityScope {
            try ImageCollectionCopyingView.save(url: url, to: destination, resolvingConflicts: resolveConflicts)
          }
        }
      }
    }
  }
}

struct ImageCollectionDetailVisualView: View {
  @AppStorage(Keys.brightness.key) private var brightness = Keys.brightness.value
  @AppStorage(Keys.grayscale.key) private var grayscale = Keys.grayscale.value

  var body: some View {
    // FIXME: Using .focusable on ResetButtonView allows users to select but not perform action.
    //
    // Using .focusable allows me to tab to the button, but not hit Space to perform the action. Sometimes, however,
    // I'll need to tab back once and hit Space for it to function.
    Form {
      HStack(alignment: .firstTextBaseline) {
        LabeledContent {
          Slider(value: $brightness, in: -0.5...0.5, step: 0.1) {
            // Empty
          } minimumValueLabel: {
            Text("50%")
              .fontDesign(.monospaced)
          } maximumValueLabel: {
            Text("150%")
              .fontDesign(.monospaced)
          }.frame(width: 250)
        } label: {
          Text("Brightness:")
        }

        ResetButtonView {
          brightness = Keys.brightness.value
        }.disabled(brightness == Keys.brightness.value)
      }

      HStack(alignment: .firstTextBaseline) {
        LabeledContent {
          Slider(value: $grayscale, in: 0...1, step: 0.1) {
            // Empty
          } minimumValueLabel: {
            // I can't figure out how to align the labels.
            Text(" 0%")
              .fontDesign(.monospaced)
          } maximumValueLabel: {
            Text("100%")
              .fontDesign(.monospaced)
          }.frame(width: 250)
        } label: {
          Text("Grayscale:")
        }

        ResetButtonView {
          grayscale = Keys.grayscale.value
        }.disabled(grayscale == Keys.grayscale.value)
      }
    }
    .formStyle(SettingsFormStyle())
    .padding()
    .frame(width: 384)
  }
}

struct ImageCollectionDetailVisibleView: View {
  @Environment(ImageCollection.self) private var collection
  @Environment(ImageCollectionSidebar.self) private var sidebar
  @Environment(\.id) private var id
  @Environment(\.sidebarScroller) private var sidebarScroller
  @Default(.windowRestoreLastImage) private var windowRestoreLastImage
  @Default(.displayTitleBarImage) private var displayTitleBarImage

  let images: [ImageCollectionItemImage]

  private var primary: ImageCollectionItemImage? { images.first }

  var body: some View {
    let analysis = images.filter(\.hasAnalysisResults)
    let hasAnalysis = !analysis.isEmpty
    let isHighlighted = analysis.allSatisfy(\.isAnalysisHighlighted)

    let primaryID: Set<ImageCollectionItemImage.ID> = if let primary {
      [primary.id]
    } else {
      []
    }

    Color.clear
      .focusedSceneValue(\.liveTextHighlight, .init(
        identity: analysis.map(\.id),
        enabled: hasAnalysis,
        state: hasAnalysis && isHighlighted
      ) { highlight in
        analysis.forEach(setter(value: highlight, on: \.isAnalysisHighlighted))
      })
      .focusedSceneValue(\.finderShow, .init(identity: primaryID, enabled: primary != nil) {
        guard let primary else {
          return
        }

        openFinder(selecting: primary.url)
      })
      .focusedSceneValue(\.currentImageShow, .init(identity: primary?.id, enabled: primary != nil) {
        guard let primary else {
          return
        }

        sidebarScroller.scroll(.init(id: primary.id) {
          sidebar.selection = [primary.id]
        })
      })
      .focusedSceneValue(\.bookmark, .init(
        identity: primaryID,
        enabled: primary != nil,
        state: primary?.bookmarked ?? false
      ) { bookmark in
        guard let primary else {
          return
        }

        primary.bookmarked = bookmark

        collection.updateBookmarks()

        Task {
          do {
            try await collection.persist(id: id)
          } catch {
            Logger.model.error("Could not persist image collection \"\(id)\" via bookmark focus: \(error)")
          }
        }
      })
      .onChange(of: primary) {
        guard windowRestoreLastImage else {
          return
        }

        collection.current = primary?.id

        Task {
          do {
            try await collection.persist(id: id)
          } catch {
            Logger.model.error("Could not persist image collection \"\(id)\" via current: \(error)")
          }
        }
      }

    if let primary {
      if displayTitleBarImage {
        let url = primary.url

        Color.clear
          .navigationTitle(Text(url.lastPath))
          .navigationDocument(url)
      }
    }
  }
}

struct ImageCollectionDetailView: View {
  typealias VisibleImagesPreferenceKey = VisiblePreferenceKey<ImageCollectionItemImage>

  private let items: [ImageCollectionDetailItem]
  private let subject = PassthroughSubject<VisibleImagesPreferenceKey.Value, Never>()
  private let publisher: AnyPublisher<VisibleImagesPreferenceKey.Value, Never>

  @Environment(\.id) private var id
  @Default(.margins) private var margins
  @Default(.collapseMargins) private var collapseMargins
  @Default(.liveTextIcon) private var appLiveTextIcon
  @SceneStorage(Defaults.Keys.liveTextIcon.name) private var liveTextIcon: Bool?
  private var showLiveTextIcon: Bool { liveTextIcon ?? appLiveTextIcon }
  private var margin: Double { Double(margins) }
  private var half: Double { margin * 3 }
  private var full: Double { half * 2 }
  private var all: EdgeInsets { EdgeInsets(full) }
  private var top: EdgeInsets { EdgeInsets(horizontal: full, top: full, bottom: half) }
  private var middle: EdgeInsets { EdgeInsets(horizontal: full, top: half, bottom: half) }
  private var bottom: EdgeInsets { EdgeInsets(horizontal: full, top: half, bottom: full) }

  init(items: [ImageCollectionDetailItem]) {
    self.items = items
    self.publisher = subject
      .throttle(for: .scrollInteraction, scheduler: DispatchQueue.main, latest: true)
      .eraseToAnyPublisher()
  }

  var body: some View {
    List(items) { item in
      let image = item.image
      let insets: EdgeInsets = if let edge = item.edge {
        switch edge {
          case .top: top
          case .bottom: bottom
        }
      } else {
        middle
      }

      ImageCollectionDetailItemView(image: image)
        .listRowInsets(.listRow + (collapseMargins ? insets : all))
        .listRowSeparator(.hidden)
        .shadow(radius: margin / 2)
        .anchorPreference(key: VisiblePreferenceKey.self, value: .bounds) { [VisibleItem(item: image, anchor: $0)] }
    }
    .listStyle(.plain)
    .preferencePublisher(VisibleImagesPreferenceKey.self, defaultValue: [], subject: subject, publisher: publisher)
    .overlayPreferenceValue(VisibleImagesPreferenceKey.self) { items in
      GeometryReader { proxy in
        let local = proxy.frame(in: .local)
        let images = items
          .filter { local.intersects(proxy[$0.anchor]) }
          .map(\.item)

        // The reason we're factoring the view into its own preference value is because the current one will be called
        // on *every scroll* event the user performs. While views are cheap, there is a cost to always recreating
        // them—and some are slower than others (navigationDocument(_:), for example). In my experience, this split
        // causes CPU usage to decrease from 60-68% to 47-52%, which is a major performance improvement (before anchor
        // preferences, CPU usage was often 42-48%).
        //
        // Now, the reason we're using preferences to report the filtered images (instead of, say, a @State variable),
        // is because of SwiftUI's ability to track changes. @State, just from observing its effects, has no way of
        // distinguishing itself from other observables besides reporting the change and letting SwiftUI diff them.
        // As a result, users may experience slight hangs when the set of visible images changes (~55ms). A preference
        // key, meanwhile, just floats up the view hierarchy and dispenses its value to an attached view. The result
        // is that using preference values here results in no hangs, making it suitable for this case.
        Color.clear.preference(key: ImageCollectionVisiblePreferenceKey.self, value: images)
      }
      .preference(key: ScrollOffsetPreferenceKey.self, value: items.last?.anchor)
    }
    .backgroundPreferenceValue(ImageCollectionVisiblePreferenceKey.self) { images in
      ImageCollectionDetailVisibleView(images: images)
    }
    .toolbar(id: "Canvas") {
      ToolbarItem(id: "Visual") {
        PopoverButtonView(edge: .bottom) {
          ImageCollectionDetailVisualView()
        } label: {
          Label("Visual Effects", systemImage: "paintbrush.pointed")
        }.help("Visual Effects")
      }

      ToolbarItem(id: "Live Text Icon") {
        let icons = Binding {
          showLiveTextIcon
        } set: {
          liveTextIcon = $0
        }

        Toggle("Images.Toolbar.LiveTextIcon", systemImage: "text.viewfinder", isOn: icons)
          .help(showLiveTextIcon ? "Images.Toolbar.LiveTextIcon.Hide" : "Images.Toolbar.LiveTextIcon.Show")
      }
    }
    .environment(\.supplementaryInterfaceHidden, showLiveTextIcon)
    .focusedSceneValue(\.liveTextIcon, .init(identity: id, enabled: true, state: showLiveTextIcon) { icon in
      liveTextIcon = icon
    })
  }
}
