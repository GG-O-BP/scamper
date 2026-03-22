//// Scamper — Type-safe finite state machine library for Gleam.
////
//// Generic over `Machine(state, context, event)`. Build configs with the
//// pipeline operator, then create machines and transition them with events.
////
//// ```gleam
//// let cfg =
////   config.new(timestamp_fn)
////   |> config.add_transition(from: Idle, on: Start, to: Running)
////   |> config.add_transition(from: Running, on: Complete, to: Done)
////   |> config.set_final_states([Done])
////
//// let machine = scamper.new(cfg, Idle, initial_context)
//// let assert Ok(machine) = scamper.transition(machine, Start)
//// ```

import gleam/list
import gleam/result
import scamper/config.{type Config}
import scamper/error.{type TransitionError}
import scamper/history.{type TransitionRecord}
import scamper/transition

/// An opaque finite state machine, generic over state, context, and event types.
pub opaque type Machine(state, context, event) {
  Machine(
    config: Config(state, context, event),
    state: state,
    context: context,
    history: List(TransitionRecord(state, event, context)),
    created_at: Int,
    entered_at: Int,
  )
}

/// Create a new state machine with the given configuration, initial state, and context.
pub fn new(
  config: Config(state, context, event),
  initial_state: state,
  context: context,
) -> Machine(state, context, event) {
  let now = config.get_timestamp(config)
  Machine(
    config: config,
    state: initial_state,
    context: context,
    history: [],
    created_at: now,
    entered_at: now,
  )
}

/// Restore a machine from serialized components.
/// Used by the serialization module to reconstruct a machine.
pub fn restore(
  config: Config(state, context, event),
  state: state,
  context: context,
  history_records: List(TransitionRecord(state, event, context)),
  created_at: Int,
  entered_at: Int,
) -> Machine(state, context, event) {
  Machine(
    config: config,
    state: state,
    context: context,
    history: history_records,
    created_at: created_at,
    entered_at: entered_at,
  )
}

/// Attempt to transition the machine by processing an event.
/// Returns a new machine on success, or a TransitionError on failure.
/// The input machine is never modified.
pub fn transition(
  machine: Machine(state, context, event),
  event: event,
) -> Result(Machine(state, context, event), TransitionError(state, event)) {
  transition.execute(
    machine.state,
    machine.context,
    event,
    machine.config,
    machine.history,
  )
  |> result.map(fn(r) {
    Machine(
      ..machine,
      state: r.state,
      context: r.context,
      history: r.history,
      entered_at: r.entered_at,
    )
  })
}

/// Check whether a transition is possible for the given event
/// without actually executing it. Does not run callbacks or invariants.
pub fn can_transition(
  machine: Machine(state, context, event),
  event: event,
) -> Bool {
  transition.can_execute(machine.state, event, machine.context, machine.config)
}

/// Get the current state of the machine.
pub fn current_state(machine: Machine(state, context, event)) -> state {
  machine.state
}

/// Get the current context of the machine.
pub fn current_context(machine: Machine(state, context, event)) -> context {
  machine.context
}

/// Check whether the machine is in a final (terminal) state.
pub fn is_final(machine: Machine(state, context, event)) -> Bool {
  list.contains(config.get_final_states(machine.config), machine.state)
}

/// Get the list of events that have at least one matching transition rule
/// from the current state. Does not evaluate guards.
pub fn available_events(machine: Machine(state, context, event)) -> List(event) {
  transition.available_events(machine.state, machine.config)
}

/// Get the full transition history (newest first).
pub fn history(
  machine: Machine(state, context, event),
) -> List(TransitionRecord(state, event, context)) {
  machine.history
}

/// Get milliseconds elapsed since the last transition
/// (or since creation if no transitions have occurred).
pub fn elapsed(machine: Machine(state, context, event)) -> Int {
  config.get_timestamp(machine.config) - machine.entered_at
}

/// Get the machine's configuration.
pub fn get_config(
  machine: Machine(state, context, event),
) -> Config(state, context, event) {
  machine.config
}

/// Get the timestamp when the machine was created.
pub fn created_at(machine: Machine(state, context, event)) -> Int {
  machine.created_at
}

/// Get the timestamp when the current state was entered.
pub fn entered_at(machine: Machine(state, context, event)) -> Int {
  machine.entered_at
}
