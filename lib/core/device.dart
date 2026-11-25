import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'capture.dart';
import 'location.dart';
import 'models.dart';
import 'network/api_client.dart';
import 'plus_ledger.dart';

/// The phone's camera through the `camera` plugin. The camera screen opens it while visible and shows
/// [controller] as the viewfinder; with no camera (simulators, tests, a refused permission) it stays closed and
/// [take] returns null, so a story goes out as words.
class DeviceCamera implements CaptureSource {
  /// The live controller, or null while closed. The viewfinder listens to this.
  final ValueNotifier<CameraController?> controller = ValueNotifier(null);

  bool _opening = false;
  bool _recording = false;

  bool get ready => controller.value?.value.isInitialized ?? false;

  /// Opens the front or back camera. Failing quietly is the point: the drawn viewfinder stays.
  Future<void> open({required bool front}) async {
    if (_opening) return;
    _opening = true;
    try {
      await close();
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final wanted = front ? CameraLensDirection.front : CameraLensDirection.back;
      final description = cameras.firstWhere(
        (c) => c.lensDirection == wanted,
        orElse: () => cameras.first,
      );
      final next = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await next.initialize();
      controller.value = next;
    } catch (_) {
      controller.value = null; // no plugin, no camera or no permission
    } finally {
      _opening = false;
    }
  }

  Future<void> close() async {
    final current = controller.value;
    controller.value = null;
    _recording = false;
    try {
      await current?.dispose();
    } catch (_) {
      // Already released.
    }
  }

  @override
  Future<void> startVideo() async {
    final current = controller.value;
    if (current == null || !ready || _recording) return;
    try {
      await current.startVideoRecording();
      _recording = true;
    } catch (_) {
      _recording = false;
    }
  }

  @override
  Future<Capture?> take({required bool video, required bool front}) async {
    final current = controller.value;
    if (current == null || !ready) return null;
    try {
      final XFile file;
      if (video) {
        if (!_recording) return null;
        _recording = false;
        file = await current.stopVideoRecording();
      } else {
        file = await current.takePicture();
      }
      final name = file.path.toLowerCase();
      return Capture(
        bytes: await file.readAsBytes(),
        video: video,
        contentType: video
            ? (name.endsWith('.mov') ? 'video/quicktime' : 'video/mp4')
            : (name.endsWith('.png') ? 'image/png' : 'image/jpeg'),
      );
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    unawaited(close());
    controller.dispose();
  }
}

/// The phone's position through `geolocator`, asked for only while the app is open. [precise] is for Date Mode;
/// everything else needs the area only (the server snaps it to a ~0.7 km² cell either way).
class DeviceLocationSource implements LocationSource {
  const DeviceLocationSource({this.precise = false});

  final bool precise;

  @override
  Future<({double lat, double lon})?> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: precise ? LocationAccuracy.high : LocationAccuracy.low,
          timeLimit: const Duration(seconds: 15),
        ),
      );
      return (lat: position.latitude, lon: position.longitude);
    } catch (_) {
      return null;
    }
  }
}

/// Where push tokens come from. Firebase Cloud Messaging plugs in here once the Firebase project files
/// (google-services.json, GoogleService-Info.plist) exist; until then there is no token and nothing registers.
abstract interface class PushTokenSource {
  Future<String?> token();
}

class NoPushTokens implements PushTokenSource {
  const NoPushTokens();

  @override
  Future<String?> token() async => null;
}

/// Registers this phone for pushes after sign-in (`POST /devices`) and unregisters it on sign-out.
class PushRegistration {
  PushRegistration(this.api, this.tokens, {String? platform})
    : _platform = platform ?? currentPlatform;

  final ApiClient api;
  final PushTokenSource tokens;
  final String? _platform;
  String? _registered;

  /// `ANDROID` or `IOS`; null where the server has no push (web, desktop).
  static String? get currentPlatform {
    if (kIsWeb) return null;
    if (Platform.isAndroid) return 'ANDROID';
    if (Platform.isIOS) return 'IOS';
    return null;
  }

  Future<void> register() async {
    final token = await tokens.token();
    final os = _platform;
    if (token == null || os == null || token == _registered) return;
    try {
      await api.post('/devices', body: {'pushToken': token, 'platform': os});
      _registered = token;
    } catch (_) {
      // Pushes are a nicety; in-app notices still arrive.
    }
  }

  Future<void> unregister() async {
    final token = _registered;
    if (token == null) return;
    _registered = null;
    try {
      await api.post('/devices/unregister', body: {'pushToken': token});
    } catch (_) {
      // The server drops tokens that stop working.
    }
  }
}

/// How payment happens once the server has created a subscription.
enum CheckoutResult {
  /// Paid; Plus turns on when Razorpay's webhook reaches the server.
  paid,

  /// The person closed the checkout.
  cancelled,

  /// Something failed; [CheckoutOutcome.message] says what.
  failed,

  /// No in-app checkout here (web, desktop, no key): use the link.
  unavailable,
}

class CheckoutOutcome {
  const CheckoutOutcome(this.result, [this.message]);

  final CheckoutResult result;
  final String? message;
}

abstract interface class CheckoutLauncher {
  Future<CheckoutOutcome> open(Checkout checkout);
}

/// Razorpay's native checkout (UPI Autopay) on Android and iOS.
class RazorpayCheckout implements CheckoutLauncher {
  @override
  Future<CheckoutOutcome> open(Checkout checkout) async {
    final key = checkout.key;
    if (kIsWeb ||
        !(Platform.isAndroid || Platform.isIOS) ||
        key == null ||
        key.isEmpty ||
        checkout.subscriptionId.isEmpty) {
      return const CheckoutOutcome(CheckoutResult.unavailable);
    }
    final done = Completer<CheckoutOutcome>();
    final razorpay = Razorpay();
    razorpay
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse _) {
        if (!done.isCompleted) done.complete(const CheckoutOutcome(CheckoutResult.paid));
      })
      ..on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse failure) {
        if (done.isCompleted) return;
        done.complete(
          failure.code == Razorpay.PAYMENT_CANCELLED
              ? const CheckoutOutcome(CheckoutResult.cancelled)
              : CheckoutOutcome(CheckoutResult.failed, failure.message),
        );
      })
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse _) {
        if (!done.isCompleted) done.complete(const CheckoutOutcome(CheckoutResult.paid));
      });
    try {
      razorpay.open({
        'key': key,
        'subscription_id': checkout.subscriptionId,
        'name': 'OneDay Plus',
        if (checkout.price != null) 'description': checkout.price,
        'recurring': 1,
      });
      return await done.future;
    } catch (e) {
      return CheckoutOutcome(CheckoutResult.failed, '$e');
    } finally {
      razorpay.clear();
    }
  }
}
