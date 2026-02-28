import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens — home screen green theme
// ─────────────────────────────────────────────────────────────────────────────

const _kGreen1    = Color(0xFF43A047);
const _kGreen2    = Color(0xFF66BB6A);
const _kGreenDark = Color(0xFF2E7D32);
const _kGreenMid  = Color(0xFF388E3C);
const _kGreenSoft = Color(0xFFE8F5E9);
const _kBg        = Color(0xFFF1F8F1);
const _kSurface   = Color(0xFFFFFFFF);
const _kAmber     = Color(0xFFF57C00);
const _kAmberSoft = Color(0xFFFFF3E0);
const _kRed       = Color(0xFFC62828);
const _kRedSoft   = Color(0xFFFFEBEE);
const _kBorder    = Color(0xFFC8E6C9);

// ─────────────────────────────────────────────────────────────────────────────
// Crop profiles — 15 crops with complete requirement data
// ─────────────────────────────────────────────────────────────────────────────

class _CropProfile {
  final String name, emoji, localName, category;
  final Color color;

  // Temperature requirements (°C)
  final double tempMin, tempIdealLow, tempIdealHigh, tempMax;

  // Annual rainfall requirements (mm)
  final double rainMin, rainIdealLow, rainIdealHigh, rainMax;

  // Soil moisture (0–1 fraction, 0–7 cm depth from Open-Meteo)
  final double soilMoistMin, soilMoistIdeal, soilMoistMax;

  // Soil temperature (°C, 6 cm depth)
  final double soilTempMin, soilTempMax;

  // Humidity (%)
  final double humidMin, humidMax;

  // Season hint (month range where planting makes sense)
  final List<int> plantingMonths;

  // Short why-good / why-bad explanation
  final String goodNote, badNote;

  const _CropProfile({
    required this.name,
    required this.emoji,
    required this.localName,
    required this.category,
    required this.color,
    required this.tempMin, required this.tempIdealLow,
    required this.tempIdealHigh, required this.tempMax,
    required this.rainMin, required this.rainIdealLow,
    required this.rainIdealHigh, required this.rainMax,
    required this.soilMoistMin, required this.soilMoistIdeal, required this.soilMoistMax,
    required this.soilTempMin, required this.soilTempMax,
    required this.humidMin, required this.humidMax,
    required this.plantingMonths,
    required this.goodNote, required this.badNote,
  });
}

