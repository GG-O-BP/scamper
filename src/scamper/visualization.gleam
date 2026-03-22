//// Visualization utilities for scamper FSMs.
////
//// Generate Mermaid diagrams, DOT graphs, and string representations.

import gleam/int
import gleam/list
import gleam/option
import gleam/string
import scamper
import scamper/config.{type Config}

/// Generate a Mermaid stateDiagram-v2 string from the config.
pub fn to_mermaid(
  config: Config(state, context, event),
  initial_state: state,
  state_to_string: fn(state) -> String,
  event_to_string: fn(event) -> String,
) -> String {
  let transitions = config.get_transitions(config)
  let final_states = config.get_final_states(config)

  let header = "stateDiagram-v2"

  // Initial state arrow
  let initial_arrow = "    [*] --> " <> state_to_string(initial_state)

  // Transition arrows
  let transition_lines =
    transitions
    |> list.map(fn(rule) {
      let label = event_to_string(rule.on)
      let guard_suffix = case option.is_some(rule.guard) {
        True -> " [guarded]"
        False -> ""
      }
      "    "
      <> state_to_string(rule.from)
      <> " --> "
      <> state_to_string(rule.to)
      <> " : "
      <> label
      <> guard_suffix
    })

  // Final state arrows
  let final_lines =
    final_states
    |> list.map(fn(s) { "    " <> state_to_string(s) <> " --> [*]" })

  [header, initial_arrow]
  |> list.append(transition_lines)
  |> list.append(final_lines)
  |> string.join("\n")
}

/// Generate a DOT (Graphviz) graph string from the config.
pub fn to_dot(
  config: Config(state, context, event),
  initial_state: state,
  state_to_string: fn(state) -> String,
  event_to_string: fn(event) -> String,
) -> String {
  let transitions = config.get_transitions(config)
  let final_states = config.get_final_states(config)

  let header_lines = [
    "digraph FSM {",
    "    rankdir=LR;",
    "    node [shape=circle];",
    "    __start__ [shape=point];",
  ]

  // Final state node declarations (doublecircle)
  let final_node_lines =
    final_states
    |> list.map(fn(s) {
      "    " <> state_to_string(s) <> " [shape=doublecircle];"
    })

  // Initial state edge
  let initial_edge =
    "    __start__ -> " <> state_to_string(initial_state) <> ";"

  // Transition edges
  let transition_lines =
    transitions
    |> list.map(fn(rule) {
      let label = event_to_string(rule.on)
      let guard_suffix = case option.is_some(rule.guard) {
        True -> " [guarded]"
        False -> ""
      }
      "    "
      <> state_to_string(rule.from)
      <> " -> "
      <> state_to_string(rule.to)
      <> " [label=\""
      <> label
      <> guard_suffix
      <> "\"];"
    })

  let footer = "}"

  header_lines
  |> list.append(final_node_lines)
  |> list.append([initial_edge])
  |> list.append(transition_lines)
  |> list.append([footer])
  |> string.join("\n")
}

/// Generate a one-line summary of a machine's current state.
pub fn machine_to_string(
  machine: scamper.Machine(state, context, event),
  state_to_string: fn(state) -> String,
) -> String {
  let state_str = state_to_string(scamper.current_state(machine))
  let history_count = list.length(scamper.history(machine))
  "Machine(state: "
  <> state_str
  <> ", history: "
  <> int.to_string(history_count)
  <> ")"
}
