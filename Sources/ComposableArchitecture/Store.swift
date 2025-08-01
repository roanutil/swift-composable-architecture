import Combine
import Foundation
import SwiftUI

/// A store represents the runtime that powers the application. It is the object that you will pass
/// around to views that need to interact with the application.
///
/// You will typically construct a single one of these at the root of your application:
///
/// ```swift
/// @main
/// struct MyApp: App {
///   var body: some Scene {
///     WindowGroup {
///       RootView(
///         store: Store(initialState: AppFeature.State()) {
///           AppFeature()
///         }
///       )
///     }
///   }
/// }
/// ```
///
/// …and then use the ``scope(state:action:)-90255`` method to derive more focused stores that can be
/// passed to subviews.
///
/// ### Scoping
///
/// The most important operation defined on ``Store`` is the ``scope(state:action:)-90255`` method,
/// which allows you to transform a store into one that deals with child state and actions. This is
/// necessary for passing stores to subviews that only care about a small portion of the entire
/// application's domain.
///
/// For example, if an application has a tab view at its root with tabs for activity, search, and
/// profile, then we can model the domain like this:
///
/// ```swift
/// @Reducer
/// struct AppFeature {
///   struct State {
///     var activity: Activity.State
///     var profile: Profile.State
///     var search: Search.State
///   }
///
///   enum Action {
///     case activity(Activity.Action)
///     case profile(Profile.Action)
///     case search(Search.Action)
///   }
///
///   // ...
/// }
/// ```
///
/// We can construct a view for each of these domains by applying ``scope(state:action:)-90255`` to
/// a store that holds onto the full app domain in order to transform it into a store for each
/// subdomain:
///
/// ```swift
/// struct AppView: View {
///   let store: StoreOf<AppFeature>
///
///   var body: some View {
///     TabView {
///       ActivityView(
///         store: store.scope(state: \.activity, action: \.activity)
///       )
///       .tabItem { Text("Activity") }
///
///       SearchView(
///         store: store.scope(state: \.search, action: \.search)
///       )
///       .tabItem { Text("Search") }
///
///       ProfileView(
///         store: store.scope(state: \.profile, action: \.profile)
///       )
///       .tabItem { Text("Profile") }
///     }
///   }
/// }
/// ```
///
/// ### ObservableObject conformance
///
/// The store conforms to `ObservableObject` but is _not_ observable via the `@ObservedObject`
/// property wrapper. This conformance is completely inert and its sole purpose is to allow stores
/// to be held in SwiftUI's `@StateObject` property wrapper.
///
/// Instead, stores should be observed through Swift's Observation framework (or the Perception
/// package when targeting iOS <17) by applying the ``ObservableState()`` macro to your feature's
/// state.
@dynamicMemberLookup
#if swift(<5.10)
  @MainActor(unsafe)
#else
  @preconcurrency@MainActor
#endif
public final class Store<State, Action>: _Store {
  var children: [ScopeID<State, Action>: AnyObject] = [:]
  private weak var parent: (any _Store)?
  private let scopeID: AnyHashable?

  func removeChild(scopeID: AnyHashable) {
    children[scopeID as! ScopeID<State, Action>] = nil
  }

  let core: any Core<State, Action>
  @_spi(Internals) public var effectCancellables: [UUID: AnyCancellable] { core.effectCancellables }

  #if !os(visionOS)
    let _$observationRegistrar = PerceptionRegistrar(
      isPerceptionCheckingEnabled: _isStorePerceptionCheckingEnabled
    )
  #else
    let _$observationRegistrar = ObservationRegistrar()
  #endif
  private var parentCancellable: AnyCancellable?