const _kCrops = <_CropProfile>[
  // ── IMPORTANT: soilMoist values are in Open-Meteo native units: m³/m³
  // Typical real-world range: 0.05 (very dry) → 0.45 (saturated/waterlogged)
  // Kerala monsoon soil typically reads 0.30–0.42 m³/m³ from the API.
  // DO NOT use percentage-like values (0.30–0.80) here — those are 6–10× too high
  // and will always make soilMoisture score = 0% on the detail screen.
  _CropProfile(
    name: 'Rice (Paddy)', emoji: '🌾', localName: 'Njavara / Jaya / Uma', category: 'Cereal',
    color: Color(0xFF2E7D32),
    tempMin: 20, tempIdealLow: 24, tempIdealHigh: 32, tempMax: 38,
    rainMin: 1200, rainIdealLow: 1800, rainIdealHigh: 3000, rainMax: 5500,
    soilMoistMin: 0.28, soilMoistIdeal: 0.38, soilMoistMax: 0.50,
    soilTempMin: 22, soilTempMax: 36,
    humidMin: 65, humidMax: 98,
    plantingMonths: [5, 6, 7, 8, 9],
    goodNote: "Alappuzha's backwaters and heavy monsoon make this the No.1 crop here.",
    badNote: "Needs flooded fields — well matched to Kerala's wetlands.",
  ),
  _CropProfile(
    name: 'Coconut', emoji: '🥥', localName: 'Thenga', category: 'Plantation',
    color: Color(0xFF558B2F),
    tempMin: 22, tempIdealLow: 27, tempIdealHigh: 34, tempMax: 40,
    rainMin: 1200, rainIdealLow: 1800, rainIdealHigh: 3000, rainMax: 5000,
    soilMoistMin: 0.18, soilMoistIdeal: 0.28, soilMoistMax: 0.42,
    soilTempMin: 24, soilTempMax: 38,
    humidMin: 70, humidMax: 98,
    plantingMonths: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
    goodNote: "Kerala's most iconic crop — thrives in coastal humid heat.",
    badNote: 'Needs well-drained but moisture-retaining laterite soil.',
  ),
  _CropProfile(
    name: 'Banana', emoji: '🍌', localName: 'Nendran / Palayamkodan', category: 'Fruit',
    color: Color(0xFFF9A825),
    tempMin: 20, tempIdealLow: 26, tempIdealHigh: 35, tempMax: 40,
    rainMin: 1200, rainIdealLow: 1800, rainIdealHigh: 2800, rainMax: 4500,
    soilMoistMin: 0.22, soilMoistIdeal: 0.32, soilMoistMax: 0.44,
    soilTempMin: 22, soilTempMax: 36,
    humidMin: 70, humidMax: 98,
    plantingMonths: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
    goodNote: 'Nendran banana is a prized Kerala variety — perfect climate match.',
    badNote: 'Avoid waterlogged lowlands; raised beds improve drainage.',
  ),
  _CropProfile(
    name: 'Tapioca', emoji: '🫚', localName: 'Kappa / Cassava', category: 'Tuber',
    color: Color(0xFF8D6E63),
    tempMin: 20, tempIdealLow: 25, tempIdealHigh: 35, tempMax: 40,
    rainMin: 1000, rainIdealLow: 1500, rainIdealHigh: 2500, rainMax: 4000,
    soilMoistMin: 0.15, soilMoistIdeal: 0.25, soilMoistMax: 0.40,
    soilTempMin: 22, soilTempMax: 36,
    humidMin: 60, humidMax: 95,
    plantingMonths: [4, 5, 6, 10, 11],
    goodNote: "Kappa is Kerala's staple — thrives in humid uplands and midlands.",
    badNote: 'Avoid waterlogging; does best on well-drained slopes.',
  ),
  _CropProfile(
    name: 'Black Pepper', emoji: '🌿', localName: 'Kurumulaku', category: 'Spice',
    color: Color(0xFF37474F),
    tempMin: 22, tempIdealLow: 26, tempIdealHigh: 34, tempMax: 40,
    rainMin: 1500, rainIdealLow: 2000, rainIdealHigh: 3000, rainMax: 4500,
    soilMoistMin: 0.20, soilMoistIdeal: 0.30, soilMoistMax: 0.42,
    soilTempMin: 24, soilTempMax: 36,
    humidMin: 70, humidMax: 98,
    plantingMonths: [5, 6, 7],
    goodNote: 'Kerala is the spice capital — black pepper loves this climate.',
    badNote: 'Needs support trees (like arecanut) and well-drained soil.',
  ),
  _CropProfile(
    name: 'Arecanut', emoji: '🌴', localName: 'Adakka / Betel Nut', category: 'Plantation',
    color: Color(0xFF6D4C41),
    tempMin: 22, tempIdealLow: 26, tempIdealHigh: 35, tempMax: 40,
    rainMin: 1500, rainIdealLow: 2000, rainIdealHigh: 3000, rainMax: 4500,
    soilMoistMin: 0.20, soilMoistIdeal: 0.30, soilMoistMax: 0.42,
    soilTempMin: 24, soilTempMax: 36,
    humidMin: 70, humidMax: 98,
    plantingMonths: [4, 5, 6, 7],
    goodNote: "Widely grown across Kerala's midlands — ideal humidity match.",
    badNote: 'Susceptible to yellow leaf disease in poorly drained soils.',
  ),
  _CropProfile(
    name: 'Turmeric', emoji: '🟡', localName: 'Manjal', category: 'Spice',
    color: Color(0xFFF57F17),
    tempMin: 22, tempIdealLow: 26, tempIdealHigh: 35, tempMax: 40,
    rainMin: 1200, rainIdealLow: 1800, rainIdealHigh: 2500, rainMax: 3500,
    soilMoistMin: 0.20, soilMoistIdeal: 0.30, soilMoistMax: 0.42,
    soilTempMin: 24, soilTempMax: 36,
    humidMin: 65, humidMax: 92,
    plantingMonths: [4, 5, 6],
    goodNote: 'Hot humid monsoon conditions are perfect for turmeric.',
    badNote: 'Waterlogging rots the rhizomes — raised beds recommended.',
  ),
  _CropProfile(
    name: 'Ginger', emoji: '🫚', localName: 'Inji', category: 'Spice',
    color: Color(0xFFFFB300),
    tempMin: 22, tempIdealLow: 25, tempIdealHigh: 35, tempMax: 40,
    rainMin: 1200, rainIdealLow: 1800, rainIdealHigh: 2500, rainMax: 3500,
    soilMoistMin: 0.22, soilMoistIdeal: 0.32, soilMoistMax: 0.43,
    soilTempMin: 24, soilTempMax: 36,
    humidMin: 65, humidMax: 92,
    plantingMonths: [4, 5, 6],
    goodNote: "Kerala's warm humid summers produce excellent quality ginger.",
    badNote: 'Shade partial shade during hot summer months to avoid leaf burn.',
  ),
  _CropProfile(
    name: 'Rubber', emoji: '🌳', localName: 'Rubber', category: 'Plantation',
    color: Color(0xFF546E7A),
    tempMin: 22, tempIdealLow: 26, tempIdealHigh: 34, tempMax: 40,
    rainMin: 1500, rainIdealLow: 2000, rainIdealHigh: 3000, rainMax: 4500,
    soilMoistMin: 0.20, soilMoistIdeal: 0.29, soilMoistMax: 0.42,
    soilTempMin: 24, soilTempMax: 36,
    humidMin: 70, humidMax: 98,
    plantingMonths: [4, 5, 6, 7],
    goodNote: "Kerala accounts for 90% of India's rubber — climate is perfectly suited.",
    badNote: 'Not suitable for waterlogged or very shallow soils.',
  ),
  _CropProfile(
    name: 'Jackfruit', emoji: '🍈', localName: 'Chakka', category: 'Fruit',
    color: Color(0xFF9E7D1A),
    tempMin: 22, tempIdealLow: 26, tempIdealHigh: 35, tempMax: 40,
    rainMin: 1200, rainIdealLow: 1800, rainIdealHigh: 2800, rainMax: 4500,
    soilMoistMin: 0.18, soilMoistIdeal: 0.28, soilMoistMax: 0.42,
    soilTempMin: 22, soilTempMax: 36,
    humidMin: 65, humidMax: 98,
    plantingMonths: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
    goodNote: "Kerala's state fruit — grows effortlessly in backyard gardens.",
    badNote: 'Young trees need protection from strong monsoon winds.',
  ),
  _CropProfile(
    name: 'Vegetables (Mixed)', emoji: '🥬', localName: 'Patchakkari', category: 'Vegetable',
    color: Color(0xFF43A047),
    tempMin: 22, tempIdealLow: 25, tempIdealHigh: 33, tempMax: 38,
    rainMin: 800, rainIdealLow: 1200, rainIdealHigh: 2500, rainMax: 4000,
    soilMoistMin: 0.18, soilMoistIdeal: 0.27, soilMoistMax: 0.40,
    soilTempMin: 22, soilTempMax: 35,
    humidMin: 60, humidMax: 92,
    plantingMonths: [1, 2, 9, 10, 11, 12],
    goodNote: 'Bitter gourd, snake gourd, cowpea, amaranth all thrive here.',
    badNote: 'Use raised beds during heavy monsoon to prevent waterlogging.',
  ),
  _CropProfile(
    name: 'Sugarcane', emoji: '🎋', localName: 'Karimbu', category: 'Cash Crop',
    color: Color(0xFF7B1FA2),
    tempMin: 22, tempIdealLow: 26, tempIdealHigh: 35, tempMax: 42,
    rainMin: 1000, rainIdealLow: 1600, rainIdealHigh: 3000, rainMax: 5000,
    soilMoistMin: 0.20, soilMoistIdeal: 0.30, soilMoistMax: 0.44,
    soilTempMin: 22, soilTempMax: 38,
    humidMin: 65, humidMax: 95,
    plantingMonths: [1, 2, 10, 11],
    goodNote: "Grows well in Kerala's lowland areas with adequate drainage.",
    badNote: 'Waterlogging during monsoon is the key risk.',
  ),
  _CropProfile(
    name: 'Pineapple', emoji: '🍍', localName: 'Kaitha Chakka', category: 'Fruit',
    color: Color(0xFFE65100),
    tempMin: 22, tempIdealLow: 25, tempIdealHigh: 34, tempMax: 38,
    rainMin: 1000, rainIdealLow: 1500, rainIdealHigh: 2500, rainMax: 3500,
    soilMoistMin: 0.14, soilMoistIdeal: 0.23, soilMoistMax: 0.36,
    soilTempMin: 22, soilTempMax: 34,
    humidMin: 60, humidMax: 90,
    plantingMonths: [4, 5, 6, 10, 11],
    goodNote: 'Vazhakulam pineapple is famous — midland Kerala is ideal.',
    badNote: 'Does not tolerate waterlogged soils; needs well-drained land.',
  ),
  _CropProfile(
    name: 'Wheat', emoji: '🌾', localName: 'Gothambu', category: 'Cereal',
    color: Color(0xFFD4860A),
    tempMin: 5, tempIdealLow: 10, tempIdealHigh: 22, tempMax: 30,
    rainMin: 300, rainIdealLow: 500, rainIdealHigh: 900, rainMax: 1400,
    soilMoistMin: 0.08, soilMoistIdeal: 0.18, soilMoistMax: 0.30,
    soilTempMin: 8, soilTempMax: 24,
    humidMin: 35, humidMax: 68,
    plantingMonths: [10, 11, 12],
    goodNote: "Grows well in north India's cool dry winters.",
    badNote: 'Kerala is too hot, too wet and too humid for wheat — not recommended.',
  ),
  _CropProfile(
    name: 'Groundnut', emoji: '🥜', localName: 'Kadala / Nilakadala', category: 'Oilseed',
    color: Color(0xFF8D6E63),
    tempMin: 18, tempIdealLow: 24, tempIdealHigh: 33, tempMax: 40,
    rainMin: 400, rainIdealLow: 600, rainIdealHigh: 1000, rainMax: 1400,
    soilMoistMin: 0.10, soilMoistIdeal: 0.18, soilMoistMax: 0.28,
    soilTempMin: 20, soilTempMax: 34,
    humidMin: 45, humidMax: 72,
    plantingMonths: [5, 6],
    goodNote: 'Suits sandy loam soils in dry climates.',
    badNote: "Kerala's excess rainfall and humidity cause pod rot — not suitable.",
  ),
  _CropProfile(
    name: 'Onion', emoji: '🧅', localName: 'Savola / Ulli', category: 'Vegetable',
    color: Color(0xFFAD1457),
    tempMin: 10, tempIdealLow: 15, tempIdealHigh: 24, tempMax: 32,
    rainMin: 300, rainIdealLow: 500, rainIdealHigh: 750, rainMax: 1000,
    soilMoistMin: 0.10, soilMoistIdeal: 0.17, soilMoistMax: 0.26,
    soilTempMin: 12, soilTempMax: 26,
    humidMin: 35, humidMax: 65,
    plantingMonths: [10, 11, 12],
    goodNote: 'Thrives in cool dry weather.',
    badNote: "Kerala's high humidity causes neck rot — not commercially viable here.",
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class _FieldConditions {
  final double lat, lon;
  final String placeName, district, state, country;
  final double currentTemp, currentHumidity, currentWindSpeed;
  final String currentWeatherDesc;
  final double rain30d, avgTemp30d, estimatedAnnualRain;
  final double forecast16Rain, forecastAvgTemp;
  final double soilMoisture, soilTemp;
  final bool soilDataAvailable;   // false → fallback values were used
  final int currentMonth;
  final String season;

  _FieldConditions({
    required this.lat, required this.lon,
    required this.placeName, required this.district,
    required this.state, required this.country,
    required this.currentTemp, required this.currentHumidity,
    required this.currentWindSpeed, required this.currentWeatherDesc,
    required this.rain30d, required this.avgTemp30d,
    required this.estimatedAnnualRain,
    required this.forecast16Rain, required this.forecastAvgTemp,
    required this.soilMoisture, required this.soilTemp,
    this.soilDataAvailable = true,
    required this.currentMonth, required this.season,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Crop suitability score
// ─────────────────────────────────────────────────────────────────────────────

class _CropScore {
  final _CropProfile crop;
  final double score;
  final String label;
  final Color labelColor;
  final String primaryReason;
  final List<_ScoreFactor> factors;
  final bool isDisqualified;

  const _CropScore({
    required this.crop, required this.score, required this.label,
    required this.labelColor, required this.primaryReason,
    required this.factors,
    this.isDisqualified = false,
  });
}

class _ScoreFactor {
  final String name, emoji;
  final double score;
  final String note;
  final Color color;
  const _ScoreFactor(this.name, this.emoji, this.score, this.note, this.color);
}

// ─────────────────────────────────────────────────────────────────────────────
// Location + weather service
// ─────────────────────────────────────────────────────────────────────────────

class _FieldService {
  static Future<_FieldConditions> fetchAll() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception('Location services are disabled on your device.');

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission not granted. Please allow location access.');
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    ).timeout(const Duration(seconds: 15));

    final lat = pos.latitude;
    final lon = pos.longitude;

    String placeName = 'Your Location', district = '', state = '', country = '';
    try {
      final placemarks = await placemarkFromCoordinates(lat, lon)
          .timeout(const Duration(seconds: 8));
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        placeName = p.locality ?? p.subLocality ?? p.administrativeArea ?? 'Your Location';
        district  = p.subAdministrativeArea ?? '';
        state     = p.administrativeArea ?? '';
        country   = p.country ?? '';
      }
    } catch (_) {}

    final now       = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    final d30Start  = now.subtract(const Duration(days: 30));
    final d365Start = DateTime(now.year - 1, now.month, now.day);

    String fmtDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

    final archiveFut = http.get(Uri.parse(
      'https://archive-api.open-meteo.com/v1/archive'
      '?latitude=$lat&longitude=$lon'
      '&start_date=${fmtDate(d365Start)}&end_date=${fmtDate(yesterday)}'
      '&daily=precipitation_sum,temperature_2m_mean,relative_humidity_2m_mean'
      '&timezone=auto',
    )).timeout(const Duration(seconds: 25));

    final forecastFut = http.get(Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat&longitude=$lon'
      '&current=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code'
      '&daily=precipitation_sum,temperature_2m_mean'
      '&hourly=soil_temperature_6cm,soil_moisture_0_to_7cm'
      '&forecast_days=16'
      '&timezone=auto',
    )).timeout(const Duration(seconds: 20));

    final responses = await Future.wait([archiveFut, forecastFut]);
    final archRes   = responses[0];
    final fcstRes   = responses[1];

    double annualRain = 0, avgTemp365 = 0, rain30d = 0, avgTemp30d = 0;
    if (archRes.statusCode == 200) {
      final bd    = jsonDecode(archRes.body)['daily'];
      final dates = (bd['time'] as List).map((e) => e as String).toList();
      final rains = (bd['precipitation_sum'] as List)
          .whereType<num>().map((v) => v.toDouble()).toList();
      final temps = (bd['temperature_2m_mean'] as List)
          .whereType<num>().map((v) => v.toDouble()).toList();

      final d30str = fmtDate(d30Start);
      double tempSum365 = 0, tempSum30d = 0; int cnt30 = 0;
      for (int i = 0; i < rains.length; i++) {
        annualRain += rains[i];
        if (i < temps.length) tempSum365 += temps[i];
        if (i < dates.length && dates[i].compareTo(d30str) >= 0) {
          rain30d   += rains[i];
          if (i < temps.length) tempSum30d += temps[i];
          cnt30++;
        }
      }
      avgTemp365 = temps.isNotEmpty ? tempSum365 / temps.length : 0;
      avgTemp30d = cnt30 > 0 ? tempSum30d / cnt30 : avgTemp365;
    }

    double currentTemp = 0, currentHumidity = 0, currentWind = 0;
    String weatherDesc = 'Clear skies';
    double forecast16Rain = 0, forecastAvgTemp = 0;
    double soilMoisture = 0.0, soilTemp = 28.0;
    bool soilDataAvailable = false;

    if (fcstRes.statusCode == 200) {
      final fc = jsonDecode(fcstRes.body);
      final cur = fc['current'];
      currentTemp     = (cur['temperature_2m']      as num?)?.toDouble() ?? 0;
      currentHumidity = (cur['relative_humidity_2m'] as num?)?.toDouble() ?? 0;
      currentWind     = (cur['wind_speed_10m']       as num?)?.toDouble() ?? 0;
      final wCode     = (cur['weather_code']         as num?)?.toInt() ?? 0;
      weatherDesc     = _weatherCodeToText(wCode);

      final fcd = fc['daily'];
      final fr  = (fcd['precipitation_sum'] as List)
          .whereType<num>().map((v) => v.toDouble()).toList();
      final ft  = (fcd['temperature_2m_mean'] as List)
          .whereType<num>().map((v) => v.toDouble()).toList();
      forecast16Rain  = fr.fold(0.0, (double a, double b) => a + b);
      forecastAvgTemp = ft.isEmpty ? currentTemp
          : ft.fold(0.0, (double a, double b) => a + b) / ft.length;

      final hourly = fc['hourly'];

      // Open-Meteo hourly arrays have 384 entries (16 days × 24 h).
      // Future hours and some soil variables can be null in the JSON.
      // This helper picks the current hour's value first, then scans
      // forward for the first non-null, returning null if all are null.
      double? firstNonNull(List<dynamic> raw) {
        if (raw.isEmpty) return null;
        final hourIdx = now.hour.clamp(0, raw.length - 1);
        if (raw[hourIdx] != null) return (raw[hourIdx] as num).toDouble();
        for (int i = 0; i < min(24, raw.length); i++) {
          if (raw[i] != null) return (raw[i] as num).toDouble();
        }
        for (int i = 0; i < raw.length; i++) {
          if (raw[i] != null) return (raw[i] as num).toDouble();
        }
        return null;
      }

      final rawSt = hourly['soil_temperature_6cm']   as List? ?? [];
      final rawSm = hourly['soil_moisture_0_to_7cm'] as List? ?? [];

      final realSt = firstNonNull(rawSt);
      final realSm = firstNonNull(rawSm);

      soilTemp     = realSt ?? 28.0;   // 28 °C — typical Kerala soil
      soilMoisture = realSm ?? 0.25;   // 0.25 m³/m³ — typical Kerala
      soilDataAvailable = (realSt != null && realSm != null);
    }

    final month  = now.month;
    String season;
    if (month >= 6 && month <= 10)       season = 'Kharif (Monsoon)';
    else if (month >= 11 || month <= 3)  season = 'Rabi (Winter)';
    else                                 season = 'Zaid (Summer)';

    return _FieldConditions(
      lat: lat, lon: lon,
      placeName: placeName, district: district, state: state, country: country,
      currentTemp: currentTemp, currentHumidity: currentHumidity,
      currentWindSpeed: currentWind, currentWeatherDesc: weatherDesc,
      rain30d: rain30d, avgTemp30d: avgTemp30d,
      estimatedAnnualRain: annualRain,
      forecast16Rain: forecast16Rain, forecastAvgTemp: forecastAvgTemp,
      soilMoisture: soilMoisture.clamp(0.0, 1.0),
      soilTemp: soilTemp,
      soilDataAvailable: soilDataAvailable,
      currentMonth: month, season: season,
    );
  }

  static String _weatherCodeToText(int code) {
    if (code == 0) return 'Clear skies';
    if (code <= 3) return 'Partly cloudy';
    if (code <= 49) return 'Foggy / misty';
    if (code <= 67) return 'Rainy';
    if (code <= 77) return 'Snowy';
    if (code <= 82) return 'Showers';
    return 'Thunderstorms';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scoring engine
// ─────────────────────────────────────────────────────────────────────────────

class _ScoringEngine {
  static List<_CropScore> score(_FieldConditions c) {
    final scores = <_CropScore>[];
    for (final crop in _kCrops) {
      scores.add(_scoreCrop(crop, c));
    }
    scores.sort((a, b) => b.score.compareTo(a.score));
    return scores;
  }

  static double _curve(double v, double absMin, double idealLow,
      double idealHigh, double absMax) {
    if (v <= absMin || v >= absMax) return 0.0;
    if (v >= idealLow && v <= idealHigh) return 1.0;
    if (v < idealLow) return (v - absMin) / (idealLow - absMin);
    return (absMax - v) / (absMax - idealHigh);
  }

  static String? _hardStop(_CropProfile crop, _FieldConditions c) {
    if (c.currentHumidity > crop.humidMax + 5) {
      return 'Humidity too high — '
          '${c.currentHumidity.toStringAsFixed(0)}% vs max ${crop.humidMax.toStringAsFixed(0)}%';
    }
    if (c.estimatedAnnualRain > crop.rainMax * 1.15) {
      return 'Too much annual rain — '
          '${c.estimatedAnnualRain.toStringAsFixed(0)} mm vs max ${crop.rainMax.toStringAsFixed(0)} mm';
    }
    if (c.estimatedAnnualRain < crop.rainMin * 0.5) {
      return 'Too little annual rain — '
          '${c.estimatedAnnualRain.toStringAsFixed(0)} mm vs min ${crop.rainMin.toStringAsFixed(0)} mm';
    }
    if (c.avgTemp30d > crop.tempMax + 2) {
      return 'Temperature too high — '
          '${c.avgTemp30d.toStringAsFixed(1)}°C vs max ${crop.tempMax.toStringAsFixed(0)}°C';
    }
    if (c.avgTemp30d < crop.tempMin - 2) {
      return 'Temperature too low — '
          '${c.avgTemp30d.toStringAsFixed(1)}°C vs min ${crop.tempMin.toStringAsFixed(0)}°C';
    }
    return null;
  }

  static _CropScore _scoreCrop(_CropProfile crop, _FieldConditions c) {
    final tempScore = _curve(
        c.avgTemp30d,
        crop.tempMin - 1, crop.tempIdealLow, crop.tempIdealHigh, crop.tempMax + 1);

    final rainScore = _curve(
        c.estimatedAnnualRain,
        crop.rainMin, crop.rainIdealLow, crop.rainIdealHigh, crop.rainMax);

    // soilMoisture from Open-Meteo is m³/m³ (e.g. 0.05–0.45).
    // Guard so idealLow < idealHigh even if profile values are tight.
    final smIdealLow  = (crop.soilMoistIdeal - 0.04).clamp(crop.soilMoistMin, crop.soilMoistMax - 0.02);
    final smIdealHigh = (crop.soilMoistIdeal + 0.06).clamp(smIdealLow + 0.01, crop.soilMoistMax);
    final smScore = _curve(
        c.soilMoisture,
        crop.soilMoistMin, smIdealLow, smIdealHigh, crop.soilMoistMax);

    double stScore;
    if (c.soilTemp >= crop.soilTempMin && c.soilTemp <= crop.soilTempMax) {
      stScore = 1.0;
    } else if (c.soilTemp < crop.soilTempMin) {
      stScore = ((c.soilTemp - (crop.soilTempMin - 6)) / 6).clamp(0.0, 1.0);
    } else {
      stScore = (((crop.soilTempMax + 6) - c.soilTemp) / 6).clamp(0.0, 1.0);
    }

    double humScore;
    if (c.currentHumidity >= crop.humidMin && c.currentHumidity <= crop.humidMax) {
      humScore = 1.0;
    } else if (c.currentHumidity < crop.humidMin) {
      humScore = ((c.currentHumidity - (crop.humidMin - 15)) / 15).clamp(0.0, 1.0);
    } else {
      final excess = c.currentHumidity - crop.humidMax;
      humScore = (1.0 - (excess / 20.0)).clamp(0.0, 1.0);
    }

    final inSeason   = crop.plantingMonths.contains(c.currentMonth);
    final seasonMult = inSeason ? 1.0 : 0.80;

    final stopReason = _hardStop(crop, c);

    double total;
    String primaryReason;

    if (stopReason != null) {
      total         = (tempScore * rainScore * humScore * 30.0).clamp(0.0, 18.0);
      primaryReason = '🚫 Not suitable here — $stopReason. ${crop.badNote}';
    } else {
      final climateCore = tempScore * rainScore;
      final total_raw =
          climateCore * 0.50 +
          humScore    * 0.20 +
          smScore     * 0.15 +
          stScore     * 0.10 +
          (inSeason ? 0.05 : 0.0);

      total = (total_raw * 100 * seasonMult).clamp(0.0, 100.0);

      final factorNames  = [
        '🌡 Temperature', '🌧 Rainfall', '💦 Humidity',
        '💧 Soil Moisture', '🌱 Soil Temp'
      ];
      final factorVals = [tempScore, rainScore, humScore, smScore, stScore];
      int worstIdx = 0;
      for (int i = 1; i < factorVals.length; i++) {
        if (factorVals[i] < factorVals[worstIdx]) worstIdx = i;
      }
      if (total >= 72) {
        primaryReason = crop.goodNote;
      } else if (factorVals[worstIdx] < 0.45) {
        primaryReason =
            '${factorNames[worstIdx]} is the limiting factor. ${crop.badNote}';
      } else {
        primaryReason = crop.badNote;
      }
    }

    String label; Color labelColor;
    if (total >= 72)      { label = 'Excellent'; labelColor = _kGreenDark; }
    else if (total >= 52) { label = 'Good';      labelColor = _kGreenMid;  }
    else if (total >= 30) { label = 'Fair';      labelColor = _kAmber;     }
    else                  { label = 'Poor';      labelColor = _kRed;       }

    final factors = [
      _mkFactor('Temperature', '🌡', tempScore,
          '${c.avgTemp30d.toStringAsFixed(1)}°C  ·  ideal ${crop.tempIdealLow.toStringAsFixed(0)}–${crop.tempIdealHigh.toStringAsFixed(0)}°C'),
      _mkFactor('Annual Rainfall', '🌧', rainScore,
          '${c.estimatedAnnualRain.toStringAsFixed(0)} mm  ·  ideal ${crop.rainIdealLow.toStringAsFixed(0)}–${crop.rainIdealHigh.toStringAsFixed(0)} mm'),
      _mkFactor('Humidity', '💦', humScore,
          '${c.currentHumidity.toStringAsFixed(0)}%  ·  ideal ${crop.humidMin.toStringAsFixed(0)}–${crop.humidMax.toStringAsFixed(0)}%'),
      _mkFactor('Soil Moisture', '💧', smScore,
          '${(c.soilMoisture * 100).toStringAsFixed(1)}% (${c.soilMoisture.toStringAsFixed(3)} m³/m³)  ·  ideal ${(crop.soilMoistIdeal * 100).toStringAsFixed(0)}%'),
      _mkFactor('Soil Temp', '🌱', stScore,
          '${c.soilTemp.toStringAsFixed(1)}°C  ·  ideal ${crop.soilTempMin.toStringAsFixed(0)}–${crop.soilTempMax.toStringAsFixed(0)}°C'),
    ];

    return _CropScore(
      crop: crop,
      score: total,
      label: label,
      labelColor: labelColor,
      primaryReason: primaryReason,
      factors: factors,
      isDisqualified: stopReason != null,
    );
  }

  static _ScoreFactor _mkFactor(
      String name, String emoji, double score, String note) {
    final col = score >= 0.70 ? _kGreenDark
              : score >= 0.45 ? _kAmber
              : _kRed;
    return _ScoreFactor(name, emoji, score.clamp(0.0, 1.0), note, col);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page widget
// ─────────────────────────────────────────────────────────────────────────────

class CropPredictionPage extends StatefulWidget {
  const CropPredictionPage({Key? key}) : super(key: key);
  @override
  State<CropPredictionPage> createState() => _CropPredState();
}

class _CropPredState extends State<CropPredictionPage>
    with TickerProviderStateMixin {

  bool   _loading = false;
  String? _loadingMsg;
  String? _error;

  _FieldConditions? _cond;
  List<_CropScore>  _scores = [];
  int?              _expandedIdx;

  late AnimationController _headerAnim;
  late AnimationController _listAnim;
  late Animation<double>   _headerFade;

  @override
  void initState() {
    super.initState();
    _headerAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    // Duration must exceed the last tile's delay. With 16 crops × 60 ms stagger
    // the last delay is 15 × 60 = 900 ms, so we need > 900 ms total.
    _listAnim   = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _headerFade = CurvedAnimation(parent: _headerAnim, curve: Curves.easeOut);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchAndScore());
  }

  @override
  void dispose() {
    _headerAnim.dispose();
    _listAnim.dispose();
    super.dispose();
  }

  Future<void> _fetchAndScore() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _loading    = true;
      _loadingMsg = '📍 Getting your exact location…';
      _cond       = null;
      _scores     = [];
      _error      = null;
      _expandedIdx = null;
    });
    _headerAnim.reset(); _listAnim.reset();

    try {
      await Future.delayed(const Duration(milliseconds: 200));
      setState(() => _loadingMsg = '☁️ Fetching real-time weather…');
      final cond = await _FieldService.fetchAll();

      setState(() => _loadingMsg = '🌱 Fetching soil conditions…');
      await Future.delayed(const Duration(milliseconds: 200));

      setState(() => _loadingMsg = '🧠 Scoring 15 crops for your farm…');
      await Future.delayed(const Duration(milliseconds: 300));

      final scores = _ScoringEngine.score(cond);
      setState(() {
        _cond    = cond;
        _scores  = scores;
        _loading = false;
      });
      _headerAnim.forward();
      await Future.delayed(const Duration(milliseconds: 200));
      _listAnim.forward();
    } catch (e) {
      setState(() {
        _loading = false;
        _error   = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: _loading ? _buildLoadingBody()
             : _error  != null ? _buildErrorBody()
             : _buildResultsBody(),
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() => AppBar(
    flexibleSpace: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kGreen1, _kGreen2],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
      ),
    ),
    backgroundColor: Colors.transparent, elevation: 0,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back, color: Colors.white),
      onPressed: () { HapticFeedback.lightImpact(); Navigator.pop(context); },
    ),
    title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Best Crops For My Farm',
          style: TextStyle(color: Colors.white,
              fontWeight: FontWeight.bold, fontSize: 18)),
      Text('Based on your location, soil & weather',
          style: TextStyle(color: Colors.white70, fontSize: 11.5)),
    ]),
    actions: [
      Container(
        margin: const EdgeInsets.only(right: 14, top: 10, bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.25),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.gps_fixed_rounded, color: Colors.white, size: 14),
          SizedBox(width: 4),
          Text('Live', style: TextStyle(color: Colors.white,
              fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
      ),
    ],
  );

  // ── Loading body ──────────────────────────────────────────────────────────

  Widget _buildLoadingBody() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(seconds: 2),
          builder: (_, v, __) => Opacity(
            opacity: (sin(v * pi * 4) * 0.3 + 0.7).clamp(0.0, 1.0),
            child: Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                color: _kGreenSoft,
                shape: BoxShape.circle,
                border: Border.all(color: _kGreen1, width: 3),
              ),
              child: const Center(
                child: Text('🌱', style: TextStyle(fontSize: 44)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(_loadingMsg ?? 'Loading…',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                color: _kGreenDark),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        const SizedBox(width: 200,
          child: LinearProgressIndicator(
            valueColor: AlwaysStoppedAnimation(_kGreen1),
            backgroundColor: _kGreenSoft,
          ),
        ),
        const SizedBox(height: 28),
        const Text('Analysing your exact field conditions\nusing live satellite & weather data',
            style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.5),
            textAlign: TextAlign.center),
      ]),
    ),
  );

  // ── Error body ────────────────────────────────────────────────────────────

  Widget _buildErrorBody() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 80, height: 80,
          decoration: const BoxDecoration(
              color: _kRedSoft, shape: BoxShape.circle),
          child: const Icon(Icons.location_off_rounded,
              color: _kRed, size: 40),
        ),
        const SizedBox(height: 20),
        const Text('Could not get your location',
            style: TextStyle(fontSize: 18,
                fontWeight: FontWeight.bold, color: _kRed)),
        const SizedBox(height: 10),
        Text(_error ?? '',
            style: const TextStyle(fontSize: 13, color: Colors.grey, height: 1.5),
            textAlign: TextAlign.center),
        const SizedBox(height: 28),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _kGreen1, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try Again', style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.bold)),
          onPressed: _fetchAndScore,
        ),
      ]),
    ),
  );

  // ── Results body ──────────────────────────────────────────────────────────

  Widget _buildResultsBody() {
    final c = _cond!;
    return RefreshIndicator(
      color: _kGreen1,
      onRefresh: _fetchAndScore,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 48),
        children: [
          FadeTransition(opacity: _headerFade, child: Column(children: [
            _locationCard(c),
            const SizedBox(height: 12),
            _conditionsGrid(c),
            const SizedBox(height: 12),
            _soilCard(c),
            const SizedBox(height: 16),
            _sectionTitle('🌾 Crop Suitability for Your Farm',
                'Ranked by how well they match your current conditions'),
            const SizedBox(height: 10),
          ])),
          ..._scores.asMap().entries.map((e) {
            final idx   = e.key;
            final score = e.value;
            return _AnimatedCropTile(
              score: score,
              rank: idx + 1,
              // 60 ms stagger per tile, no upper cap — last tile (idx=15) starts
              // at 900 ms and the controller runs for 1800 ms, so it fully completes.
              delay: Duration(milliseconds: 60 * idx),
              isExpanded: _expandedIdx == idx,
              onTap: () => setState(() =>
                  _expandedIdx = _expandedIdx == idx ? null : idx),
              controller: _listAnim,
            );
          }),
        ],
      ),
    );
  }

  // ── Location card ─────────────────────────────────────────────────────────
  // FIX: Replaced inner Row with Column+Row combo and used Flexible/Expanded
  // properly to prevent horizontal overflow on narrow screens.

  Widget _locationCard(_FieldConditions c) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [_kGreen1, _kGreen2],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
      boxShadow: [BoxShadow(color: _kGreen1.withOpacity(0.35),
          blurRadius: 14, offset: const Offset(0, 6))],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.location_on_rounded,
              color: Colors.white, size: 28),
        ),
        const SizedBox(width: 12),
        // FIX: Expanded so this column takes all available space
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // FIX: Wrap place name to avoid overflow on long names
            Text(
              c.placeName,
              style: const TextStyle(color: Colors.white,
                  fontSize: 20, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            if (c.district.isNotEmpty || c.state.isNotEmpty)
              Text(
                '${c.district.isNotEmpty ? "${c.district}, " : ""}${c.state}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            const SizedBox(height: 4),
            Text('${c.lat.toStringAsFixed(4)}°N  ${c.lon.toStringAsFixed(4)}°E',
                style: const TextStyle(color: Colors.white60, fontSize: 11)),
            const SizedBox(height: 6),
            // FIX: Moved season + weather to bottom of this column
            // so they don't fight for horizontal space with the name.
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    c.season,
                    style: const TextStyle(color: Colors.white,
                        fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    c.currentWeatherDesc,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ]),
        ),
      ],
    ),
  );

  // ── Conditions grid (weather) ─────────────────────────────────────────────

  Widget _conditionsGrid(_FieldConditions c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(left: 2, bottom: 8),
        child: Text('🌤 Current Weather Conditions',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                color: _kGreenDark)),
      ),
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true, childAspectRatio: 2.1,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10, mainAxisSpacing: 10,
        children: [
          _weatherTile('🌡 Temperature', '${c.currentTemp.toStringAsFixed(1)}°C',
              _kGreen1, 'Right now'),
          _weatherTile('💧 Humidity', '${c.currentHumidity.toStringAsFixed(0)}%',
              _kAmber, 'Right now'),
          _weatherTile('🌧 Rain (30 days)', '${c.rain30d.toStringAsFixed(0)} mm',
              Colors.blue.shade600, 'Last 30 days'),
          _weatherTile('📅 Annual Rain', '${c.estimatedAnnualRain.toStringAsFixed(0)} mm',
              _kGreenMid, 'Past 12 months'),
          _weatherTile('💨 Wind Speed', '${c.currentWindSpeed.toStringAsFixed(1)} km/h',
              Colors.blueGrey, 'Right now'),
          _weatherTile('🔭 Forecast Rain', '${c.forecast16Rain.toStringAsFixed(0)} mm',
              Colors.indigo.shade600, 'Next 16 days'),
        ],
      ),
    ]);
  }

  Widget _weatherTile(String label, String value, Color color, String sub) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.06),
            blurRadius: 8, offset: const Offset(0, 3))],
      ),
      // FIX: Removed inner Row wrapper that had no Expanded/Flexible,
      // just use the Column directly so text wraps instead of overflowing.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
              maxLines: 1),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(fontSize: 16,
                  fontWeight: FontWeight.bold, color: color),
              overflow: TextOverflow.ellipsis,
              maxLines: 1),
          Text(sub,
              style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
        ],
      ),
    );

  // ── Soil card ─────────────────────────────────────────────────────────────

  Widget _soilCard(_FieldConditions c) {
    final smPct   = c.soilMoisture * 100; // kept for progress bar scaling only
    final smColor = c.soilMoisture > 0.35 ? Colors.blue.shade600
                  : c.soilMoisture > 0.18 ? _kGreenDark : _kRed;
    final stColor = c.soilTemp > 35 ? _kRed
                  : c.soilTemp < 10 ? Colors.blue.shade700 : _kGreenDark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
        boxShadow: [BoxShadow(color: _kGreen1.withOpacity(0.05),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🌱', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Soil Conditions (0–7 cm depth)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                    color: _kGreenDark)),
          ),
          if (!c.soilDataAvailable)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _kAmberSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kAmber.withOpacity(0.4)),
              ),
              child: const Text('Estimated',
                  style: TextStyle(fontSize: 10, color: _kAmber,
                      fontWeight: FontWeight.bold)),
            ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _soilMeter(
            label: 'Soil Moisture',
            value: c.soilMoisture,
            maxVal: 0.50,
            valueText: '${(c.soilMoisture * 100).toStringAsFixed(1)}%',
            subText: '${c.soilMoisture.toStringAsFixed(3)} m³/m³',
            desc: c.soilMoisture > 0.35 ? 'Very wet'
                : c.soilMoisture > 0.20 ? 'Moist'
                : c.soilMoisture > 0.10 ? 'Dry'
                : 'Very dry',
            color: smColor,
          )),
          const SizedBox(width: 16),
          Expanded(child: _soilMeter(
            label: 'Soil Temperature',
            value: c.soilTemp,
            maxVal: 45,
            valueText: '${c.soilTemp.toStringAsFixed(1)}°C',
            subText: 'at 6 cm depth',
            desc: c.soilTemp > 32 ? 'Hot' : c.soilTemp < 12 ? 'Cold' : 'Warm',
            color: stColor,
          )),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _kGreenSoft,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorder),
          ),
          // FIX: Wrapped icon + text in a Row with Expanded on the text
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, color: _kGreen1, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.soilDataAvailable
                      ? 'Soil data from Open-Meteo satellite estimates for your GPS location. Actual values may vary by field.'
                      : 'Live soil data was unavailable. Showing regional estimates typical for your area. Actual values may differ.',
                  style: TextStyle(fontSize: 11, color: _kGreenDark.withOpacity(0.8),
                      height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _soilMeter({
    required String label, required double value,
    required double maxVal, required String valueText,
    required String subText,
    required String desc, required Color color,
  }) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700,
        fontWeight: FontWeight.w600)),
    const SizedBox(height: 6),
    Text(valueText, style: TextStyle(fontSize: 22,
        fontWeight: FontWeight.bold, color: color)),
    Text(desc, style: TextStyle(fontSize: 11, color: color)),
    Text(subText, style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
    const SizedBox(height: 6),
    ClipRRect(borderRadius: BorderRadius.circular(5),
      child: LinearProgressIndicator(
        value: (value / maxVal).clamp(0.0, 1.0), minHeight: 8,
        backgroundColor: Colors.grey.shade200,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    ),
  ]);

  Widget _sectionTitle(String title, String sub) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontSize: 16,
          fontWeight: FontWeight.bold, color: _kGreenDark)),
      const SizedBox(height: 3),
      Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated crop tile widget
