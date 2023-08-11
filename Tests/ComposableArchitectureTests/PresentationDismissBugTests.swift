//
//  File.swift
//
//
//  Created by andrew on 8/10/23.
//

import ComposableArchitecture
import Foundation
import SwiftUI
import XCTest

// MARK: Modal

/// A feature modeling an 'options' form which is not supported in all cases
private struct ModalFeature: Reducer {

  struct State: Equatable {
    /// The initialization of ``ModalFeature.State`` requires context of the parent feature. But it's reused across different variants of 'Example'.
    let variant: ExampleVariant
  }

  enum Action: Equatable {
    case cancel
    case save
  }

  @Dependency(\.dismiss) var dismiss

  var body: some Reducer<State, Action> {
    Reduce { _, action in
      switch action {
      case .cancel,
        .save:
        return Effect.run { _ in
          await dismiss()
        }
      }
    }
  }

  init() {}
}

private struct ModalView: View {
  let store: StoreOf<ModalFeature>

  var body: some View {
    WithViewStore(store, observe: { $0 }) { viewStore in
      VStack {
        Text(viewStore.variant.rawValue)
      }
    }
  }
}

// MARK: Modal Container

/// A 'container' or 'wrapper' feature for ``ModalFeature`` that makes it easily reusable for all parent feature.
private struct ModalContainerFeature: Reducer {

  struct State: Equatable {
    @PresentationState var modal: ModalFeature.State?
  }

  enum Action: Equatable {
    case openModal
    case modalAction(PresentationAction<ModalFeature.Action>)
  }

  @Dependency(\.dismiss) var dismiss

  var body: some Reducer<State, Action> {
    EmptyReducer()
      .ifLet(\State.$modal, action: /Action.modalAction) {
        ModalFeature()
      }
  }

  init() {}
}

private struct ModalContainerView: View {
  let store: StoreOf<ModalContainerFeature>

  var body: some View {
    Button("Options", action: { store.send(.openModal) })
      .sheet(store: store.scope(state: \.$modal, action: ModalContainerFeature.Action.modalAction))
    { modalStore in
      ModalView(store: modalStore)
    }
  }
}

// MARK: Example Title

private struct ExampleTitleFeature: Reducer {
  struct State: Equatable {
    @BindingState var title: String = ""
  }

  enum Action: Equatable, BindableAction {
    case binding(BindingAction<State>)
  }

  var body: some ReducerOf<Self> {
    BindingReducer()
  }
}

private struct ExampleTitleView: View {
  let store: StoreOf<ExampleTitleFeature>

  var body: some View {
    WithViewStore(store, observe: { $0 }) { viewStore in
      TextField("Title", text: viewStore.$title)
    }
  }
}

// MARK: Example

/// Enumeration of all 'Example' variants
private enum ExampleVariant: String, Equatable {
  case a
  case b
  case c
  // ...
}

/// Modular view for all 'Example' variants. If ``ModalContainerFeature`` did not exist and was implemented in each parent feature,
/// ``ExampleView`` would not be reusable and each `Example{Variant}View` would need to fully re-implement ``ExampleView``.
private struct ExampleView: View {
  let titleStore: StoreOf<ExampleTitleFeature>
  let modalContainerStore: StoreOf<ModalContainerFeature>?

  var body: some View {
    Form {
      ExampleTitleView(store: titleStore)
      if let modalContainerStore {
        ModalContainerView(store: modalContainerStore)
      }
    }
  }
}

// MARK: Example A

/// A detail feature for the 'A' variant of 'Example' which does support ``ModalFeature``
private struct ExampleAFeature: Reducer {
  struct State: Equatable {
    var title: ExampleTitleFeature.State = ExampleTitleFeature.State()
    var modalContainer: ModalContainerFeature.State = ModalContainerFeature.State()
  }

  enum Action: Equatable {
    case titleAction(ExampleTitleFeature.Action)
    case modalContainerAction(ModalContainerFeature.Action)
  }

