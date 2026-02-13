import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FaceScanScreen(),
    ),
  );
}

class FaceScanScreen extends StatefulWidget {
  const FaceScanScreen({super.key});

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends State<FaceScanScreen> {
  CameraController? _cameraController;
  bool _isProcessing = false;
  String _faceCodeText = "Arahkan wajah ke kamera...";

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    // Pakai kamera depan (index 1)
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset
          .low, // Pake low aja biar proses AI-nya cepet dan HP nggak panas
      enableAudio: false,
      imageFormatGroup:
          ImageFormatGroup.yuv420, // Format wajib buat diproses AI
    );

    await _cameraController!.initialize();
    if (!mounted) return;

    setState(() {});

    // Mulai dengerin gambar dari kamera tiap frame
    _cameraController!.startImageStream((CameraImage image) {
      if (!_isProcessing) {
        _processCameraImage(image);
      }
    });
  }

  // FUNGSI UTAMA AI NANTI DI SINI
  Future<void> _processCameraImage(CameraImage image) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      // 1. Nanti kita taruh fungsi Deteksi Wajah (ML Kit) di sini
      // 2. Nanti kita taruh fungsi Potong Wajah di sini
      // 3. Nanti kita taruh fungsi Ekstrak Wajah (TFLite) di sini

      // Simulasi sementara biar kamu lihat UI-nya jalan
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      print("Error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Face Code Prototype')),
      body: Stack(
        children: [
          // Tampilan Kamera Full Screen
          SizedBox.expand(child: CameraPreview(_cameraController!)),

          // Kotak overlay buat nandain area wajah
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          // Teks buat nampilin "Face Code"
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _faceCodeText,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
