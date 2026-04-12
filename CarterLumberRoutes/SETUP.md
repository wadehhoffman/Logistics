# Carter Lumber Route Planner — iOS App Setup

## Prerequisites

- Xcode 16+ (iOS 17 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (recommended) or manual Xcode project creation
- Mapbox account with access token

## Quick Start

### Option A: Using XcodeGen (Recommended)

```bash
# Install XcodeGen if not already installed
brew install xcodegen

# Generate the Xcode project
cd CarterLumberRoutes
xcodegen generate

# Open in Xcode
open CarterLumberRoutes.xcodeproj
```

### Option B: Manual Xcode Project

1. Open Xcode → File → New Project → iOS → App
2. Product Name: `CarterLumberRoutes`
3. Interface: SwiftUI, Language: Swift
4. Minimum Deployment: iOS 17.0
5. Delete the auto-generated ContentView.swift and CarterLumberRoutesApp.swift
6. Drag the `CarterLumberRoutes/` source folder into the project navigator
7. Add SPM dependencies (see below)

## Mapbox Setup

1. Create a Mapbox account at [mapbox.com](https://www.mapbox.com)
2. Get your **public access token** from [account.mapbox.com](https://account.mapbox.com/access-tokens/)
3. Replace `YOUR_MAPBOX_PUBLIC_TOKEN_HERE` in `Info.plist` with your token

### For Mapbox SDK via SPM (when adding Mapbox Maps SDK):

Add to `~/.netrc`:
```
machine api.mapbox.com
login mapbox
password sk.eyJ1Ijoi...YOUR_SECRET_TOKEN...
```

Then in Xcode: File → Add Package Dependencies → `https://github.com/mapbox/mapbox-maps-ios.git`

> **Note:** The current implementation uses Apple MapKit as the map provider. To switch to Mapbox Maps SDK, add the SPM package and update `MapContainerView.swift` to use `UIViewRepresentable` wrapping `MapboxMaps.MapView`.

## SPM Dependencies

Add these in Xcode → File → Add Package Dependencies:

| Package | URL | Version |
|---------|-----|---------|
| KeychainAccess | `https://github.com/kishikawakatsumi/KeychainAccess.git` | 4.2+ |

## Configuration

### EIA API Key (Diesel Pricing)
1. Get a free API key at [eia.gov/opendata](https://www.eia.gov/opendata/)
2. Enter it in the app's Settings tab

### IntelliShift (Truck Tracking)
The app connects to your Node.js proxy server for IntelliShift data.
1. Start the Node.js server: `node server.js` (in the project root)
2. In the app Settings, set the server URL (default: `http://localhost:3003`)
3. For testing on a physical device, use your Mac's local IP (e.g., `http://192.168.1.100:3003`)

## Project Structure

```
CarterLumberRoutes/
├── App/                    # App entry point + configuration
├── Models/                 # Data models (Mill, Yard, Vehicle, Route, etc.)
├── Services/               # API clients (Routing, Geocoding, Diesel, Weather, IntelliShift)
├── ViewModels/             # MVVM view models
├── Views/                  # SwiftUI views organized by feature
│   ├── Route/              # Single route planning
│   ├── TruckRoute/         # 2-leg truck routing
│   ├── Batch/              # Batch route calculator
│   ├── Map/                # Map container
│   └── Settings/           # App settings
├── Resources/              # Bundled JSON data + assets
│   ├── mills.json          # 58 mill/supplier locations
│   └── yards.json          # 238 yard locations
├── Utilities/              # Helpers (Haversine, formatting)
└── Extensions/             # Swift extensions
```

## Features

- **Single Route**: Select mill + yard → route on map with distance/time
- **Truck Route**: Select truck + mill + yard → 2-leg route (truck→mill→yard)
- **Batch Calculator**: One or all mills to all yards with CSV export
- **Diesel Pricing**: EIA API integration with per-state cost breakdown
- **Weather**: Open-Meteo weather at 5 points along route
- **Traffic**: Real-time traffic layer toggle on map
