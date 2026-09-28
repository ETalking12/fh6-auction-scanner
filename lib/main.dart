import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("Ошибка камер: $e");
  }
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ScannerPage(),
  ));
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  CameraController? _controller;
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  bool _busy = false;
  String _displayInfo = "Наведите камеру на ценник аукциона";

  @override
  void initState() {
    super.initState();
    if (cameras.isNotEmpty) {
      _controller = CameraController(cameras[0], ResolutionPreset.medium, enableAudio: false);
      _controller!.initialize().then((_) {
        if (!mounted) return;
        _controller!.startImageStream(_scanFrame);
        setState(() {});
      });
    }
  }

  void _scanFrame(CameraImage image) async {
    if (_busy) return;
    _busy = true;
    try {
      final inputImage = _buildInputImage(image);
      if (inputImage != null) {
        final recognized = await _recognizer.processImage(inputImage);
        for (var block in recognized.blocks) {
          final clean = block.text.replaceAll(',', '').replaceAll(' ', '');
          final match = RegExp(r'(\d{5,9})').firstMatch(clean);
          if (match != null) {
            setState(() {
              _displayInfo = "Найдена цена: ${match.group(1)} CR";
            });
            break;
          }
        }
      }
    } catch (_) {}
    _busy = false;
  }

  InputImage? _buildInputImage(CameraImage image) {
    final bytes = image.planes.fold<List<int>>([], (prev, p) => prev..addAll(p.bytes));
    return InputImage.fromBytes(
      bytes: Uint8List.fromList(bytes),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation90deg,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _recognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.greenAccent)),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("FH6 Auction Scanner"),
        backgroundColor: Colors.black,
      ),
      body: Stack(
        children: [
          CameraPreview(_controller!),
          Center(
            child: Container(
              width: 280,
              height: 120,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                _displayInfo,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          )
        ],
      ),
    );
  }
}
