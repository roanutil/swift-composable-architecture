//
//  File.swift
//
//
//  Created by andrew on 8/10/23.
//

import ComposableArchitecture
import Foundation
import XCTest

private struct ModalFeature: Reducer {

  struct State: Equatable {}

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

private struct ExampleFeature: Reducer {
  struct State: Equatable {
    var modalContainer: ModalContainerFeature.State = ModalContainerFeature.State()
  }

  enum Action: Equatable {
    case modalContainerAction(ModalContainerFeature.Action)
  }

  var body: some Reducer<State, Action> {
    Scope(state: \State.modalContainer, action: /Action.modalContainerAction) {
      ModalContainerFeature()
    }
    Reduce { state, action in
      switch action {
      case .modalContainerAction(.openModal):
        state.modalContainer.modal = ModalFeature.State()
        return .none
      default:
        return .none
      }
    }
  }
}

@MainActor
final class PresentationDismissBugTests: XCTestCase {
  func testRepeatedOpenAndDismiss() async throws {
    let store = TestStore(initialState: ExampleFeature.State(), reducer: ExampleFeature.init)

    _ = await store.send(.modalContainerAction(.openModal)) { state in
      state.modalContainer.modal = ModalFeature.State()
    }

    _ = await store.send(.modalContainerAction(.modalAction(.presented(.cancel))))

    await store.receive(.modalContainerAction(.modalAction(.dismiss))) { state in
      state.modalContainer.modal = nil
    }

    _ = await store.send(.modalContainerAction(.openModal)) { state in
      state.modalContainer.modal = ModalFeature.State()
    }

    _ = await store.send(.modalContainerAction(.modalAction(.presented(.cancel))))

    await store.receive(.modalContainerAction(.modalAction(.dismiss))) { state in
      state.modalContainer.modal = nil
    }

    _ = await store.send(.modalContainerAction(.openModal)) { state in
      state.modalContainer.modal = ModalFeature.State()
    }

    _ = await store.send(.modalContainerAction(.modalAction(.presented(.cancel))))

    await store.receive(.modalContainerAction(.modalAction(.dismiss))) { state in
      state.modalContainer.modal = nil
    }
  }
}
