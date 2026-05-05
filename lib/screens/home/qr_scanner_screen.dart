import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../styles/text_styles.dart';

/// QR code scanner screen for scanning scoreboard addresses.
class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
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
        title: Text('SCAN QR CODE', style: AppTextStyles.appBarTitle),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          CustomPaint(
            painter: _ScannerOverlayPainter(),
            child: const SizedBox.expand(),
          ),
          Positioned(
            bottom: 100,
            left: 24,
            right: 24,
            child: Text(
              'Point your camera at the QR code\non the scoreboard\'s index page',
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
    final cutoutSize = size.width * 0.7;
    final cutoutRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 50),
      width: cutoutSize,
      height: cutoutSize,
    );
    final cutoutRRect = RRect.fromRectAndRadius(
      cutoutRect,
      const Radius.circular(16),
    );

    // Dark overlay with cutout
    canvas.drawPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addRRect(cutoutRRect)
        ..fillType = PathFillType.evenOdd,
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );

    // White border
    canvas.drawRRect(
      cutoutRRect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Orange corner accents
    final accentPaint = Paint()
      ..color = Colors.deepOrange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    const L = 30.0;
    for (final [from, to] in [
      [cutoutRect.topLeft, Offset(cutoutRect.left + L, cutoutRect.top)],
      [cutoutRect.topLeft, Offset(cutoutRect.left, cutoutRect.top + L)],
      [cutoutRect.topRight, Offset(cutoutRect.right - L, cutoutRect.top)],
      [cutoutRect.topRight, Offset(cutoutRect.right, cutoutRect.top + L)],
      [cutoutRect.bottomLeft, Offset(cutoutRect.left + L, cutoutRect.bottom)],
      [cutoutRect.bottomLeft, Offset(cutoutRect.left, cutoutRect.bottom - L)],
      [cutoutRect.bottomRight, Offset(cutoutRect.right - L, cutoutRect.bottom)],
      [cutoutRect.bottomRight, Offset(cutoutRect.right, cutoutRect.bottom - L)],
    ]) {
      canvas.drawLine(from, to, accentPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