  /// Initializes a store from an initial state and a reducer.
  ///
  /// - Parameters:
  ///   - initialState: The state to start the application in.
  ///   - reducer: The reducer that powers the business logic of the application.
  ///   - prepareDependencies: A closure that can be used to override dependencies that will be accessed
  ///     by the reducer.
  public convenience init<R: Reducer<State, Action>>(
    initialState: @autoclosure () -> R.State,
    @ReducerBuilder<State, Action> reducer: () -> R,
    withDependencies prepareDependencies: ((inout DependencyValues) -> Void)? = nil
  ) {
    let (initialState, reducer, dependencies) = withDependencies(prepareDependencies ?? { _ in }) {
      @Dependency(\.self) var dependencies
      var updatedDependencies = dependencies
      updatedDependencies.navigationIDPath.append(NavigationID())
      return (initialState(), reducer(), updatedDependencies)
    }
    self.init(
      initialState: initialState,
      reducer: reducer.dependency(\.self, dependencies)
    )
  }

  init() {
    self.core = InvalidCore()
    self.scopeID = nil
  }

  deinit {
    guard Thread.isMainThread else { return }
    MainActor._assumeIsolated {
      Logger.shared.log("\(storeTypeName(of: self)).deinit")
    }
  }

  /// Calls the given closure with a snapshot of the current state of the store.
  ///
  /// A lightweight way of accessing store state when state is not observable and ``state-1qxwl`` is
  /// unavailable.
  ///
  /// - Parameter body: A closure that takes the current state of the store as its sole argument. If
  ///   the closure has a return value, that value is also used as the return value of the
  ///   `withState` method. The state argument reflects the current state of the store only for the
  ///   duration of the closure's execution, and is only observable over time, _e.g._ by SwiftUI, if
  ///   it conforms to ``ObservableState``.
  /// - Returns: The return value, if any, of the `body` closure.
  public func withState<R>(_ body: (_ state: State) -> R) -> R {
    #if DEBUG
      _PerceptionLocals.$skipPerceptionChecking.withValue(true) {
        body(self.currentState)
      }
    #else
      body(self.currentState)
    #endif
  }

  /// Sends an action to the store.
  ///
  /// This method returns a ``StoreTask``, which represents the lifecycle of the effect started from
  /// sending an action. You can use this value to tie the effect's lifecycle _and_ cancellation to
  /// an asynchronous context, such as SwiftUI's `task` view modifier:
  ///
  /// ```swift
  /// .task { await store.send(.task).finish() }
  /// ```
  ///
  /// - Parameter action: An action.
  /// - Returns: A ``StoreTask`` that represents the lifecycle of the effect executed when
  ///   sending the action.
  @discardableResult
  public func send(_ action: Action) -> StoreTask {
    .init(rawValue: self.send(action))
  }

  /// Sends an action to the store with a given animation.
  ///
  /// See ``Store/send(_:)`` for more info.
  ///
  /// - Parameters:
  ///   - action: An action.
  ///   - animation: An animation.
  @discardableResult
  public func send(_ action: Action, animation: Animation?) -> StoreTask {
    send(action, transaction: Transaction(animation: animation))
  }

  /// Sends an action to the store with a given transaction.
  ///
  /// See ``Store/send(_:)`` for more info.
  ///
  /// - Parameters:
  ///   - action: An action.
  ///   - transaction: A transaction.
  @discardableResult
  public func send(_ action: Action, transaction: Transaction) -> StoreTask {
    withTransaction(transaction) {
      .init(rawValue: self.send(action))
    }
  }

