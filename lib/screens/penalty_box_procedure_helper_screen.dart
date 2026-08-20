import 'package:flutter/material.dart';

import '../styles/background.dart';

/// Quick reference for the standardized communications used in the Penalty Box.
class PenaltyBoxProcedureHelperScreen extends StatelessWidget {
  const PenaltyBoxProcedureHelperScreen({super.key});

  static const _items = [
    _ProcedureItem(
      cue: '10 seconds remaining',
      call: '[Team Color], [Skater Number], Stand',
      detail:
          'Time the word “Stand” to exactly 10 seconds remaining. When multiple Skaters should stand together, you may instead use their position: “[Team Color], [Skater Position], Stand” or “[Skater Position], Stand.”',
      signal: 'Raise a flat, open palm.',
    ),
    _ProcedureItem(
      cue: 'Penalty time stops',
      call:
          'Time stopped, [Team Color], [Skater Number], [additional information]',
      detail:
          'Tell the Skater that their penalty time has stopped. For example, if a Skater stands early: “Time stopped, Blue, one-two, please sit.” Their time resumes when they are seated again. If possible, include what they need to do before their time can resume.',
    ),
    _ProcedureItem(
      cue: 'Penalty time expires',
      call: '[Team Color], [Skater Number], Done',
      detail:
          'Time the word “Done” exactly as the Skater’s penalty time expires. For simultaneous releases, position may replace color and number: “[Team Color], [Position], Done” or “[Position], Done.”',
      signal: 'Use an open palm with a pushing motion toward the track.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return DynamicBackground(
      accentColor: Colors.deepOrange.shade400,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Penalty Box Signals'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              Text(
                'PENALTY BOX COMMUNICATION',
                style: TextStyle(
                  color: Colors.deepOrange.shade200,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.9,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The verbal cues below are standardized. Hand signals are common practice only and are not required.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 14,
                  height: 1.32,
                ),
              ),
              const SizedBox(height: 14),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.045),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Column(
                  children: [
                    for (var index = 0; index < _items.length; index++) ...[
                      _ProcedureItemView(item: _items[index]),
                      if (index < _items.length - 1)
                        Divider(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.09),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Reference: WFTDA Officiating Cues, Codes and Signals, December 2018.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.52),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
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
            item.call,
            style: TextStyle(
              color: Colors.deepOrange.shade200,
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
          if (item.signal case final signal?) ...[
            const SizedBox(height: 10),
            Text(
              'COMMON HAND SIGNAL (NOT REQUIRED)',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.52),
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              signal,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 14,
                height: 1.32,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProcedureItem {
  final String cue;
  final String call;
  final String detail;
  final String? signal;

  const _ProcedureItem({
    required this.cue,
    required this.call,
    required this.detail,
    this.signal,
  });
}
