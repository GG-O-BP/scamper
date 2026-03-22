import gleam/list
import gleam/option.{None, Some}
import scamper/config.{Ignore, Reject, TransitionRule}

// Test types

pub type State {
  Idle
  Running
  Done
  Failed
}

pub type Event {
  Start
  Complete
  Fail
}

pub type Context {
  Context(count: Int)
}

fn test_timestamp() -> Int {
  1_000_000
}

pub fn new_creates_empty_config_test() {
  let cfg = config.new(test_timestamp)
  assert config.get_transitions(cfg) == []
  assert config.get_final_states(cfg) == []
  assert config.get_on_enter(cfg) == []
  assert config.get_on_exit(cfg) == []
  assert config.get_on_transition_state(cfg) == []
  assert config.get_global_on_enter(cfg) == []
  assert config.get_global_on_exit(cfg) == []
  assert config.get_global_on_transition(cfg) == []
  assert config.get_invariants(cfg) == []
  assert config.get_event_policy(cfg) == Reject
  assert config.get_history_limit(cfg) == None
  assert config.get_history_snapshots(cfg) == False
  assert config.get_timeouts(cfg) == []
}

pub fn add_transition_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)

  let transitions = config.get_transitions(cfg)
  assert list.length(transitions) == 1

  let assert [TransitionRule(from: Idle, on: Start, to: Running, guard: None)] =
    transitions
}

pub fn add_multiple_transitions_preserves_order_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.add_transition(from: Running, on: Complete, to: Done)
    |> config.add_transition(from: Running, on: Fail, to: Failed)

  let transitions = config.get_transitions(cfg)
  assert list.length(transitions) == 3

  let assert [
    TransitionRule(from: Idle, on: Start, to: Running, guard: None),
    TransitionRule(from: Running, on: Complete, to: Done, guard: None),
    TransitionRule(from: Running, on: Fail, to: Failed, guard: None),
  ] = transitions
}

pub fn add_guarded_transition_test() {
  let guard = fn(_ctx: Context, _evt: Event) -> Bool { True }
  let cfg =
    config.new(test_timestamp)
    |> config.add_guarded_transition(
      from: Running,
      on: Complete,
      guard: guard,
      to: Done,
    )

  let transitions = config.get_transitions(cfg)
  assert list.length(transitions) == 1

  let assert [
    TransitionRule(from: Running, on: Complete, to: Done, guard: Some(_)),
  ] = transitions
}

pub fn set_final_states_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.set_final_states([Done, Failed])

  assert config.get_final_states(cfg) == [Done, Failed]
}

pub fn set_final_states_replaces_previous_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.set_final_states([Done])
    |> config.set_final_states([Done, Failed])

  assert config.get_final_states(cfg) == [Done, Failed]
}

