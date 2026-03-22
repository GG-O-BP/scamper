//// Transition engine for scamper FSMs.
////
//// Handles guard evaluation, callback execution, invariant checking,
//// and rollback on failure. This is the core algorithmic module.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import scamper/config.{
  type Config, type StateCallback, type TransitionCallback, type TransitionRule,
  Ignore,
}
import scamper/error.{
  type TransitionError, AlreadyFinal, CallbackFailed, GuardRejected,
  InvalidTransition, InvariantViolation, OnEnter, OnExit, OnTransition,
}
import scamper/history.{type TransitionRecord}

/// Result of a successful transition execution.
pub type TransitionResult(state, event, context) {
  TransitionResult(
    state: state,
    context: context,
    history: List(TransitionRecord(state, event, context)),
    entered_at: Int,
  )
}

/// Execute a state transition.
///
/// Algorithm:
/// 1. Check if in final state → AlreadyFinal
/// 2. Find matching rules for (from, event)
/// 3. No rules → check event policy (Reject/Ignore)
/// 4. Evaluate guards top-to-bottom, first passing wins
/// 5. Execute callbacks: on_exit → on_transition → on_enter
/// 6. Run invariants on new context
/// 7. Record history
pub fn execute(
  state: state,
  context: context,
  event: event,
  config: Config(state, context, event),
  current_history: List(TransitionRecord(state, event, context)),
) -> Result(
  TransitionResult(state, event, context),
  TransitionError(state, event),
) {
  // 1. Final state check
  let final_states = config.get_final_states(config)
  case list.contains(final_states, state) {
    True -> Error(AlreadyFinal(state: state))
    False -> execute_non_final(state, context, event, config, current_history)
  }
}

fn execute_non_final(
  state: state,
  context: context,
  event: event,
  config: Config(state, context, event),
  current_history: List(TransitionRecord(state, event, context)),
) -> Result(
  TransitionResult(state, event, context),
  TransitionError(state, event),
) {
  // 2. Find matching rules
  let matching_rules =
    config.get_transitions(config)
    |> list.filter(fn(rule) { rule.from == state && rule.on == event })

  case matching_rules {
    // 3. No rules found
    [] ->
      case config.get_event_policy(config) {
        Ignore ->
          Ok(TransitionResult(
            state: state,
            context: context,
            history: current_history,
            entered_at: config.get_timestamp(config),
          ))
        config.Reject -> Error(InvalidTransition(from: state, event: event))
      }
    rules ->
      resolve_guards(state, context, event, rules, config, current_history)
  }
}

fn resolve_guards(
  from: state,
  context: context,
  event: event,
  rules: List(TransitionRule(state, context, event)),
  config: Config(state, context, event),
  current_history: List(TransitionRecord(state, event, context)),
) -> Result(
  TransitionResult(state, event, context),
  TransitionError(state, event),
) {
  // 4. Evaluate guards top-to-bottom
  case find_matching_rule(rules, context, event) {
    Some(rule) ->
      execute_transition(from, context, event, rule.to, config, current_history)
    None ->
      Error(GuardRejected(
        from: from,
        event: event,
        reason: "All guards rejected",
      ))
  }
}

/// Find the first matching rule by evaluating guards top-to-bottom.
/// Rules with Some(guard) are tested; rules with None (fallback) are collected.
/// First passing guarded rule wins. If none pass, use fallback if available.
fn find_matching_rule(
  rules: List(TransitionRule(state, context, event)),
  context: context,
  event: event,
) -> Option(TransitionRule(state, context, event)) {
  find_matching_rule_loop(rules, context, event, None)
}

fn find_matching_rule_loop(
  rules: List(TransitionRule(state, context, event)),
  context: context,
  event: event,
  fallback: Option(TransitionRule(state, context, event)),
) -> Option(TransitionRule(state, context, event)) {
  case rules {
    [] -> fallback
    [rule, ..rest] ->
      case rule.guard {
        None ->
          // First fallback (no guard) encountered — save it, continue looking for guarded match
          case fallback {
            None -> find_matching_rule_loop(rest, context, event, Some(rule))
            Some(_) -> find_matching_rule_loop(rest, context, event, fallback)
          }
        Some(guard_fn) ->
          case guard_fn(context, event) {
            True -> Some(rule)
            False -> find_matching_rule_loop(rest, context, event, fallback)
          }
      }
  }
}

/// Execute the transition with callbacks and invariants.
fn execute_transition(
  from: state,
  context: context,
  event: event,
  to: state,
  config: Config(state, context, event),
  current_history: List(TransitionRecord(state, event, context)),
) -> Result(
  TransitionResult(state, event, context),
  TransitionError(state, event),
) {
  // 5. Execute callbacks with rollback on error
  use ctx_after_callbacks <- result.try(run_all_callbacks(
    from,
    event,
    to,
    context,
    config,
  ))

  // 6. Run invariants
  use _ <- result.try(run_invariants(ctx_after_callbacks, config))

  // 7. Record history
  let timestamp = config.get_timestamp(config)
  let snapshot = case config.get_history_snapshots(config) {
    True -> Some(ctx_after_callbacks)
    False -> None
  }
  let record =
    history.new_record(
      from: from,
      event: event,
      to: to,
      timestamp: timestamp,
      context_snapshot: snapshot,
    )
  let new_history =
    history.append(current_history, record, config.get_history_limit(config))

  Ok(TransitionResult(
    state: to,
    context: ctx_after_callbacks,
    history: new_history,
    entered_at: timestamp,
  ))
}

