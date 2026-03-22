//// OTP actor wrapper for scamper FSMs.
////
//// Provides a thin wrapper around `gleam/otp/actor` to run a state machine
//// as an OTP-compatible process. Events are serialized (processed one at a
//// time) and the pure FSM logic remains fully testable without OTP.

import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import scamper.{type Machine}
import scamper/config.{type Config}
import scamper/error.{type TransitionError}

/// Messages the FSM actor can receive.
pub opaque type Message(state, context, event) {
  SendEvent(
    event: event,
    reply_to: Subject(
      Result(Machine(state, context, event), TransitionError(state, event)),
    ),
  )
  GetState(reply_to: Subject(state))
  GetContext(reply_to: Subject(context))
  GetMachine(reply_to: Subject(Machine(state, context, event)))
}

/// Start an FSM actor process.
/// Returns the actor's subject for sending messages.
pub fn start(
  config: Config(state, context, event),
  initial_state: state,
  context: context,
) -> Result(
  actor.Started(Subject(Message(state, context, event))),
  actor.StartError,
) {
  let machine = scamper.new(config, initial_state, context)
  actor.new(machine)
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(
  machine: Machine(state, context, event),
  message: Message(state, context, event),
) -> actor.Next(Machine(state, context, event), Message(state, context, event)) {
  case message {
    SendEvent(event, reply_to) -> {
      let result = scamper.transition(machine, event)
      process.send(reply_to, result)
      case result {
        Ok(new_machine) -> actor.continue(new_machine)
        Error(_) -> actor.continue(machine)
      }
    }
    GetState(reply_to) -> {
      process.send(reply_to, scamper.current_state(machine))
      actor.continue(machine)
    }
    GetContext(reply_to) -> {
      process.send(reply_to, scamper.current_context(machine))
      actor.continue(machine)
    }
    GetMachine(reply_to) -> {
      process.send(reply_to, machine)
      actor.continue(machine)
    }
  }
}

/// Send an event to the FSM actor and wait for the result.
/// Times out after `timeout` milliseconds.
pub fn send_event(
  subject: Subject(Message(state, context, event)),
  event: event,
  timeout timeout: Int,
) -> Result(Machine(state, context, event), TransitionError(state, event)) {
  actor.call(subject, waiting: timeout, sending: fn(reply_to) {
    SendEvent(event: event, reply_to: reply_to)
  })
}

/// Query the current state of the FSM actor.
pub fn get_state(
  subject: Subject(Message(state, context, event)),
  timeout timeout: Int,
) -> state {
  actor.call(subject, waiting: timeout, sending: fn(reply_to) {
    GetState(reply_to: reply_to)
  })
}

/// Query the current context of the FSM actor.
pub fn get_context(
  subject: Subject(Message(state, context, event)),
  timeout timeout: Int,
) -> context {
  actor.call(subject, waiting: timeout, sending: fn(reply_to) {
    GetContext(reply_to: reply_to)
  })
}

/// Get the full machine from the actor.
pub fn get_machine(
  subject: Subject(Message(state, context, event)),
  timeout timeout: Int,
) -> Machine(state, context, event) {
  actor.call(subject, waiting: timeout, sending: fn(reply_to) {
    GetMachine(reply_to: reply_to)
  })
}
