# ASA Cebu

A Flutter indoor-place discovery prototype inspired by the supplied mobile app
reference. The app includes Home, Map, and Settings tabs, a sample SM Seaside
map, and a map editor for adding floor plans and labeled navigation spots.

## Create a map

1. Open **Settings → Create map** (or use the add button in **Map**).
2. Enter a map name and upload a floor-plan image from the device gallery.
3. Enter the mall's latitude, longitude, and geofence radius in meters.
4. Select **Add spot**, tap the floor plan, then give the point a label and
   choose whether it is a place, elevator, escalator, or stairs.
5. Select **Connect spots**, then tap two spots in sequence to draw a path.
6. For live location on the floor plan, capture two GPS reference points and
   tap each point's corresponding location on the image. This calibration is
   optional when creating a map but required for live map tracking.
7. Tap a spot in **Add spot** mode to rename or delete it, then save the map.

Drag the map to explore it and use pinch gestures or the zoom controls to zoom.
Use the full-screen control for a larger view. The floor plan keeps its original
aspect ratio and is not cropped.

Saved maps and a copy of each uploaded image are stored in the app's private
documents directory. This lets maps persist after the app restarts. Flutter
bundled assets are read-only at runtime, so maps created on a device cannot be
written into the source `assets/` folder; add maps to bundled assets during
development/build time if they need to ship with the app.

## Find your way

Open a mall from the **Map** tab, choose your current labeled spot and the
destination, then select **Show route**. ASA finds the shortest available path
through the map's saved connections and highlights it on the floor plan.
Select **Start navigation** to check the device's location against the mall's
geofence and display a blue dot using live GPS updates and the saved reference
points. The dot does not move by itself. Indoor GPS can be inaccurate; maps need
GPS coordinates, a radius, two calibration points, and connected spots for live
route tracking.

Use the delete button on a saved map card to remove that map and its copied
floor-plan image from the device.

The existing `assests/data/sm_seaside.json` is intentionally not used by the
prototype because its contents are incomplete.

## Run

```sh
flutter pub get
flutter run
```

## Test

```sh
flutter test
```
