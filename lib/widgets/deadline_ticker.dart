import 'dart:async';

import 'package:flutter/widgets.dart';

/// Rebuilds [builder] on a timer so a countdown actually counts down.
///
/// Without this a deadline is only as fresh as the last rebuild, which on the
/// status screen could be minutes stale — exactly when the number matters
/// most. The tick coarsens with distance: no point waking once a second for a
/// deadline twenty hours out.
class DeadlineTicker extends StatefulWidget {
  const DeadlineTicker({
    required this.deadline,
    required this.builder,
    super.key,
  });

  final DateTime deadline;
  final Widget Function(BuildContext context, Duration remaining) builder;

  @override
  State<DeadlineTicker> createState() => _DeadlineTickerState();
}

class _DeadlineTickerState extends State<DeadlineTicker> {
  Timer? _timer;

  Duration get _remaining => widget.deadline.difference(DateTime.now());

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(DeadlineTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadline != widget.deadline) _schedule();
  }

  void _schedule() {
    _timer?.cancel();

    final left = _remaining;
    // Past the deadline nothing changes again, so stop entirely rather than
    // burning a timer for the life of the screen.
    if (left.isNegative) return;

    final interval = left.inMinutes >= 2
        ? const Duration(seconds: 30)
        : const Duration(seconds: 1);

    _timer = Timer.periodic(interval, (_) {
      if (!mounted) return;
      setState(() {});
      // Crossing into the final minutes needs the faster tick, and crossing
      // the deadline needs the timer gone.
      if (_remaining.isNegative || _remaining.inMinutes < 2) _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _remaining);
}

/// Shared phrasing for "how long is left", so the status screen and the
/// history list never disagree about the same deadline.
String formatRemaining(Duration d) {
  if (d.isNegative) return 'no time';
  if (d.inDays >= 1) return '${d.inDays}d ${d.inHours.remainder(24)}h';
  if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  if (d.inMinutes >= 1) return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  return '${d.inSeconds}s';
}