  /// Scopes the store to one that exposes child state and actions.
  ///
  /// This can be useful for deriving new stores to hand to child views in an application. For
  /// example:
  ///
  /// ```swift
  /// @Reducer
  /// struct AppFeature {
  ///   @ObservableState
  ///   struct State {
  ///     var login: Login.State
  ///     // ...
  ///   }
  ///   enum Action {
  ///     case login(Login.Action)
  ///     // ...
  ///   }
  ///   // ...
  /// }
  ///
  /// // A store that runs the entire application.
  /// let store = Store(initialState: AppFeature.State()) {
  ///   AppFeature()
  /// }
  ///
  /// // Construct a login view by scoping the store
  /// // to one that works with only login domain.
  /// LoginView(
  ///   store: store.scope(state: \.login, action: \.login)
  /// )
  /// ```
  ///
  /// Scoping in this fashion allows you to better modularize your application. In this case,
  /// `LoginView` could be extracted to a module that has no access to `AppFeature.State` or
  /// `AppFeature.Action`.
  ///
  /// - Parameters:
  ///   - state: A key path from `State` to `ChildState`.
  ///   - action: A case key path from `Action` to `ChildAction`.
  /// - Returns: A new store with its domain (state and action) transformed.
  public func scope<ChildState, ChildAction>(
    state: KeyPath<State, ChildState>,
    action: CaseKeyPath<Action, ChildAction>
  ) -> Store<ChildState, ChildAction> {
    func open(_ core: some Core<State, Action>) -> any Core<ChildState, ChildAction> {
      ScopedCore(base: core, stateKeyPath: state, actionKeyPath: action)
    }
    return scope(id: id(state: state, action: action), childCore: open(core))
  }

  func scope<ChildState, ChildAction>(
    id: ScopeID<State, Action>?,
    childCore: @autoclosure () -> any Core<ChildState, ChildAction>
  ) -> Store<ChildState, ChildAction> {
    guard
      core.canStoreCacheChildren,
      let id,
      let child = children[id] as? Store<ChildState, ChildAction>
    else {
      let child = Store<ChildState, ChildAction>(core: childCore(), scopeID: id, parent: self)
      if core.canStoreCacheChildren, let id {
        children[id] = child
      }
      return child
    }
    return child
  }

  @available(
    *,
    deprecated,
    message:
      "Pass 'state' a key path to child state and 'action' a case key path to child action, instead. For more information see the following migration guide: https://pointfreeco.github.io/swift-composable-architecture/main/documentation/composablearchitecture/migratingto1.5#Store-scoping-with-key-paths"
  )
  public func scope<ChildState, ChildAction>(
    state toChildState: @escaping (_ state: State) -> ChildState,
    action fromChildAction: @escaping (_ childAction: ChildAction) -> Action
  ) -> Store<ChildState, ChildAction> {
    _scope(state: toChildState, action: fromChildAction)
  }

  func _scope<ChildState, ChildAction>(
    state toChildState: @escaping (_ state: State) -> ChildState,
    action fromChildAction: @escaping (_ childAction: ChildAction) -> Action
  ) -> Store<ChildState, ChildAction> {
    func open(_ core: some Core<State, Action>) -> any Core<ChildState, ChildAction> {
      ClosureScopedCore(
        base: core,
        toState: toChildState,
        fromAction: fromChildAction
      )
    }
    return scope(id: nil, childCore: open(core))
  }

  @_spi(Internals)
  public var currentState: State {
    core.state
  }

  @_spi(Internals)
  @_disfavoredOverload
  public func send(_ action: Action) -> Task<Void, Never>? {
    core.send(action)
  }

  private init(core: some Core<State, Action>, scopeID: AnyHashable?, parent: (any _Store)?) {
    defer { Logger.shared.log("\(storeTypeName(of: self)).init") }
    self.core = core
    self.parent = parent
    self.scopeID = scopeID

    if let stateType = State.self as? any ObservableState.Type {
      func subscribeToDidSet<T: ObservableState>(_ type: T.Type) -> AnyCancellable {
        return core.didSet
          .prefix { [weak self] _ in self?.core.isInvalid == false }
          .compactMap { [weak self] in (self?.currentState as? T)?._$id }
          .removeDuplicates()
          .dropFirst()
          .sink { [weak self] _ in
            guard let scopeID = self?.scopeID
            else { return }
            parent?.removeChild(scopeID: scopeID)
          } receiveValue: { [weak self] _ in
            guard let self else { return }
            self._$observationRegistrar.withMutation(of: self, keyPath: \.currentState) {}
          }
      }
      self.parentCancellable = subscribeToDidSet(stateType)
    }
  }

