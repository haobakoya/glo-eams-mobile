import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/diagnostics/face_diagnostic_log.dart';

enum _Challenge { blink, turn }
enum _Phase { align, challenge, capture }

/// Front-camera face check with an on-device liveness challenge.
/// Returns the saved JPEG path, or null if cancelled.
class FaceCaptureScreen extends StatefulWidget {
  final String title;
  final bool challenge;

  const FaceCaptureScreen({
    super.key,
    this.title = 'Face check',
    this.challenge = true,
  });

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen> {
  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  CameraController? _cam;
  CameraDescription? _desc;

  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  final _Challenge _challenge =
      Random().nextBool() ? _Challenge.blink : _Challenge.turn;

  _Phase _phase = _Phase.align;

  bool _busy = false;
  bool _done = false;
  bool _starting = false;
  bool _loggedFirstDetection = false;
  bool _disposed = false;

  int _frontal = 0;
  int _still = 0;

  bool _sawClosed = false;
  double _rw = 1;

  String _msg = 'Starting camera...';
  String? _error;
  String? _lastFrameDiagnostic;
  String? _lastDetectionError;
  String? _lastLoggedDetectionError;

  Timer? _timeout;

  void _log(String message) {
    unawaited(FaceDiagnosticLog.write(message));
  }

  @override
  void initState() {
    super.initState();

    _log(
      'FACE SCREEN: Opened; challenge=${widget.challenge}; '
      'platform=${Platform.operatingSystem}',
    );

    _init();
  }

  Future<void> _init() async {
    if (_starting || !mounted || _disposed) return;

    _starting = true;
    CameraController? controller;

    try {
      await FaceDiagnosticLog.write(
        'FACE CAMERA: Initializing camera',
      );

      final cameras = await availableCameras();

      await FaceDiagnosticLog.write(
        'FACE CAMERA: Cameras discovered=${cameras.length}',
      );

      if (cameras.isEmpty) {
        throw StateError('No cameras were reported by the device.');
      }

      final desc = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _desc = desc;

      await FaceDiagnosticLog.write(
        'FACE CAMERA: lens=${desc.lensDirection}, '
        'sensorOrientation=${desc.sensorOrientation}, '
        'name=${desc.name}',
      );

      controller = CameraController(
        desc,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();

      if (!mounted || _disposed) {
        await controller.dispose();
        return;
      }

      await controller.lockCaptureOrientation(
        DeviceOrientation.portraitUp,
      );

      _cam = controller;

      await FaceDiagnosticLog.write(
        'FACE CAMERA: Initialized; '
        'preview=${controller.value.previewSize}, '
        'deviceOrientation=${controller.value.deviceOrientation}',
      );

      setState(() {
        _error = null;
        _msg = 'Look straight at the camera';
      });

      await controller.startImageStream(_onFrame);

      await FaceDiagnosticLog.write(
        'FACE CAMERA: Stream started; '
        'streaming=${controller.value.isStreamingImages}',
      );

      _timeout?.cancel();

      _timeout = Timer(const Duration(seconds: 25), () {
        if (!_done && mounted && !_disposed) {
          _log(
            'FACE CAMERA TIMEOUT: '
            'phase=$_phase, frontal=$_frontal, still=$_still, '
            'lastDiagnostic=$_lastFrameDiagnostic, '
            'lastDetectionError=$_lastDetectionError',
          );

          _fail('Timed out. Please try again.');
        }
      });
    } catch (e, st) {
      await FaceDiagnosticLog.write(
        'FACE CAMERA INIT ERROR: $e\nSTACK TRACE:\n$st',
      );

      if (controller != null) {
        try {
          await controller.dispose();
        } catch (_) {}
      }

      if (identical(_cam, controller)) {
        _cam = null;
      }

      _fail(
        'Camera unavailable. Check the camera permission and try again.',
      );
    } finally {
      _starting = false;
    }
  }

  Future<void> _restart() async {
    if (_starting || _disposed) return;

    _log('FACE CAMERA: Restart requested');
    _timeout?.cancel();

    final oldCamera = _cam;
    _cam = null;
    _desc = null;

    if (oldCamera != null) {
      try {
        if (oldCamera.value.isStreamingImages) {
          await oldCamera.stopImageStream();
        }
      } catch (e) {
        _log('FACE CAMERA: Stop stream failed: $e');
      }

      try {
        await oldCamera.dispose();
      } catch (e) {
        _log('FACE CAMERA: Dispose failed: $e');
      }
    }

    if (!mounted || _disposed) return;

    setState(() {
      _error = null;
      _msg = 'Starting camera...';
      _phase = _Phase.align;
      _done = false;
      _busy = false;
      _frontal = 0;
      _still = 0;
      _sawClosed = false;
      _rw = 1;
      _lastFrameDiagnostic = null;
      _lastDetectionError = null;
      _lastLoggedDetectionError = null;
      _loggedFirstDetection = false;
    });

    await _init();
  }

  void _setMsg(String message) {
    if (mounted && !_disposed && message != _msg) {
      setState(() => _msg = message);
    }
  }

  void _fail(String message) {
    _done = true;
    _timeout?.cancel();

    _log('FACE FLOW FAILED: $message');

    if (mounted && !_disposed) {
      setState(() => _error = message);
    }
  }

  void _diagnoseFrame(String message) {
    if (_lastFrameDiagnostic == message) return;

    _lastFrameDiagnostic = message;
    _log('FACE FRAME: $message');
  }

  InputImageRotation? _getRotation(
    CameraController cam,
    CameraDescription desc,
  ) {
    if (Platform.isIOS) {
      final rotation = InputImageRotationValue.fromRawValue(
        desc.sensorOrientation,
      );

      if (rotation == null) {
        _diagnoseFrame(
          'Invalid iOS sensor rotation: ${desc.sensorOrientation}',
        );
      }

      return rotation;
    }

    final orientation = _orientations[cam.value.deviceOrientation];

    if (orientation == null) {
      _diagnoseFrame(
        'Unsupported device orientation: '
        '${cam.value.deviceOrientation}',
      );
      return null;
    }

    final sensor = desc.sensorOrientation;

    final degrees = desc.lensDirection == CameraLensDirection.front
        ? (sensor + orientation) % 360
        : (sensor - orientation + 360) % 360;

    final rotation = InputImageRotationValue.fromRawValue(degrees);

    if (rotation == null) {
      _diagnoseFrame('Invalid image rotation: $degrees');
    }

    return rotation;
  }

  /// Converts Android YUV_420_888 frames into packed NV21.
  Uint8List? _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;

    if (width <= 0 || height <= 0 || width.isOdd || height.isOdd) {
      _diagnoseFrame(
        'Cannot convert to NV21: invalid size ${width}x$height',
      );
      return null;
    }

    if (image.planes.length != 3) {
      _diagnoseFrame(
        'Cannot convert YUV420: expected 3 planes, '
        'received ${image.planes.length}',
      );
      return null;
    }

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yBytes = yPlane.bytes;
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;

    final yRowStride = yPlane.bytesPerRow;
    final yPixelStride = yPlane.bytesPerPixel ?? 1;
    final uRowStride = uPlane.bytesPerRow;
    final uPixelStride = uPlane.bytesPerPixel ?? 1;
    final vRowStride = vPlane.bytesPerRow;
    final vPixelStride = vPlane.bytesPerPixel ?? 1;

    if (yRowStride <= 0 ||
        uRowStride <= 0 ||
        vRowStride <= 0 ||
        yPixelStride <= 0 ||
        uPixelStride <= 0 ||
        vPixelStride <= 0) {
      _diagnoseFrame(
        'Invalid YUV plane strides: '
        'Y(row=$yRowStride,pixel=$yPixelStride), '
        'U(row=$uRowStride,pixel=$uPixelStride), '
        'V(row=$vRowStride,pixel=$vPixelStride)',
      );
      return null;
    }

    final output = Uint8List(width * height * 3 ~/ 2);
    var position = 0;

    // Copy the Y plane without row padding.
    for (var row = 0; row < height; row++) {
      final rowStart = row * yRowStride;

      for (var col = 0; col < width; col++) {
        final index = rowStart + col * yPixelStride;

        if (index >= yBytes.length) {
          _diagnoseFrame('Y plane buffer too short');
          return null;
        }

        output[position++] = yBytes[index];
      }
    }

    // Interleave chroma VU to produce NV21.
    for (var row = 0; row < height ~/ 2; row++) {
      final uRowStart = row * uRowStride;
      final vRowStart = row * vRowStride;

      for (var col = 0; col < width ~/ 2; col++) {
        final uIndex = uRowStart + col * uPixelStride;
        final vIndex = vRowStart + col * vPixelStride;

        if (uIndex >= uBytes.length || vIndex >= vBytes.length) {
          _diagnoseFrame('Chroma plane buffer too short');
          return null;
        }

        output[position++] = vBytes[vIndex];
        output[position++] = uBytes[uIndex];
      }
    }

    if (position != output.length) {
      _diagnoseFrame(
        'NV21 conversion length mismatch: '
        'written=$position, expected=${output.length}',
      );
      return null;
    }

    return output;
  }

  InputImage? _toInput(CameraImage image) {
    final cam = _cam;
    final desc = _desc;

    if (cam == null || desc == null) {
      _diagnoseFrame('Camera controller or description is missing');
      return null;
    }

    final width = image.width;
    final height = image.height;

    if (width <= 0 || height <= 0 || image.planes.isEmpty) {
      _diagnoseFrame(
        'Invalid frame: size=${width}x$height, '
        'planes=${image.planes.length}',
      );
      return null;
    }

    final rotation = _getRotation(cam, desc);

    if (rotation == null) {
      _diagnoseFrame('Unable to determine image rotation');
      return null;
    }

    final group = image.format.group;
    final rawFormat = image.format.raw;

    _diagnoseFrame(
      'CAMERA FRAME: platform=${Platform.operatingSystem}, '
      'group=$group, rawFormat=$rawFormat, '
      'planes=${image.planes.length}, '
      'size=${width}x$height, rotation=$rotation, '
      'planeDetails=${image.planes.map((p) => "bytes=${p.bytes.length}/row=${p.bytesPerRow}/pixel=${p.bytesPerPixel}").join(";")}',
    );

    _rw = (rotation == InputImageRotation.rotation90deg ||
            rotation == InputImageRotation.rotation270deg)
        ? height.toDouble()
        : width.toDouble();

    // iOS: require BGRA8888.
    if (Platform.isIOS) {
      final format = InputImageFormatValue.fromRawValue(rawFormat);

      if (format != InputImageFormat.bgra8888 ||
          image.planes.length != 1) {
        _diagnoseFrame(
          'Unsupported iOS frame: format=$format, '
          'group=$group, rawFormat=$rawFormat, '
          'planes=${image.planes.length}',
        );
        return null;
      }

      final plane = image.planes.first;
      final minimumRowBytes = width * 4;

      if (plane.bytesPerRow < minimumRowBytes ||
          plane.bytes.length < plane.bytesPerRow * height) {
        _diagnoseFrame(
          'Invalid iOS BGRA buffer: '
          'bytes=${plane.bytes.length}, '
          'rowBytes=${plane.bytesPerRow}, '
          'minimumRowBytes=$minimumRowBytes, height=$height',
        );
        return null;
      }

      _log(
        'FACE INPUT: iOS BGRA validated; '
        'bytes=${plane.bytes.length}, '
        'rowBytes=${plane.bytesPerRow}, '
        'size=${width}x$height, rotation=$rotation',
      );

      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: rotation,
          format: format!,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    // Android: always repack to a tightly packed NV21 buffer.
    //
    // NOTE: We intentionally do NOT pass the raw camera NV21 buffer
    // directly to ML Kit. Some Android camera HALs supply NV21 with
    // internal padding/stride metadata that causes ML Kit's native
    // InputImageConverter to throw a NullPointerException. Repacking
    // through our own converter (or a tight copy) avoids this.
    if (Platform.isAndroid) {
      Uint8List? nv21;

      if (group == ImageFormatGroup.yuv420) {
        nv21 = _yuv420ToNv21(image);
      } else if (group == ImageFormatGroup.nv21) {
        // Camera reported NV21 directly (single plane). Repack to a
        // fresh, tightly sized buffer with no extra trailing bytes.
        if (image.planes.length != 1) {
          _diagnoseFrame(
            'Invalid Android NV21 plane count: '
            'planes=${image.planes.length}',
          );
          return null;
        }

        final plane = image.planes.first;
        final expectedLength = width * height * 3 ~/ 2;

        if (width.isOdd ||
            height.isOdd ||
            plane.bytesPerRow < width ||
            plane.bytes.length < expectedLength) {
          _diagnoseFrame(
            'Invalid Android NV21 buffer: '
            'bytes=${plane.bytes.length}, '
            'expectedBytes=$expectedLength, '
            'rowBytes=${plane.bytesPerRow}, '
            'size=${width}x$height',
          );
          return null;
        }

        nv21 = Uint8List.fromList(
          plane.bytes.sublist(0, expectedLength),
        );
      } else {
        _diagnoseFrame(
          'Unsupported Android camera format: '
          'group=$group, rawFormat=$rawFormat, '
          'planes=${image.planes.length}, size=${width}x$height',
        );
        return null;
      }

      if (nv21 == null) return null;

      _log(
        'FACE INPUT: Android packed NV21; '
        'bytes=${nv21.length}, '
        'size=${width}x$height, rotation=$rotation',
      );

      return InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: width,
        ),
      );
    }

    _diagnoseFrame(
      'Unsupported camera platform: '
      'platform=${Platform.operatingSystem}, '
      'group=$group, rawFormat=$rawFormat, '
      'planes=${image.planes.length}, size=${width}x$height',
    );

    return null;
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _done || !mounted || _disposed) return;

