# scamper

[![Package Version](https://img.shields.io/hexpm/v/scamper)](https://hex.pm/packages/scamper)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/scamper/)

Type-safe finite state machine library for Gleam.

Generic over `Machine(state, context, event)` — define your own custom types for states, events, and context data.

## Installation

```sh
gleam add scamper@1
```

## Quick Start

```gleam
import scamper
import scamper/config

// Define your types
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
  Context(attempts: Int)
}

// Provide a timestamp function (milliseconds).
// In real code, use erlang.system_time(Millisecond).
fn timestamp() -> Int {
  0
}

pub fn main() {
  // Build config
  let cfg =
    config.new(timestamp)
    |> config.add_transition(from: Idle, on: Start, to: Running)
    |> config.add_transition(from: Running, on: Complete, to: Done)
    |> config.add_transition(from: Running, on: Fail, to: Failed)
    |> config.set_final_states([Done, Failed])

  // Create and use a machine
  let machine = scamper.new(cfg, Idle, Context(attempts: 0))
  let assert Ok(machine) = scamper.transition(machine, Start)
  let assert Ok(machine) = scamper.transition(machine, Complete)

  scamper.current_state(machine)  // => Done
  scamper.is_final(machine)       // => True
}
```

## Features

### Guarded Transitions

Same `(from, event)` pair with different destinations based on context:

```gleam
config.new(timestamp_fn)
|> config.add_guarded_transition(
  from: Running, on: Complete,
  guard: fn(ctx, _event) { ctx.attempts > 3 },
  to: Done,
)
|> config.add_transition(from: Running, on: Complete, to: Failed)
```

Guards are evaluated top-to-bottom. First passing guard wins. Unguarded rules act as fallbacks.

### Lifecycle Callbacks

Guaranteed execution order: `on_exit(from)` -> `on_transition` -> `on_enter(to)`.
Global callbacks run before state-specific callbacks at each stage.

```gleam
config.new(timestamp_fn)
|> config.add_transition(from: Idle, on: Start, to: Running)
|> config.set_on_exit(Idle, fn(_state, ctx) {
  Ok(Context(..ctx, log: ["left idle", ..ctx.log]))
})
|> config.set_on_enter(Running, fn(_state, ctx) {
  Ok(Context(..ctx, started_at: now()))
})
// State-specific on_transition — keyed by the "from" state
|> config.set_on_transition(Running, fn(_from, _event, _to, ctx) {
  Ok(Context(..ctx, attempts: ctx.attempts + 1))
})
// Global on_transition — runs for every transition, before state-specific
|> config.add_global_on_transition(fn(_from, _event, _to, ctx) {
  Ok(Context(..ctx, transition_count: ctx.transition_count + 1))
})
```

Callbacks return `Result(context, String)`. On failure, the entire transition rolls back.

`set_on_transition(config, state, callback)` registers a callback for transitions **from** a specific state. `add_global_on_transition` registers a callback that runs on every transition.

### Context Invariants

Validate context after every transition:

```gleam
config.new(timestamp_fn)
|> config.add_invariant(fn(ctx) {
  case ctx.balance >= 0 {
    True -> Ok(Nil)
    False -> Error("Balance must be non-negative")
  }
})
```

Invariant violation rolls back to the pre-transition state.

### Event Policy

Control how undefined transitions are handled:

```gleam
config.set_event_policy(config.Reject)  // Error on undefined (default)
config.set_event_policy(config.Ignore)  // Return Ok(machine) unchanged
```

### Transition History

```gleam
config.new(timestamp_fn)
|> config.set_history_limit(100)       // Keep last 100 records
|> config.set_history_snapshots(True)  // Include context snapshots

// Query history
scamper.history(machine)  // => List(TransitionRecord)
```

### Query Functions

```gleam
scamper.current_state(machine)    // => state
scamper.current_context(machine)  // => context
scamper.is_final(machine)         // => Bool
scamper.can_transition(machine, event)  // => Bool (no side effects)
scamper.available_events(machine) // => List(event)
scamper.elapsed(machine)          // => Int (ms since last transition)
```

### Validation

```gleam
import scamper/validation

validation.validate_config(cfg, initial_state)
// Detects: unreachable states, transitions from final states, missing fallbacks

validation.detect_deadlocks(cfg)
// Non-final states with no outgoing transitions

validation.reachable_states(cfg, initial_state)
// BFS from initial state
```

### Visualization

```gleam
import scamper/visualization

visualization.to_mermaid(cfg, Idle, state_to_string, event_to_string)
// stateDiagram-v2
//     [*] --> Idle
//     Idle --> Running : Start
//     Running --> Done : Complete
//     Done --> [*]

visualization.to_dot(cfg, Idle, state_to_string, event_to_string)
// DOT/Graphviz format

visualization.machine_to_string(machine, state_to_string)
// "Machine(state: Running, history: 5)"
```

### Test Helpers

```gleam
import scamper/testing

machine
|> testing.assert_transition(Start, Running)
|> testing.assert_transition(Complete, Done)
|> testing.assert_final()

testing.run_events(machine, [Start, Complete])  // => Result(Machine, Error)
testing.reachable_states(cfg, Idle)             // => List(state)
```

### JSON Serialization

```gleam
import scamper/serialization

let json = serialization.serialize(machine, state_encoder, context_encoder, event_encoder)

let assert Ok(restored) =
  serialization.deserialize(json, cfg, state_decoder, context_decoder, event_decoder)
```

Users provide encoder/decoder functions for their custom types.

### OTP Actor

```gleam
import scamper/actor

let assert Ok(started) = actor.start(cfg, Idle, Context(count: 0))
let subject = started.data

let assert Ok(machine) = actor.send_event(subject, Start, timeout: 5000)
let state = actor.get_state(subject, timeout: 5000)
```

Events are serialized (one at a time) within the actor process.

## Error Types

All transition failures return structured errors:

```gleam
type TransitionError(state, event) {
  InvalidTransition(from: state, event: event)
  GuardRejected(from: state, event: event, reason: String)
  AlreadyFinal(state: state)
  CallbackFailed(stage: CallbackStage, reason: String)
  InvariantViolation(reason: String)
}
```

## Module Structure

| Module | Purpose |
|--------|---------|
| `scamper` | Public API: `Machine`, `new`, `transition`, queries |
| `scamper/config` | Config builder with pipeline API |
| `scamper/error` | `TransitionError`, `CallbackStage` |
| `scamper/history` | `TransitionRecord`, filtering, querying |
| `scamper/transition` | Transition engine (internal) |
| `scamper/validation` | Config validation, deadlock detection |
| `scamper/visualization` | Mermaid, DOT, string representation |
| `scamper/testing` | Test helpers |
| `scamper/serialization` | JSON serialize/deserialize |
| `scamper/actor` | OTP actor wrapper |

## Development

```sh
gleam build   # Compile
gleam test    # Run tests
gleam format src test  # Format code
gleam docs build       # Generate documentation
```
