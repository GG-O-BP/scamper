import scamper/error.{
  AlreadyFinal, CallbackFailed, GuardRejected, InvalidTransition,
  InvariantViolation, OnEnter, OnExit, OnTransition,
}

// Test types

pub type State {
  Idle
  Running
}

pub type Event {
  Start
}

pub fn callback_stage_on_exit_test() {
  let stage = OnExit
  assert stage == OnExit
}

pub fn callback_stage_on_transition_test() {
  let stage = OnTransition
  assert stage == OnTransition
}

pub fn callback_stage_on_enter_test() {
  let stage = OnEnter
  assert stage == OnEnter
}

pub fn invalid_transition_test() {
  let err: error.TransitionError(State, Event) =
    InvalidTransition(from: Idle, event: Start)
  let assert InvalidTransition(from: Idle, event: Start) = err
}

pub fn guard_rejected_test() {
  let err: error.TransitionError(State, Event) =
    GuardRejected(from: Idle, event: Start, reason: "too early")
  let assert GuardRejected(from: Idle, event: Start, reason: "too early") = err
}

pub fn already_final_test() {
  let err: error.TransitionError(State, Event) = AlreadyFinal(state: Idle)
  let assert AlreadyFinal(state: Idle) = err
}

pub fn callback_failed_test() {
  let err: error.TransitionError(State, Event) =
    CallbackFailed(stage: OnEnter, reason: "init failed")
  let assert CallbackFailed(stage: OnEnter, reason: "init failed") = err
}

pub fn invariant_violation_test() {
  let err: error.TransitionError(State, Event) =
    InvariantViolation(reason: "count must be positive")
  let assert InvariantViolation(reason: "count must be positive") = err
}

pub fn callback_stages_are_distinct_test() {
  let stages = [OnExit, OnTransition, OnEnter]
  assert stages == [OnExit, OnTransition, OnEnter]
}

pub fn error_field_access_test() {
  let err = InvalidTransition(from: Running, event: Start)
  assert err.from == Running
  assert err.event == Start
}
