import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../styles/text_styles.dart';
import 'jam_timer_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hostController.text = prefs.getString('server_host') ?? '10.0.2.2';
      _portController.text = prefs.getString('server_port') ?? '8000';
    });
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_host', _hostController.text.trim());
      await prefs.setString('server_port', _portController.text.trim());

      if (mounted) {
        setState(() => _isLoading = false);
        // Navigate to Jam Timer, replacing the current route to prevent back navigation loop
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const JamTimerScreen()),
        );
      }
    }
  }

  Future<void> _scanQRCode() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => const _QRScannerScreen(),
      ),
    );

    if (result != null && mounted) {
      _parseAndSetAddress(result);
    }
  }

  void _parseAndSetAddress(String scannedValue) {
    // Expected format: "host:port" e.g., "169.254.99.171:8000"
    // Also handle URLs like "http://169.254.99.171:8000"
    String value = scannedValue.trim();

    // Remove protocol prefix if present
    if (value.startsWith('http://')) {
      value = value.substring(7);
    } else if (value.startsWith('https://')) {
      value = value.substring(8);
    }

    // Remove trailing path if present
    final pathIndex = value.indexOf('/');
    if (pathIndex != -1) {
      value = value.substring(0, pathIndex);
    }

    // Split by colon to get host and port
    final parts = value.split(':');
    if (parts.isNotEmpty) {
      setState(() {
        _hostController.text = parts[0];
        if (parts.length > 1) {
          _portController.text = parts[1];
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Loaded: ${parts[0]}:${parts.length > 1 ? parts[1] : _portController.text}'),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Text("SETTINGS", style: AppTextStyles.appBarTitle),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "SERVER CONFIGURATION",
                style: AppTextStyles.clockLabel.copyWith(
                  color: Colors.white70,
                  fontSize: 14,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 24),

              // QR Code Scan Button
              SizedBox(
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: _scanQRCode,
                  icon: const Icon(Icons.qr_code_scanner, size: 24),
                  label: Text(
                    "SCAN QR CODE",
                    style: AppTextStyles.buttonText.copyWith(fontSize: 16),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Divider with "OR" text
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.white24)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      "OR ENTER MANUALLY",
                      style: AppTextStyles.clockLabel.copyWith(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.white24)),
                ],
              ),

              const SizedBox(height: 24),

              TextFormField(
                controller: _hostController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(
                  "Host / IP Address",
                  "e.g. 192.168.1.100",
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a host address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _portController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration("Port", "e.g. 8000"),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a port';
                  }
                  if (int.tryParse(value) == null) {
                    return 'Port must be a number';
                  }
                  return null;
                },
              ),
              const Spacer(),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          "CONNECT",
                          style: AppTextStyles.buttonText.copyWith(
                            fontSize: 18,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Colors.white70),
      hintStyle: const TextStyle(color: Colors.white24),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.blue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
    );
  }
}

class _QRScannerScreen extends StatefulWidget {
  const _QRScannerScreen();

  @override
  State<_QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<_QRScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue != null) {
      _hasScanned = true;
      Navigator.of(context).pop(barcode!.rawValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text("SCAN QR CODE", style: AppTextStyles.appBarTitle),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Overlay with cutout
          CustomPaint(
            painter: _ScannerOverlayPainter(),
            child: const SizedBox.expand(),
          ),
          // Instructions
          Positioned(
            bottom: 100,
            left: 24,
            right: 24,
            child: Text(
              "Point your camera at the QR code\non the scoreboard's index page",
              textAlign: TextAlign.center,
              style: AppTextStyles.clockLabel.copyWith(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    final cutoutSize = size.width * 0.7;
    final cutoutRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 50),
      width: cutoutSize,
      height: cutoutSize,
    );

    // Draw overlay with cutout
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(cutoutRect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    // Draw border around cutout
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawRRect(
      RRect.fromRectAndRadius(cutoutRect, const Radius.circular(16)),
      borderPaint,
    );

    // Draw corner accents
    final accentPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    const cornerLength = 30.0;
    final corners = [
      // Top-left
      [cutoutRect.topLeft, Offset(cutoutRect.left + cornerLength, cutoutRect.top)],
      [cutoutRect.topLeft, Offset(cutoutRect.left, cutoutRect.top + cornerLength)],
      // Top-right
      [cutoutRect.topRight, Offset(cutoutRect.right - cornerLength, cutoutRect.top)],
      [cutoutRect.topRight, Offset(cutoutRect.right, cutoutRect.top + cornerLength)],
      // Bottom-left
      [cutoutRect.bottomLeft, Offset(cutoutRect.left + cornerLength, cutoutRect.bottom)],
      [cutoutRect.bottomLeft, Offset(cutoutRect.left, cutoutRect.bottom - cornerLength)],
      // Bottom-right
      [cutoutRect.bottomRight, Offset(cutoutRect.right - cornerLength, cutoutRect.bottom)],
      [cutoutRect.bottomRight, Offset(cutoutRect.right, cutoutRect.bottom - cornerLength)],
    ];

    for (final corner in corners) {
      canvas.drawLine(corner[0], corner[1], accentPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}