  convenience init<R: Reducer<State, Action>>(
    initialState: R.State,
    reducer: R
  ) {
    self.init(
      core: RootCore(initialState: initialState, reducer: reducer),
      scopeID: nil,
      parent: nil
    )
  }

  /// A publisher that emits when state changes.
  ///
  /// This publisher supports dynamic member lookup so that you can pluck out a specific field in
  /// the state:
  ///
  /// ```swift
  /// store.publisher.alert
  ///   .sink { ... }
  /// ```
  public var publisher: StorePublisher<State> {
    StorePublisher(
      store: self,
      upstream: self.core.didSet.map { self.currentState }
    )
  }

  @_spi(Internals) public func id<ChildState, ChildAction>(
    state: KeyPath<State, ChildState>,
    action: CaseKeyPath<Action, ChildAction>
  ) -> ScopeID<State, Action> {
    ScopeID(state: state, action: action)
  }
}

@_spi(Internals) public struct ScopeID<State, Action>: Hashable {
  let state: PartialKeyPath<State>
  let action: PartialCaseKeyPath<Action>
}

extension Store: CustomDebugStringConvertible {
  public nonisolated var debugDescription: String {
    storeTypeName(of: self)
  }
}

extension Store: ObservableObject {}

/// A convenience type alias for referring to a store of a given reducer's domain.
///
/// Instead of specifying two generics:
///
/// ```swift
/// let store: Store<Feature.State, Feature.Action>
/// ```
///
/// You can specify a single generic:
///
/// ```swift
/// let store: StoreOf<Feature>
/// ```
public typealias StoreOf<R: Reducer> = Store<R.State, R.Action>

/// A publisher of store state.
@dynamicMemberLookup
public struct StorePublisher<State>: Publisher {
  public typealias Output = State
  public typealias Failure = Never

  let store: Any
  let upstream: AnyPublisher<State, Never>

  init(store: Any, upstream: some Publisher<Output, Failure>) {
    self.store = store
    self.upstream = upstream.eraseToAnyPublisher()
  }

  public func receive(subscriber: some Subscriber<Output, Failure>) {
    self.upstream.subscribe(
      AnySubscriber(
        receiveSubscription: subscriber.receive(subscription:),
        receiveValue: subscriber.receive(_:),
        receiveCompletion: { [store = self.store] in
          subscriber.receive(completion: $0)
          _ = store
        }
      )
    )
  }

  /// Returns the resulting publisher of a given key path.
  public subscript<Value: Equatable>(
    dynamicMember keyPath: KeyPath<State, Value>
  ) -> StorePublisher<Value> {
    .init(store: self.store, upstream: self.upstream.map(keyPath).removeDuplicates())
  }
}

/// The type returned from ``Store/send(_:)`` that represents the lifecycle of the effect
/// started from sending an action.
///
/// You can use this value to tie the effect's lifecycle _and_ cancellation to an asynchronous
/// context, such as the `task` view modifier.
///
/// ```swift
/// .task { await store.send(.task).finish() }
/// ```
///
/// > Note: Unlike Swift's `Task` type, ``StoreTask`` automatically sets up a cancellation
/// > handler between the current async context and the task.
///
/// See ``TestStoreTask`` for the analog returned from ``TestStore``.
public struct StoreTask: Hashable, Sendable {
  internal let rawValue: Task<Void, Never>?

  internal init(rawValue: Task<Void, Never>?) {
    self.rawValue = rawValue
  }

  /// Cancels the underlying task.
  public func cancel() {
    self.rawValue?.cancel()
  }

  /// Waits for the task to finish.
  public func finish() async {
    await self.rawValue?.cancellableValue
  }

