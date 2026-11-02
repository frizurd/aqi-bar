<p align="center">
  <img src="docs/images/logo.png" width="112" height="112" alt="AQI Bar icon">
</p>

# AQI Bar

Air quality in your Mac’s menu bar. Pick a city and see its US AQI in the system font. The number changes color as air quality gets worse, and turns bold above 150.

![Choose a city, see its AQI, and read the colored number in the menu bar](docs/images/demo.png)

*The app views above use sample data.*

## Install

[Download AQI Bar for Apple silicon](https://github.com/frizurd/aqi-bar/releases/latest). Requires macOS 13 or later. Unzip it and move **AQI Bar.app** to Applications.

The download is ad hoc signed, not notarized by Apple. You can also build it yourself; Intel Macs need a local build.

## Set your location

1. Open AQI Bar. Settings appears on first launch.
2. Expand **IQAir API key** and paste your [free IQAir Community key](https://www.iqair.com/air-pollution-data-api).
3. Search for a city and country, then click **Use location** beside the result you want.

The app saves your choice. Click the menu bar number to see the reporting city, measurement time, and last check. You can refresh or change location from that menu.

IQAir returns the nearest supported city, which may have a different name from the place you picked. **Automatic location** uses your public IP instead; a VPN can change that result.

## Colors

| US AQI | Category | Color |
| --- | --- | --- |
| 0–50 | Good | Green |
| 51–100 | Moderate | Yellow |
| 101–150 | Unhealthy for sensitive groups | Orange |
| 151–200 | Unhealthy | Red |
| 201–300 | Very unhealthy | Purple |
| 301+ | Hazardous | Pink |

The colors come from the original SketchyBar plugin. AQI Bar runs on its own; SketchyBar isn't required.

## Refreshes and missed readings

The app checks IQAir every 15 minutes and when your Mac wakes. After a connection failure, it retries after 10, 20, and 40 seconds.

If a refresh fails, the last reading stays visible with a trailing dot: `AQI 160 ·`. The details say **Last known**. The app also marks a reading stale if it was checked over 30 minutes ago or measured over three hours ago. Changing cities clears the previous reading immediately.

## Data and API keys

Location searches go to Apple Maps. The selected coordinates go to IQAir. The app doesn't ask for device-location access.

Keys entered in Settings are saved to macOS Keychain. Your chosen location and latest reading are saved locally. If you used the original SketchyBar plugin, AQI Bar can import its existing IQAir key on first launch.

## Build

With Xcode 15 or newer installed:

```sh
git clone https://github.com/frizurd/aqi-bar.git
cd aqi-bar
./build.sh
open "build/AQI Bar.app"
```

To run the tests:

```sh
xcrun swift test --disable-sandbox
```

There are no third-party package dependencies. See [development notes](docs/development.md) for the code layout and screenshot renderer.
