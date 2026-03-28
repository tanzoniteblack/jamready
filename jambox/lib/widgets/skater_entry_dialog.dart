import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/skater_seat.dart';
import '../styles/text_styles.dart';

class SkaterEntryResult {
  final String number;
  final SkaterPosition position;

  const SkaterEntryResult({required this.number, required this.position});
}

/// Shows the skater picker. If [knownNumbers] is non-empty, displays a button
/// grid first; a "?" button falls back to keyboard entry.
/// Set [barrierDismissible] to true when the timer is already running.
Future<SkaterEntryResult?> showSkaterEntryDialog(
  BuildContext context, {
  SkaterPosition initialPosition = SkaterPosition.blocker,
  bool allowJammer = true,
  String? teamName,
  bool barrierDismissible = false,
  List<String> knownNumbers = const [],
}) {
  return showDialog<SkaterEntryResult>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => _SkaterEntryDialog(
      initialPosition: initialPosition,
      allowJammer: allowJammer,
      teamName: teamName,
      knownNumbers: knownNumbers,
    ),
  );
}

class _SkaterEntryDialog extends StatefulWidget {
  final SkaterPosition initialPosition;
  final bool allowJammer;
  final String? teamName;
  final List<String> knownNumbers;

  const _SkaterEntryDialog({
    required this.initialPosition,
    required this.allowJammer,
    this.teamName,
    required this.knownNumbers,
  });

  @override
  State<_SkaterEntryDialog> createState() => _SkaterEntryDialogState();
}

class _SkaterEntryDialogState extends State<_SkaterEntryDialog> {
  final _controller = TextEditingController();
  late SkaterPosition _position;
  late bool _keyboardMode;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
    _keyboardMode = widget.knownNumbers.isEmpty;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submitNumber(String number) {
    if (number.isEmpty) return;
    Navigator.of(context).pop(SkaterEntryResult(number: number, position: _position));
  }

  void _submitFromField() => _submitNumber(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1C21),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.teamName != null ? widget.teamName!.toUpperCase() : 'REPORTING SKATER',
                    style: AppTextStyles.clockLabel.copyWith(
                      color: Colors.white54,
                      fontSize: 13,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                if (widget.knownNumbers.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() => _keyboardMode = !_keyboardMode),
                    child: Icon(
                      _keyboardMode ? Icons.grid_view_rounded : Icons.keyboard,
                      color: Colors.white38,
                      size: 20,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Number input — grid or keyboard
            _keyboardMode ? _buildKeyboard() : _buildGrid(),

            const SizedBox(height: 16),

            // Position chips
            Text(
              'POSITION',
              style: AppTextStyles.clockLabel.copyWith(
                color: Colors.white38,
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (widget.allowJammer) ...[
                  _PositionChip(
                    label: 'J',
                    selected: _position == SkaterPosition.jammer,
                    color: Colors.purple.shade400,
                    onTap: () => setState(() => _position = SkaterPosition.jammer),
                  ),
                  const SizedBox(width: 8),
                ],
                _PositionChip(
                  label: 'P',
                  selected: _position == SkaterPosition.pivot,
                  color: Colors.teal.shade400,
                  onTap: () => setState(() => _position = SkaterPosition.pivot),
                ),
                const SizedBox(width: 8),
                _PositionChip(
                  label: 'B',
                  selected: _position == SkaterPosition.blocker,
                  color: Colors.blue.shade400,
                  onTap: () => setState(() => _position = SkaterPosition.blocker),
                ),
              ],
            ),

            if (_keyboardMode) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'CANCEL',
                        style: AppTextStyles.buttonText.copyWith(color: Colors.white38, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _submitFromField,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('SEAT SKATER', style: AppTextStyles.buttonText.copyWith(fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'CANCEL',
                  style: AppTextStyles.buttonText.copyWith(color: Colors.white38, fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildKeyboard() {
    return TextField(
      controller: _controller,
      autofocus: true,
      style: AppTextStyles.skaterNumber.copyWith(fontSize: 28),
      keyboardType: TextInputType.numberWithOptions(signed: false, decimal: false),
      textCapitalization: TextCapitalization.characters,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
        LengthLimitingTextInputFormatter(4),
      ],
      decoration: InputDecoration(
        hintText: '#',
        hintStyle: AppTextStyles.skaterNumber.copyWith(color: Colors.white24, fontSize: 28),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
      ),
      onSubmitted: (_) => _submitFromField(),
    );
  }

  Widget _buildGrid() {
    // Alphabetically sorted, '?' always last
    final numbers = [...widget.knownNumbers]..sort();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...numbers.map((n) => _NumberChip(
              number: n,
              onTap: () => _submitNumber(n),
            )),
        // '?' = open keyboard to type manually
        GestureDetector(
          onTap: () => setState(() => _keyboardMode = true),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '?',
              style: AppTextStyles.skaterNumber.copyWith(
                fontSize: 20,
                color: Colors.white38,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NumberChip extends StatelessWidget {
  final String number;
  final VoidCallback onTap;

  const _NumberChip({required this.number, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.15),
          border: Border.all(color: Colors.blue.shade700),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '#$number',
          style: AppTextStyles.skaterNumber.copyWith(
            fontSize: 20,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _PositionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _PositionChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.25) : Colors.transparent,
          border: Border.all(color: selected ? color : Colors.white24, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: AppTextStyles.clockLabel.copyWith(
            color: selected ? color : Colors.white54,
            fontSize: 14,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
