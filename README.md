# EcoYield 

EcoYield is a Flutter-based smart farming companion app focused on crop decisions, plant diagnostics, weather-aware guidance, and farm finance tools.

It combines:
- AI-assisted crop/plant support
- Live weather + location intelligence
- Crop suitability scoring
- Disease and weed identification from images
- Watering schedules with local notifications
- Market price visibility
- Risk-based insurance guidance
- Government subsidy eligibility optimization
- Monte Carlo yield simulation

---

## Table of Contents

- [Overview](#overview)
- [Core Features](#core-features)
- [Screen-by-Screen Module Map](#screen-by-screen-module-map)
- [Architecture](#architecture)
- [Data & Persistence](#data--persistence)
- [External APIs and Services](#external-apis-and-services)
- [Environment Variables](#environment-variables)
- [Permissions](#permissions)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Build & Run](#build--run)
- [Known Gaps / Notes](#known-gaps--notes)

---

## Overview

App identity in code:
- App title/branding: `Ecoyield` / `ecoyield`
- Package name in Dart imports: `cropmate`

Entry flow:
1. `main.dart` initializes Flutter bindings and attempts to load `.env`.
2. Preferred orientation is locked to portrait.
3. App starts on `SplashScreen`.
4. After splash delay, navigation transitions to `HomePage`.

Main user journey is centered around `HomePage`, with tabs and feature launch cards.

---

## Core Features

### 1) Smart Home Dashboard
- Curved bottom navigation with 3 tabs:
	- Home tools dashboard
	- My Plants collection
	- Live market prices
- Weather card with:
	- Current location name
	- Temperature, humidity, wind speed
	- Manual refresh action
- Floating assistant chat dialog powered by Groq.

### 2) Disease Detection (Image-Based)
- Capture/select plant image via camera or gallery.
- Sends multipart image request to Roboflow model.
- Displays:
	- Disease/no-disease dialog
	- Confidence
	- Visual bounding boxes over detections
- Error dialogs for network/processing failures.

### 3) Weed / Plant Identification
- Capture/select image.
- Sends base64 payload to Plant.id endpoint.
- Shows identification suggestions with probability and similar images.
- Allows adding top suggestion to personal plant collection.

### 4) My Plants Collection
- Displays saved identified plants with:
	- Name
	- Confidence
	- Added date
	- Stored local image (if available)
	- Fallback reference image
- Empty-state CTA routes to identification flow.

### 5) Watering Schedule + Reminders
- Add custom plant schedules with frequency presets.
- Optional plant image.
- Tracks last watered / next watering date.
- “Water now” updates schedule and reschedules reminders.
- Local notifications via `flutter_local_notifications` + timezone support.
- Adaptive UI for phone/tablet list/grid rendering.

### 6) Live Market Prices
- Fetches commodity pricing from backend API.
- 30-minute local cache using `SharedPreferences`.
- Pull-to-refresh for forced updates.
- Sort modes:
	- Name A–Z
	- Price low→high
	- Price high→low
- Rich card UI with min/modal/max pricing.

### 7) Crop Prediction (Location + Soil + Weather)
- Auto-acquires geolocation and reverse geocoding.
- Fetches Open-Meteo historical + forecast data.
- Scores 15 crop profiles using:
	- Temperature
	- Rainfall
	- Soil moisture
	- Soil temperature
	- Humidity
	- Seasonal fit
- Outputs ranked suitability cards and expandable details.

### 8) Insurance Optimizer
- Uses historical weather and crop risk profiles.
- Simulates losses across 500 seasons.
- Calculates:
	- Risk score
	- Expected loss
	- Premium vs payout
	- Net expected value
	- Recommended coverage
	- Verdict (`RECOMMENDED` / `MARGINAL` / `NOT RECOMMENDED`)
- Adds rule-based advisor output:
	- Summary
	- Risk factors
	- Action plan

### 9) Monte Carlo Yield Simulation
- Uses historical rainfall/temperature from Open-Meteo.
- Simulates 500 seasonal outcomes per crop/location.
- Produces:
	- Mean and percentile yield bands
	- Histogram distribution
	- Farm-total yield estimates by acreage
	- Practical advisory card


### 10) GlobalReach Community
- Community feed (GET) + Share Yield form (POST).
- Cloud-backed message stream with name/location/message model.

---

## Screen-by-Screen Module Map

### Actively wired from main navigation/home
- `splash_screen.dart`
- `home.dart`
- `disease_detection_page.dart`
- `plant_identification_page.dart`
- `plants_page.dart`
- `watering_page.dart`
- `livenarketprice.dart`
- `crop_prediction_page.dart`
- `insurance_optimizer_page.dart`
- `monte_carlo_simulation_page.dart`
- `GlobalReach.dart` (from app bar action)


### Standalone / legacy / placeholder screens
- `chat_page.dart` (legacy DeepSeek chat page; not used in current nav)
- `settings_page.dart` (static settings placeholders)
- `seasonal_care_page.dart` (placeholder)
- `soil_selection.dart` (coming soon screen)

---

## Architecture

### UI Layer
- Feature-first screen files under `lib/screens/`
- Shared UI utility under `lib/widgets/` (`GrowthStageWidget`)

### Service Layer
- `WeatherService`:
	- location permission + retrieval
	- OpenWeather integration
- `GroqService`:
	- chatbot completions endpoint

### Model Layer
- `WateringSchedule`
- `CropWateringPlan` and `GrowthStage`
- `Plant` and `PlantCollection` are currently defined inside `plant_identification_page.dart` (not extracted into `lib/models/`).

---

## Data & Persistence

`SharedPreferences` keys observed in code:
- `watering_schedules` → serialized watering schedules
- `plants` → serialized identified plants (used by `PlantCollection`)
- `identified_plants` → read by `PlantsPage` (key mismatch with `plants` write path)
- `cached_market_prices` and `cache_timestamp` → live price cache
- `isDarkMode` → theme preference (theme provider exists)

Local file storage:
- Captured plant images are copied into app documents directory in plant identification flow.

---

## External APIs and Services

### Weather & Location
- OpenWeather Current Weather + Reverse Geocoding
- Open-Meteo Archive + Forecast endpoints

### AI / Assistant
- Groq Chat Completions API
- (Legacy) DeepSeek Chat API in `chat_page.dart`

### Vision / Diagnostics
- Plant.id identification API
- Roboflow disease detection model endpoint

### Community / Prices
- Market prices backend:
	- `https://ecoyieldbackend-production.up.railway.app/api/prices`
- GlobalReach backend:
	- `https://old-mode-eb4a.neerajofficial1133.workers.dev/`

---

## Environment Variables

The app reads `.env` at startup (`main.dart`).

Expected keys in runtime code:
- `Weather` → OpenWeather API key
- `Groq` → Groq API key

Create `.env` in project root:

```env
Weather=your_openweather_api_key
Groq=your_groq_api_key
```

Note: Some screens still contain hardcoded API keys in source (see Known Gaps).

---

## Permissions

### Android (`android/app/src/main/AndroidManifest.xml`)
- `INTERNET`
- `ACCESS_FINE_LOCATION`
- `ACCESS_COARSE_LOCATION`
- `SCHEDULE_EXACT_ALARM`
- `USE_EXACT_ALARM`
- `RECEIVE_BOOT_COMPLETED`

### iOS (`ios/Runner/Info.plist`)
Current file does **not** include explicit usage descriptions for:
- location permissions
- camera/photo library permissions
- notification permissions

For iOS production, add required `NS*UsageDescription` keys before shipping.

---

## Tech Stack

- Flutter (Material 3)
- Dart
- HTTP networking: `http`
- Location: `geolocator`, `geocoding`
- Image input: `image_picker`
- Local storage: `shared_preferences`, `path_provider`
- Notifications: `flutter_local_notifications`, `timezone`
- AI integrations: `google_generative_ai` (dependency), Groq service implementation in app

---

## Project Structure

```text
lib/
	main.dart
	models/
		watering_schedule.dart
		crop_watering_plan.dart
	services/
		weather_service.dart
		groq_service.dart
	screens/
		home.dart
		splash_screen.dart
		disease_detection_page.dart
		plant_identification_page.dart
		plants_page.dart
		watering_page.dart
		livenarketprice.dart
		crop_prediction_page.dart
		insurance_optimizer_page.dart
		monte_carlo_simulation_page.dart
		subsidy_optimizer_page.dart
		GlobalReach.dart
		...
	widgets/
		growth_stage_widget.dart
```

---

## Getting Started

### 1) Install dependencies

```bash
flutter pub get
```

### 2) Configure environment

Add `.env` in project root with at least:

```env
Weather=your_openweather_api_key
Groq=your_groq_api_key
```

### 3) Run app

```bash
flutter run
```

---

## Build & Run

Common commands:

```bash
flutter clean
flutter pub get
flutter run
```

For release builds:

```bash
flutter build apk
flutter build ios
```

---

## Known Gaps / Notes

1. **API key hygiene**
	 - `plant_identification_page.dart`, `disease_detection_page.dart`, and `chat_page.dart` include hardcoded keys.
	 - Move all secrets to `.env`/secure backend before production.

2. **Plants persistence key mismatch**
	 - `PlantCollection` writes to key `plants`, while `PlantsPage` reads `identified_plants`.
	 - This can cause collection desync depending on flow.

3. **Subsidy optimizer not exposed in home UI**
	 - Navigation button is present but commented in `home.dart`.

4. **Settings/Seasonal/Soil modules are not feature-complete**
	 - `SettingsPage` actions are placeholders.
	 - `SeasonalCarePage` is a placeholder widget.
	 - `SoilSelection` is “Coming Soon”.

5. **iOS permissions metadata incomplete**
	 - Missing usage description keys required for location/camera/notifications.

---

## Maintainers

If you continue development, recommended next cleanups:
- centralize secrets management
- unify persistent storage keys
- extract `Plant`/`PlantCollection` into `lib/models/`
- wire subsidy optimizer in home tools
- add iOS permission keys and test on physical device
