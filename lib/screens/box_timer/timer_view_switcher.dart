import 'package:flutter/material.dart';

import '../../models/penalty_box_state.dart';
import '../../models/skater_seat.dart';
import '../../styles/text_styles.dart';

/// A compact, always-visible control for changing the active timer view.
class TimerViewSwitcher extends StatelessWidget {
  final PenaltyBoxState state;
  final ValueChanged<AppRole> onSelected;

  const TimerViewSwitcher({
    super.key,
    required this.state,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Change timer view. Currently showing ${timerViewLabel(state)}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showMenu(context),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(color: Colors.white30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.visibility_outlined, size: 18),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    timerViewLabel(state),
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.infoText.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final selected = await showModalBottomSheet<AppRole>(
      context: context,
      backgroundColor: const Color(0xFF1A1C21),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.9,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TIMER VIEW', style: AppTextStyles.clockLabel),
                  const SizedBox(height: 8),
                  for (final role in orderedTimerViews(state))
                    _TimerViewOption(
                      role: role,
                      state: state,
                      selected: role == state.role,
                      onTap: () => Navigator.of(sheetContext).pop(role),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (selected != null && selected != state.role) onSelected(selected);
  }
}

String timerViewLabel(PenaltyBoxState state) => switch (state.role) {
  AppRole.pbm => 'Jammers only',
  AppRole.solo => 'All players',
  AppRole.team1Full => '${state.team1.name} · Full team',
  AppRole.team2Full => '${state.team2.name} · Full team',
  AppRole.team1BlockersOnly => '${state.team1.name} · Blockers only',
  AppRole.team2BlockersOnly => '${state.team2.name} · Blockers only',
};

String timerViewLabelForRole(AppRole role, PenaltyBoxState state) =>
    switch (role) {
      AppRole.pbm => 'Jammers only',
      AppRole.solo => 'All players',
      AppRole.team1Full => '${state.team1.name} · Full team',
      AppRole.team2Full => '${state.team2.name} · Full team',
      AppRole.team1BlockersOnly => '${state.team1.name} · Blockers only',
      AppRole.team2BlockersOnly => '${state.team2.name} · Blockers only',
    };

List<AppRole> orderedTimerViews(PenaltyBoxState state) {
  final current = state.role;
  final fullViews = [AppRole.team1Full, AppRole.team2Full];
  final blockerViews = [AppRole.team1BlockersOnly, AppRole.team2BlockersOnly];

  if (fullViews.contains(current)) {
    return [
      ...fullViews.where((role) => role != current),
      _blockerViewFor(current),
      ...blockerViews.where((role) => role != _blockerViewFor(current)),
      AppRole.pbm,
      AppRole.solo,
    ];
  }
  if (blockerViews.contains(current)) {
    return [
      ...blockerViews.where((role) => role != current),
      _fullViewFor(current),
      ...fullViews.where((role) => role != _fullViewFor(current)),
      AppRole.pbm,
      AppRole.solo,
    ];
  }
  return [...fullViews, ...blockerViews, AppRole.pbm, AppRole.solo];
}

AppRole _blockerViewFor(AppRole role) => switch (role) {
  AppRole.team1Full => AppRole.team1BlockersOnly,
  AppRole.team2Full => AppRole.team2BlockersOnly,
  _ => throw ArgumentError.value(role, 'role', 'Expected a full-team view'),
};

AppRole _fullViewFor(AppRole role) => switch (role) {
  AppRole.team1BlockersOnly => AppRole.team1Full,
  AppRole.team2BlockersOnly => AppRole.team2Full,
  _ => throw ArgumentError.value(role, 'role', 'Expected a blockers-only view'),
};

class _TimerViewOption extends StatelessWidget {
  final AppRole role;
  final PenaltyBoxState state;
  final bool selected;
  final VoidCallback onTap;

  const _TimerViewOption({
    required this.role,
    required this.state,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSpecialist = role == AppRole.pbm || role == AppRole.solo;
    return Column(
      children: [
        if (role == AppRole.pbm) const Divider(color: Colors.white24),
        ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: onTap,
          title: Text(timerViewLabelForRole(role, state)),
          trailing: selected
              ? const Icon(Icons.check, color: Colors.deepOrangeAccent)
              : null,
          textColor: selected ? Colors.deepOrange.shade200 : Colors.white,
          dense: false,
        ),
      ],
    );
  }
}
