import gleam/dynamic/decode
import gleam/json
import gleam/option.{Some}
import gleam/string
import scamper
import scamper/config
import scamper/serialization

// Test types

pub type State {
  Idle
  Running
  Done
}

pub type Event {
  Start
  Complete
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
  |> config.set_final_states([Done])
}

// Encoders

fn state_encoder(state: State) -> json.Json {
  case state {
    Idle -> json.string("Idle")
    Running -> json.string("Running")
    Done -> json.string("Done")
  }
}

fn event_encoder(event: Event) -> json.Json {
  case event {
    Start -> json.string("Start")
    Complete -> json.string("Complete")
  }
}

fn context_encoder(ctx: Context) -> json.Json {
  json.object([#("count", json.int(ctx.count))])
}

// Decoders

fn state_decoder() -> decode.Decoder(State) {
  use value <- decode.then(decode.string)
  case value {
    "Idle" -> decode.success(Idle)
    "Running" -> decode.success(Running)
    "Done" -> decode.success(Done)
    _ -> decode.failure(Idle, "State")
  }
}

fn event_decoder() -> decode.Decoder(Event) {
  use value <- decode.then(decode.string)
  case value {
    "Start" -> decode.success(Start)
    "Complete" -> decode.success(Complete)
    _ -> decode.failure(Start, "Event")
  }
}

fn context_decoder() -> decode.Decoder(Context) {
  use count <- decode.field("count", decode.int)
  decode.success(Context(count: count))
}

// --- Serialize tests ---

pub fn serialize_produces_json_test() {
  let machine = scamper.new(basic_config(), Idle, Context(count: 0))
  let json_str =
    serialization.serialize(
      machine,
      state_encoder,
      context_encoder,
      event_encoder,
    )
  assert string.contains(json_str, "\"state\"") == True
  assert string.contains(json_str, "\"Idle\"") == True
  assert string.contains(json_str, "\"context\"") == True
}

pub fn serialize_includes_timestamps_test() {
  let machine = scamper.new(basic_config(), Idle, Context(count: 0))
  let json_str =
    serialization.serialize(
      machine,
      state_encoder,
      context_encoder,
      event_encoder,
    )
  assert string.contains(json_str, "\"created_at\"") == True
  assert string.contains(json_str, "\"entered_at\"") == True
}

pub fn serialize_includes_history_test() {
  let machine = scamper.new(basic_config(), Idle, Context(count: 0))
  let assert Ok(machine) = scamper.transition(machine, Start)
  let json_str =
    serialization.serialize(
      machine,
      state_encoder,
      context_encoder,
      event_encoder,
    )
  assert string.contains(json_str, "\"history\"") == True
  assert string.contains(json_str, "\"from\"") == True
}

// --- Round-trip tests ---

pub fn round_trip_basic_test() {
  let machine = scamper.new(basic_config(), Idle, Context(count: 42))

  let json_str =
    serialization.serialize(
      machine,
      state_encoder,
      context_encoder,
      event_encoder,
    )
  let assert Ok(restored) =
    serialization.deserialize(
      json_str,
      basic_config(),
      state_decoder(),
      context_decoder(),
      event_decoder(),
    )

  assert scamper.current_state(restored) == Idle
  assert scamper.current_context(restored) == Context(count: 42)
}

pub fn round_trip_with_transitions_test() {
  let machine = scamper.new(basic_config(), Idle, Context(count: 0))
  let assert Ok(machine) = scamper.transition(machine, Start)

  let json_str =
    serialization.serialize(
      machine,
      state_encoder,
      context_encoder,
      event_encoder,
    )
  let assert Ok(restored) =
    serialization.deserialize(
      json_str,
      basic_config(),
      state_decoder(),
      context_decoder(),
      event_decoder(),
    )

  assert scamper.current_state(restored) == Running
  let assert [record] = scamper.history(restored)
  assert record.from == Idle
  assert record.event == Start
  assert record.to == Running
}

pub fn round_trip_with_context_snapshots_test() {
  let cfg =
    basic_config()
    |> config.set_history_snapshots(True)

  let machine = scamper.new(cfg, Idle, Context(count: 5))
  let assert Ok(machine) = scamper.transition(machine, Start)

  let json_str =
    serialization.serialize(
      machine,
      state_encoder,
      context_encoder,
      event_encoder,
    )
  let assert Ok(restored) =
    serialization.deserialize(
      json_str,
      cfg,
      state_decoder(),
      context_decoder(),
      event_decoder(),
    )

  let assert [record] = scamper.history(restored)
  assert record.context_snapshot == Some(Context(count: 5))
}

pub fn round_trip_preserves_timestamps_test() {
  let machine = scamper.new(basic_config(), Idle, Context(count: 0))

  let json_str =
    serialization.serialize(
      machine,
      state_encoder,
      context_encoder,
      event_encoder,
    )
  let assert Ok(restored) =
    serialization.deserialize(
      json_str,
      basic_config(),
      state_decoder(),
      context_decoder(),
      event_decoder(),
    )

  assert scamper.created_at(restored) == scamper.created_at(machine)
  assert scamper.entered_at(restored) == scamper.entered_at(machine)
}

// --- Error tests ---

pub fn deserialize_invalid_json_fails_test() {
  let result =
    serialization.deserialize(
      "not json",
      basic_config(),
      state_decoder(),
      context_decoder(),
      event_decoder(),
    )
  let assert Error(_) = result
}

pub fn deserialize_empty_string_fails_test() {
  let result =
    serialization.deserialize(
      "",
      basic_config(),
      state_decoder(),
      context_decoder(),
      event_decoder(),
    )
  let assert Error(_) = result
}

// --- Restored machine can still transition ---

pub fn restored_machine_can_transition_test() {
  let machine = scamper.new(basic_config(), Idle, Context(count: 0))
  let assert Ok(machine) = scamper.transition(machine, Start)

  let json_str =
    serialization.serialize(
      machine,
      state_encoder,
      context_encoder,
      event_encoder,
    )
  let assert Ok(restored) =
    serialization.deserialize(
      json_str,
      basic_config(),
      state_decoder(),
      context_decoder(),
      event_decoder(),
    )

  let assert Ok(final_machine) = scamper.transition(restored, Complete)
  assert scamper.current_state(final_machine) == Done
  assert scamper.is_final(final_machine) == True
}
