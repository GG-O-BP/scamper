import gleam/list
import gleam/option.{None, Some}
import scamper/history.{type TransitionRecord, TransitionRecord}

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

pub fn new_record_test() {
  let record =
    history.new_record(
      from: Idle,
      event: Start,
      to: Running,
      timestamp: 1000,
      context_snapshot: None,
    )

  assert record.from == Idle
  assert record.event == Start
  assert record.to == Running
  assert record.timestamp == 1000
  assert record.context_snapshot == None
}

pub fn new_record_with_snapshot_test() {
  let ctx = Context(count: 5)
  let record =
    history.new_record(
      from: Running,
      event: Complete,
      to: Done,
      timestamp: 2000,
      context_snapshot: Some(ctx),
    )

  assert record.context_snapshot == Some(Context(count: 5))
}

pub fn append_to_empty_history_test() {
  let record =
    history.new_record(
      from: Idle,
      event: Start,
      to: Running,
      timestamp: 1000,
      context_snapshot: None,
    )

  let result = history.append([], record, None)
  assert list.length(result) == 1

  let assert [first] = result
  assert first.from == Idle
}

pub fn append_prepends_newest_first_test() {
  let r1 =
    history.new_record(
      from: Idle,
      event: Start,
      to: Running,
      timestamp: 1000,
      context_snapshot: None,
    )
  let r2 =
    history.new_record(
      from: Running,
      event: Complete,
      to: Done,
      timestamp: 2000,
      context_snapshot: None,
    )

  let h1 = history.append([], r1, None)
  let h2 = history.append(h1, r2, None)
  assert list.length(h2) == 2

  let assert [newest, oldest] = h2
  assert newest.timestamp == 2000
  assert oldest.timestamp == 1000
}

pub fn append_with_limit_trims_test() {
  let r1 =
    history.new_record(
      from: Idle,
      event: Start,
      to: Running,
      timestamp: 1000,
      context_snapshot: None,
    )
  let r2 =
    history.new_record(
      from: Running,
      event: Complete,
      to: Done,
      timestamp: 2000,
      context_snapshot: None,
    )
  let r3 =
    history.new_record(
      from: Idle,
      event: Start,
      to: Running,
      timestamp: 3000,
      context_snapshot: None,
    )

  let h1 = history.append([], r1, Some(2))
  let h2 = history.append(h1, r2, Some(2))
  assert list.length(h2) == 2

  let h3 = history.append(h2, r3, Some(2))
  assert list.length(h3) == 2

  let assert [newest, _] = h3
  assert newest.timestamp == 3000
}

pub fn append_with_limit_one_test() {
  let r1 =
    history.new_record(
      from: Idle,
      event: Start,
      to: Running,
      timestamp: 1000,
      context_snapshot: None,
    )
  let r2 =
    history.new_record(
      from: Running,
      event: Complete,
      to: Done,
      timestamp: 2000,
      context_snapshot: None,
    )

  let h1 = history.append([], r1, Some(1))
  let h2 = history.append(h1, r2, Some(1))
  assert list.length(h2) == 1

  let assert [only] = h2
  assert only.timestamp == 2000
}

pub fn filter_by_from_test() {
  let r1 =
    TransitionRecord(
      from: Idle,
      event: Start,
      to: Running,
      timestamp: 1000,
      context_snapshot: None,
    )
  let r2 =
    TransitionRecord(
      from: Running,
      event: Complete,
      to: Done,
      timestamp: 2000,
      context_snapshot: None,
    )
  let r3 =
    TransitionRecord(
      from: Idle,
      event: Start,
      to: Running,
      timestamp: 3000,
      context_snapshot: None,
    )

  let filtered = history.filter_by_from([r3, r2, r1], Idle)
  assert list.length(filtered) == 2
}

pub fn filter_by_to_test() {
  let r1 =
    TransitionRecord(
      from: Idle,
      event: Start,
      to: Running,
      timestamp: 1000,
      context_snapshot: None,
    )
  let r2 =
    TransitionRecord(
      from: Running,
      event: Complete,
      to: Done,
      timestamp: 2000,
      context_snapshot: None,
    )

  let filtered = history.filter_by_to([r2, r1], Done)
  assert list.length(filtered) == 1
}

pub fn filter_by_event_test() {
  let r1 =
    TransitionRecord(
      from: Idle,
      event: Start,
      to: Running,
      timestamp: 1000,
      context_snapshot: None,
    )
  let r2 =
    TransitionRecord(
      from: Running,
      event: Complete,
      to: Done,
      timestamp: 2000,
      context_snapshot: None,
    )
  let r3 =
    TransitionRecord(
      from: Idle,
      event: Start,
      to: Running,
      timestamp: 3000,
      context_snapshot: None,
    )

  let filtered = history.filter_by_event([r3, r2, r1], Start)
  assert list.length(filtered) == 2
}

pub fn last_n_test() {
  let r1 =
    TransitionRecord(
      from: Idle,
      event: Start,
      to: Running,
      timestamp: 1000,
      context_snapshot: None,
    )
  let r2 =
    TransitionRecord(
      from: Running,
      event: Complete,
      to: Done,
      timestamp: 2000,
      context_snapshot: None,
    )
  let r3 =
    TransitionRecord(
      from: Idle,
      event: Start,
      to: Running,
      timestamp: 3000,
      context_snapshot: None,
    )

  let result = history.last_n([r3, r2, r1], 2)
  assert list.length(result) == 2

  let assert [first, _] = result
  assert first.timestamp == 3000
}

pub fn last_n_more_than_available_test() {
  let r1 =
    TransitionRecord(
      from: Idle,
      event: Start,
      to: Running,
      timestamp: 1000,
      context_snapshot: None,
    )

  let result = history.last_n([r1], 10)
  assert list.length(result) == 1
}

pub fn empty_history_operations_test() {
  let empty: List(TransitionRecord(State, Event, Context)) = []
  assert history.filter_by_from(empty, Idle) == []
  assert history.filter_by_to(empty, Running) == []
  assert history.filter_by_event(empty, Start) == []
  assert history.last_n(empty, 5) == []
}
