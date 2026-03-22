//// Test helpers for scamper FSMs.
////
//// Provides convenience functions for testing state machine behavior.
//// These functions use `let assert` which panics on failure — they are
//// designed for test code only, not for library or application code.

import gleam/list
import scamper.{type Machine}
import scamper/config.{type Config}
import scamper/error.{type TransitionError}
import scamper/validation

/// Attempt a transition and assert the machine reaches the expected state.
/// Panics if the transition fails or the machine is not in the expected state.
/// Returns the new machine for chaining.
pub fn assert_transition(
  machine: Machine(state, context, event),
  event: event,
  expected_state: state,
) -> Machine(state, context, event) {
  let assert Ok(new_machine) = scamper.transition(machine, event)
  let assert True = scamper.current_state(new_machine) == expected_state
  new_machine
}

/// Assert that the machine is in a final state.
/// Panics if the machine is not in a final state.
/// Returns the machine for chaining.
pub fn assert_final(
  machine: Machine(state, context, event),
) -> Machine(state, context, event) {
  let assert True = scamper.is_final(machine)
  machine
}

/// Find all states reachable from the initial state via transition rules.
/// Delegates to validation.reachable_states.
pub fn reachable_states(
  config: Config(state, context, event),
  initial_state: state,
) -> List(state) {
  validation.reachable_states(config, initial_state)
}

/// Run a sequence of events against the machine.
/// Returns the final machine if all transitions succeed,
/// or the first TransitionError encountered.
pub fn run_events(
  machine: Machine(state, context, event),
  events: List(event),
) -> Result(Machine(state, context, event), TransitionError(state, event)) {
  list.try_fold(events, machine, fn(m, evt) { scamper.transition(m, evt) })
}