  var body: some Reducer<State, Action> {
    Scope(state: \State.title, action: /Action.titleAction) {
      ExampleTitleFeature()
    }
    Scope(state: \State.modalContainer, action: /Action.modalContainerAction) {
      ModalContainerFeature()
    }
    Reduce { state, action in
      switch action {
      case .modalContainerAction(.openModal):
        state.modalContainer.modal = ModalFeature.State(variant: .a)
        return .none
      default:
        return .none
      }
    }
  }
}

private struct ExampleAView: View {
  let store: StoreOf<ExampleAFeature>

  var body: some View {
    ExampleView(
      titleStore: store.scope(state: \.title, action: ExampleAFeature.Action.titleAction),
      modalContainerStore: store.scope(
        state: \.modalContainer, action: ExampleAFeature.Action.modalContainerAction))
  }
}

// MARK: Example B

/// A detail feature for the 'B' variant of 'Example' which does NOT support ``ModalFeature``
private struct ExampleBFeature: Reducer {
  struct State: Equatable {
    var title: ExampleTitleFeature.State = ExampleTitleFeature.State()
  }

  enum Action: Equatable {
    case titleAction(ExampleTitleFeature.Action)
  }

  var body: some Reducer<State, Action> {
    Scope(state: \State.title, action: /Action.titleAction) {
      ExampleTitleFeature()
    }
  }
}

// MARK: Example C

/// A detail feature for the 'A' variant of 'Example' which does support ``ModalFeature``
private struct ExampleCFeature: Reducer {
  struct State: Equatable {
    var title: ExampleTitleFeature.State = ExampleTitleFeature.State()
    var modalContainer: ModalContainerFeature.State = ModalContainerFeature.State()
  }

  enum Action: Equatable {
    case titleAction(ExampleTitleFeature.Action)
    case modalContainerAction(ModalContainerFeature.Action)
  }

  var body: some Reducer<State, Action> {
    Scope(state: \State.title, action: /Action.titleAction) {
      ExampleTitleFeature()
    }
    Scope(state: \State.modalContainer, action: /Action.modalContainerAction) {
      ModalContainerFeature()
    }
    Reduce { state, action in
      switch action {
      case .modalContainerAction(.openModal):
        state.modalContainer.modal = ModalFeature.State(variant: .c)
        return .none
      default:
        return .none
      }
    }
  }
}

private struct ExampleCView: View {
  let store: StoreOf<ExampleCFeature>

  var body: some View {
    ExampleView(
      titleStore: store.scope(state: \.title, action: ExampleCFeature.Action.titleAction),
      modalContainerStore: store.scope(
        state: \.modalContainer, action: ExampleCFeature.Action.modalContainerAction))
  }
}

private struct ExampleBView: View {
  let store: StoreOf<ExampleBFeature>

  var body: some View {
    ExampleView(
      titleStore: store.scope(state: \.title, action: ExampleBFeature.Action.titleAction),
      modalContainerStore: nil)
  }
}

// MARK: Tests

@MainActor
final class PresentationDismissBugTests: XCTestCase {
  func testRepeatedOpenAndDismiss() async throws {
    let store = TestStore(initialState: ExampleAFeature.State(), reducer: ExampleAFeature.init)

    _ = await store.send(.modalContainerAction(.openModal)) { state in
      state.modalContainer.modal = ModalFeature.State(variant: .a)
    }

    _ = await store.send(.modalContainerAction(.modalAction(.presented(.cancel))))

    await store.receive(.modalContainerAction(.modalAction(.dismiss))) { state in
      state.modalContainer.modal = nil
    }

    _ = await store.send(.modalContainerAction(.openModal)) { state in
      state.modalContainer.modal = ModalFeature.State(variant: .a)
    }

    _ = await store.send(.modalContainerAction(.modalAction(.presented(.cancel))))

    await store.receive(.modalContainerAction(.modalAction(.dismiss))) { state in
      state.modalContainer.modal = nil
    }

    _ = await store.send(.modalContainerAction(.openModal)) { state in
      state.modalContainer.modal = ModalFeature.State(variant: .a)
    }

    _ = await store.send(.modalContainerAction(.modalAction(.presented(.cancel))))

    await store.receive(.modalContainerAction(.modalAction(.dismiss))) { state in
      state.modalContainer.modal = nil
    }
  }
}
