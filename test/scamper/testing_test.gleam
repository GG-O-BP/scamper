import gleam/list
import scamper
import scamper/config
import scamper/error.{InvalidTransition}
import scamper/testing

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

// --- assert_transition tests ---

pub fn assert_transition_succeeds_test() {
  let machine = scamper.new(basic_config(), Idle, Context(count: 0))
  let machine = testing.assert_transition(machine, Start, Running)
  assert scamper.current_state(machine) == Running
}

pub fn assert_transition_chaining_test() {
  let machine = scamper.new(basic_config(), Idle, Context(count: 0))
  let machine =
    machine
    |> testing.assert_transition(Start, Running)
    |> testing.assert_transition(Complete, Done)
  assert scamper.current_state(machine) == Done
}

// --- assert_final tests ---

pub fn assert_final_succeeds_test() {
  let machine = scamper.new(basic_config(), Idle, Context(count: 0))
  let machine =
    machine
    |> testing.assert_transition(Start, Running)
    |> testing.assert_transition(Complete, Done)
    |> testing.assert_final()
  assert scamper.current_state(machine) == Done
}

// --- reachable_states tests ---

pub fn reachable_states_test() {
  let reachable = testing.reachable_states(basic_config(), Idle)
  assert list.contains(reachable, Idle) == True
  assert list.contains(reachable, Running) == True
  assert list.contains(reachable, Done) == True
  assert list.contains(reachable, Failed) == True
}

// --- run_events tests ---

pub fn run_events_success_test() {
  let machine = scamper.new(basic_config(), Idle, Context(count: 0))
  let assert Ok(machine) = testing.run_events(machine, [Start, Complete])
  assert scamper.current_state(machine) == Done
}

pub fn run_events_fails_on_invalid_test() {
  let machine = scamper.new(basic_config(), Idle, Context(count: 0))
  let result = testing.run_events(machine, [Start, Start])
  let assert Error(InvalidTransition(from: Running, event: Start)) = result
}

pub fn run_events_empty_list_test() {
  let machine = scamper.new(basic_config(), Idle, Context(count: 0))
  let assert Ok(machine) = testing.run_events(machine, [])
  assert scamper.current_state(machine) == Idle
}
