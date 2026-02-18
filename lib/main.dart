// import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:math';
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

  List<Map<String, dynamic>> _registeredFaces = [];

  Rect? _faceRect;

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

          Rect scaledReact;

          Size imageSize = Size(img!.width.toDouble(), img.height.toDouble());
          Size previewSize = _cameraController!.value.previewSize!;

          double scaleX = previewSize.width / imageSize.width;
          double scaleY = previewSize.height / imageSize.height;

          final double mirrorLeft = imageSize.width - face.boundingBox.right;
          final double mirrorRight = imageSize.width - face.boundingBox.left;

          scaledReact = Rect.fromLTRB(
            mirrorLeft * scaleX,
            face.boundingBox.top * scaleY,
            mirrorRight * scaleX,
            face.boundingBox.bottom * scaleY,
          );

          // double scaleX = previewSize.width / imageSize.width;
          // double scaleY = previewSize.height / imageSize.height;

          // final scaledReact = Rect.fromLTRB(
          //   face.boundingBox.left * scaleX,
          //   face.boundingBox.top * scaleY,
          //   face.boundingBox.right * scaleX,
          //   face.boundingBox.bottom * scaleY,
          // );

          setState(() {
            _faceRect = scaledReact;
          });

          final faceCrop = imeg.copyCrop(
            img,
            x: face.boundingBox.left.toInt(),
            y: face.boundingBox.top.toInt(),
            width: face.boundingBox.width.toInt(),
            height: face.boundingBox.height.toInt(),
          );

          setState(() {
            _faceRect = scaledReact;
          });

          final resized = imeg.copyResize(faceCrop, width: 112, height: 112);

          var input = List.generate(1 * 112 * 112 * 3, (i) => 0.0);
          int pixelIndex = 0;
          for (int y = 0; y < 112; y++) {
            for (int x = 0; x < 112; x++) {
              final pixel = resized.getPixel(x, y);
              int r = pixel.r.toInt();
              int g = pixel.g.toInt();

              int b = pixel.b.toInt();

              input[pixelIndex++] = (r - 128) / 128.0;
              input[pixelIndex++] = (g - 128) / 128.0;
              input[pixelIndex++] = (b - 128) / 128.0;
            }
          }

          var output = List.filled(192, 0.0).reshape([1, 192]);
          _interpreter!.run(input.reshape([1, 112, 112, 3]), output);

          List<double> embedding = List<double>.from(output[0]);

          String? matchedName;
          double maxSimilarity = 0.0;
          const double threshold = 0.75;

          for (var entry in _registeredFaces) {
            double sim = cosineSimilarity(embedding, entry['embedding']);
            if (sim > maxSimilarity && sim > threshold) {
              maxSimilarity = sim;
              matchedName = entry['name'];
            }
          }

          if (matchedName != null) {
            setState(() {
              _faceCodeText = "Wajah Dikenali sebagai : $matchedName";
            });
          } else {
            String? name = await _showNameInput(context);
            if (name != null && name.isNotEmpty) {
              _registeredFaces.add({'name': name, 'embedding': embedding});

              setState(() {
                _faceCodeText = "Wajah $name berhasil disimpan";
              });
            } else {
              setState(() {
                _faceCodeText = "nama dan embedding tidak dimasukkan";
              });
            }
          }

          // await _cameraController!.pausePreview();
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

  double cosineSimilarity(List<double> a, List<double> b) {
    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    return dot / (sqrt(normA) * sqrt(normB));
  }

  Future<String?> _showNameInput(BuildContext context) async {
    TextEditingController _nameController = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Masukkan Nama"),
          content: TextField(
            controller: _nameController,
            decoration: InputDecoration(hintText: "Contoh : Bambang"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text("Batal"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, _nameController.text),
              child: Text("Simpan"),
            ),
          ],
        );
      },
    );
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

          if (_faceRect != null)
            Positioned(
              left: _faceRect!.left + 128,
              top: _faceRect!.top + 256,
              width: _faceRect!.width,
              height: _faceRect!.height,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 3),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            )
          else
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
              child: Column(
                children: [
                  Text(
                    _faceCodeText,
                    style: TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),

                  // ElevatedButton(
                  //   onPressed: () async {
                  //     setState(() {
                  //       _isDetection = true;
                  //       _faceCodeText = "Mendeteksi Ulang....";
                  //     });
                  //     await _cameraController?.resumePreview();
                  //   },
                  //   child: Text("Deteksi Ulang"),
                  // ),
                  ElevatedButton(
                    onPressed: () {
                      print("Daftar wajah terdaftar:");
                      for (var face in _registeredFaces) {
                        print("- ${face['name']} - ${face['embedding']}");
                      }
                    },
                    child: Text("Lihat Daftar Wajah"),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
