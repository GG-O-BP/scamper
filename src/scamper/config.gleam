//// Configuration builder for scamper finite state machines.
////
//// Build a config using the pipeline operator:
////
//// ```gleam
//// config.new(timestamp_fn)
//// |> config.add_transition(from: Idle, on: Start, to: Running)
//// |> config.add_guarded_transition(from: Running, on: Complete, guard: is_valid, to: Done)
//// |> config.set_final_states([Done, Failed])
//// |> config.set_on_enter(Running, start_handler)
//// |> config.set_event_policy(config.Ignore)
//// |> config.set_history_limit(100)
//// ```

import gleam/list
import gleam/option.{type Option, None, Some}

// --- Public Types ---

/// Policy for handling events that have no matching transition rule.
pub type EventPolicy {
  /// Return an `InvalidTransition` error (default).
  Reject
  /// Silently return the machine unchanged.
  Ignore
}

/// A single transition rule in the transition table.
pub type TransitionRule(state, context, event) {
  TransitionRule(
    from: state,
    on: event,
    to: state,
    guard: Option(fn(context, event) -> Bool),
  )
}

// --- Callback Type Aliases ---

/// Callback invoked when entering or exiting a state.
/// Receives the state and current context, returns updated context or error.
pub type StateCallback(state, context) =
  fn(state, context) -> Result(context, String)

/// Callback invoked during a transition.
/// Receives (from, event, to, context), returns updated context or error.
pub type TransitionCallback(state, context, event) =
  fn(state, event, state, context) -> Result(context, String)

// --- Opaque Config Type ---

