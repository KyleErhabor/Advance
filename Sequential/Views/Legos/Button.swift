//
//  Button.swift
//  Sequential
//
//  Created by Kyle Erhabor on 12/12/23.
//

import SwiftUI

struct ResetButtonView: View {
  let action: () -> Void

  var body: some View {
    Button("Reset", systemImage: "arrow.uturn.backward.circle.fill", role: .cancel) {
      action()
    }
    .buttonStyle(.plain)
    .labelStyle(.iconOnly)
    .foregroundStyle(.secondary)
  }
}

struct PopoverButtonView<Label, Content>: View where Label: View, Content: View {
  @State private var isPresenting = false

  private let label: Label
  private let content: Content
  private let edge: Edge

  var body: some View {
    Button {
      isPresenting.toggle()
    } label: {
      label
    }.popover(isPresented: $isPresenting, arrowEdge: edge) {
      content
    }
  }

  init(edge: Edge, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
    self.label = label()
    self.content = content()
    self.edge = edge
  }
}

struct MenuItemButton<I, Label>: View where I: Equatable, Label: View {
  typealias Item = AppMenuItem<I>

  private let item: Item
  private let label: Label

  var body: some View {
    Button {
      item()
    } label: {
      label
    }.disabled(!item.enabled)
  }

  init(item: Item, @ViewBuilder label: () -> Label) {
    self.item = item
    self.label = label()
  }
}

struct MenuItemToggle<I, Label, Content>: View where I: Equatable, Label: View, Content: View {
  typealias Item = AppMenuToggleItem<I>
  typealias ContentBuilder = (Binding<Bool>) -> Content

  private let toggle: Item
  @ViewBuilder private var content: ContentBuilder
  private var isOn: Binding<Bool> {
    .init {
      toggle.state
    } set: { _ in
      toggle.item()
    }
  }

  var body: some View {
    content(isOn)
      .disabled(!toggle.item.enabled)
  }
}

extension MenuItemToggle where Label == EmptyView {
  init(toggle: Item, @ViewBuilder content: @escaping ContentBuilder) {
    self.toggle = toggle
    self.content = content
  }
}

extension MenuItemToggle where Content == Toggle<Label> {
  init(toggle: Item, @ViewBuilder label: () -> Label) {
    let label = label()

    self.init(toggle: toggle) { $isOn in
      Toggle(isOn: $isOn) {
        label
      }
    }
  }
}
