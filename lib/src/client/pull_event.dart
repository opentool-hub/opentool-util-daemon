import '../controller/dto.dart';

/// Typed events emitted by [DaemonClient.pullServerEvents].
sealed class PullEvent {
  const PullEvent();
}

final class PullStarted extends PullEvent {
  final PullStartDto data;

  const PullStarted(this.data);
}

final class PullProgress extends PullEvent {
  final PullDownloadDto data;

  const PullProgress(this.data);
}

final class PullCompleted extends PullEvent {
  final PullDoneDto data;

  const PullCompleted(this.data);
}

final class PullFailed extends PullEvent {
  final PullErrorDto data;

  const PullFailed(this.data);
}
