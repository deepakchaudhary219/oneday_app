import 'models.dart';

/// The device camera, behind an interface so the screens and tests don't depend on a plugin. `DeviceCamera`
/// (core/device.dart) is the `camera` plugin; providers.dart selects it.
abstract interface class CaptureSource {
  /// Starts recording when the shutter is held; [take] with `video: true` ends it.
  Future<void> startVideo();

  /// The shot just taken, or null when there's no camera to take it with. A story is then shared as words.
  Future<Capture?> take({required bool video, required bool front});
}

/// No camera: the drawn viewfinder (design and demo mode, simulators, tests).
class NoCameraSource implements CaptureSource {
  const NoCameraSource();

  @override
  Future<void> startVideo() async {}

  @override
  Future<Capture?> take({required bool video, required bool front}) async =>
      null;
}
