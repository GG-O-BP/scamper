import gleam/string
import scamper
import scamper/config
import scamper/visualization

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
  Context
}

fn test_timestamp() -> Int {
  1_000_000
}

fn state_to_string(state: State) -> String {
  case state {
    Idle -> "Idle"
    Running -> "Running"
    Done -> "Done"
    Failed -> "Failed"
  }
}

fn event_to_string(event: Event) -> String {
  case event {
    Start -> "Start"
    Complete -> "Complete"
    Fail -> "Fail"
  }
}

fn basic_config() -> config.Config(State, Context, Event) {
  config.new(test_timestamp)
  |> config.add_transition(from: Idle, on: Start, to: Running)
  |> config.add_transition(from: Running, on: Complete, to: Done)
  |> config.add_transition(from: Running, on: Fail, to: Failed)
  |> config.set_final_states([Done, Failed])
}

// --- Mermaid tests ---

pub fn to_mermaid_contains_header_test() {
  let result =
    visualization.to_mermaid(
      basic_config(),
      Idle,
      state_to_string,
      event_to_string,
    )
  assert string.contains(result, "stateDiagram-v2") == True
}

pub fn to_mermaid_contains_initial_arrow_test() {
  let result =
    visualization.to_mermaid(
      basic_config(),
      Idle,
      state_to_string,
      event_to_string,
    )
  assert string.contains(result, "[*] --> Idle") == True
}

pub fn to_mermaid_contains_transitions_test() {
  let result =
    visualization.to_mermaid(
      basic_config(),
      Idle,
      state_to_string,
      event_to_string,
    )
  assert string.contains(result, "Idle --> Running : Start") == True
  assert string.contains(result, "Running --> Done : Complete") == True
  assert string.contains(result, "Running --> Failed : Fail") == True
}

pub fn to_mermaid_contains_final_state_arrows_test() {
  let result =
    visualization.to_mermaid(
      basic_config(),
      Idle,
      state_to_string,
      event_to_string,
    )
  assert string.contains(result, "Done --> [*]") == True
  assert string.contains(result, "Failed --> [*]") == True
}

pub fn to_mermaid_marks_guarded_transitions_test() {
  let cfg =
    config.new(test_timestamp)
    |> config.add_guarded_transition(
      from: Running,
      on: Complete,
      guard: fn(_ctx: Context, _evt) { True },
      to: Done,
    )

  let result =
    visualization.to_mermaid(cfg, Running, state_to_string, event_to_string)
  assert string.contains(result, "[guarded]") == True
}

// --- DOT tests ---

pub fn to_dot_contains_header_test() {
  let result =
    visualization.to_dot(basic_config(), Idle, state_to_string, event_to_string)
  assert string.contains(result, "digraph FSM {") == True
  assert string.contains(result, "rankdir=LR;") == True
}

pub fn to_dot_contains_initial_edge_test() {
  let result =
    visualization.to_dot(basic_config(), Idle, state_to_string, event_to_string)
  assert string.contains(result, "__start__ -> Idle;") == True
}

pub fn to_dot_contains_final_state_nodes_test() {
  let result =
    visualization.to_dot(basic_config(), Idle, state_to_string, event_to_string)
  assert string.contains(result, "Done [shape=doublecircle];") == True
  assert string.contains(result, "Failed [shape=doublecircle];") == True
}

pub fn to_dot_contains_transitions_test() {
  let result =
    visualization.to_dot(basic_config(), Idle, state_to_string, event_to_string)
  assert string.contains(result, "Idle -> Running [label=\"Start\"];") == True
}

pub fn to_dot_ends_with_closing_brace_test() {
  let result =
    visualization.to_dot(basic_config(), Idle, state_to_string, event_to_string)
  assert string.ends_with(result, "}") == True
}

// --- machine_to_string tests ---

pub fn machine_to_string_test() {
  let machine = scamper.new(basic_config(), Idle, Context)
  let result = visualization.machine_to_string(machine, state_to_string)
  assert result == "Machine(state: Idle, history: 0)"
}

pub fn machine_to_string_with_history_test() {
  let machine = scamper.new(basic_config(), Idle, Context)
  let assert Ok(machine) = scamper.transition(machine, Start)
  let result = visualization.machine_to_string(machine, state_to_string)
  assert result == "Machine(state: Running, history: 1)"
}
