//
//  TestStoreReceiveBindingActionTests.swift
//
//
//  Created by andrew on 6/24/22.
//

import ComposableArchitecture
import Foundation
import XCTest

final class TestStoreReceiveBindingActionTests: XCTestCase {

    func testBindingInvocation() throws {
        let store = TestStore(initialState: FeatureState(), reducer: featureReducer, environment: ())
        store.send(FeatureAction.sayHello)
        store.receive(.set(\.$text, "Hello World!")) { state in
            state.text = "Hello World!"
        }
    }
}

struct FeatureState: Equatable {
    @BindableState var text: String

    init(text: String = "") {
        self.text = text
    }
}

enum FeatureAction: Equatable, BindableAction {
    /// An action that in turn sends a binding action
    case sayHello
    case binding(BindingAction<FeatureState>)
}

let featureReducer = Reducer<FeatureState, FeatureAction, Void> { _, action, _ in
    switch action {
    case .sayHello:
        return Effect(value: .set(\.$text, "Hello World!"))
    case .binding:
        return .none
    }
}.binding()
