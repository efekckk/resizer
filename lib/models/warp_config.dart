class WarpConfig {
  final double kg;

  const WarpConfig({required this.kg});

  /// Belly/torso expansion strength (main area).
  double get bellyStrength => (kg / 80.0).clamp(0.0, 0.65);

  /// Face/cheek puffiness (subtler than body).
  double get faceStrength => (kg / 160.0).clamp(0.0, 0.30);

  /// Upper-arm thickness.
  double get armStrength => (kg / 200.0).clamp(0.0, 0.25);

  /// Thigh thickness.
  double get legStrength => (kg / 200.0).clamp(0.0, 0.25);
}