// ─────────────────────────────────────────────────────────────────────────────

class _AnimatedCropTile extends StatelessWidget {
  final _CropScore score;
  final int rank;
  final Duration delay;
  final bool isExpanded;
  final VoidCallback onTap;
  final AnimationController controller;

  const _AnimatedCropTile({
    required this.score, required this.rank, required this.delay,
    required this.isExpanded, required this.onTap, required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (ctx, child) {
        // progress: how far this tile's own animation has gone (0→1).
        // We subtract the tile's normalised start offset from controller.value.
        // Total duration is 1800 ms; each tile gets 900 ms to animate in.
        final normDelay = delay.inMilliseconds / 1800.0;
        final normSpan  = 900.0 / 1800.0; // each tile animates over half the total
        final progress  = ((controller.value - normDelay) / normSpan).clamp(0.0, 1.0);
        final curve   = Curves.easeOut.transform(progress);
        return Opacity(
          opacity: curve,
          child: Transform.translate(
            offset: Offset(0, 30 * (1 - curve)),
            child: child,
          ),
        );
      },
      child: _CropTile(
        score: score, rank: rank,
        isExpanded: isExpanded, onTap: onTap,
      ),
    );
  }
}

class _CropTile extends StatelessWidget {
  final _CropScore score;
  final int rank;
  final bool isExpanded;
  final VoidCallback onTap;

