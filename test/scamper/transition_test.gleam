import gleam/option.{None, Some}
import scamper/config
import scamper/error.{
  AlreadyFinal, CallbackFailed, GuardRejected, InvalidTransition,
  InvariantViolation, OnEnter, OnExit, OnTransition,
}
import scamper/transition.{TransitionResult}

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
  Refresh
}

pub type Context {
  Context(count: Int, log: List(String))
}

fn test_timestamp() -> Int {
  1_000_000
}

fn basic_config() -> config.Config(State, Context, Event) {
  config.new(test_timestamp)
  |> config.add_transition(from: Idle, on: Start, to: Running)
  |> config.add_transition(from: Running, on: Complete, to: Done)
  |> config.add_transition(from: Running, on: Fail, to: Failed)
  |> config.set_final_states([Done, Failed])
}

fn ctx() -> Context {
  Context(count: 0, log: [])
}

// --- Simple transition tests ---

pub fn simple_transition_succeeds_test() {
  let result = transition.execute(Idle, ctx(), Start, basic_config(), [])
  let assert Ok(TransitionResult(state: Running, ..)) = result
}

pub fn transition_updates_state_test() {
  let assert Ok(r) = transition.execute(Idle, ctx(), Start, basic_config(), [])
  assert r.state == Running
}

pub fn transition_preserves_context_test() {
  let context = Context(count: 42, log: ["hello"])
  let assert Ok(r) =
    transition.execute(Idle, context, Start, basic_config(), [])
  assert r.context == context
}

// --- Final state tests ---

pub fn final_state_rejects_all_events_test() {
  let result = transition.execute(Done, ctx(), Start, basic_config(), [])
  let assert Error(AlreadyFinal(state: Done)) = result
}

pub fn final_state_rejects_valid_events_too_test() {
  let result = transition.execute(Done, ctx(), Complete, basic_config(), [])
  let assert Error(AlreadyFinal(state: Done)) = result
}

// --- Invalid transition tests ---

pub fn undefined_transition_rejected_test() {
  let result = transition.execute(Idle, ctx(), Complete, basic_config(), [])
  let assert Error(InvalidTransition(from: Idle, event: Complete)) = result
}

pub fn undefined_transition_with_ignore_policy_test() {
  let cfg =
    basic_config()
    |> config.set_event_policy(config.Ignore)

  let result = transition.execute(Idle, ctx(), Complete, cfg, [])
  let assert Ok(TransitionResult(state: Idle, ..)) = result
}

// --- Guard evaluation tests ---

pub fn guarded_transition_passes_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_guarded_transition(
      from: Running,
      on: Complete,
      guard: fn(ctx: Context, _evt) { ctx.count > 0 },
      to: Done,
    )

  let result =
    transition.execute(Running, Context(count: 5, log: []), Complete, cfg, [])
  let assert Ok(TransitionResult(state: Done, ..)) = result
}

pub fn guarded_transition_fails_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_guarded_transition(
      from: Running,
      on: Complete,
      guard: fn(ctx: Context, _evt) { ctx.count > 10 },
      to: Done,
    )

  let result =
    transition.execute(Running, Context(count: 5, log: []), Complete, cfg, [])
  let assert Error(GuardRejected(from: Running, event: Complete, ..)) = result
}

pub fn guard_evaluation_order_first_wins_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_guarded_transition(
      from: Running,
      on: Complete,
      guard: fn(_ctx: Context, _evt) { True },
      to: Done,
    )
    |> config.add_guarded_transition(
      from: Running,
      on: Complete,
      guard: fn(_ctx: Context, _evt) { True },
      to: Failed,
    )

  let result = transition.execute(Running, ctx(), Complete, cfg, [])
  let assert Ok(TransitionResult(state: Done, ..)) = result
}

pub fn guard_fallback_used_when_all_guards_fail_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_guarded_transition(
      from: Running,
      on: Complete,
      guard: fn(_ctx: Context, _evt) { False },
      to: Done,
    )
    |> config.add_transition(from: Running, on: Complete, to: Failed)

  let result = transition.execute(Running, ctx(), Complete, cfg, [])
  let assert Ok(TransitionResult(state: Failed, ..)) = result
}

