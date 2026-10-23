# ASA Cebu

A Flutter indoor-place discovery prototype inspired by the supplied mobile app
reference. The app includes Home, Map, and Settings tabs, a sample SM Seaside
map, and a map editor for adding floor plans and labeled navigation spots.

## Create a map

1. Admin map management is hidden by default. Tap the **Settings** tab or
   Settings heading 10 times, then sign in with a Gmail and password for an
   existing Supabase Auth user. The app checks the credentials with Supabase;
   accounts that do not exist or have the wrong password cannot enter admin
   mode. The auth session persists on the device and is restored on later app
   launches. In Supabase, create the account and enable email/password sign-in.
   The app's publishable key is intended for client use; never put a Supabase
   secret or service-role key in the app. Email/password authentication controls
   the app UI, but local map files are not protected from device owners
   modifying app data.
2. In the admin-only **Settings → Maps** section, select an existing map to
   edit it, or choose **Create map**.
3. Enter a map name and upload a floor-plan image from the device gallery.
   Select **Add floor** for each additional level and give it a name.
4. Enter the mall's latitude, longitude, and geofence radius in meters.
5. Select **Add spot**, tap the active floor plan, give the point a label, and
   choose Pathway, Stores, Restroom, Escalators, Elevators, Stairs, or Custom.
   Stores and custom nodes require labels; Custom also lets you name the node
   type.
6. Select **Connect spots**, then tap two spots in sequence to draw a path.
   To connect floors, switch floors while in Connect spots mode and connect
   matching elevator, escalator, or stairs nodes between levels.
7. For a better-scaled live GPS dot during navigation, optionally enter the
   floor plan's real width and height. If you leave them blank, the app uses
   the mall's GPS coordinates as the floor-plan center and the geofence radius
   to estimate the map scale. The plan is assumed north-up. No GPS setup is
   needed to create spots or paths.
8. Tap a spot in **Add spot** mode to rename or delete it, then save the map.

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
through the map's saved connections and highlights it on the selected floor
plan. Switch floors to inspect each leg of a multi-floor route.
Select **Start navigation** to check the device's location against the mall's
geofence and display a blue dot using live GPS updates. The mall's coordinates
anchor the center of the floor plan. Entered floor dimensions give a better
scale; otherwise the geofence radius estimates it. Indoor GPS and this fallback
scale can be inaccurate. Maps need mall coordinates, a radius, and connected
spots for live route tracking. The map image is assumed to be north-up.

The included sample mall is for route-planning demos. Add its GPS coordinates
and geofence radius in the editor before starting live location navigation.

Admins can delete saved maps from **Settings → Maps**; deleting a map also
removes its copied floor-plan images from the device.

The existing `assests/data/sm_seaside.json` is intentionally not used by the
prototype because its contents are incomplete.
The editable SM Seaside sample currently has no bundled floor-plan image; add
one from the editor to give it an image preview.

## Run

```sh
flutter pub get
flutter run
```

## Test

```sh
flutter test
```
