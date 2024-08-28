import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:tflite_v2/tflite_v2.dart';

class ObjectRecognitionApp extends StatefulWidget {
  @override
  _ObjectRecognitionAppState createState() => _ObjectRecognitionAppState();
}

class _ObjectRecognitionAppState extends State<ObjectRecognitionApp> {
  late CameraController _cameraController;
  bool _isCameraActive = false;
  bool _isProcessing = false;
  FlutterTts flutterTts = FlutterTts();
  List<dynamic> _recognitions = [];
  String? _error;
  double _confidenceThreshold = 0.5;
  double _speakConfidenceThreshold = 0.6;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadModel();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _error = 'No cameras available';
        });
        return;
      }
      final camera = cameras.first;
      _cameraController = CameraController(camera, ResolutionPreset.high);
      await _cameraController.initialize();
      if (!mounted) return;
      setState(() {
        _isCameraActive = true;
      });
      _startCameraStream();
    } catch (e) {
      setState(() {
        _error = 'Failed to initialize camera: $e';
      });
    }
  }

  Future<void> _loadModel() async {
    try {
      await Tflite.loadModel(
        model: 'assets/mobilenet_v1_1.0_224.tflite',
        labels: 'assets/mobilenet_v1_1.0_224.txt',
      );
    } catch (e) {
      setState(() {
        _error = 'Failed to load model: $e';
      });
    }
  }

  void _startCameraStream() {
    if (_isCameraActive && !_isProcessing) {
      _cameraController.startImageStream((CameraImage image) {
        if (!_isProcessing) {
          _isProcessing = true;
          _recognizeObjects(image);
        }
      });
    }
  }

  void _recognizeObjects(CameraImage cameraImage) async {
    try {
      var recognitions = await Tflite.runModelOnFrame(
        bytesList: cameraImage.planes.map((plane) => plane.bytes).toList(),
        imageHeight: cameraImage.height,
        imageWidth: cameraImage.width,
        imageMean: 127.5,
        imageStd: 127.5,
        numResults: 3,
        threshold: _confidenceThreshold,
      );

      if (recognitions != null && recognitions.isNotEmpty) {
        setState(() {
          _recognitions = recognitions;
          _error = null;
        });
        _speakObjects();
      } else {
        setState(() {
          _recognitions = [];
          _error = 'Object not recognized';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Object recognition failed: $e';
      });
    } finally {
      _isProcessing = false;
    }
  }

  void _speakObjects() async {
    for (var recognition in _recognitions) {
      if (recognition != null &&
          recognition.containsKey('label') &&
          recognition.containsKey('confidence')) {
        String recognizedObject = recognition['label'];
        double confidence = recognition['confidence'];
        if (confidence >= _speakConfidenceThreshold) {
          await flutterTts.speak(recognizedObject);

          int delayDuration = (recognizedObject.split(' ').length * 400).clamp(800, 3000);
          await Future.delayed(Duration(milliseconds: delayDuration));
        }
      }
    }
  }

  @override
  void dispose() {
    _cameraController.stopImageStream();
    _cameraController.dispose();
    Tflite.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Object Recognition', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blueAccent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isCameraActive)
              Container(
                width: double.infinity,
                height: 300,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueAccent),
                ),
                child: CameraPreview(_cameraController),
              ),
            SizedBox(height: 20),
            if (_error != null)
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red, fontSize: 18.0, fontWeight: FontWeight.w600),
                ),
              ),
            SizedBox(height: 20),
            if (_recognitions.isNotEmpty)
              Expanded(
                child: ListView(
                  children: _recognitions.map<Widget>((recognition) {
                    if (recognition == null ||
                        !recognition.containsKey('label') ||
                        !recognition.containsKey('confidence')) {
                      return Container(
                        padding: EdgeInsets.all(12),
                        margin: EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey),
                        ),
                        child: Text(
                          'Unrecognized object',
                          style: TextStyle(color: Colors.black, fontSize: 18.0),
                        ),
                      );
                    }
                    String label = recognition['label'] ?? 'Unknown';
                    double confidence = recognition['confidence'] ?? 0.0;
                    return Container(
                      padding: EdgeInsets.all(12),
                      margin: EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blueAccent),
                      ),
                      child: Text(
                        'Detected object: $label\nConfidence: ${(confidence * 100).toStringAsFixed(2)}%',
                        style: TextStyle(color: Colors.black, fontSize: 18.0),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