  /// A Boolean value that indicates whether the task should stop executing.
  ///
  /// After the value of this property becomes `true`, it remains `true` indefinitely. There is no
  /// way to uncancel a task.
  public var isCancelled: Bool {
    self.rawValue?.isCancelled ?? true
  }
}

func storeTypeName<State, Action>(of store: Store<State, Action>) -> String {
  let stateType = typeName(State.self, genericsAbbreviated: false)
  let actionType = typeName(Action.self, genericsAbbreviated: false)
  if stateType.hasSuffix(".State"),
    actionType.hasSuffix(".Action"),
    stateType.dropLast(6) == actionType.dropLast(7)
  {
    return "StoreOf<\(stateType.dropLast(6))>"
  } else if stateType.hasSuffix(".State?"),
    actionType.hasSuffix(".Action"),
    stateType.dropLast(7) == actionType.dropLast(7)
  {
    return "StoreOf<\(stateType.dropLast(7))?>"
  } else if stateType.hasPrefix("IdentifiedArray<"),
    actionType.hasPrefix("IdentifiedAction<"),
    stateType.dropFirst(16).dropLast(7) == actionType.dropFirst(17).dropLast(8)
  {
    return "IdentifiedStoreOf<\(stateType.drop(while: { $0 != "," }).dropFirst(2).dropLast(7))>"
  } else if stateType.hasPrefix("PresentationState<"),
    actionType.hasPrefix("PresentationAction<"),
    stateType.dropFirst(18).dropLast(7) == actionType.dropFirst(19).dropLast(8)
  {
    return "PresentationStoreOf<\(stateType.dropFirst(18).dropLast(7))>"
  } else if stateType.hasPrefix("StackState<"),
    actionType.hasPrefix("StackAction<"),
    stateType.dropFirst(11).dropLast(7)
      == actionType.dropFirst(12).prefix(while: { $0 != "," }).dropLast(6)
  {
    return "StackStoreOf<\(stateType.dropFirst(11).dropLast(7))>"
  } else {
    return "Store<\(stateType), \(actionType)>"
  }
}

// NB: From swift-custom-dump. Consider publicizing interface in some way to keep things in sync.
@usableFromInline
func typeName(
  _ type: Any.Type,
  qualified: Bool = true,
  genericsAbbreviated: Bool = true
) -> String {
  var name = _typeName(type, qualified: qualified)
    .replacingOccurrences(
      of: #"\(unknown context at \$[[:xdigit:]]+\)\."#,
      with: "",
      options: .regularExpression
    )
  for _ in 1...10 {  // NB: Only handle so much nesting
    let abbreviated =
      name
      .replacingOccurrences(
        of: #"\bSwift.Optional<([^><]+)>"#,
        with: "$1?",
        options: .regularExpression
      )
      .replacingOccurrences(
        of: #"\bSwift.Array<([^><]+)>"#,
        with: "[$1]",
        options: .regularExpression
      )
      .replacingOccurrences(
        of: #"\bSwift.Dictionary<([^,<]+), ([^><]+)>"#,
        with: "[$1: $2]",
        options: .regularExpression
      )
    if abbreviated == name { break }
    name = abbreviated
  }
  name = name.replacingOccurrences(
    of: #"\w+\.([\w.]+)"#,
    with: "$1",
    options: .regularExpression
  )
  if genericsAbbreviated {
    name = name.replacingOccurrences(
      of: #"<.+>"#,
      with: "",
      options: .regularExpression
    )
  }
  return name
}

let _isStorePerceptionCheckingEnabled: Bool = {
  if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, *) {
    return false
  } else {
    return true
  }
}()

#if canImport(Observation)
  // NB: This extension must be placed in the same file as 'class Store' due to either a bug
  //     in Swift, or very opaque and undocumented behavior of Swift.
  //     See https://github.com/tuist/tuist/issues/6320#issuecomment-2148554117
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension Store: Observable {}
#endif

@MainActor
private protocol _Store: AnyObject {
  func removeChild(scopeID: AnyHashable)
}
