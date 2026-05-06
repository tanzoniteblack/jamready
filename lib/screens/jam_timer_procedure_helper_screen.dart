import 'package:flutter/material.dart';
import 'package:jam_ready/styles/background.dart';

class JamTimerProcedureHelperScreen extends StatelessWidget {
  const JamTimerProcedureHelperScreen({super.key});

  static const List<_ProcedureGroup> _groups = [
    _ProcedureGroup(
      title: 'Jam Flow',
      items: [
        _ProcedureItem(
          cue: 'Initial lineup',
          signal: 'Rolling whistle',
          detail: 'Call teams to the track and begin lineup procedures.',
        ),
        _ProcedureItem(
          cue: '5 seconds before jam start',
          signal: 'Verbal call plus raised hand',
          detail:
              'Call "Five Seconds" with one hand raised and all five fingers extended toward the track.',
        ),
        _ProcedureItem(
          cue: 'Jam starts',
          signal: '1 short whistle blast',
          detail:
              'Lower the raised hand and point toward the track in front of the foremost blocker.',
        ),
        _ProcedureItem(
          cue: 'Jam ends',
          signal: '4 rapid short blasts',
          detail:
              'Use the jam ending signal with hands repeatedly lifting off hips, elbows outward.',
        ),
      ],
    ),
    _ProcedureGroup(
      title: 'Timeouts and Reviews',
      items: [
        _ProcedureItem(
          cue: 'Timeout, OTO, or review begins',
          signal: '4 rapid short blasts',
          detail: 'Stop the period clock and signal the time stoppage.',
        ),
        _ProcedureItem(
          cue: 'Team Timeout',
          signal: 'Announce "Timeout, [Team Color/Name]"',
          detail: 'Form a clear T shape with the hands.',
        ),
        _ProcedureItem(
          cue: 'Official Timeout',
          signal: 'Announce "Official Timeout"',
          detail:
              'Tap the tops of the shoulders with fingertips, elbows extended at shoulder height.',
        ),
        _ProcedureItem(
          cue: 'Official Review',
          signal: 'Announce "Official Review, [Team Color/Name]"',
          detail: 'Form a round O shape with fingers and thumbs.',
        ),
        _ProcedureItem(
          cue: 'Timeout ends',
          signal: 'Rolling whistle',
          detail:
              'Use to close the timeout. Recommended to verbally indicate to players this whistle ends timeout only.',
        ),
      ],
    ),
    _ProcedureGroup(
      title: 'Period End and Other Whistles',
      items: [
        _ProcedureItem(
          cue: 'End of period or game',
          signal: 'Rolling whistle after review window',
          detail:
              'Wait until reviews are resolved or 30 seconds after the final jam ends.',
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return DynamicBackground(
      accentColor: Colors.orange.shade400,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Jam Timer Signals'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          foregroundColor: Colors.white,
        ),
        body: SafeArea(child: _ScrollableProcedureList(groups: _groups)),
      ),
    );
  }
}

class _ScrollableProcedureList extends StatefulWidget {
  final List<_ProcedureGroup> groups;

  const _ScrollableProcedureList({required this.groups});

  @override
  State<_ScrollableProcedureList> createState() =>
      _ScrollableProcedureListState();
}

class _ScrollableProcedureListState extends State<_ScrollableProcedureList> {
  final ScrollController _scrollController = ScrollController();
  bool _hasMoreBelow = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollHint);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollHint());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollHint);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollHint() {
    if (!_scrollController.hasClients) return;

    final hasMoreBelow =
        _scrollController.position.extentAfter > 20 &&
        _scrollController.position.maxScrollExtent > 0;
    if (hasMoreBelow == _hasMoreBelow) return;

    setState(() {
      _hasMoreBelow = hasMoreBelow;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 44),
          children: [
            for (final group in widget.groups) ...[
              _ProcedureGroupView(group: group),
              const SizedBox(height: 14),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Reference: WFTDA Officiating Cues, Codes and Signals, December 2018.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.52),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _hasMoreBelow ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: const _ScrollHint(),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScrollHint extends StatelessWidget {
  const _ScrollHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            const Color(0xFF0E0F12).withValues(alpha: 0.86),
          ],
        ),
      ),
      child: Container(
        width: 34,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.46),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Icon(
          Icons.keyboard_arrow_down_rounded,
          color: Colors.orange.shade200,
          size: 22,
        ),
      ),
    );
  }
}

class _ProcedureGroupView extends StatelessWidget {
  final _ProcedureGroup group;

  const _ProcedureGroupView({required this.group});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            group.title.toUpperCase(),
            style: TextStyle(
              color: Colors.orange.shade300,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.9,
            ),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < group.items.length; i++) ...[
                  _ProcedureItemView(item: group.items[i]),
                  if (i != group.items.length - 1)
                    Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.09),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProcedureItemView extends StatelessWidget {
  final _ProcedureItem item;

  const _ProcedureItemView({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.cue,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.signal,
            style: TextStyle(
              color: Colors.orange.shade200,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.detail,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 14,
              height: 1.32,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProcedureGroup {
  final String title;
  final List<_ProcedureItem> items;

  const _ProcedureGroup({required this.title, required this.items});
}

class _ProcedureItem {
  final String cue;
  final String signal;
  final String detail;

  const _ProcedureItem({
    required this.cue,
    required this.signal,
    required this.detail,
  });
}