pub fn no_fallback_returns_guard_rejected_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_guarded_transition(
      from: Running,
      on: Complete,
      guard: fn(_ctx: Context, _evt) { False },
      to: Done,
    )

  let result = transition.execute(Running, ctx(), Complete, cfg, [])
  let assert Error(GuardRejected(..)) = result
}

// --- Self-transition tests ---

pub fn self_transition_is_valid_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Running, on: Refresh, to: Running)

  let result = transition.execute(Running, ctx(), Refresh, cfg, [])
  let assert Ok(TransitionResult(state: Running, ..)) = result
}

// --- Callback execution order tests ---

pub fn callback_order_exit_transition_enter_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.set_on_exit(Idle, fn(_state, ctx: Context) {
      Ok(Context(..ctx, log: ["exit", ..ctx.log]))
    })
    |> config.set_on_transition(Idle, fn(_from, _event, _to, ctx: Context) {
      Ok(Context(..ctx, log: ["transition", ..ctx.log]))
    })
    |> config.set_on_enter(Running, fn(_state, ctx: Context) {
      Ok(Context(..ctx, log: ["enter", ..ctx.log]))
    })

  let assert Ok(r) = transition.execute(Idle, ctx(), Start, cfg, [])
  // Log is prepended, so newest first → reverse to get execution order
  assert r.context.log == ["enter", "transition", "exit"]
}

pub fn global_callbacks_before_state_specific_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.add_global_on_exit(fn(_state, ctx: Context) {
      Ok(Context(..ctx, log: ["global_exit", ..ctx.log]))
    })
    |> config.set_on_exit(Idle, fn(_state, ctx: Context) {
      Ok(Context(..ctx, log: ["state_exit", ..ctx.log]))
    })
    |> config.add_global_on_enter(fn(_state, ctx: Context) {
      Ok(Context(..ctx, log: ["global_enter", ..ctx.log]))
    })
    |> config.set_on_enter(Running, fn(_state, ctx: Context) {
      Ok(Context(..ctx, log: ["state_enter", ..ctx.log]))
    })

  let assert Ok(r) = transition.execute(Idle, ctx(), Start, cfg, [])
  // Newest first in log
  assert r.context.log
    == ["state_enter", "global_enter", "state_exit", "global_exit"]
}

pub fn multiple_global_callbacks_in_registration_order_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.add_global_on_transition(fn(_from, _event, _to, ctx: Context) {
      Ok(Context(..ctx, log: ["global1", ..ctx.log]))
    })
    |> config.add_global_on_transition(fn(_from, _event, _to, ctx: Context) {
      Ok(Context(..ctx, log: ["global2", ..ctx.log]))
    })

  let assert Ok(r) = transition.execute(Idle, ctx(), Start, cfg, [])
  assert r.context.log == ["global2", "global1"]
}

// --- Callback error and rollback tests ---

pub fn on_exit_callback_failure_rolls_back_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.set_on_exit(Idle, fn(_state, _ctx: Context) {
      Error("exit failed")
    })

  let result = transition.execute(Idle, ctx(), Start, cfg, [])
  let assert Error(CallbackFailed(stage: OnExit, reason: "exit failed")) =
    result
}

pub fn on_transition_callback_failure_rolls_back_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.add_global_on_transition(fn(_from, _event, _to, _ctx: Context) {
      Error("transition failed")
    })

  let result = transition.execute(Idle, ctx(), Start, cfg, [])
  let assert Error(CallbackFailed(
    stage: OnTransition,
    reason: "transition failed",
  )) = result
}

pub fn on_enter_callback_failure_rolls_back_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.set_on_enter(Running, fn(_state, _ctx: Context) {
      Error("enter failed")
    })

  let result = transition.execute(Idle, ctx(), Start, cfg, [])
  let assert Error(CallbackFailed(stage: OnEnter, reason: "enter failed")) =
    result
}

pub fn callback_threads_context_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.set_on_exit(Idle, fn(_state, ctx: Context) {
      Ok(Context(..ctx, count: ctx.count + 1))
    })
    |> config.add_global_on_transition(fn(_from, _event, _to, ctx: Context) {
      Ok(Context(..ctx, count: ctx.count + 10))
    })
    |> config.set_on_enter(Running, fn(_state, ctx: Context) {
      Ok(Context(..ctx, count: ctx.count + 100))
    })

  let assert Ok(r) = transition.execute(Idle, ctx(), Start, cfg, [])
  assert r.context.count == 111
}

