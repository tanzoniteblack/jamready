import 'package:flutter/material.dart';
import '../styles/background.dart';
import '../styles/text_styles.dart';
import 'home_screen.dart';
import 'penalty_box_home_screen.dart';

class AppHomeScreen extends StatelessWidget {
  const AppHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicBackground(
      accentColor: Colors.deepOrange.shade400,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          toolbarHeight: 78,
          titleSpacing: 16,
          title: Text('JamReady', style: AppTextStyles.appBarTitle),
          centerTitle: false,
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          flexibleSpace: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;
              final cards = [
                _FocusCard(
                  title: 'Jam Timer Operator',
                  subtitle:
                      'Run game, jam, lineup, timeout, review, and score flow.',
                  icon: Icons.sports_score_rounded,
                  color: Colors.blue.shade400,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const JamTimerHomeScreen(),
                    ),
                  ),
                ),
                _FocusCard(
                  title: 'Penalty Box',
                  subtitle:
                      'Pick PBM, solo, or team seats without jam timer controls.',
                  icon: Icons.timer_rounded,
                  color: Colors.deepOrange.shade400,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PenaltyBoxHomeScreen(),
                    ),
                  ),
                ),
              ];

              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 48,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'CHOOSE YOUR ROLE',
                        style: AppTextStyles.clockLabel.copyWith(
                          color: Colors.white70,
                          fontSize: 14,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Open only the controls you are responsible for during the bout.',
                        style: AppTextStyles.infoText.copyWith(
                          color: Colors.white54,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (isWide)
                        Row(
                          children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 16),
                            Expanded(child: cards[1]),
                          ],
                        )
                      else
                        Column(
                          children: [
                            cards[0],
                            const SizedBox(height: 14),
                            cards[1],
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FocusCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _FocusCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 170),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            border: Border.all(
              color: color.withValues(alpha: 0.62),
              width: 1.4,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 34),
              const SizedBox(height: 28),
              Text(title, style: AppTextStyles.teamName.copyWith(fontSize: 22)),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: AppTextStyles.infoText.copyWith(
                  color: Colors.white60,
                  fontSize: 14,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
