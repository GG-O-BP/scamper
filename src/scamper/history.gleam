//// Transition history recording and querying for scamper FSMs.

import gleam/list
import gleam/option.{type Option, None, Some}

/// A record of a single state transition.
pub type TransitionRecord(state, event, context) {
  TransitionRecord(
    from: state,
    event: event,
    to: state,
    timestamp: Int,
    context_snapshot: Option(context),
  )
}

/// Create a new transition record.
pub fn new_record(
  from from: state,
  event event: event,
  to to: state,
  timestamp timestamp: Int,
  context_snapshot context_snapshot: Option(context),
) -> TransitionRecord(state, event, context) {
  TransitionRecord(
    from: from,
    event: event,
    to: to,
    timestamp: timestamp,
    context_snapshot: context_snapshot,
  )
}

/// Append a record to the history (newest first).
/// Trims to the limit during append if a limit is set.
pub fn append(
  history: List(TransitionRecord(state, event, context)),
  record: TransitionRecord(state, event, context),
  limit: Option(Int),
) -> List(TransitionRecord(state, event, context)) {
  let new_history = [record, ..history]
  case limit {
    None -> new_history
    Some(n) -> list.take(new_history, n)
  }
}

/// Filter history records by the source state.
pub fn filter_by_from(
  history: List(TransitionRecord(state, event, context)),
  from: state,
) -> List(TransitionRecord(state, event, context)) {
  list.filter(history, fn(record) { record.from == from })
}

/// Filter history records by the destination state.
pub fn filter_by_to(
  history: List(TransitionRecord(state, event, context)),
  to: state,
) -> List(TransitionRecord(state, event, context)) {
  list.filter(history, fn(record) { record.to == to })
}

/// Filter history records by the event.
pub fn filter_by_event(
  history: List(TransitionRecord(state, event, context)),
  event: event,
) -> List(TransitionRecord(state, event, context)) {
  list.filter(history, fn(record) { record.event == event })
}

/// Get the last n records from history (newest first).
pub fn last_n(
  history: List(TransitionRecord(state, event, context)),
  n: Int,
) -> List(TransitionRecord(state, event, context)) {
  list.take(history, n)
}