// --- Invariant tests ---

pub fn invariant_passes_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.add_invariant(fn(ctx: Context) {
      case ctx.count >= 0 {
        True -> Ok(Nil)
        False -> Error("count must be non-negative")
      }
    })

  let result = transition.execute(Idle, ctx(), Start, cfg, [])
  let assert Ok(_) = result
}

pub fn invariant_violation_rolls_back_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.set_on_enter(Running, fn(_state, ctx: Context) {
      Ok(Context(..ctx, count: -1))
    })
    |> config.add_invariant(fn(ctx: Context) {
      case ctx.count >= 0 {
        True -> Ok(Nil)
        False -> Error("count must be non-negative")
      }
    })

  let result = transition.execute(Idle, ctx(), Start, cfg, [])
  let assert Error(InvariantViolation(reason: "count must be non-negative")) =
    result
}

// --- History recording tests ---

pub fn transition_records_history_test() {
  let assert Ok(r) = transition.execute(Idle, ctx(), Start, basic_config(), [])
  assert r.history != []

  let assert [record] = r.history
  assert record.from == Idle
  assert record.event == Start
  assert record.to == Running
  assert record.context_snapshot == None
}

pub fn history_includes_snapshot_when_enabled_test() {
  let cfg =
    basic_config()
    |> config.set_history_snapshots(True)

  let assert Ok(r) = transition.execute(Idle, ctx(), Start, cfg, [])
  let assert [record] = r.history
  assert record.context_snapshot == Some(ctx())
}

pub fn history_respects_limit_test() {
  let cfg =
    basic_config()
    |> config.set_history_limit(1)

  let assert Ok(r1) = transition.execute(Idle, ctx(), Start, cfg, [])
  let assert Ok(r2) =
    transition.execute(Running, r1.context, Complete, cfg, r1.history)

  let assert [only_record] = r2.history
  assert only_record.to == Done
}

// --- can_execute tests ---

pub fn can_execute_valid_transition_test() {
  assert transition.can_execute(Idle, Start, ctx(), basic_config()) == True
}

pub fn can_execute_invalid_transition_test() {
  assert transition.can_execute(Idle, Complete, ctx(), basic_config()) == False
}

pub fn can_execute_final_state_test() {
  assert transition.can_execute(Done, Start, ctx(), basic_config()) == False
}

pub fn can_execute_with_ignore_policy_test() {
  let cfg =
    basic_config()
    |> config.set_event_policy(config.Ignore)

  assert transition.can_execute(Idle, Complete, ctx(), cfg) == True
}

pub fn can_execute_with_passing_guard_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_guarded_transition(
      from: Running,
      on: Complete,
      guard: fn(ctx: Context, _evt) { ctx.count > 0 },
      to: Done,
    )

  assert transition.can_execute(
      Running,
      Complete,
      Context(count: 5, log: []),
      cfg,
    )
    == True
}

pub fn can_execute_with_failing_guard_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_guarded_transition(
      from: Running,
      on: Complete,
      guard: fn(ctx: Context, _evt) { ctx.count > 10 },
      to: Done,
    )

  assert transition.can_execute(
      Running,
      Complete,
      Context(count: 5, log: []),
      cfg,
    )
    == False
}

// --- available_events tests ---

pub fn available_events_test() {
  let events = transition.available_events(Running, basic_config())
  assert events == [Complete, Fail]
}

pub fn available_events_empty_for_final_state_test() {
  let events = transition.available_events(Done, basic_config())
  assert events == []
}

pub fn available_events_from_idle_test() {
  let events = transition.available_events(Idle, basic_config())
  assert events == [Start]
}

// --- Self-transition with context update test ---

pub fn self_transition_updates_context_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Running, on: Refresh, to: Running)
    |> config.set_on_enter(Running, fn(_state, ctx: Context) {
      Ok(Context(..ctx, count: ctx.count + 1))
    })

  let assert Ok(r) = transition.execute(Running, ctx(), Refresh, cfg, [])
  assert r.state == Running
  assert r.context.count == 1
}