pub fn set_on_enter_test() {
  let callback = fn(_state: State, ctx: Context) -> Result(Context, String) {
    Ok(ctx)
  }
  let cfg =
    config.new(test_timestamp)
    |> config.set_on_enter(Running, callback)

  let entries = config.get_on_enter(cfg)
  assert list.length(entries) == 1

  let assert [#(Running, _)] = entries
}

pub fn set_on_enter_replaces_for_same_state_test() {
  let cb1 = fn(_state: State, ctx: Context) -> Result(Context, String) {
    Ok(ctx)
  }
  let cb2 = fn(_state: State, _ctx: Context) -> Result(Context, String) {
    Ok(Context(count: 99))
  }
  let cfg =
    config.new(test_timestamp)
    |> config.set_on_enter(Running, cb1)
    |> config.set_on_enter(Running, cb2)

  let entries = config.get_on_enter(cfg)
  assert list.length(entries) == 1

  let assert [#(Running, cb)] = entries
  let assert Ok(Context(count: 99)) = cb(Running, Context(count: 0))
}

pub fn set_on_exit_test() {
  let callback = fn(_state: State, ctx: Context) -> Result(Context, String) {
    Ok(ctx)
  }
  let cfg =
    config.new(test_timestamp)
    |> config.set_on_exit(Running, callback)

  let entries = config.get_on_exit(cfg)
  assert list.length(entries) == 1

  let assert [#(Running, _)] = entries
}

pub fn set_on_transition_test() {
  let callback = fn(_from: State, _event: Event, _to: State, ctx: Context) -> Result(
    Context,
    String,
  ) {
    Ok(ctx)
  }
  let cfg =
    config.new(test_timestamp)
    |> config.set_on_transition(Running, callback)

  let entries = config.get_on_transition_state(cfg)
  assert list.length(entries) == 1

  let assert [#(Running, _)] = entries
}

pub fn add_global_on_enter_test() {
  let cb1 = fn(_state: State, ctx: Context) -> Result(Context, String) {
    Ok(ctx)
  }
  let cb2 = fn(_state: State, ctx: Context) -> Result(Context, String) {
    Ok(ctx)
  }
  let cfg =
    config.new(test_timestamp)
    |> config.add_global_on_enter(cb1)
    |> config.add_global_on_enter(cb2)

  assert list.length(config.get_global_on_enter(cfg)) == 2
}

pub fn add_global_on_exit_test() {
  let cb = fn(_state: State, ctx: Context) -> Result(Context, String) {
    Ok(ctx)
  }
  let cfg =
    config.new(test_timestamp)
    |> config.add_global_on_exit(cb)

  assert list.length(config.get_global_on_exit(cfg)) == 1
}

pub fn add_global_on_transition_test() {
  let cb = fn(_from: State, _event: Event, _to: State, ctx: Context) -> Result(
    Context,
    String,
  ) {
    Ok(ctx)
  }
  let cfg =
    config.new(test_timestamp)
    |> config.add_global_on_transition(cb)

  assert list.length(config.get_global_on_transition(cfg)) == 1
}

pub fn add_invariant_test() {
  let inv = fn(_ctx: Context) -> Result(Nil, String) { Ok(Nil) }
  let cfg =
    config.new(test_timestamp)
    |> config.add_invariant(inv)

  assert list.length(config.get_invariants(cfg)) == 1
}

pub fn set_event_policy_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.set_event_policy(Ignore)

  assert config.get_event_policy(cfg) == Ignore
}

pub fn set_event_policy_default_is_reject_test() {
  let cfg = config.new(test_timestamp)
  assert config.get_event_policy(cfg) == Reject
}

pub fn set_history_limit_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.set_history_limit(50)

  assert config.get_history_limit(cfg) == Some(50)
}

pub fn set_history_snapshots_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.set_history_snapshots(True)

  assert config.get_history_snapshots(cfg) == True
}

pub fn set_timeout_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.set_timeout(Running, 5000, Fail)

  let timeouts = config.get_timeouts(cfg)
  assert timeouts == [#(Running, 5000, Fail)]
}

pub fn set_timeout_replaces_for_same_state_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.set_timeout(Running, 5000, Fail)
    |> config.set_timeout(Running, 10_000, Complete)

  let timeouts = config.get_timeouts(cfg)
  assert timeouts == [#(Running, 10_000, Complete)]
}

pub fn get_timestamp_test() {
  let cfg = config.new(test_timestamp)
  assert config.get_timestamp(cfg) == 1_000_000
}

pub fn builder_chaining_test() {
  let guard = fn(_ctx: Context, _evt: Event) -> Bool { True }
  let on_enter_cb = fn(_state: State, ctx: Context) -> Result(Context, String) {
    Ok(ctx)
  }
  let invariant = fn(_ctx: Context) -> Result(Nil, String) { Ok(Nil) }

  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.add_guarded_transition(
      from: Running,
      on: Complete,
      guard: guard,
      to: Done,
    )
    |> config.add_transition(from: Running, on: Fail, to: Failed)
    |> config.set_final_states([Done, Failed])
    |> config.set_on_enter(Running, on_enter_cb)
    |> config.add_invariant(invariant)
    |> config.set_event_policy(Ignore)
    |> config.set_history_limit(100)
    |> config.set_history_snapshots(True)
    |> config.set_timeout(Running, 30_000, Fail)

  assert list.length(config.get_transitions(cfg)) == 3
  assert config.get_final_states(cfg) == [Done, Failed]
  assert list.length(config.get_on_enter(cfg)) == 1
  assert list.length(config.get_invariants(cfg)) == 1
  assert config.get_event_policy(cfg) == Ignore
  assert config.get_history_limit(cfg) == Some(100)
  assert config.get_history_snapshots(cfg) == True
  assert config.get_timeouts(cfg) == [#(Running, 30_000, Fail)]
}