  const _CropTile({
    required this.score, required this.rank,
    required this.isExpanded, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c   = score.crop;
    final s   = score;
    final top = rank <= 3;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: s.isDisqualified ? Colors.grey.shade50 : _kSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: s.isDisqualified
                  ? Colors.grey.shade300
                  : isExpanded
                      ? s.labelColor.withOpacity(0.5)
                      : top ? s.labelColor.withOpacity(0.3) : _kBorder,
              width: isExpanded ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: s.isDisqualified
                    ? Colors.transparent
                    : s.labelColor.withOpacity(isExpanded ? 0.12 : 0.05),
                blurRadius: isExpanded ? 16 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(children: [

            // ── Collapsed header ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [

                  // Rank badge — fixed width, no flex needed
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: top
                          ? [Colors.amber.shade600, Colors.grey.shade400,
                             Colors.brown.shade400][rank - 1].withOpacity(0.15)
                          : _kGreenSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        rank <= 3 ? ['🥇','🥈','🥉'][rank - 1] : '$rank',
                        style: TextStyle(
                            fontSize: rank <= 3 ? 18 : 12,
                            fontWeight: FontWeight.bold,
                            color: rank <= 3 ? null : Colors.grey.shade600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Emoji — fixed, just let it breathe
                  Opacity(
                    opacity: s.isDisqualified ? 0.45 : 1.0,
                    child: Text(c.emoji, style: const TextStyle(fontSize: 26)),
                  ),
                  const SizedBox(width: 8),

                  // FIX: Name + category column — MUST be Expanded so it
                  // shrinks to give the score pill its natural space.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // FIX: Wrap the name+category row in a Wrap so the
                        // category badge drops to the next line on narrow screens
                        // rather than pushing outside the viewport.
                        Wrap(
                          spacing: 6,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              c.name,
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: s.isDisqualified
                                      ? Colors.grey.shade400
                                      : _kGreenDark),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _kGreenSoft,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                c.category,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: _kGreenMid,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          c.localName,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Score pill — intrinsic width, no flex
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: s.labelColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: s.labelColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          s.label,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: s.labelColor),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${s.score.toStringAsFixed(0)}/100',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: s.labelColor),
                      ),
                    ],
                  ),

                  const SizedBox(width: 4),

                  // Chevron
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(Icons.expand_more_rounded,
                        color: Colors.grey.shade400, size: 22),
                  ),
                ],
              ),
            ),

            // ── Score bar / disqualified banner ───────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(children: [
                if (s.isDisqualified)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _kRedSoft,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kRed.withOpacity(0.3)),
                    ),
                    // FIX: Row with Expanded on the text so it won't overflow
                    child: Row(children: [
                      const Icon(Icons.block_rounded, color: _kRed, size: 15),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Not suitable for your area',
                          style: TextStyle(fontSize: 12, color: _kRed,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ]),
                  )
                else ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: s.score / 100, minHeight: 8,
                      backgroundColor: Colors.grey.shade100,
                      valueColor: AlwaysStoppedAnimation(s.labelColor),
                    ),
                  ),
                ],
                const SizedBox(height: 5),
                // FIX: SizedBox + width:infinity ensures text has full width
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    s.primaryReason,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: s.isDisqualified
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                        height: 1.3),
                    maxLines: isExpanded ? null : 2,
                    overflow: isExpanded ? null : TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),

            // ── Expanded detail ───────────────────────────────────────────────
            if (isExpanded) _ExpandedDetail(score: s),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expanded detail panel