/// Opaque configuration for a finite state machine.
pub opaque type Config(state, context, event) {
  Config(
    transitions: List(TransitionRule(state, context, event)),
    final_states: List(state),
    // State-specific callbacks
    on_enter: List(#(state, StateCallback(state, context))),
    on_exit: List(#(state, StateCallback(state, context))),
    on_transition_state: List(
      #(state, TransitionCallback(state, context, event)),
    ),
    // Global callbacks (in registration order)
    global_on_enter: List(StateCallback(state, context)),
    global_on_exit: List(StateCallback(state, context)),
    global_on_transition: List(TransitionCallback(state, context, event)),
    // Invariants
    invariants: List(fn(context) -> Result(Nil, String)),
    // Policy
    event_policy: EventPolicy,
    // History settings
    history_limit: Option(Int),
    history_snapshots: Bool,
    // Timeouts: (state, duration_ms, timeout_event)
    timeouts: List(#(state, Int, event)),
    // Timestamp provider
    timestamp_fn: fn() -> Int,
  )
}

// --- Builder Functions ---

/// Create a new empty configuration.
/// The `timestamp_fn` is called to get the current time in milliseconds.
pub fn new(timestamp_fn: fn() -> Int) -> Config(state, context, event) {
  Config(
    transitions: [],
    final_states: [],
    on_enter: [],
    on_exit: [],
    on_transition_state: [],
    global_on_enter: [],
    global_on_exit: [],
    global_on_transition: [],
    invariants: [],
    event_policy: Reject,
    history_limit: None,
    history_snapshots: False,
    timeouts: [],
    timestamp_fn: timestamp_fn,
  )
}

/// Add a simple (unguarded) transition rule.
pub fn add_transition(
  config: Config(state, context, event),
  from from: state,
  on on: event,
  to to: state,
) -> Config(state, context, event) {
  let rule = TransitionRule(from: from, on: on, to: to, guard: None)
  Config(..config, transitions: list.append(config.transitions, [rule]))
}

/// Add a guarded transition rule.
pub fn add_guarded_transition(
  config: Config(state, context, event),
  from from: state,
  on on: event,
  guard guard: fn(context, event) -> Bool,
  to to: state,
) -> Config(state, context, event) {
  let rule = TransitionRule(from: from, on: on, to: to, guard: Some(guard))
  Config(..config, transitions: list.append(config.transitions, [rule]))
}

/// Set the list of final (terminal) states.
pub fn set_final_states(
  config: Config(state, context, event),
  states: List(state),
) -> Config(state, context, event) {
  Config(..config, final_states: states)
}

/// Set a state-specific on_enter callback.
pub fn set_on_enter(
  config: Config(state, context, event),
  state: state,
  callback: StateCallback(state, context),
) -> Config(state, context, event) {
  let on_enter =
    config.on_enter
    |> list.filter(fn(entry) { entry.0 != state })
    |> list.append([#(state, callback)])
  Config(..config, on_enter: on_enter)
}

/// Set a state-specific on_exit callback.
pub fn set_on_exit(
  config: Config(state, context, event),
  state: state,
  callback: StateCallback(state, context),
) -> Config(state, context, event) {
  let on_exit =
    config.on_exit
    |> list.filter(fn(entry) { entry.0 != state })
    |> list.append([#(state, callback)])
  Config(..config, on_exit: on_exit)
}

/// Set a state-specific on_transition callback (keyed by from-state).
pub fn set_on_transition(
  config: Config(state, context, event),
  state: state,
  callback: TransitionCallback(state, context, event),
) -> Config(state, context, event) {
  let on_transition_state =
    config.on_transition_state
    |> list.filter(fn(entry) { entry.0 != state })
    |> list.append([#(state, callback)])
  Config(..config, on_transition_state: on_transition_state)
}

/// Add a global on_enter callback (runs for all transitions).
pub fn add_global_on_enter(
  config: Config(state, context, event),
  callback: StateCallback(state, context),
) -> Config(state, context, event) {
  Config(
    ..config,
    global_on_enter: list.append(config.global_on_enter, [callback]),
  )
}

/// Add a global on_exit callback (runs for all transitions).
pub fn add_global_on_exit(
  config: Config(state, context, event),
  callback: StateCallback(state, context),
) -> Config(state, context, event) {
  Config(
    ..config,
    global_on_exit: list.append(config.global_on_exit, [callback]),
  )
}

/// Add a global on_transition callback (runs for all transitions).
pub fn add_global_on_transition(
  config: Config(state, context, event),
  callback: TransitionCallback(state, context, event),
) -> Config(state, context, event) {
  Config(
    ..config,
    global_on_transition: list.append(config.global_on_transition, [callback]),
  )
}

/// Add a context invariant that is checked after every successful transition.
pub fn add_invariant(
  config: Config(state, context, event),
  invariant: fn(context) -> Result(Nil, String),
) -> Config(state, context, event) {
  Config(..config, invariants: list.append(config.invariants, [invariant]))
}

/// Set the event filtering policy.
pub fn set_event_policy(
  config: Config(state, context, event),
  policy: EventPolicy,
) -> Config(state, context, event) {
  Config(..config, event_policy: policy)
}

/// Set the maximum number of history records to keep.
pub fn set_history_limit(
  config: Config(state, context, event),
  limit: Int,
) -> Config(state, context, event) {
  Config(..config, history_limit: Some(limit))
}

/// Set whether to include context snapshots in history records.
pub fn set_history_snapshots(
  config: Config(state, context, event),
  enabled: Bool,
) -> Config(state, context, event) {
  Config(..config, history_snapshots: enabled)
}

/// Declare a timeout for a state.
/// After `duration_ms` milliseconds in `state`, the `timeout_event` should be sent.
/// The library only declares this — actual timer management is external.
pub fn set_timeout(
  config: Config(state, context, event),
  state: state,
  duration_ms: Int,
  timeout_event: event,
) -> Config(state, context, event) {
  let timeouts =
    config.timeouts
    |> list.filter(fn(entry) { entry.0 != state })
    |> list.append([#(state, duration_ms, timeout_event)])
  Config(..config, timeouts: timeouts)
}

// --- Accessor Functions (for internal use by other scamper modules) ---

/// Get the transition rules list.
pub fn get_transitions(
  config: Config(state, context, event),
) -> List(TransitionRule(state, context, event)) {
  config.transitions
}

/// Get the final states list.
pub fn get_final_states(config: Config(state, context, event)) -> List(state) {
  config.final_states
}

/// Get state-specific on_enter callbacks.
pub fn get_on_enter(
  config: Config(state, context, event),
) -> List(#(state, StateCallback(state, context))) {
  config.on_enter
}

/// Get state-specific on_exit callbacks.
pub fn get_on_exit(
  config: Config(state, context, event),
) -> List(#(state, StateCallback(state, context))) {
  config.on_exit
}

/// Get state-specific on_transition callbacks.
pub fn get_on_transition_state(
  config: Config(state, context, event),
) -> List(#(state, TransitionCallback(state, context, event))) {
  config.on_transition_state
}

/// Get global on_enter callbacks.
pub fn get_global_on_enter(
  config: Config(state, context, event),
) -> List(StateCallback(state, context)) {
  config.global_on_enter
}

/// Get global on_exit callbacks.
pub fn get_global_on_exit(
  config: Config(state, context, event),
) -> List(StateCallback(state, context)) {
  config.global_on_exit
}

/// Get global on_transition callbacks.
pub fn get_global_on_transition(
  config: Config(state, context, event),
) -> List(TransitionCallback(state, context, event)) {
  config.global_on_transition
}

/// Get context invariants.
pub fn get_invariants(
  config: Config(state, context, event),
) -> List(fn(context) -> Result(Nil, String)) {
  config.invariants
}

/// Get the event policy.
pub fn get_event_policy(config: Config(state, context, event)) -> EventPolicy {
  config.event_policy
}

/// Get the history limit.
pub fn get_history_limit(config: Config(state, context, event)) -> Option(Int) {
  config.history_limit
}

/// Get whether history snapshots are enabled.
pub fn get_history_snapshots(config: Config(state, context, event)) -> Bool {
  config.history_snapshots
}

/// Get timeout declarations.
pub fn get_timeouts(
  config: Config(state, context, event),
) -> List(#(state, Int, event)) {
  config.timeouts
}

/// Get the current timestamp by calling the configured timestamp function.
pub fn get_timestamp(config: Config(state, context, event)) -> Int {
  { config.timestamp_fn }()
}

/// Get the timestamp function itself.
pub fn get_timestamp_fn(config: Config(state, context, event)) -> fn() -> Int {
  config.timestamp_fn
}
