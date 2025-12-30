enum RunStatus {
  idle,
  running,
  paused,
  finished,
}

class RunState {
  RunStatus status = RunStatus.idle;
  double distanceKm = 0;
  int factsCount = 0;
}
