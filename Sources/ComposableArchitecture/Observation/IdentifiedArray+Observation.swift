import OrderedCollections
import SwiftUI

extension Store where State: ObservableState {
  /// Scopes the store of an identified collection to a collection of stores.
  ///
  /// This operator is most often used with SwiftUI's `ForEach` view. For example, suppose you
  /// have a feature that contains an `IdentifiedArray` of child features like so:
  ///
  /// ```swift
  /// @Reducer
  /// struct Feature {
  ///   @ObservableState
  ///   struct State {
  ///     var rows: IdentifiedArrayOf<Child.State> = []
  ///   }
  ///   enum Action {
  ///     case rows(IdentifiedActionOf<Child>)
  ///   }
  ///   var body: some ReducerOf<Self> {
  ///     Reduce { state, action in
  ///       // Core feature logic
  ///     }
  ///     .forEach(\.rows, action: \.rows) {
  ///       Child()
  ///     }
  ///   }
  /// }
  /// ```
  ///
  /// Then in the view you can use this operator, with `ForEach`, to derive a store for
  /// each element in the identified collection:
  ///
  /// ```swift
  /// struct FeatureView: View {
  ///   let store: StoreOf<Feature>
  ///
  ///   var body: some View {
  ///     List {
  ///       ForEach(store.scope(state: \.rows, action: \.rows), id: \.state.id) { store in
  ///         ChildView(store: store)
  ///       }
  ///     }
  ///   }
  /// }
  /// ```
  ///
  /// > Tip: If you do not depend on the identity of the state of each row (_e.g._, the state's
  /// > `id` is not associated with a selection binding), you can omit the `id` parameter, as the
  /// > `Store` type is identifiable by its object identity:
  /// >
  /// > ```diff
  /// >  ForEach(
  /// > -  store.scope(state: \.rows, action: \.rows),
  /// > -  id: \.state.id,
  /// > +  store.scope(state: \.rows, action: \.rows)
  /// >  ) { childStore in
  /// >    ChildView(store: childStore)
  /// >  }
  /// > ```
  ///
  /// - Parameters:
  ///   - state: A key path to an identified array of child state.
  ///   - action: A case key path to an identified child action.
  ///   - column: The column.
  ///   - fileID: The fileID.
  ///   - filePath: The filePath.
  ///   - line: The line.
  /// - Returns: An collection of stores of child state.
  @_disfavoredOverload
  public func scope<ElementID, ElementState, ElementAction>(
    state: KeyPath<State, IdentifiedArray<ElementID, ElementState>>,
    action: CaseKeyPath<Action, IdentifiedAction<ElementID, ElementAction>>,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) -> some RandomAccessCollection<Store<ElementState, ElementAction>> {
    if !core.canStoreCacheChildren {
      reportIssue(
        uncachedStoreWarning(self),
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
    }
    return _StoreCollection(self.scope(state: state, action: action))
  }
}

public struct _StoreCollection<ID: Hashable & Sendable, State, Action>: RandomAccessCollection {
  private let store: Store<IdentifiedArray<ID, State>, IdentifiedAction<ID, Action>>
  private let data: IdentifiedArray<ID, State>
  private let isInPerceptionTracking = _isInPerceptionTracking

  #if swift(<5.10)
    @MainActor(unsafe)
  #else
    @preconcurrency@MainActor
  #endif
  fileprivate init(_ store: Store<IdentifiedArray<ID, State>, IdentifiedAction<ID, Action>>) {
    self.store = store
    store._$observationRegistrar.access(store, keyPath: \.currentState)
    self.data = store.withState { $0 }
  }

  public var startIndex: Int { self.data.startIndex }
  public var endIndex: Int { self.data.endIndex }
  public subscript(position: Int) -> Store<State, Action> {
    precondition(
      Thread.isMainThread,
      #"""
      Store collections must be interacted with on the main actor.

      When passing a scoped store to a 'ForEach' in a lazy view (for example, 'LazyVStack'), it \
      must be eagerly transformed into a collection to avoid access off the main actor:

          Array(store.scope(state: \.elements, action: \.elements))
      """#
    )
    return MainActor._assumeIsolated { [uncheckedSelf = UncheckedSendable(self)] in
      let `self` = uncheckedSelf.wrappedValue
      var child: Store<State, Action> {
        guard self.data.indices.contains(position)
        else {
          return Store()
        }
        let elementID = self.data.ids[position]
        let scopeID = self.store.id(state: \.[id: elementID], action: \.[id: elementID])
        guard let child = self.store.children[scopeID] as? Store<State, Action>
        else {
          @MainActor
          func open(
            _ core: some Core<IdentifiedArray<ID, State>, IdentifiedAction<ID, Action>>
          ) -> any Core<State, Action> {
            IfLetCore(
              base: core,
              cachedState: self.data[position],
              stateKeyPath: \.[id: elementID],
              actionKeyPath: \.[id: elementID]
            )
          }
          return self.store.scope(id: scopeID, childCore: open(self.store.core))
        }
        return child
      }
      #if DEBUG
        return _PerceptionLocals.$isInPerceptionTracking.withValue(self.isInPerceptionTracking) {
          child
        }
      #else
        return child
      #endif
    }
  }
}
