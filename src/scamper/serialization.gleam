//// JSON serialization and deserialization for scamper FSMs.
////
//// Users must provide encoder/decoder functions for their custom
//// state, context, and event types.

import gleam/dynamic/decode
import gleam/json
import gleam/result
import scamper
import scamper/config.{type Config}
import scamper/history.{type TransitionRecord, TransitionRecord}

/// Errors that can occur during serialization or deserialization.
pub type SerializationError {
  JsonEncodeError(reason: String)
  JsonDecodeError(reason: String)
}

/// Serialize a machine's state to a JSON string.
/// User must provide encoder functions for state, context, and event types.
pub fn serialize(
  machine: scamper.Machine(state, context, event),
  state_encoder: fn(state) -> json.Json,
  context_encoder: fn(context) -> json.Json,
  event_encoder: fn(event) -> json.Json,
) -> String {
  let history_json =
    scamper.history(machine)
    |> json.array(of: fn(record) {
      encode_record(record, state_encoder, context_encoder, event_encoder)
    })

  json.object([
    #("state", state_encoder(scamper.current_state(machine))),
    #("context", context_encoder(scamper.current_context(machine))),
    #("created_at", json.int(scamper.created_at(machine))),
    #("entered_at", json.int(scamper.entered_at(machine))),
    #("history", history_json),
  ])
  |> json.to_string
}

fn encode_record(
  record: TransitionRecord(state, event, context),
  state_encoder: fn(state) -> json.Json,
  context_encoder: fn(context) -> json.Json,
  event_encoder: fn(event) -> json.Json,
) -> json.Json {
  json.object([
    #("from", state_encoder(record.from)),
    #("event", event_encoder(record.event)),
    #("to", state_encoder(record.to)),
    #("timestamp", json.int(record.timestamp)),
    #(
      "context_snapshot",
      json.nullable(record.context_snapshot, context_encoder),
    ),
  ])
}

/// Deserialize a machine from a JSON string and a config.
/// User must provide decoder functions for state, context, and event types.
pub fn deserialize(
  data: String,
  config: Config(state, context, event),
  state_decoder: decode.Decoder(state),
  context_decoder: decode.Decoder(context),
  event_decoder: decode.Decoder(event),
) -> Result(scamper.Machine(state, context, event), SerializationError) {
  let record_decoder =
    build_record_decoder(state_decoder, context_decoder, event_decoder)
  let machine_decoder =
    build_machine_decoder(state_decoder, context_decoder, record_decoder)

  json.parse(data, machine_decoder)
  |> result.map_error(fn(err) {
    case err {
      json.UnexpectedEndOfInput ->
        JsonDecodeError(reason: "Unexpected end of input")
      json.UnexpectedByte(b) ->
        JsonDecodeError(reason: "Unexpected byte: " <> b)
      json.UnexpectedSequence(s) ->
        JsonDecodeError(reason: "Unexpected sequence: " <> s)
      json.UnableToDecode(_) -> JsonDecodeError(reason: "Unable to decode JSON")
    }
  })
  |> result.map(fn(decoded) {
    scamper.restore(
      config,
      decoded.state,
      decoded.context,
      decoded.history,
      decoded.created_at,
      decoded.entered_at,
    )
  })
}

// Internal decoded representation before constructing Machine
type DecodedMachine(state, context, event) {
  DecodedMachine(
    state: state,
    context: context,
    created_at: Int,
    entered_at: Int,
    history: List(TransitionRecord(state, event, context)),
  )
}

fn build_machine_decoder(
  state_decoder: decode.Decoder(state),
  context_decoder: decode.Decoder(context),
  record_decoder: decode.Decoder(TransitionRecord(state, event, context)),
) -> decode.Decoder(DecodedMachine(state, context, event)) {
  use state <- decode.field("state", state_decoder)
  use context <- decode.field("context", context_decoder)
  use created_at <- decode.field("created_at", decode.int)
  use entered_at <- decode.field("entered_at", decode.int)
  use history <- decode.field("history", decode.list(record_decoder))
  decode.success(DecodedMachine(
    state: state,
    context: context,
    created_at: created_at,
    entered_at: entered_at,
    history: history,
  ))
}

fn build_record_decoder(
  state_decoder: decode.Decoder(state),
  context_decoder: decode.Decoder(context),
  event_decoder: decode.Decoder(event),
) -> decode.Decoder(TransitionRecord(state, event, context)) {
  use from <- decode.field("from", state_decoder)
  use event <- decode.field("event", event_decoder)
  use to <- decode.field("to", state_decoder)
  use timestamp <- decode.field("timestamp", decode.int)
  use context_snapshot <- decode.field(
    "context_snapshot",
    decode.optional(context_decoder),
  )
  decode.success(TransitionRecord(
    from: from,
    event: event,
    to: to,
    timestamp: timestamp,
    context_snapshot: context_snapshot,
  ))
}
