// import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
// import 'dart:typed_data';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as imeg;
import 'package:tflite_flutter/tflite_flutter.dart';

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

  late FaceDetector _faceDetector;
  Interpreter? _interpreter;

  bool _isProcessing = false;
  String _faceCodeText = "Arahkan Wajah Ke Kamera";

  @override
  void initState() {
    super.initState();

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
    );

    _loadModel();
    _initCamera();
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/mobilefacenet.tflite',
      );
      print("Model TFlite berhasil dimuat");
    } catch (e) {
      print("Gagal memuat models $e");
    }
  }

  Future<void> _initCamera() async {
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );

    await _cameraController!.initialize();
    if (!mounted) return;

    setState(() {});

    _cameraController!.startImageStream((CameraImage image) {
      if (!_isProcessing) {
        _processCameraImage(image);
      }
    });
  }

  bool _isCapturing = false;

  Future<void> _processCameraImage(CameraImage image) async {
    if (_cameraController != null &&
        _cameraController!.value.isInitialized &&
        !_isCapturing) {
      _isCapturing = true;
      try {
        XFile file = await _cameraController!.takePicture();

        final inputImage = InputImage.fromFilePath(file.path);
        final faces = await _faceDetector.processImage(inputImage);

        if (faces.isNotEmpty) {
          final face = faces.first;

          final bytes = await File(inputImage.filePath!).readAsBytes();
          final img = imeg.decodeImage(bytes);

          if (img == null) {
            print("Gagal Decode Image");
            return;
          }

          final faceCrop = imeg.copyCrop(
            img,
            x: face.boundingBox.left.toInt(),
            y: face.boundingBox.top.toInt(),
            width: face.boundingBox.width.toInt(),
            height: face.boundingBox.height.toInt(),
          );

          final resized = imeg.copyResize(faceCrop, width: 112, height: 112);

          var input = List.generate(1 * 112 * 112 * 3, (i) => 0.0);
          int pixelIndex = 0;
          for (int y = 0; y < 112; y++) {
            for (int x = 0; x < 112; x++) {
              final pixel = resized.getPixel(x, y);
              int r = (pixel >> 16) & 0xFF;
              int g = (pixel >> 8) & 0xFF;
              int b = pixel & 0xFF;

            }
          }

          var output = List.filled(128, 0.0).reshape([1, 128]);
          _interpreter!.run(input.reshape([1, 112, 112, 3]), output);

          List<double> embedding = output[0];

          setState(() {
            _faceCodeText =
                "Wajah terdeteksi!\nEmbedding; ${embedding.take(5).toList()}....";
          });
        } else {
          setState(() {
            _faceCodeText = "Arahkan Wajah Ke Kamera";
          });
        }
      } catch (e) {
        print("Error ambil foto: $e");
      } finally {
        _isCapturing = false;
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
      appBar: AppBar(title: Text('Face Code Prototype')),
      body: Stack(
        children: [
          SizedBox(child: CameraPreview(_cameraController!)),
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

          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(200),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _faceCodeText,
                style: TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),

              // FloatingActionButton(
              //   onPressed: () async {
              //     _cameraController;
              //   },
              //   child: Icon(Icons.camera_alt),
              // ),
            ),
          ),
        ],
      ),
    );
  }
}
