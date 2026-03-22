import gleam/list
import gleam/option.{None, Some}
import gleeunit
import scamper
import scamper/config
import scamper/error.{AlreadyFinal, CallbackFailed, InvalidTransition, OnEnter}

pub fn main() -> Nil {
  gleeunit.main()
}

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

// --- Creation tests ---

pub fn new_creates_machine_with_initial_state_test() {
  let machine = scamper.new(basic_config(), Idle, ctx())
  assert scamper.current_state(machine) == Idle
}

pub fn new_creates_machine_with_context_test() {
  let context = Context(count: 42, log: ["init"])
  let machine = scamper.new(basic_config(), Idle, context)
  assert scamper.current_context(machine) == context
}

pub fn new_machine_has_empty_history_test() {
  let machine = scamper.new(basic_config(), Idle, ctx())
  assert scamper.history(machine) == []
}

pub fn new_machine_is_not_final_test() {
  let machine = scamper.new(basic_config(), Idle, ctx())
  assert scamper.is_final(machine) == False
}

// --- Transition tests ---

pub fn transition_success_test() {
  let machine = scamper.new(basic_config(), Idle, ctx())
  let assert Ok(machine) = scamper.transition(machine, Start)
  assert scamper.current_state(machine) == Running
}

pub fn transition_chain_test() {
  let machine = scamper.new(basic_config(), Idle, ctx())
  let assert Ok(machine) = scamper.transition(machine, Start)
  let assert Ok(machine) = scamper.transition(machine, Complete)
  assert scamper.current_state(machine) == Done
  assert scamper.is_final(machine) == True
}

pub fn transition_error_propagation_test() {
  let machine = scamper.new(basic_config(), Idle, ctx())
  let result = scamper.transition(machine, Complete)
  let assert Error(InvalidTransition(from: Idle, event: Complete)) = result
}

pub fn transition_does_not_modify_input_machine_test() {
  let machine = scamper.new(basic_config(), Idle, ctx())
  let assert Ok(_new_machine) = scamper.transition(machine, Start)
  assert scamper.current_state(machine) == Idle
}

pub fn final_state_rejects_transition_test() {
  let machine = scamper.new(basic_config(), Idle, ctx())
  let assert Ok(machine) = scamper.transition(machine, Start)
  let assert Ok(machine) = scamper.transition(machine, Complete)
  let result = scamper.transition(machine, Start)
  let assert Error(AlreadyFinal(state: Done)) = result
}

// --- Query tests ---

pub fn current_state_test() {
  let machine = scamper.new(basic_config(), Running, ctx())
  assert scamper.current_state(machine) == Running
}

pub fn current_context_test() {
  let context = Context(count: 99, log: ["test"])
  let machine = scamper.new(basic_config(), Idle, context)
  assert scamper.current_context(machine) == context
}

pub fn is_final_true_test() {
  let machine = scamper.new(basic_config(), Done, ctx())
  assert scamper.is_final(machine) == True
}

pub fn is_final_false_test() {
  let machine = scamper.new(basic_config(), Running, ctx())
  assert scamper.is_final(machine) == False
}

pub fn can_transition_true_test() {
  let machine = scamper.new(basic_config(), Idle, ctx())
  assert scamper.can_transition(machine, Start) == True
}

pub fn can_transition_false_test() {
  let machine = scamper.new(basic_config(), Idle, ctx())
  assert scamper.can_transition(machine, Complete) == False
}

pub fn can_transition_no_side_effects_test() {
  let machine = scamper.new(basic_config(), Idle, ctx())
  let _ = scamper.can_transition(machine, Start)
  assert scamper.current_state(machine) == Idle
}

pub fn available_events_test() {
  let machine = scamper.new(basic_config(), Running, ctx())
  assert scamper.available_events(machine) == [Complete, Fail]
}

pub fn available_events_idle_test() {
  let machine = scamper.new(basic_config(), Idle, ctx())
  assert scamper.available_events(machine) == [Start]
}

pub fn available_events_final_state_test() {
  let machine = scamper.new(basic_config(), Done, ctx())
  assert scamper.available_events(machine) == []
}

// --- History tests ---

pub fn history_records_transitions_test() {
  let machine = scamper.new(basic_config(), Idle, ctx())
  let assert Ok(machine) = scamper.transition(machine, Start)

  let h = scamper.history(machine)
  assert list.length(h) == 1

  let assert [record] = h
  assert record.from == Idle
  assert record.event == Start
  assert record.to == Running
}