// ─────────────────────────────────────────────────────────────────────────────

class _ExpandedDetail extends StatelessWidget {
  final _CropScore score;
  const _ExpandedDetail({required this.score});

  @override
  Widget build(BuildContext context) {
    final s = score;
    return Column(children: [
      Divider(color: _kBorder, height: 1),
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('How each factor scored:',
              style: TextStyle(fontSize: 13,
                  fontWeight: FontWeight.bold, color: _kGreenDark)),
          const SizedBox(height: 12),
          ...s.factors.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // FIX: Use Flexible on the name so it wraps instead of overflows
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(f.emoji, style: const TextStyle(fontSize: 15)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              f.name,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade800),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(f.score * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: f.color),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: f.score.clamp(0.0, 1.0), minHeight: 6,
                    backgroundColor: Colors.grey.shade100,
                    valueColor: AlwaysStoppedAnimation(f.color),
                  ),
                ),
                const SizedBox(height: 2),
                Text(f.note,
                    style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
              ],
            ),
          )),
          const SizedBox(height: 4),

          // Planting season row
          // FIX: Use Flexible on the text to prevent overflow on narrow screens
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.calendar_today_rounded,
                  color: _kGreenMid, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Best planting months: ${_monthNames(s.crop.plantingMonths)}',
                  style: const TextStyle(fontSize: 12, color: _kGreenMid,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ]),
      ),
    ]);
  }

  String _monthNames(List<int> months) {
    const names = ['', 'Jan','Feb','Mar','Apr','May','Jun',
                       'Jul','Aug','Sep','Oct','Nov','Dec'];
    return months.map((m) => names[m]).join(', ');
  }
}