    _busy = true;

    try {
      final input = _toInput(image);
      if (input == null) return;

      final faces = await _detector.processImage(input);

      _lastDetectionError = null;
      _lastLoggedDetectionError = null;

      if (!_loggedFirstDetection) {
        _loggedFirstDetection = true;

        await FaceDiagnosticLog.write(
          'FACE DETECTION: First frame processed successfully; '
          'faces=${faces.length}',
        );
      }

      if (faces.length != 1) {
        _frontal = 0;
        _setMsg(
          faces.isEmpty ? 'No face found' : 'Only one person, please',
        );
        return;
      }

      final face = faces.first;
      final big = face.boundingBox.width / _rw >= 0.30;
      final leftEye = face.leftEyeOpenProbability ?? 1.0;
      final rightEye = face.rightEyeOpenProbability ?? 1.0;
      final yaw = face.headEulerAngleY ?? 0.0;
      final eyesOpen = leftEye > 0.6 && rightEye > 0.6;

      switch (_phase) {
        case _Phase.align:
          if (!big) {
            _frontal = 0;
            _setMsg('Move a little closer');
            break;
          }

          _frontal = yaw.abs() < 12 && eyesOpen ? _frontal + 1 : 0;

          if (_frontal >= 4) {
            if (!widget.challenge) {
              _phase = _Phase.capture;
              _still = 0;
              _log('FACE FLOW: Alignment passed; capture phase');
              _setMsg('Hold still');
            } else {
              _phase = _Phase.challenge;

              _log('FACE FLOW: Alignment passed; challenge=$_challenge');

              _setMsg(
                _challenge == _Challenge.blink
                    ? 'Now blink'
                    : 'Now turn your head slowly to one side',
              );
            }
          }
          break;

        case _Phase.challenge:
          var passed = false;

          if (_challenge == _Challenge.blink) {
            if (leftEye < 0.25 && rightEye < 0.25) {
              _sawClosed = true;
            }

            passed = _sawClosed && eyesOpen;
          } else {
            passed = yaw.abs() > 20;
          }

          if (passed) {
            _phase = _Phase.capture;
            _still = 0;
            _log('FACE FLOW: Liveness challenge passed');
            _setMsg('Good. Look straight and hold still');
          }
          break;

        case _Phase.capture:
          _still = big && yaw.abs() < 10 && eyesOpen ? _still + 1 : 0;

          if (_still >= 3) {
            _log('FACE FLOW: Stable face detected; taking photo');
            await _capture();
          }
          break;
      }
    } catch (e, st) {
      final errorText = e.toString();
      _lastDetectionError = errorText;

      // Log the first occurrence and any different error, rather than
      // writing the same exception for every incoming camera frame.
      if (_lastLoggedDetectionError != errorText) {
        _lastLoggedDetectionError = errorText;

        await FaceDiagnosticLog.write(
          'FACE DETECTION ERROR: $e\n'
          'STACK TRACE:\n$st',
        );
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _capture() async {
    if (_done || _disposed) return;

    _done = true;
    _timeout?.cancel();

    try {
      final cam = _cam;

      if (cam == null || !cam.value.isInitialized) {
        throw StateError('Camera is not initialized');
      }

      if (cam.value.isStreamingImages) {
        await cam.stopImageStream();
      }

      final shot = await cam.takePicture();
      final directory = await getApplicationDocumentsDirectory();
      final selfies = Directory('${directory.path}/selfies');

      await selfies.create(recursive: true);

      final destination = '${selfies.path}/${const Uuid().v4()}.jpg';
      await File(shot.path).copy(destination);

      try {
        await File(shot.path).delete();
      } catch (_) {}

      await FaceDiagnosticLog.write(
        'FACE CAPTURE SUCCESS: JPEG saved',
      );

      if (mounted && !_disposed) {
        Navigator.of(context).pop(destination);
      }
    } catch (e, st) {
      await FaceDiagnosticLog.write(
        'FACE CAPTURE ERROR: $e\nSTACK TRACE:\n$st',
      );

      _fail('Could not take the photo. Please try again.');
    }
  }

  Future<void> _shareDiagnostics() async {
    await FaceDiagnosticLog.write(
      'FACE DIAGNOSTICS: Share requested',
    );

    try {
      await FaceDiagnosticLog.share();
    } catch (e, st) {
      await FaceDiagnosticLog.write(
        'FACE DIAGNOSTICS SHARE ERROR: $e\nSTACK TRACE:\n$st',
      );

      if (mounted && !_disposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not share the diagnostic log.'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timeout?.cancel();

    _log('FACE SCREEN: Closed');

    unawaited(_detector.close());
    unawaited(_cam?.dispose() ?? Future<void>.value());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    final ready =
        cam != null && cam.value.isInitialized && _error == null;
    final previewSize = cam?.value.previewSize;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Share diagnostic log',
            onPressed: _shareDiagnostics,
            icon: const Icon(Icons.share),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Expanded(
              child: Center(
                child: ready && previewSize != null
                    ? ClipOval(
                        child: SizedBox(
                          width: 290,
                          height: 380,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: previewSize.height,
                              height: previewSize.width,
                              child: CameraPreview(cam),
                            ),
                          ),
                        ),
                      )
                    : _error != null
                        ? const Icon(
                            Icons.no_photography,
                            color: Colors.white54,
                            size: 72,
                          )
                        : const CircularProgressIndicator(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                _error ?? _msg,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('Cancel'),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _restart,
                        child: const Text('Try again'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}