/// Run all callbacks in the guaranteed order:
/// 1. Global on_exit → 2. State-specific on_exit(from)
/// 3. Global on_transition → 4. State-specific on_transition(from)
/// 5. Global on_enter → 6. State-specific on_enter(to)
fn run_all_callbacks(
  from: state,
  event: event,
  to: state,
  context: context,
  config: Config(state, context, event),
) -> Result(context, TransitionError(state, event)) {
  // Stage 1: on_exit
  use ctx <- result.try(run_state_callbacks(
    from,
    context,
    config.get_global_on_exit(config),
    find_state_callback(config.get_on_exit(config), from),
    OnExit,
  ))

  // Stage 2: on_transition
  use ctx <- result.try(run_transition_callbacks(
    from,
    event,
    to,
    ctx,
    config.get_global_on_transition(config),
    find_transition_callback(config.get_on_transition_state(config), from),
    OnTransition,
  ))

  // Stage 3: on_enter
  run_state_callbacks(
    to,
    ctx,
    config.get_global_on_enter(config),
    find_state_callback(config.get_on_enter(config), to),
    OnEnter,
  )
}

/// Run global state callbacks, then state-specific callback.
fn run_state_callbacks(
  target_state: state,
  context: context,
  global_callbacks: List(StateCallback(state, context)),
  state_callback: Option(StateCallback(state, context)),
  stage: error.CallbackStage,
) -> Result(context, TransitionError(state, event)) {
  // Run global callbacks in order
  use ctx <- result.try(
    list.try_fold(global_callbacks, context, fn(ctx, cb) {
      cb(target_state, ctx)
      |> result.map_error(fn(reason) {
        CallbackFailed(stage: stage, reason: reason)
      })
    }),
  )

  // Run state-specific callback
  case state_callback {
    None -> Ok(ctx)
    Some(cb) ->
      cb(target_state, ctx)
      |> result.map_error(fn(reason) {
        CallbackFailed(stage: stage, reason: reason)
      })
  }
}

/// Run global transition callbacks, then state-specific transition callback.
fn run_transition_callbacks(
  from: state,
  event: event,
  to: state,
  context: context,
  global_callbacks: List(TransitionCallback(state, context, event)),
  state_callback: Option(TransitionCallback(state, context, event)),
  stage: error.CallbackStage,
) -> Result(context, TransitionError(state, event)) {
  // Run global callbacks in order
  use ctx <- result.try(
    list.try_fold(global_callbacks, context, fn(ctx, cb) {
      cb(from, event, to, ctx)
      |> result.map_error(fn(reason) {
        CallbackFailed(stage: stage, reason: reason)
      })
    }),
  )

  // Run state-specific callback
  case state_callback {
    None -> Ok(ctx)
    Some(cb) ->
      cb(from, event, to, ctx)
      |> result.map_error(fn(reason) {
        CallbackFailed(stage: stage, reason: reason)
      })
  }
}

/// Find a state-specific callback for a given state.
fn find_state_callback(
  callbacks: List(#(state, StateCallback(state, context))),
  target: state,
) -> Option(StateCallback(state, context)) {
  case list.find(callbacks, fn(entry) { entry.0 == target }) {
    Ok(#(_, cb)) -> Some(cb)
    Error(_) -> None
  }
}

/// Find a state-specific transition callback for a given from-state.
fn find_transition_callback(
  callbacks: List(#(state, TransitionCallback(state, context, event))),
  target: state,
) -> Option(TransitionCallback(state, context, event)) {
  case list.find(callbacks, fn(entry) { entry.0 == target }) {
    Ok(#(_, cb)) -> Some(cb)
    Error(_) -> None
  }
}

/// Run all context invariants. Returns Ok or InvariantViolation.
fn run_invariants(
  context: context,
  config: Config(state, context, event),
) -> Result(Nil, TransitionError(state, event)) {
  let invariants = config.get_invariants(config)
  list.try_fold(invariants, Nil, fn(_, inv) {
    inv(context)
    |> result.map_error(fn(reason) { InvariantViolation(reason: reason) })
  })
}

/// Check whether a transition is possible without executing it.
/// Only checks final state, matching rules, and guards.
pub fn can_execute(
  state: state,
  event: event,
  context: context,
  config: Config(state, context, event),
) -> Bool {
  let final_states = config.get_final_states(config)
  case list.contains(final_states, state) {
    True -> False
    False -> {
      let matching_rules =
        config.get_transitions(config)
        |> list.filter(fn(rule) { rule.from == state && rule.on == event })
      case matching_rules {
        [] ->
          case config.get_event_policy(config) {
            Ignore -> True
            config.Reject -> False
          }
        rules ->
          case find_matching_rule(rules, context, event) {
            Some(_) -> True
            None -> False
          }
      }
    }
  }
}

/// Get all events that have at least one matching transition rule
/// from the current state. Does not evaluate guards.
pub fn available_events(
  state: state,
  config: Config(state, context, event),
) -> List(event) {
  config.get_transitions(config)
  |> list.filter(fn(rule) { rule.from == state })
  |> list.map(fn(rule) { rule.on })
  |> list.unique
}
