import 'dart:math';
import 'dart:ui' as ui;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../models/warp_config.dart';

class WarpRegion {
  final ui.Offset center;
  final double radius;
  final double strength;

  const WarpRegion({
    required this.center,
    required this.radius,
    required this.strength,
  });
}

class WarpEngine {
  static const int _gridCols = 40;

  /// Build a warped mesh from pose landmarks + kg config.
  /// Positions are in image-pixel space; texture coordinates are distorted
  /// so that body regions appear expanded.
  static ui.Vertices createWarpedMesh({
    required double imageWidth,
    required double imageHeight,
    required List<PoseLandmark> landmarks,
    required WarpConfig config,
  }) {
    final regions = _buildWarpRegions(landmarks, config);
    return _buildMesh(imageWidth, imageHeight, regions);
  }

  /// Identity mesh (no distortion) for when no pose is detected.
  static ui.Vertices createIdentityMesh({
    required double imageWidth,
    required double imageHeight,
  }) {
    return _buildMesh(imageWidth, imageHeight, const []);
  }

  // ── private ──────────────────────────────────────────────────────────

  static ui.Vertices _buildMesh(
    double w,
    double h,
    List<WarpRegion> regions,
  ) {
    final cols = _gridCols;
    final rows = (cols * h / w).round().clamp(10, 80);

    final vertexCount = (cols + 1) * (rows + 1);
    final positions = List<ui.Offset>.filled(vertexCount, ui.Offset.zero);
    final texCoords = List<ui.Offset>.filled(vertexCount, ui.Offset.zero);

    for (int j = 0; j <= rows; j++) {
      for (int i = 0; i <= cols; i++) {
        final idx = j * (cols + 1) + i;
        final x = (i / cols) * w;
        final y = (j / rows) * h;
        final pt = ui.Offset(x, y);

        positions[idx] = pt;

        // Distort texture coordinate toward body-region centers.
        var tc = pt;
        for (final region in regions) {
          tc = _distort(tc, region);
        }
        texCoords[idx] = tc;
      }
    }

    final indices = <int>[];
    for (int j = 0; j < rows; j++) {
      for (int i = 0; i < cols; i++) {
        final tl = j * (cols + 1) + i;
        final tr = tl + 1;
        final bl = tl + (cols + 1);
        final br = bl + 1;
        indices.addAll([tl, tr, bl, tr, br, bl]);
      }
    }

    return ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: texCoords,
      indices: indices,
    );
  }

  /// Pull [texCoord] toward [region.center] so the rendered image
  /// appears expanded outward at that point.
  static ui.Offset _distort(ui.Offset texCoord, WarpRegion region) {
    final delta = texCoord - region.center;
    final dist = delta.distance;

    if (dist >= region.radius || dist < 0.001) return texCoord;

    final normalized = dist / region.radius;
    final t = 1.0 - normalized;
    final factor = region.strength * t * t; // quadratic falloff

    return texCoord - delta * factor;
  }

  /// Derive warp regions from ML Kit pose landmarks.
  static List<WarpRegion> _buildWarpRegions(
    List<PoseLandmark> landmarks,
    WarpConfig config,
  ) {
    final lm = {for (final l in landmarks) l.type: l};
    final regions = <WarpRegion>[];

    final leftHip = lm[PoseLandmarkType.leftHip];
    final rightHip = lm[PoseLandmarkType.rightHip];
    final leftShoulder = lm[PoseLandmarkType.leftShoulder];
    final rightShoulder = lm[PoseLandmarkType.rightShoulder];

    // ── Belly ───────────────────────────────────────────────────────
    if (leftHip != null &&
        rightHip != null &&
        leftShoulder != null &&
        rightShoulder != null) {
      final hipCx = (leftHip.x + rightHip.x) / 2;
      final hipCy = (leftHip.y + rightHip.y) / 2;
      final shCx = (leftShoulder.x + rightShoulder.x) / 2;
      final shCy = (leftShoulder.y + rightShoulder.y) / 2;

      final bellyCenter = ui.Offset(
        (hipCx + shCx) / 2,
        shCy + (hipCy - shCy) * 0.55,
      );
      final hipWidth = (leftHip.x - rightHip.x).abs();

      regions.add(WarpRegion(
        center: bellyCenter,
        radius: hipWidth * 1.6,
        strength: config.bellyStrength,
      ));
    }

    // ── Face ────────────────────────────────────────────────────────
    final nose = lm[PoseLandmarkType.nose];
    if (nose != null) {
      final leftEar = lm[PoseLandmarkType.leftEar];
      final rightEar = lm[PoseLandmarkType.rightEar];
      double faceRadius = 60.0;
      if (leftEar != null && rightEar != null) {
        faceRadius = (leftEar.x - rightEar.x).abs() * 0.9;
      }
      regions.add(WarpRegion(
        center: ui.Offset(nose.x, nose.y),
        radius: faceRadius,
        strength: config.faceStrength,
      ));
    }

    // ── Arms ────────────────────────────────────────────────────────
    void addArm(PoseLandmark? shoulder, PoseLandmark? elbow) {
      if (shoulder == null || elbow == null) return;
      final cx = (shoulder.x + elbow.x) / 2;
      final cy = (shoulder.y + elbow.y) / 2;
      final len = sqrt(
        pow(shoulder.x - elbow.x, 2) + pow(shoulder.y - elbow.y, 2),
      );
      regions.add(WarpRegion(
        center: ui.Offset(cx, cy),
        radius: len * 0.5,
        strength: config.armStrength,
      ));
    }

    addArm(leftShoulder, lm[PoseLandmarkType.leftElbow]);
    addArm(rightShoulder, lm[PoseLandmarkType.rightElbow]);

    // ── Thighs ──────────────────────────────────────────────────────
    void addThigh(PoseLandmark? hip, PoseLandmark? knee) {
      if (hip == null || knee == null) return;
      final cx = (hip.x + knee.x) / 2;
      final cy = (hip.y + knee.y) / 2;
      final len = sqrt(pow(hip.x - knee.x, 2) + pow(hip.y - knee.y, 2));
      regions.add(WarpRegion(
        center: ui.Offset(cx, cy),
        radius: len * 0.45,
        strength: config.legStrength,
      ));
    }

    addThigh(leftHip, lm[PoseLandmarkType.leftKnee]);
    addThigh(rightHip, lm[PoseLandmarkType.rightKnee]);

    return regions;
  }
}
