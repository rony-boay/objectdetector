import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:camera/camera.dart';
import 'package:tflite_v2/tflite_v2.dart';
import 'dart:async';

class VoiceInteractionScreen extends StatefulWidget {
  @override
  _VoiceInteractionScreenState createState() => _VoiceInteractionScreenState();
}

class _VoiceInteractionScreenState extends State<VoiceInteractionScreen>
    with SingleTickerProviderStateMixin {
  late CameraController _cameraController;
  bool _isCameraActive = false;
  bool _isProcessing = false;
  bool _isLoading = false;
  FlutterTts flutterTts = FlutterTts();
  List<dynamic> _recognitions = [];
  String? _error;
  double _confidenceThreshold = 0.5;
  double _speakConfidenceThreshold = 0.6;
  bool _isListening = false;
  String _command = '';
  String _targetObject = '';
  stt.SpeechToText _speechToText = stt.SpeechToText();
  Timer? _recognitionTimer;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadModel();
    _checkSpeechRecognitionAvailability();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500),
    );
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _isLoading = true;
    });
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to initialize camera: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _checkSpeechRecognitionAvailability() async {
    try {
      bool available = await _speechToText.initialize(
        onError: (error) => _handleSpeechError(error.errorMsg),
        onStatus: (status) => _handleSpeechStatus(status),
      );
      if (!mounted) return;
      setState(() {
        _isListening = available;
      });
    } catch (e) {
      setState(() {
        _error = 'Speech recognition initialization failed: $e';
      });
    }
  }

  void _handleSpeechError(String errorMsg) {
    setState(() {
      _error = 'Speech recognition error: $errorMsg';
      _isListening = false;
    });
  }

  void _handleSpeechStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      setState(() {
        _isListening = false;
      });
    }
  }

  void _startListening() {
    if (_isListening) return;

    try {
      _speechToText.listen(
        onResult: (result) {
          if (!mounted) return;
          setState(() {
            _command = result.recognizedWords.toLowerCase();
            _isListening = false;
          });
          _processCommand();
        },
        cancelOnError: true,
        partialResults: false,
        listenFor: Duration(seconds: 10),
      );
      setState(() {
        _error = null;
        _isListening = true;
      });
    } catch (e) {
      setState(() {
        _error = 'Error starting speech recognition: $e';
        _isListening = false;
      });
    }
  }

  void _stopListening() {
    if (_isListening) {
      try {
        _speechToText.stop();
        setState(() {
          _isListening = false;
        });
      } catch (e) {
        setState(() {
          _error = 'Error stopping speech recognition: $e';
        });
      }
    }
  }

  void _processCommand() {
    if (_command.contains('stop')) {
      _stopCameraStream();
    } else if (_command.contains('set target')) {
      _setTargetObject();
    } else {
      if (_isCameraActive) {
        _stopCameraStream(); // Stop any ongoing camera stream
      }
      _targetObject = _command;
      setState(() {
        _isLoading = true;
        _recognitions = [];
      });
      flutterTts.speak('Searching for $_targetObject');
      _startRecognitionTimer();
      _startCameraStream();
    }
  }

  void _setTargetObject() {
    List<String> words = _command.split(' ');
    int index = words.indexOf('target');
    if (index != -1 && index + 1 < words.length) {
      setState(() {
        _targetObject = words[index + 1];
      });
      flutterTts.speak('Target object set to $_targetObject.');
    } else {
      flutterTts.speak('Please specify a target object.');
    }
  }

  Future<void> _loadModel() async {
    setState(() {
      _isLoading = true;
    });
    try {
      await Tflite.loadModel(
        model: 'assets/mobilenet_v1_1.0_224.tflite',
        labels: 'assets/mobilenet_v1_1.0_224.txt',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load model: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startRecognitionTimer() {
    _recognitionTimer?.cancel();
    _recognitionTimer =
        Timer(const Duration(seconds: 10), _handleRecognitionTimeout);
  }

  void _startCameraStream() {
    if (_isCameraActive && !_isProcessing) {
      try {
        _cameraController.startImageStream((CameraImage image) {
          if (!_isProcessing) {
            _isProcessing = true;
            _recognizeObjects(image);
          }
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = 'Error starting image stream: $e';
        });
      }
    }
  }

  void _stopCameraStream() {
    if (_isCameraActive && _cameraController.value.isStreamingImages) {
      _cameraController.stopImageStream();
      setState(() {
        _isProcessing = false;
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

      if (mounted) {
        setState(() {
          if (recognitions != null && recognitions.isNotEmpty) {
            _recognitions = recognitions;
            _error = null;
          } else {
            _recognitions = [];
            _error = 'Object not recognized';
          }
          _isLoading = false;
        });
      }
      _speakTargetObject();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Object recognition failed: $e';
          _isLoading = false;
        });
      }
    } finally {
      _isProcessing = false;
    }
  }

  void _speakTargetObject() async {
    bool objectFound = false;
    for (var recognition in _recognitions) {
      if (recognition != null &&
          recognition.containsKey('label') &&
          recognition.containsKey('confidence')) {
        String recognizedObject = recognition['label'];
        double confidence = recognition['confidence'];
        if (recognizedObject.toLowerCase() == _targetObject.toLowerCase() &&
            confidence >= _speakConfidenceThreshold) {
          await flutterTts.speak('$recognizedObject found');
          objectFound = true;
          _recognitionTimer?.cancel(); // Cancel the timer
          break;
        }
      }
    }
    if (!objectFound) {
      _recognitionTimer
          ?.cancel(); // Ensure the timer is canceled if no object is found
    }
  }

  void _handleRecognitionTimeout() {
    if (_recognitions.isEmpty ||
        !_recognitions.any((recognition) =>
            recognition != null &&
            recognition.containsKey('label') &&
            recognition['label'].toLowerCase() ==
                _targetObject.toLowerCase())) {
      flutterTts.speak('$_targetObject not found');
    }
    _stopCameraStream(); // Stop the camera stream when the timeout occurs
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _recognitionTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF191970),
      appBar: AppBar(
        title: Text('Voice Interaction Screen',style: TextStyle(color: Colors.white),),
        backgroundColor: Color(0xFF191970),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: _isCameraActive &&
                          _cameraController.value.isInitialized
                      ? Center(
                          child: AspectRatio(
                            aspectRatio: _cameraController.value.aspectRatio,
                            child: CameraPreview(_cameraController),
                          ),
                        )
                      : Center(
                          child: _error != null
                              ? Text(
                                  _error!,
                                  style: TextStyle(color: Colors.red),
                                )
                              : Text(
                                  'Camera not active',
                                  style: TextStyle(color: Colors.white),
                                ),
                        ),
                ),
                SizedBox(height: 20),
                GestureDetector(
                  onTapDown: (details) {
                    _startListening();
                    _animationController.forward();
                  },
                  onTapUp: (details) {
                    _stopListening();
                    _animationController.reverse();
                  },
                  onTapCancel: () {
                    _stopListening();
                    _animationController.reverse();
                  },
                  child: AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return Container(
                        width: 100 + (_animationController.value * 20),
                        height: 100 + (_animationController.value * 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              spreadRadius: 5,
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.mic,
                          size: 50,
                          color: Color(0xFF191970),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  _command.isEmpty ? 'Listening...' : 'Command: $_command',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
    );
  }
}
