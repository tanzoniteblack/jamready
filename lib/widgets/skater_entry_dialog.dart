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
  String? teamName,
  bool barrierDismissible = false,
  List<String> knownNumbers = const [],
}) {
  return showDialog<SkaterEntryResult>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => _SkaterEntryDialog(
      initialPosition: initialPosition,
      teamName: teamName,
      knownNumbers: knownNumbers,
    ),
  );
}

class _SkaterEntryDialog extends StatefulWidget {
  final SkaterPosition initialPosition;
  final String? teamName;
  final List<String> knownNumbers;

  const _SkaterEntryDialog({
    required this.initialPosition,
    this.teamName,
    required this.knownNumbers,
  });

  @override
  State<_SkaterEntryDialog> createState() => _SkaterEntryDialogState();
}

class _SkaterEntryDialogState extends State<_SkaterEntryDialog> {
  final _controller = TextEditingController();
  late bool _keyboardMode;
  String? _selectedNumber;

  @override
  void initState() {
    super.initState();
    _keyboardMode = widget.knownNumbers.isEmpty;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submitNumber(String number) {
    if (number.isEmpty) return;
    Navigator.of(
      context,
    ).pop(SkaterEntryResult(number: number, position: widget.initialPosition));
  }

  void _submitFromField() => _submitNumber(_controller.text.trim());

  void _onChipTap(String number) {
    // Second tap on the same chip confirms immediately (fast-operator shortcut).
    if (_selectedNumber == number) {
      _submitNumber(number);
    } else {
      setState(() => _selectedNumber = number);
    }
  }

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
                    widget.teamName != null
                        ? widget.teamName!.toUpperCase()
                        : 'REPORTING SKATER',
                    style: AppTextStyles.clockLabel.copyWith(
                      color: Colors.white54,
                      fontSize: 13,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                if (widget.knownNumbers.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() {
                      _keyboardMode = !_keyboardMode;
                      _selectedNumber = null;
                    }),
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

            if (_keyboardMode)
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'CANCEL',
                          style: AppTextStyles.buttonText.copyWith(
                            color: Colors.white38,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _submitFromField,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'SEAT SKATER',
                          style: AppTextStyles.buttonText.copyWith(
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'CANCEL',
                          style: AppTextStyles.buttonText.copyWith(
                            color: Colors.white38,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _selectedNumber != null
                            ? () => _submitNumber(_selectedNumber!)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          disabledBackgroundColor: Colors.white.withValues(
                            alpha: 0.08,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _selectedNumber != null
                              ? 'CONFIRM #$_selectedNumber'
                              : 'SELECT NUMBER',
                          style: AppTextStyles.buttonText.copyWith(
                            fontSize: 15,
                          ),
                        ),
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

  Widget _buildKeyboard() {
    return TextField(
      controller: _controller,
      autofocus: true,
      style: AppTextStyles.skaterNumber.copyWith(fontSize: 28),
      keyboardType: TextInputType.numberWithOptions(
        signed: false,
        decimal: false,
      ),
      textCapitalization: TextCapitalization.characters,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
        LengthLimitingTextInputFormatter(4),
      ],
      decoration: InputDecoration(
        hintText: '#',
        hintStyle: AppTextStyles.skaterNumber.copyWith(
          color: Colors.white24,
          fontSize: 28,
        ),
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
    final numbers = [...widget.knownNumbers]..sort();

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        ...numbers.map(
          (n) => _NumberChip(
            number: n,
            selected: _selectedNumber == n,
            onTap: () => _onChipTap(n),
          ),
        ),
        // '?' = open keyboard to type manually
        GestureDetector(
          onTap: () => setState(() {
            _keyboardMode = true;
            _selectedNumber = null;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '?',
              style: AppTextStyles.skaterNumber.copyWith(
                fontSize: 22,
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
  final bool selected;
  final VoidCallback onTap;

  const _NumberChip({
    required this.number,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? Colors.blue.withValues(alpha: 0.35)
              : Colors.blue.withValues(alpha: 0.12),
          border: Border.all(
            color: selected ? Colors.blue.shade300 : Colors.blue.shade700,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '#$number',
          style: AppTextStyles.skaterNumber.copyWith(
            fontSize: 22,
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}
