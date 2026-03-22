import scamper
import scamper/actor as fsm_actor
import scamper/config
import scamper/error.{AlreadyFinal, InvalidTransition}

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

fn basic_config() -> config.Config(State, Context, Event) {
  config.new(test_timestamp)
  |> config.add_transition(from: Idle, on: Start, to: Running)
  |> config.add_transition(from: Running, on: Complete, to: Done)
  |> config.add_transition(from: Running, on: Fail, to: Failed)
  |> config.set_final_states([Done, Failed])
}

const timeout = 1000

// --- Start tests ---

pub fn start_creates_running_actor_test() {
  let assert Ok(started) =
    fsm_actor.start(basic_config(), Idle, Context(count: 0))
  let state = fsm_actor.get_state(started.data, timeout: timeout)
  assert state == Idle
}

// --- send_event tests ---

pub fn send_event_executes_transition_test() {
  let assert Ok(started) =
    fsm_actor.start(basic_config(), Idle, Context(count: 0))
  let subject = started.data

  let assert Ok(machine) =
    fsm_actor.send_event(subject, Start, timeout: timeout)
  assert scamper.current_state(machine) == Running
}

pub fn send_event_returns_error_for_invalid_transition_test() {
  let assert Ok(started) =
    fsm_actor.start(basic_config(), Idle, Context(count: 0))
  let subject = started.data

  let result = fsm_actor.send_event(subject, Complete, timeout: timeout)
  let assert Error(InvalidTransition(from: Idle, event: Complete)) = result
}

pub fn send_event_chain_test() {
  let assert Ok(started) =
    fsm_actor.start(basic_config(), Idle, Context(count: 0))
  let subject = started.data

  let assert Ok(_) = fsm_actor.send_event(subject, Start, timeout: timeout)
  let assert Ok(machine) =
    fsm_actor.send_event(subject, Complete, timeout: timeout)
  assert scamper.current_state(machine) == Done
}

pub fn send_event_final_state_rejected_test() {
  let assert Ok(started) =
    fsm_actor.start(basic_config(), Idle, Context(count: 0))
  let subject = started.data

  let assert Ok(_) = fsm_actor.send_event(subject, Start, timeout: timeout)
  let assert Ok(_) = fsm_actor.send_event(subject, Complete, timeout: timeout)
  let result = fsm_actor.send_event(subject, Start, timeout: timeout)
  let assert Error(AlreadyFinal(state: Done)) = result
}

// --- get_state tests ---

pub fn get_state_returns_current_state_test() {
  let assert Ok(started) =
    fsm_actor.start(basic_config(), Idle, Context(count: 0))
  let subject = started.data

  assert fsm_actor.get_state(subject, timeout: timeout) == Idle

  let assert Ok(_) = fsm_actor.send_event(subject, Start, timeout: timeout)
  assert fsm_actor.get_state(subject, timeout: timeout) == Running
}

// --- get_context tests ---

pub fn get_context_returns_current_context_test() {
  let cfg =
    basic_config()
    |> config.set_on_enter(Running, fn(_state, ctx: Context) {
      Ok(Context(count: ctx.count + 1))
    })

  let assert Ok(started) = fsm_actor.start(cfg, Idle, Context(count: 0))
  let subject = started.data

  assert fsm_actor.get_context(subject, timeout: timeout) == Context(count: 0)

  let assert Ok(_) = fsm_actor.send_event(subject, Start, timeout: timeout)
  assert fsm_actor.get_context(subject, timeout: timeout) == Context(count: 1)
}

// --- get_machine tests ---

pub fn get_machine_returns_full_machine_test() {
  let assert Ok(started) =
    fsm_actor.start(basic_config(), Idle, Context(count: 0))
  let subject = started.data

  let assert Ok(_) = fsm_actor.send_event(subject, Start, timeout: timeout)
  let machine = fsm_actor.get_machine(subject, timeout: timeout)
  assert scamper.current_state(machine) == Running
  assert scamper.current_context(machine) == Context(count: 0)
}

// --- Sequential processing test ---

pub fn actor_processes_events_sequentially_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.add_transition(from: Running, on: Complete, to: Done)
    |> config.set_final_states([Done])
    |> config.set_on_enter(Running, fn(_state, ctx: Context) {
      Ok(Context(count: ctx.count + 1))
    })
    |> config.set_on_enter(Done, fn(_state, ctx: Context) {
      Ok(Context(count: ctx.count + 10))
    })

  let assert Ok(started) = fsm_actor.start(cfg, Idle, Context(count: 0))
  let subject = started.data

  let assert Ok(_) = fsm_actor.send_event(subject, Start, timeout: timeout)
  let assert Ok(_) = fsm_actor.send_event(subject, Complete, timeout: timeout)

  let ctx = fsm_actor.get_context(subject, timeout: timeout)
  assert ctx.count == 11
}
