# Resizer

A Flutter camera experiment that answers a question nobody asked:
*what would I look like N kilograms heavier?*

Point the camera at a person, drag the slider, and a real-time mesh warp
expands belly, cheeks, arms and thighs proportionally to the chosen weight.
Everything runs on-device.

## How it works

1. **Pose detection** — Google ML Kit finds body landmarks (shoulders, hips,
   knees, nose, ears) in the camera frame.
2. **Warp regions** — landmark geometry is turned into circular warp regions:
   belly center from the hip/shoulder midpoints, face radius from ear
   distance, arm/thigh regions along the limb segments. Region strength is
   derived from the kg value (belly grows fastest, face subtler).
3. **Mesh warp** — the frame is rendered as a 40-column triangle mesh
   (`ui.Vertices`); texture coordinates are pulled toward region centers with
   a quadratic falloff, so those areas appear expanded outward.

No pose detected → identity mesh, i.e. the plain camera image.

## Stack

- Flutter (Material 3, dark theme)
- `camera` for the live feed
- `google_mlkit_pose_detection` for landmarks
- Custom `ui.Vertices` mesh rendering — no image-processing dependency

## Run

```bash
flutter pub get
flutter run
```

Requires a physical device (camera + ML Kit).

## Status

A weekend experiment in real-time mesh warping — not a product, and
deliberately unserious.

## Türkçe özet

Kamerayı bir kişiye tutup kaydıraçla "+N kg" seçince, ML Kit pose detection
ile bulunan vücut noktaları etrafında gerçek zamanlı mesh warp uygulayarak o
kilodaki halini gösteren eğlencelik bir Flutter deneyi. Tamamen cihaz
üzerinde çalışır; hafta sonu projesidir.
