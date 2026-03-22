import gleam/list
import scamper/config
import scamper/validation.{
  MissingFallback, TransitionFromFinalState, UnreachableState,
}

// Test types

pub type State {
  Idle
  Running
  Done
  Failed
  Orphan
}

pub type Event {
  Start
  Complete
  Fail
  Reset
}

pub type Context {
  Context
}

fn test_timestamp() -> Int {
  1_000_000
}

// --- validate_config tests ---

pub fn valid_config_returns_ok_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.add_transition(from: Running, on: Complete, to: Done)
    |> config.set_final_states([Done])

  let assert Ok(Nil) = validation.validate_config(cfg, Idle)
}

pub fn detects_unreachable_state_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.add_transition(from: Orphan, on: Start, to: Running)
    |> config.set_final_states([])

  let assert Error(warnings) = validation.validate_config(cfg, Idle)
  let has_unreachable =
    list.any(warnings, fn(w) {
      case w {
        UnreachableState(state: Orphan) -> True
        _ -> False
      }
    })
  assert has_unreachable == True
}

pub fn detects_transitions_from_final_state_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.add_transition(from: Done, on: Reset, to: Idle)
    |> config.set_final_states([Done])

  let assert Error(warnings) = validation.validate_config(cfg, Idle)
  let has_final_transition =
    list.any(warnings, fn(w) {
      case w {
        TransitionFromFinalState(state: Done) -> True
        _ -> False
      }
    })
  assert has_final_transition == True
}

pub fn detects_missing_fallback_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.add_guarded_transition(
      from: Running,
      on: Complete,
      guard: fn(_ctx: Context, _evt) { True },
      to: Done,
    )

  let assert Error(warnings) = validation.validate_config(cfg, Idle)
  let has_missing_fallback =
    list.any(warnings, fn(w) {
      case w {
        MissingFallback(from: Running) -> True
        _ -> False
      }
    })
  assert has_missing_fallback == True
}

pub fn no_missing_fallback_when_unguarded_exists_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.add_guarded_transition(
      from: Running,
      on: Complete,
      guard: fn(_ctx: Context, _evt) { True },
      to: Done,
    )
    |> config.add_transition(from: Running, on: Complete, to: Failed)

  let result = validation.validate_config(cfg, Idle)
  let has_missing_fallback = case result {
    Ok(_) -> False
    Error(warnings) ->
      list.any(warnings, fn(w) {
        case w {
          MissingFallback(..) -> True
          _ -> False
        }
      })
  }
  assert has_missing_fallback == False
}

// --- detect_deadlocks tests ---

pub fn detect_deadlocks_finds_stuck_states_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    // Running has no outgoing transitions and is not final
    |> config.set_final_states([])

  let deadlocks = validation.detect_deadlocks(cfg)
  assert list.contains(deadlocks, Running) == True
}

pub fn detect_deadlocks_ignores_final_states_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Done)
    |> config.set_final_states([Done])

  let deadlocks = validation.detect_deadlocks(cfg)
  assert list.contains(deadlocks, Done) == False
}

pub fn detect_deadlocks_empty_for_valid_config_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.add_transition(from: Running, on: Complete, to: Done)
    |> config.set_final_states([Done])

  assert validation.detect_deadlocks(cfg) == []
}

// --- reachable_states tests ---

pub fn reachable_states_from_initial_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.add_transition(from: Running, on: Complete, to: Done)
    |> config.add_transition(from: Running, on: Fail, to: Failed)

  let reachable = validation.reachable_states(cfg, Idle)
  assert list.contains(reachable, Idle) == True
  assert list.contains(reachable, Running) == True
  assert list.contains(reachable, Done) == True
  assert list.contains(reachable, Failed) == True
}

pub fn reachable_states_excludes_disconnected_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.add_transition(from: Orphan, on: Start, to: Done)

  let reachable = validation.reachable_states(cfg, Idle)
  assert list.contains(reachable, Idle) == True
  assert list.contains(reachable, Running) == True
  assert list.contains(reachable, Orphan) == False
  assert list.contains(reachable, Done) == False
}

pub fn reachable_states_includes_initial_test() {
  let cfg = config.new(test_timestamp)
  let reachable = validation.reachable_states(cfg, Idle)
  assert reachable == [Idle]
}
