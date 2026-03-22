import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/skater_seat.dart';
import '../styles/text_styles.dart';

class SkaterEntryResult {
  final String number;
  final SkaterPosition position;
  final bool fouledOut;

  const SkaterEntryResult({
    required this.number,
    required this.position,
    this.fouledOut = false,
  });
}

/// Dialog to enter a skater's number and position when they report to the box.
Future<SkaterEntryResult?> showSkaterEntryDialog(
  BuildContext context, {
  SkaterPosition initialPosition = SkaterPosition.blocker,
  bool allowJammer = true,
  String? teamName,
}) {
  return showDialog<SkaterEntryResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _SkaterEntryDialog(
      initialPosition: initialPosition,
      allowJammer: allowJammer,
      teamName: teamName,
    ),
  );
}

class _SkaterEntryDialog extends StatefulWidget {
  final SkaterPosition initialPosition;
  final bool allowJammer;
  final String? teamName;

  const _SkaterEntryDialog({
    required this.initialPosition,
    required this.allowJammer,
    this.teamName,
  });

  @override
  State<_SkaterEntryDialog> createState() => _SkaterEntryDialogState();
}

class _SkaterEntryDialogState extends State<_SkaterEntryDialog> {
  final _controller = TextEditingController();
  late SkaterPosition _position;
  bool _fouledOut = false;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final number = _controller.text.trim();
    if (number.isEmpty) return;
    Navigator.of(context).pop(
      SkaterEntryResult(
        number: number,
        position: _position,
        fouledOut: _fouledOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1C21),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.teamName != null ? widget.teamName!.toUpperCase() : 'REPORTING SKATER',
              style: AppTextStyles.clockLabel.copyWith(
                color: Colors.white54,
                fontSize: 13,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              style: AppTextStyles.skaterNumber,
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: InputDecoration(
                hintText: '#',
                hintStyle: AppTextStyles.skaterNumber.copyWith(color: Colors.white24),
                labelText: 'Skater Number',
                labelStyle: const TextStyle(color: Colors.white54),
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
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),
            Text(
              'POSITION',
              style: AppTextStyles.clockLabel.copyWith(
                color: Colors.white54,
                fontSize: 12,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (widget.allowJammer) ...[
                  _PositionChip(
                    label: 'Jammer',
                    selected: _position == SkaterPosition.jammer,
                    color: Colors.purple.shade400,
                    onTap: () => setState(() => _position = SkaterPosition.jammer),
                  ),
                  const SizedBox(width: 8),
                ],
                _PositionChip(
                  label: 'Pivot',
                  selected: _position == SkaterPosition.pivot,
                  color: Colors.teal.shade400,
                  onTap: () => setState(() => _position = SkaterPosition.pivot),
                ),
                const SizedBox(width: 8),
                _PositionChip(
                  label: 'Blocker',
                  selected: _position == SkaterPosition.blocker,
                  color: Colors.blue.shade400,
                  onTap: () => setState(() => _position = SkaterPosition.blocker),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => setState(() => _fouledOut = !_fouledOut),
              child: Row(
                children: [
                  Checkbox(
                    value: _fouledOut,
                    onChanged: (v) => setState(() => _fouledOut = v ?? false),
                    activeColor: Colors.red.shade600,
                    side: const BorderSide(color: Colors.white38),
                  ),
                  Text(
                    'Fouled Out (7th penalty)',
                    style: AppTextStyles.infoText.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'CANCEL',
                      style: AppTextStyles.buttonText.copyWith(
                        color: Colors.white38,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'SEAT SKATER',
                      style: AppTextStyles.buttonText.copyWith(fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ],
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.25) : Colors.transparent,
          border: Border.all(
            color: selected ? color : Colors.white24,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: AppTextStyles.clockLabel.copyWith(
            color: selected ? color : Colors.white54,
            fontSize: 13,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
