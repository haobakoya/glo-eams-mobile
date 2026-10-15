import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../config/app_config.dart';
import '../models/punch.dart';
import '../models/roster.dart';
import 'session.dart';

class ApiException implements Exception {
  final String message;

  ApiException(this.message);

  @override
  String toString() => message;
}

class Site {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final double radius;

  Site(this.id, this.name, this.lat, this.lng, this.radius);

  factory Site.fromJson(Map<String, dynamic> j) => Site(
        j['id'].toString(),
        j['name'] as String,
        (j['lat'] as num).toDouble(),
        (j['lng'] as num).toDouble(),
        ((j['radius'] ?? AppConfig.defaultRadiusMeters) as num).toDouble(),
      );
}

class PunchSent {
  final List<String> flags;

  PunchSent(this.flags);
}

class SelfieResult {
  final String? faceStatus;

  SelfieResult(this.faceStatus);
}

class ApiService {
  static http.Client? _client;

  /// Optional certificate pinning.
  ///
  /// When pinning is enabled, the configured PEM certificate is loaded.
  /// If it cannot be loaded, this implementation falls back to the default
  /// HTTP client, matching the behaviour of the original implementation.
  static Future<http.Client> _c() async {
    if (_client != null) return _client!;

    if (!AppConfig.pinServerCertificate) {
      return _client = http.Client();
    }

    ByteData? pem;

    try {
      pem = await rootBundle.load('assets/certs/server_ca.pem');
    } catch (e) {
      debugPrint('CERTIFICATE LOAD ERROR: $e');
      pem = null;
    }

    if (pem == null) {
      debugPrint(
        'CERTIFICATE PINNING: PEM unavailable; using default HTTP client.',
      );
      return _client = http.Client();
    }

    final context = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(pem.buffer.asUint8List());

    return _client = IOClient(HttpClient(context: context));
  }

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (Session.token != null)
          'Authorization': 'Bearer ${Session.token}',
      };

  static Uri _u(String path) {
    return Uri.parse('${AppConfig.baseUrl}$path');
  }

  static String _err(http.Response response, String fallback) {
    try {
      final dynamic decoded = jsonDecode(response.body);

      if (decoded is Map) {
        if (decoded['error'] is String) {
          return decoded['error'] as String;
        }

        if (decoded['message'] is String) {
          return decoded['message'] as String;
        }

        if (decoded['title'] is String) {
          return decoded['title'] as String;
        }
      }
    } catch (_) {}

    return fallback;
  }

  static Future<http.Response> _post(
    String path,
    Object body, {
    Map<String, String>? extra,
  }) async {
    try {
      return await (await _c())
          .post(
            _u(path),
            headers: {..._headers, ...?extra},
            body: jsonEncode(body),
          )
          .timeout(AppConfig.requestTimeout);
    } on SocketException catch (e, st) {
      debugPrint('API POST SOCKET ERROR: path=$path error=$e');
      debugPrintStack(stackTrace: st);
      throw ApiException('Network connection failed. Check your connection.');
    } on HandshakeException catch (e, st) {
      debugPrint('API POST TLS ERROR: path=$path error=$e');
      debugPrintStack(stackTrace: st);
      throw ApiException('Secure connection failed. Contact IT.');
    } on TlsException catch (e, st) {
      debugPrint('API POST TLS ERROR: path=$path error=$e');
      debugPrintStack(stackTrace: st);
      throw ApiException('Secure connection failed. Contact IT.');
    } on TimeoutException catch (e, st) {
      debugPrint('API POST TIMEOUT: path=$path error=$e');
      debugPrintStack(stackTrace: st);
      throw ApiException('The request timed out. Please try again.');
    } catch (e, st) {
      debugPrint(
        'API POST ERROR: path=$path type=${e.runtimeType} error=$e',
      );
      debugPrintStack(stackTrace: st);
      throw ApiException('The request failed. Please try again.');
    }
  }

  /// GET with optional offline cache.
  static Future<dynamic> _getJson(
    String path, {
    String? cacheKey,
  }) async {
    try {
      final response = await (await _c())
          .get(_u(path), headers: _headers)
          .timeout(AppConfig.requestTimeout);

      if (response.statusCode == 200) {
        if (cacheKey != null) {
          await Session.writeRaw(cacheKey, response.body);
        }

        return jsonDecode(response.body);
      }

      if (response.statusCode == 401) {
        throw ApiException('Session expired. Please sign in again.');
      }

      if (response.statusCode == 403) {
        throw ApiException('You are not authorised to access this resource.');
      }

      debugPrint(
        'API GET HTTP ERROR: path=$path '
        'status=${response.statusCode}',
      );
    } on ApiException {
      rethrow;
    } on SocketException catch (e, st) {
      debugPrint('API GET SOCKET ERROR: path=$path error=$e');
      debugPrintStack(stackTrace: st);
    } on HandshakeException catch (e, st) {
      debugPrint('API GET TLS ERROR: path=$path error=$e');
      debugPrintStack(stackTrace: st);
    } on TlsException catch (e, st) {
      debugPrint('API GET TLS ERROR: path=$path error=$e');
      debugPrintStack(stackTrace: st);
    } on TimeoutException catch (e, st) {
      debugPrint('API GET TIMEOUT: path=$path error=$e');
      debugPrintStack(stackTrace: st);
    } catch (e, st) {
      debugPrint('API GET ERROR: path=$path type=${e.runtimeType} error=$e');
      debugPrintStack(stackTrace: st);
    }

    if (cacheKey != null) {
      final cached = await Session.readRaw(cacheKey);

      if (cached != null) {
        return jsonDecode(cached);
      }
    }

    throw ApiException('You appear to be offline.');
  }

  // ------------------------------------------------------------
  // Authentication
  // ------------------------------------------------------------

  static Future<void> login(String staffId, String password) async {
    final uri = _u('/auth/login');
    final http.Response response;

    try {
      debugPrint(
        'LOGIN REQUEST: host=${uri.host} '
        'path=${uri.path} '
        'timeoutSeconds=${AppConfig.requestTimeout.inSeconds}',
      );

      response = await (await _c())
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({
              'staffId': staffId,
              'password': password,
              'deviceId': Session.deviceId,
            }),
          )
          .timeout(AppConfig.requestTimeout);

      debugPrint(
        'LOGIN RESPONSE: status=${response.statusCode} '
        'bodyBytes=${response.bodyBytes.length}',
      );
    } on SocketException catch (e, st) {
      debugPrint('LOGIN SOCKET ERROR: $e');
      debugPrintStack(stackTrace: st);

      throw ApiException(
        'Network connection failed. Check your network or VPN.',
      );
    } on HandshakeException catch (e, st) {
      debugPrint('LOGIN TLS HANDSHAKE ERROR: $e');
      debugPrintStack(stackTrace: st);

      throw ApiException(
        'Secure connection failed. Contact IT.',
      );
    } on TlsException catch (e, st) {
      debugPrint('LOGIN TLS ERROR: $e');
      debugPrintStack(stackTrace: st);

      throw ApiException(
        'Secure connection failed. Contact IT.',
      );
    } on TimeoutException catch (e, st) {
      debugPrint('LOGIN TIMEOUT: $e');
      debugPrintStack(stackTrace: st);

      throw ApiException(
        'Login timed out. Check your connection and try again.',
      );
    } catch (e, st) {
      debugPrint(
        'LOGIN UNEXPECTED ERROR: '
        'type=${e.runtimeType} error=$e',
      );
      debugPrintStack(stackTrace: st);

      throw ApiException(
        'An unexpected error occurred during login. Please try again.',
      );
    }

    if (response.statusCode == 403) {
      throw ApiException(
        'This account is registered to another device. '
        'Contact HR/IT to rebind.',
      );
    }

    if (response.statusCode == 429) {
      throw ApiException(
        'Too many attempts. Try again in 15 minutes.',
      );
    }

    if (response.statusCode == 503) {
      debugPrint('LOGIN SERVER RESPONSE: company directory unavailable');

      throw ApiException(
        'Company directory is unavailable. Try again shortly.',
      );
    }

    if (response.statusCode != 200) {
      // Do not log the submitted password or authentication headers.
      // The response body is logged for diagnosis; review it before sharing.
      debugPrint(
        'LOGIN HTTP ERROR: status=${response.statusCode} '
        'body=${response.body}',
      );

      throw ApiException(
        'Login failed (HTTP ${response.statusCode}). '
        'Check your credentials or contact IT.',
      );
    }

    try {
      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'Login response is not a JSON object.',
        );
      }

      final token = decoded['token'];
      final name = decoded['name'];

      if (token is! String || token.isEmpty ||
          name is! String || name.isEmpty) {
        throw const FormatException(
          'Login response is missing token or name.',
        );
      }

      await Session.save(
        token: token,
        name: name,
        staffId: staffId,
        staffType: (decoded['staffType'] ?? 'regular') as String,
        isManager: decoded['isManager'] == true,
        faceEnrolled: decoded['faceEnrolled'] == true,
        faceStatus: (decoded['faceEnrolmentStatus'] ?? 'none') as String,
      );

      debugPrint('LOGIN SUCCESS: session saved.');
    } catch (e, st) {
      debugPrint(
        'LOGIN RESPONSE PARSE/SESSION ERROR: '
        'type=${e.runtimeType} error=$e',
      );
      debugPrintStack(stackTrace: st);

      throw ApiException(
        'The server responded, but the login response could not be processed.',
      );
    }
  }

  // ------------------------------------------------------------
  // Sites and shifts
  // ------------------------------------------------------------

  static Future<List<Site>> sites() async {
    try {
      final data = await _getJson(
        '/sites/mine',
        cacheKey: 'sites',
      ) as List;

      return data
          .map((e) => Site.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException {
      return [];
    }
  }

  static Future<List<Shift>> shifts() async {
    final data = await _getJson(
      '/shifts/mine',
      cacheKey: 'shifts',
    ) as List;

    return data
        .map((e) => Shift.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ------------------------------------------------------------
  // Attendance punches
  // ------------------------------------------------------------

  static Future<PunchSent?> sendPunch(Punch punch) async {
    final response = await (await _c())
        .post(
          _u('/punches'),
          headers: _headers,
          body: jsonEncode(punch.toJson()),
        )
        .timeout(AppConfig.requestTimeout);

    if (response.statusCode == 409) {
      return PunchSent(const []);
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      debugPrint(
        'PUNCH HTTP ERROR: status=${response.statusCode}',
      );
      return null;
    }

    try {
      final decoded = jsonDecode(response.body);
      final flags = ((decoded['flags'] ?? []) as List)
          .map((e) => e.toString())
          .toList();

      return PunchSent(flags);
    } catch (_) {
      return PunchSent(const []);
    }
  }

  static Future<SelfieResult?> uploadSelfie(
    String punchId,
    File file,
  ) async {
    final response = await (await _c())
        .put(
          _u('/punches/$punchId/selfie'),
          headers: {
            'Authorization': 'Bearer ${Session.token}',
            'Content-Type': 'image/jpeg',
          },
          body: await file.readAsBytes(),
        )
        .timeout(const Duration(seconds: 30));

    final statusCode = response.statusCode;
    String? faceStatus;

    if (statusCode == 200) {
      try {
        faceStatus = jsonDecode(response.body)['faceStatus'] as String?;
      } catch (_) {}

      if (faceStatus == 'not_enrolled') {
        await Session.setFaceEnrolled(false);
        await Session.setFaceStatus('none');
      }
    }

    final completed = (statusCode >= 200 && statusCode < 300) ||
        statusCode == 400 ||
        statusCode == 404 ||
        statusCode == 413;

    return completed ? SelfieResult(faceStatus) : null;
  }

  // ------------------------------------------------------------
  // Face enrolment
  // ------------------------------------------------------------

  /// Returns true if a new enrolment was created.
  /// Returns false if the server already has an enrolment.
  static Future<bool> enrolFace(File file) async {
    final uri = _u('/face/enrol');
    final stopwatch = Stopwatch()..start();

    try {
      final bytes = await file.readAsBytes();

      debugPrint(
        'FACE ENROLMENT START: url=$uri '
        'imageBytes=${bytes.length} '
        'hasToken=${Session.token?.isNotEmpty == true}',
      );

      final client = await _c();

      final response = await client
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer ${Session.token}',
              'Content-Type': 'image/jpeg',
              'X-Face-Consent': 'yes',
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 30));

      stopwatch.stop();

      debugPrint(
        'FACE ENROLMENT RESPONSE: '
        'status=${response.statusCode} '
        'elapsedMs=${stopwatch.elapsedMilliseconds} '
        'responseBytes=${response.bodyBytes.length}',
      );

      if (response.statusCode == 204 || response.statusCode == 200) {
        await Session.setFaceEnrolled(true);
        return true;
      }

      if (response.statusCode == 409) {
        await Session.setFaceEnrolled(true);
        return false;
      }

      debugPrint(
        'FACE ENROLMENT HTTP ERROR: '
        'status=${response.statusCode} body=${response.body}',
      );

      throw ApiException(
        _err(response, 'Could not complete enrolment.'),
      );
    } on ApiException {
      rethrow;
    } on SocketException catch (e, st) {
      stopwatch.stop();

      debugPrint('FACE ENROLMENT SOCKET ERROR: $e');
      debugPrintStack(stackTrace: st);

      throw ApiException(
        'Network connection failed during enrolment. Please try again.',
      );
    } on HandshakeException catch (e, st) {
      stopwatch.stop();

      debugPrint('FACE ENROLMENT TLS HANDSHAKE ERROR: $e');
      debugPrintStack(stackTrace: st);

      throw ApiException(
        'Secure connection failed during enrolment. Contact IT if this persists.',
      );
    } on TlsException catch (e, st) {
      stopwatch.stop();

      debugPrint('FACE ENROLMENT TLS ERROR: $e');
      debugPrintStack(stackTrace: st);

      throw ApiException(
        'Secure connection failed during enrolment. Contact IT if this persists.',
      );
    } on TimeoutException catch (e, st) {
      stopwatch.stop();

      debugPrint('FACE ENROLMENT TIMEOUT: $e');
      debugPrintStack(stackTrace: st);

      throw ApiException(
        'Enrolment timed out after '
        '${stopwatch.elapsed.inSeconds} seconds. Please try again.',
      );
    } catch (e, st) {
      stopwatch.stop();

      debugPrint(
        'FACE ENROLMENT ERROR: '
        'type=${e.runtimeType} '
        'elapsedMs=${stopwatch.elapsedMilliseconds} '
        'error=$e',
      );
      debugPrintStack(stackTrace: st);

      throw ApiException(
        'Enrolment failed (${e.runtimeType}). Check the debug console.',
      );
    }
  }

  // ------------------------------------------------------------
  // Employee requests
  // ------------------------------------------------------------

  static Future<List<StaffRequest>> myRequests() async {
    final data = await _getJson('/requests/mine') as List;

    return data
        .map((e) => StaffRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<StaffRequest>> pendingApprovals() async {
    final data = await _getJson('/requests/pending') as List;

    return data
        .map((e) => StaffRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> createRequest({
    required String type,
    required String fromDate,
    required String toDate,
    required String reason,
  }) async {
    final response = await _post('/requests', {
      'type': type,
      'fromDate': fromDate,
      'toDate': toDate,
      'reason': reason,
    });

    if (response.statusCode == 201 || response.statusCode == 200) {
      return;
    }

    throw ApiException(
      _err(response, 'Could not submit the request.'),
    );
  }

  // ------------------------------------------------------------
  // Manager photo review and enrolment approval
  // ------------------------------------------------------------

  static Future<List<ReviewItem>> reviewQueue() async {
    final data = await _getJson('/review/queue') as List;

    return data
        .map((e) => ReviewItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<EnrolItem>> enrolments() async {
    final data = await _getJson('/review/enrolments') as List;

    return data
        .map((e) => EnrolItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<Uint8List> enrolmentPhotoBytes(String staffGuid) async {
    try {
      final response = await (await _c())
          .get(
            _u('/review/enrolment-photo/$staffGuid'),
            headers: {
              'Authorization': 'Bearer ${Session.token}',
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }

      debugPrint(
        'ENROLMENT PHOTO HTTP ERROR: status=${response.statusCode}',
      );
    } catch (e, st) {
      debugPrint('ENROLMENT PHOTO ERROR: $e');
      debugPrintStack(stackTrace: st);
    }

    throw ApiException('Photo not available.');
  }

  static Future<void> confirmEnrolment(
    String staffGuid,
    bool ok,
  ) async {
    final response = await _post(
      '/review/enrolments/$staffGuid',
      {
        'ok': ok,
        'comment': null,
      },
    );

    if (response.statusCode == 204 || response.statusCode == 200) {
      return;
    }

    throw ApiException(
      _err(response, 'Could not save your answer.'),
    );
  }

  static Future<Uint8List> selfieBytes(String punchId) async {
    try {
      final response = await (await _c())
          .get(
            _u('/review/selfie/$punchId'),
            headers: {
              'Authorization': 'Bearer ${Session.token}',
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }

      debugPrint(
        'SELFIE HTTP ERROR: status=${response.statusCode}',
      );
    } catch (e, st) {
      debugPrint('SELFIE DOWNLOAD ERROR: $e');
      debugPrintStack(stackTrace: st);
    }

    throw ApiException('Photo not available.');
  }

  static Future<int> reviewSample(int count) async {
    final response = await _post(
      '/review/sample?count=$count',
      {},
    );

    if (response.statusCode != 200) {
      throw ApiException(
        _err(response, 'Could not add photos.'),
      );
    }

    return (jsonDecode(response.body)['marked'] as num).toInt();
  }

  static Future<void> reviewDecide(
    String punchId,
    bool ok,
    String? comment,
  ) async {
    final response = await _post(
      '/review/$punchId',
      {
        'ok': ok,
        'comment': comment,
      },
    );

    if (response.statusCode == 204 || response.statusCode == 200) {
      return;
    }

    throw ApiException(
      _err(response, 'Could not save the review.'),
    );
  }

  static Future<void> decide(
    String id,
    bool approve,
    String? comment,
  ) async {
    final response = await _post(
      '/requests/$id/decision',
      {
        'approve': approve,
        'comment': comment,
      },
    );

    if (response.statusCode == 204 || response.statusCode == 200) {
      return;
    }

    throw ApiException(
      _err(response, 'Could not save the decision.'),
    );
  }
}
