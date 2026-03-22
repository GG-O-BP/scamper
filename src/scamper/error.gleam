//// Error types for the scamper finite state machine library.

/// The stage at which a callback failed during a transition.
pub type CallbackStage {
  OnExit
  OnTransition
  OnEnter
}

/// Errors that can occur when attempting a state transition.
pub type TransitionError(state, event) {
  /// The transition is not defined in the transition table.
  InvalidTransition(from: state, event: event)
  /// All guards for the matching transition rules rejected the event.
  GuardRejected(from: state, event: event, reason: String)
  /// The machine is in a final state and cannot process any events.
  AlreadyFinal(state: state)
  /// A lifecycle callback failed during the transition.
  CallbackFailed(stage: CallbackStage, reason: String)
  /// A context invariant was violated after the transition.
  InvariantViolation(reason: String)
}
