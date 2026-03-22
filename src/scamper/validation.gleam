//// Configuration validation, deadlock detection, and reachability analysis.

import gleam/list
import gleam/option.{None}
import scamper/config.{type Config}

/// Warnings produced by config validation.
pub type ValidationWarning(state) {
  /// A state has no incoming transitions (unreachable from initial state).
  UnreachableState(state: state)
  /// A final state has outgoing transitions defined (which will never execute).
  TransitionFromFinalState(state: state)
  /// A group of guarded transitions has no fallback (guard = None) rule.
  MissingFallback(from: state)
}

/// Validate a config for common issues.
/// Returns Ok(Nil) if no warnings, or Error with a list of warnings.
pub fn validate_config(
  config: Config(state, context, event),
  initial_state: state,
) -> Result(Nil, List(ValidationWarning(state))) {
  let warnings =
    list.flatten([
      check_unreachable(config, initial_state),
      check_transitions_from_final(config),
      check_missing_fallbacks(config),
    ])

  case warnings {
    [] -> Ok(Nil)
    _ -> Error(warnings)
  }
}

/// Find non-final states that have no outgoing transitions (deadlock states).
pub fn detect_deadlocks(config: Config(state, context, event)) -> List(state) {
  let transitions = config.get_transitions(config)
  let final_states = config.get_final_states(config)

  // All states that appear as destinations
  let all_to_states =
    transitions
    |> list.map(fn(rule) { rule.to })
    |> list.unique

  // States that have at least one outgoing transition
  let states_with_outgoing =
    transitions
    |> list.map(fn(rule) { rule.from })
    |> list.unique

  // Deadlocks: appear as destination, not final, no outgoing transitions
  all_to_states
  |> list.filter(fn(s) {
    !list.contains(final_states, s) && !list.contains(states_with_outgoing, s)
  })
}

/// Find all states reachable from the initial state via BFS.
/// Ignores guards (assumes all guards could pass).
pub fn reachable_states(
  config: Config(state, context, event),
  initial_state: state,
) -> List(state) {
  let transitions = config.get_transitions(config)
  bfs([initial_state], [initial_state], transitions)
}

fn bfs(
  queue: List(state),
  visited: List(state),
  transitions: List(config.TransitionRule(state, context, event)),
) -> List(state) {
  case queue {
    [] -> visited
    [current, ..rest] -> {
      // Find all states reachable from current
      let neighbors =
        transitions
        |> list.filter(fn(rule) { rule.from == current })
        |> list.map(fn(rule) { rule.to })
        |> list.unique
        |> list.filter(fn(s) { !list.contains(visited, s) })

      let new_visited = list.append(visited, neighbors)
      let new_queue = list.append(rest, neighbors)
      bfs(new_queue, new_visited, transitions)
    }
  }
}

// --- Internal validation helpers ---

fn check_unreachable(
  config: Config(state, context, event),
  initial_state: state,
) -> List(ValidationWarning(state)) {
  let transitions = config.get_transitions(config)
  let reachable = reachable_states(config, initial_state)

  // All states mentioned in the transition table
  let all_states =
    transitions
    |> list.flat_map(fn(rule) { [rule.from, rule.to] })
    |> list.unique

  all_states
  |> list.filter(fn(s) { !list.contains(reachable, s) })
  |> list.map(fn(s) { UnreachableState(state: s) })
}

fn check_transitions_from_final(
  config: Config(state, context, event),
) -> List(ValidationWarning(state)) {
  let transitions = config.get_transitions(config)
  let final_states = config.get_final_states(config)

  transitions
  |> list.filter(fn(rule) { list.contains(final_states, rule.from) })
  |> list.map(fn(rule) { rule.from })
  |> list.unique
  |> list.map(fn(s) { TransitionFromFinalState(state: s) })
}

fn check_missing_fallbacks(
  config: Config(state, context, event),
) -> List(ValidationWarning(state)) {
  let transitions = config.get_transitions(config)

  // Group by from state — find states that have guarded transitions
  let from_states =
    transitions
    |> list.map(fn(rule) { rule.from })
    |> list.unique

  from_states
  |> list.filter(fn(from) {
    let rules = list.filter(transitions, fn(rule) { rule.from == from })
    let has_guarded = list.any(rules, fn(rule) { option.is_some(rule.guard) })
    let has_fallback = list.any(rules, fn(rule) { rule.guard == None })
    has_guarded && !has_fallback
  })
  |> list.map(fn(s) { MissingFallback(from: s) })
}