pub fn history_newest_first_test() {
  let machine = scamper.new(basic_config(), Idle, ctx())
  let assert Ok(machine) = scamper.transition(machine, Start)
  let assert Ok(machine) = scamper.transition(machine, Complete)

  let h = scamper.history(machine)
  assert list.length(h) == 2

  let assert [newest, oldest] = h
  assert newest.to == Done
  assert oldest.to == Running
}

pub fn history_with_snapshots_test() {
  let cfg =
    basic_config()
    |> config.set_history_snapshots(True)

  let machine = scamper.new(cfg, Idle, ctx())
  let assert Ok(machine) = scamper.transition(machine, Start)

  let assert [record] = scamper.history(machine)
  assert record.context_snapshot == Some(ctx())
}

pub fn history_without_snapshots_test() {
  let machine = scamper.new(basic_config(), Idle, ctx())
  let assert Ok(machine) = scamper.transition(machine, Start)

  let assert [record] = scamper.history(machine)
  assert record.context_snapshot == None
}

// --- Elapsed time tests ---

pub fn elapsed_returns_non_negative_test() {
  let machine = scamper.new(basic_config(), Idle, ctx())
  assert scamper.elapsed(machine) >= 0
}

// --- Restore tests ---

pub fn restore_creates_machine_with_given_state_test() {
  let machine = scamper.restore(basic_config(), Running, ctx(), [], 500, 600)
  assert scamper.current_state(machine) == Running
  assert scamper.created_at(machine) == 500
  assert scamper.entered_at(machine) == 600
}

// --- Integration tests ---

pub fn full_lifecycle_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.add_transition(from: Running, on: Complete, to: Done)
    |> config.add_transition(from: Running, on: Fail, to: Failed)
    |> config.set_final_states([Done, Failed])
    |> config.set_on_exit(Idle, fn(_state, ctx: Context) {
      Ok(Context(..ctx, log: ["left idle", ..ctx.log]))
    })
    |> config.set_on_enter(Running, fn(_state, ctx: Context) {
      Ok(Context(..ctx, count: ctx.count + 1))
    })
    |> config.add_global_on_transition(fn(_from, _event, _to, ctx: Context) {
      Ok(Context(..ctx, log: ["transitioned", ..ctx.log]))
    })

  let machine = scamper.new(cfg, Idle, ctx())
  assert scamper.is_final(machine) == False

  let assert Ok(machine) = scamper.transition(machine, Start)
  assert scamper.current_state(machine) == Running
  assert scamper.current_context(machine).count == 1

  let assert Ok(machine) = scamper.transition(machine, Complete)
  assert scamper.current_state(machine) == Done
  assert scamper.is_final(machine) == True

  let result = scamper.transition(machine, Start)
  let assert Error(AlreadyFinal(state: Done)) = result
}

pub fn self_transition_lifecycle_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Running, on: Refresh, to: Running)
    |> config.set_on_enter(Running, fn(_state, ctx: Context) {
      Ok(Context(..ctx, count: ctx.count + 1))
    })
    |> config.set_history_snapshots(True)

  let machine = scamper.new(cfg, Running, ctx())
  let assert Ok(machine) = scamper.transition(machine, Refresh)
  let assert Ok(machine) = scamper.transition(machine, Refresh)

  assert scamper.current_state(machine) == Running
  assert scamper.current_context(machine).count == 2
  assert list.length(scamper.history(machine)) == 2
}

pub fn callback_failure_preserves_original_machine_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.set_on_enter(Running, fn(_state, _ctx: Context) {
      Error("init failed")
    })

  let machine = scamper.new(cfg, Idle, ctx())
  let result = scamper.transition(machine, Start)
  let assert Error(CallbackFailed(stage: OnEnter, reason: "init failed")) =
    result
  assert scamper.current_state(machine) == Idle
}

pub fn ignore_policy_returns_unchanged_machine_test() {
  let cfg =
    basic_config()
    |> config.set_event_policy(config.Ignore)

  let machine = scamper.new(cfg, Idle, ctx())
  let assert Ok(same) = scamper.transition(machine, Complete)
  assert scamper.current_state(same) == Idle
}
