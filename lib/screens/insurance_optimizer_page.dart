import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// Responsive helpers
// ─────────────────────────────────────────────────────────────────────────────

const double _kSmBreak = 360;
const double _kMdBreak = 600;
const double _kLgBreak = 900;

extension _Resp on BuildContext {
  double get sw => MediaQuery.of(this).size.width;
  double sp(double size) => size * (sw / 390).clamp(0.65, 1.4);
  T pick<T>({required T sm, T? md, T? lg}) {
    if (sw >= _kLgBreak && lg != null) return lg;
    if (sw >= _kMdBreak && md != null) return md;
    return sm;
  }
  bool get isXS  => sw < _kSmBreak;
  bool get isMd  => sw >= _kMdBreak;
  double get hPad  => pick<double>(sm: 10, md: 20, lg: 28);
  double get cPad  => pick<double>(sm: 10, md: 16, lg: 20);
}

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────

const _kBg        = Color(0xFFF2F7F2);
const _kSurface   = Color(0xFFFFFFFF);
const _kGreen     = Color(0xFF2E7D32);
const _kGreenMid  = Color(0xFF43A047);
const _kGreenLt   = Color(0xFFE8F5E9);
const _kAmber     = Color(0xFFE65100);
const _kRed       = Color(0xFFC62828);
const _kGold      = Color(0xFFB8860B);
const _kGoldLight = Color(0xFFFFF8E1);
const _kBorder    = Color(0xFFCFE8CF);
const _kTextDark  = Color(0xFF1B3A1F);

TextStyle _ts(double sz,
    {Color color = _kTextDark,
     FontWeight w = FontWeight.w600,
     String? family,
     double height = 1.0}) =>
    TextStyle(
        fontSize: sz, fontWeight: w, color: color,
        fontFamily: family ?? 'Georgia', height: height);

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class _WeatherStats {
  final double meanRain, stdRain, cvRain;
  final double meanTemp, stdTemp;
  final String locationName;
  final int years;
  final List<double> annualRain;

  _WeatherStats({
    required this.meanRain, required this.stdRain, required this.cvRain,
    required this.meanTemp, required this.stdTemp,
    required this.locationName, required this.years,
    required this.annualRain,
  });
}

class _InsuranceResult {
  final String cropName, locationName;
  final double landAcres, cropValuePerAcre, premiumRatePct;
  final double weatherVolatility;
  final double droughtFrequency, floodFrequency;
  final double cropRiskScore;
  final double expectedLossPct;
  final double expectedPayoutValue;
  final double annualPremiumCost;
  final double netExpectedValue;
  final double breakEvenLossPct;
  final double payoutProbability;
  final double recommendedCoverage;
  final String verdict;
  final String verdictReason;
  final List<_Scenario> scenarios;
  final List<double> lossDistribution;
  // AI analysis fields
  final String? aiSummary;
  final String? aiRiskFactors;
  final String? aiActionPlan;

  const _InsuranceResult({
    required this.cropName, required this.locationName,
    required this.landAcres, required this.cropValuePerAcre,
    required this.premiumRatePct,
    required this.weatherVolatility,
    required this.droughtFrequency, required this.floodFrequency,
    required this.cropRiskScore,
    required this.expectedLossPct, required this.expectedPayoutValue,
    required this.annualPremiumCost, required this.netExpectedValue,
    required this.breakEvenLossPct, required this.payoutProbability,
    required this.recommendedCoverage,
    required this.verdict, required this.verdictReason,
    required this.scenarios, required this.lossDistribution,
    this.aiSummary,
    this.aiRiskFactors,
    this.aiActionPlan,
  });

  _InsuranceResult copyWithAI({
    String? aiSummary,
    String? aiRiskFactors,
    String? aiActionPlan,
  }) => _InsuranceResult(
    cropName: cropName, locationName: locationName,
    landAcres: landAcres, cropValuePerAcre: cropValuePerAcre,
    premiumRatePct: premiumRatePct,
    weatherVolatility: weatherVolatility,
    droughtFrequency: droughtFrequency, floodFrequency: floodFrequency,
    cropRiskScore: cropRiskScore,
    expectedLossPct: expectedLossPct, expectedPayoutValue: expectedPayoutValue,
    annualPremiumCost: annualPremiumCost, netExpectedValue: netExpectedValue,
    breakEvenLossPct: breakEvenLossPct, payoutProbability: payoutProbability,
    recommendedCoverage: recommendedCoverage,
    verdict: verdict, verdictReason: verdictReason,
    scenarios: scenarios, lossDistribution: lossDistribution,
    aiSummary: aiSummary ?? this.aiSummary,
    aiRiskFactors: aiRiskFactors ?? this.aiRiskFactors,
    aiActionPlan: aiActionPlan ?? this.aiActionPlan,
  );
}

class _Scenario {
  final String name, emoji, description;
  final double probability, lossMultiplier;
  final Color color;
  const _Scenario(this.name, this.emoji, this.probability,
      this.lossMultiplier, this.color, this.description);
}

// ─────────────────────────────────────────────────────────────────────────────
// Crop profiles
// ─────────────────────────────────────────────────────────────────────────────

class _CropProfile {
  final String name, emoji;
  final double baseRiskFactor;
  final double droughtThresholdPct;
  final double floodThresholdPct;
  /// mm/year minimum water requirement — used to penalise dry climates
  final double minWaterReqMm;
  /// PMFBY season: 'kharif' | 'rabi' | 'commercial'
  final String pmfbySeason;
  /// Official MSP 2025-26 (₹/quintal) — from CACP / GoI notification
  final double mspPerQtl;
  /// Average national yield in quintals per acre (ICAR/Directorate of Economics data)
  final double avgYieldQtlPerAcre;

  const _CropProfile({
    required this.name, required this.emoji,
    required this.baseRiskFactor,
    required this.droughtThresholdPct, required this.floodThresholdPct,
    required this.minWaterReqMm,
    required this.pmfbySeason,
    required this.mspPerQtl,
    required this.avgYieldQtlPerAcre,
  });

  /// Crop value per acre = MSP × average yield — derived, no hardcoding needed
  double get valuePerAcre => mspPerQtl * avgYieldQtlPerAcre;

  /// Official PMFBY farmer premium cap (2% Kharif, 1.5% Rabi, 5% commercial)
  double get pmfbyPremiumPct {
    switch (pmfbySeason) {
      case 'rabi':       return 1.5;
      case 'commercial': return 5.0;
      default:           return 2.0; // kharif
    }
  }
}

// Crop value per acre is DERIVED: MSP (₹/qtl) × avg yield (qtl/acre)
// MSP source: CACP/GoI notification 2025-26 (updated annually each June/Oct)
// Yield source: Directorate of Economics & Statistics, MoA, India (3-yr avg)
// PMFBY premium caps: GoI official — 2% Kharif, 1.5% Rabi, 5% Commercial
const _kCrops = [
  _CropProfile(
    name: 'Rice', emoji: '🌾', baseRiskFactor: 0.55,
    droughtThresholdPct: 0.65, floodThresholdPct: 1.45, minWaterReqMm: 1000,
    pmfbySeason: 'kharif',
    mspPerQtl: 2369,          // GoI MSP 2025-26 (Paddy Common)
    avgYieldQtlPerAcre: 14.2, // DES avg: ~3500 kg/ha = 14.2 qtl/acre
  ),
  _CropProfile(
    name: 'Wheat', emoji: '🌿', baseRiskFactor: 0.40,
    droughtThresholdPct: 0.60, floodThresholdPct: 1.60, minWaterReqMm: 450,
    pmfbySeason: 'rabi',
    mspPerQtl: 2425,          // GoI MSP 2025-26 (Wheat)
    avgYieldQtlPerAcre: 17.8, // DES avg: ~4400 kg/ha = 17.8 qtl/acre
  ),
  _CropProfile(
    name: 'Maize', emoji: '🌽', baseRiskFactor: 0.45,
    droughtThresholdPct: 0.62, floodThresholdPct: 1.50, minWaterReqMm: 500,
    pmfbySeason: 'kharif',
    mspPerQtl: 2225,          // GoI MSP 2025-26 (Maize)
    avgYieldQtlPerAcre: 10.5, // DES avg: ~2600 kg/ha = 10.5 qtl/acre
  ),
  _CropProfile(
    name: 'Sugarcane', emoji: '🎋', baseRiskFactor: 0.35,
    droughtThresholdPct: 0.55, floodThresholdPct: 1.70, minWaterReqMm: 1500,
    pmfbySeason: 'commercial',
    mspPerQtl: 340,           // GoI FRP 2024-25 (Fair & Remunerative Price for Sugarcane)
    avgYieldQtlPerAcre: 280,  // DES avg: ~69000 kg/ha = 280 qtl/acre
  ),
  _CropProfile(
    name: 'Cotton', emoji: '🌸', baseRiskFactor: 0.60,
    droughtThresholdPct: 0.68, floodThresholdPct: 1.40, minWaterReqMm: 700,
    pmfbySeason: 'commercial',
    mspPerQtl: 7121,          // GoI MSP 2025-26 (Cotton Medium Staple)
    avgYieldQtlPerAcre: 6.2,  // DES avg: ~1530 kg/ha = 6.2 qtl/acre
  ),
  _CropProfile(
    name: 'Groundnut', emoji: '🥜', baseRiskFactor: 0.50,
    droughtThresholdPct: 0.65, floodThresholdPct: 1.45, minWaterReqMm: 500,
    pmfbySeason: 'kharif',
    mspPerQtl: 6783,          // GoI MSP 2025-26 (Groundnut in shell)
    avgYieldQtlPerAcre: 5.8,  // DES avg: ~1430 kg/ha = 5.8 qtl/acre
  ),
  _CropProfile(
    name: 'Soybean', emoji: '🫘', baseRiskFactor: 0.48,
    droughtThresholdPct: 0.63, floodThresholdPct: 1.48, minWaterReqMm: 550,
    pmfbySeason: 'kharif',
    mspPerQtl: 4892,          // GoI MSP 2025-26 (Soybean Yellow)
    avgYieldQtlPerAcre: 5.4,  // DES avg: ~1330 kg/ha = 5.4 qtl/acre
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Locations
// ─────────────────────────────────────────────────────────────────────────────

class _FarmLocation {
  final String name, region;
  final double lat, lon;
  /// Composite disaster frequency score 0–1
  /// Source: NDMA State Disaster Management Plans + IMD Historical Drought Atlas
  final double districtDisasterScore;
  /// Average number of drought years per decade from IMD published data
  final double historicalDroughtsPerDecade;
  /// Average number of flood years per decade from CWC / NDMA
  final double historicalFloodsPerDecade;
  const _FarmLocation(this.name, this.region, this.lat, this.lon,
      this.districtDisasterScore,
      this.historicalDroughtsPerDecade,
      this.historicalFloodsPerDecade);
  String get display => '$name, $region';
}

// District disaster scores & historical event frequency
// Sources:
//   NDMA State Disaster Management Plans (2021-24)
//   IMD Historical Drought Atlas (2013, updated 2020)
//   Central Water Commission Flood Damage Statistics (2023)
//   PMFBY district-level claim frequency data (public dashboard pmfby.gov.in)
const _kLocations = [
  // Kerala:  High flood/landslide risk, 3 major floods in last decade (2018,19,20)
  _FarmLocation('Kerala',         'India',   10.85,  76.27, 0.72, 1.5, 4.5),
  // Punjab:  Low drought (irrigated), low flood. Stable wheat/rice belt.
  _FarmLocation('Punjab',         'India',   31.15,  75.34, 0.38, 1.0, 1.5),
  // Maharashtra: Moderate — drought-prone Marathwada + some flood zones
  _FarmLocation('Maharashtra',    'India',   19.75,  75.71, 0.61, 3.5, 2.0),
  // Uttar Pradesh: Mixed — eastern floods, western drought in bad years
  _FarmLocation('Uttar Pradesh',  'India',   26.85,  80.91, 0.55, 2.5, 3.0),
  // Andhra Pradesh: Cyclone-prone coast + interior droughts
  _FarmLocation('Andhra Pradesh', 'India',   15.91,  79.74, 0.64, 3.0, 2.5),
  // Rajasthan: Very high drought — Thar Desert fringe, low & erratic rainfall
  _FarmLocation('Rajasthan',      'India',   26.92,  75.78, 0.76, 5.5, 0.8),
  // Bihar: High flood — Kosi/Gandak rivers, frequent inundation
  _FarmLocation('Bihar',          'India',   25.59,  85.13, 0.68, 1.5, 5.0),
  // Madhya Pradesh: Moderate — some drought years, localised floods
  _FarmLocation('Madhya Pradesh', 'India',   23.47,  77.95, 0.59, 3.0, 2.0),
  // Iowa USA: Low risk — well-irrigated Corn Belt, stable climate
  _FarmLocation('Midwest (Iowa)', 'USA',     41.87, -93.10, 0.28, 1.0, 1.0),
  // Kano Nigeria: Moderate — Sahel rainfall variability, occasional flooding
  _FarmLocation('Kano',           'Nigeria', 12.00,   8.52, 0.58, 3.0, 1.5),
];

// ─────────────────────────────────────────────────────────────────────────────
// Weather service
// ─────────────────────────────────────────────────────────────────────────────

class _WeatherService {
  static Future<_WeatherStats> fetch({
    required double lat, required double lon,
    required String locationName, int years = 15,
  }) async {
    final end   = DateTime.now().subtract(const Duration(days: 1));
    final start = DateTime(end.year - years, end.month, end.day);

    final url = Uri.parse(
      'https://archive-api.open-meteo.com/v1/archive'
      '?latitude=$lat&longitude=$lon'
      '&start_date=${_d(start)}&end_date=${_d(end)}'
      '&daily=precipitation_sum,temperature_2m_mean'
      '&timezone=auto',
    );

    final res = await http.get(url).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw Exception('Weather API error ${res.statusCode}');

    final body  = jsonDecode(res.body) as Map<String, dynamic>;
    final daily = body['daily'] as Map<String, dynamic>;

    final rain = (daily['precipitation_sum'] as List<dynamic>)
        .whereType<num>().map((v) => v.toDouble()).toList();
    final temp = (daily['temperature_2m_mean'] as List<dynamic>)
        .whereType<num>().map((v) => v.toDouble()).toList();

    if (rain.isEmpty) throw Exception('No weather data for this location.');

    const dpy = 365;
    final annualRain = <double>[];
    for (int i = 0; i + dpy <= rain.length; i += dpy) {
      annualRain.add(rain.sublist(i, i + dpy)
          .fold(0.0, (double a, double b) => a + b));
    }
    if (annualRain.isEmpty) {
      annualRain.add(rain.fold(0.0, (double a, double b) => a + b) / rain.length * 365);
    }

    final annualTemp = <double>[];
    for (int i = 0; i + dpy <= temp.length; i += dpy) {
      annualTemp.add(_mean(temp.sublist(i, i + dpy)));
    }

    final mr = _mean(annualRain);
    final sr = _std(annualRain);

    return _WeatherStats(
      meanRain: mr, stdRain: sr,
      cvRain: mr > 0 ? sr / mr : 0.0,
      meanTemp: annualTemp.isNotEmpty ? _mean(annualTemp) : 25.0,
      stdTemp:  annualTemp.isNotEmpty ? _std(annualTemp)  : 1.0,
      locationName: locationName, years: years,
      annualRain: annualRain,
    );
  }

  static String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static double _mean(List<double> s) =>
      s.isEmpty ? 0.0 : s.fold(0.0, (double a, double b) => a + b) / s.length;
  static double _std(List<double> s) {
    if (s.length < 2) return 0.0;
    final m = _mean(s);
    return sqrt(s.map((v) => pow(v - m, 2) as double)
        .fold(0.0, (double a, double b) => a + b) / s.length);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rule-Based Expert Advisor — no API, no internet, instant, works offline
// Generates context-aware advice using deterministic logic on the risk metrics.
// ─────────────────────────────────────────────────────────────────────────────

class _AIInsuranceAdvisor {
  /// Synchronous — returns instantly with no network call.
  static Map<String, String> analyze({
    required _InsuranceResult result,
    required _WeatherStats weather,
    required _CropProfile crop,
    required _FarmLocation location,
  }) {
    final totalValue  = result.cropValuePerAcre * result.landAcres;
    final mismatch    = weather.meanRain < crop.minWaterReqMm;
    final mismatchPct = mismatch
        ? ((1.0 - weather.meanRain / crop.minWaterReqMm) * 100).round()
        : 0;
    final score       = result.cropRiskScore;
    final droughtPct  = (result.droughtFrequency * 100).round();
    final floodPct    = (result.floodFrequency   * 100).round();
    final claimPct    = (result.payoutProbability * 100).round();
    final cvPct       = (weather.cvRain * 100).round();
    final isHighRisk  = score >= 60;
    final isMedRisk   = score >= 35 && score < 60;
    final nev         = result.netExpectedValue;
    final premium     = result.annualPremiumCost;
    final payout      = result.expectedPayoutValue;

    // ── SUMMARY ───────────────────────────────────────────────────────────────
    final StringBuffer summary = StringBuffer();

    if (mismatch) {
      summary.write(
        '${crop.name} needs at least ${crop.minWaterReqMm.toStringAsFixed(0)} mm of rain per year, '
        'but ${location.name} typically gets only ${weather.meanRain.toStringAsFixed(0)} mm — '
        'a shortfall of $mismatchPct%. '
        'This means your crop faces chronic water stress every season, not just in bad years. ',
      );
    }

    if (result.verdict == 'RECOMMENDED') {
      if (nev > 0) {
        summary.write(
          'Insurance is financially worth it here: on average you would receive '
          '${_fmt(payout)} back per year while paying only ${_fmt(premium)} in premium — '
          'a net gain of ${_fmt(nev.abs())} per year. ',
        );
      } else {
        summary.write(
          'Even though the average payout (${_fmt(payout)}/yr) is slightly below '
          'the premium (${_fmt(premium)}/yr), the high risk score of '
          '${score.toStringAsFixed(0)}/100 means a single bad season could cause '
          'devastating losses. Insurance is strongly advised as financial protection. ',
        );
      }
      summary.write('Do not skip insurance this year.');
    } else if (result.verdict == 'MARGINAL') {
      summary.write(
        'The numbers are close — average payout (${_fmt(payout)}/yr) versus '
        'premium (${_fmt(premium)}/yr). '
        'If losing this crop would seriously hurt your family\'s finances, '
        'insurance is still a smart choice for peace of mind.',
      );
    } else {
      summary.write(
        'Rainfall in ${location.name} has been relatively stable over the last '
        '${weather.years} years (variability: $cvPct%). '
        'The premium (${_fmt(premium)}/yr) is likely to cost more than '
        'the average payout (${_fmt(payout)}/yr). '
        'A savings reserve may serve you better than insurance this season.',
      );
    }

    // ── RISK FACTORS ──────────────────────────────────────────────────────────
    final risks = <String>[];

    // 1. Climate mismatch
    if (mismatch) {
      risks.add(
        '💧 Climate mismatch: ${crop.name} requires ${crop.minWaterReqMm.toStringAsFixed(0)} mm/year '
        'but ${location.name} averages only ${weather.meanRain.toStringAsFixed(0)} mm. '
        'The crop is under water stress even in a normal year.',
      );
    }

    // 2. Drought frequency
    if (droughtPct >= 30) {
      risks.add(
        '🔥 Very high drought risk: rainfall fell below safe levels in '
        '$droughtPct out of every 100 years of historical data. '
        '${crop.name} is particularly vulnerable — it can lose up to '
        '${(crop.baseRiskFactor * 95).toStringAsFixed(0)}% of yield in a drought year.',
      );
    } else if (droughtPct >= 15) {
      risks.add(
        '☀️ Moderate drought risk: $droughtPct% of years had insufficient rainfall for ${crop.name}. '
        'Dry spells during the critical growing window can cut yields significantly.',
      );
    } else if (droughtPct > 0) {
      risks.add(
        '☀️ Low but real drought risk: about $droughtPct% of years '
        'had below-threshold rainfall. Unlikely but possible.',
      );
    }

    // 3. Flood frequency
    if (floodPct >= 20) {
      risks.add(
        '🌊 High flood risk: $floodPct% of years had excess rainfall. '
        '${crop.name} can suffer serious waterlogging damage — '
        'field drainage and early harvesting are important precautions.',
      );
    } else if (floodPct >= 8) {
      risks.add(
        '🌊 Moderate flood risk: $floodPct% of years saw excess rain. '
        'Flash flooding after heavy monsoon spells is a real threat.',
      );
    }

    // 4. Rainfall variability
    if (cvPct >= 40) {
      risks.add(
        '📊 Very unpredictable rainfall: the year-to-year variation in '
        '${location.name} is $cvPct% (CV), which is very high. '
        'This makes it hard to plan irrigation and increases the chance '
        'of both drought and flood in the same decade.',
      );
    } else if (cvPct >= 25) {
      risks.add(
        '📊 Moderately variable rainfall (CV $cvPct%): '
        'some years are significantly wetter or drier than average, '
        'which can catch farmers unprepared mid-season.',
      );
    }

    // 5. Crop sensitivity
    if (crop.baseRiskFactor >= 0.55) {
      risks.add(
        '🌱 ${crop.name} is a weather-sensitive crop: '
        'it has a high intrinsic risk factor (${(crop.baseRiskFactor * 100).toStringAsFixed(0)}/100) '
        'and reacts strongly to both deficit and excess moisture. '
        'Timing of sowing and harvest is critical.',
      );
    }

    // 6. District history
    if (location.districtDisasterScore >= 0.65) {
      risks.add(
        '🏘 ${location.name} has a high historical disaster frequency score '
        '(${(location.districtDisasterScore * 100).toStringAsFixed(0)}/100). '
        'This district has experienced crop failures, cyclones, or floods '
        'more often than most — local conditions add extra risk.',
      );
    }

    // Ensure at least 2 risk points even in low-risk scenarios
    if (risks.isEmpty) {
      risks.add(
        '✅ No major structural risk factors identified for ${crop.name} in ${location.name}. '
        'Weather has been relatively stable over the last ${weather.years} years.',
      );
      risks.add(
        '📋 Routine risks still apply: pest outbreaks, soil health, '
        'input cost changes, and micro-climate variation at field level.',
      );
    }

    // ── ACTION PLAN ───────────────────────────────────────────────────────────
    final actions = <String>[];

    // Step 1: Insurance enrollment
    if (result.verdict == 'RECOMMENDED') {
      final enrollWindow = _enrollmentWindow(location.region);
      actions.add(
        '1️⃣  Enroll in PMFBY (Pradhan Mantri Fasal Bima Yojana) before the '
        '$enrollWindow deadline. Visit your nearest Common Service Centre (CSC), '
        'bank branch, or go to pmfby.gov.in. '
        'You only pay ${result.premiumRatePct.toStringAsFixed(1)}% of crop value — '
        'the government covers the rest.',
      );
    } else if (result.verdict == 'MARGINAL') {
      actions.add(
        '1️⃣  Consider enrolling in PMFBY — especially if this crop is your '
        'main income source. The premium is low and government-subsidised. '
        'Ask your local Patwari or KVK officer about the current season\'s cutoff date.',
      );
    } else {
      actions.add(
        '1️⃣  Insurance may not be cost-effective at the current premium rate. '
        'Instead, set aside ${_fmt(premium * 0.6)} per season as a crop emergency fund '
        'in a savings account or Kisan Credit Card (KCC).',
      );
    }

    // Step 2: Coverage amount
    actions.add(
      '2️⃣  Ask for a coverage amount of at least ${_fmtMoney(result.recommendedCoverage)}. '
      'This covers the worst-case loss in 95 out of 100 seasons based on '
      '${weather.years} years of real weather data for ${location.name}.',
    );

    // Step 3: Crop / agronomic action
    if (mismatch) {
      actions.add(
        '3️⃣  Strongly consider switching to a drought-tolerant variety of ${crop.name} '
        'or a more climate-suitable crop (e.g. ${_droughtAlternative(crop.name)}). '
        'Talk to your Krishi Vigyan Kendra (KVK) about varieties bred for '
        'low-rainfall conditions — this will reduce your risk long-term regardless of insurance.',
      );
    } else if (isHighRisk) {
      actions.add(
        '3️⃣  Take agronomic precautions to reduce your actual loss risk: '
        'use certified seeds with drought/flood tolerance, consider micro-irrigation '
        'if drought is likely, and document your crop status with photos '
        '(date-stamped) at sowing, flowering, and harvest — this speeds up insurance claims.',
      );
    } else {
      actions.add(
        '3️⃣  Keep records: photograph your crop at sowing and mid-season. '
        'If a weather event damages your crop, file a claim within 72 hours '
        'through the PMFBY app or your insurer\'s helpline. '
        'Contact your local Agriculture Department for free soil health card services.',
      );
    }

    return {
      'summary':     summary.toString().trim(),
      'riskFactors': risks.join('\n\n'),
      'actionPlan':  actions.join('\n\n'),
    };
  }

  static String _fmt(double v) {
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)} L';
    if (v >= 1000)   return '₹${(v / 1000).toStringAsFixed(1)} K';
    return '₹${v.toStringAsFixed(0)}';
  }

  static String _enrollmentWindow(String region) {
    // India Kharif: June–July, Rabi: November–December
    if (region == 'India') return 'Kharif (July 31) or Rabi (December 31)';
    if (region == 'USA')   return 'spring (check RMA crop deadline tool)';
    return 'current season';
  }

  static String _droughtAlternative(String cropName) {
    const alts = {
      'Rice':      'Pearl Millet (Bajra) or Sorghum (Jowar)',
      'Wheat':     'Barley or Chickpea',
      'Sugarcane': 'Sweet Sorghum',
      'Cotton':    'Cluster Bean (Guar) or Sesame',
      'Maize':     'Sorghum or Pearl Millet',
      'Groundnut': 'Sesame or Moth Bean',
      'Soybean':   'Pigeonpea (Arhar)',
    };
    return alts[cropName] ?? 'drought-tolerant varieties';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FIXED Insurance Engine
// Key fixes:
//  1. Climate mismatch penalty: heavily penalise crops growing in wrong climate
//  2. Drought frequency uses absolute count not fraction of mean
//  3. Risk score components are properly normalised to actually reach high values
//  4. Verdict uses BOTH NEV and risk score (high risk = recommend insurance
//     even if NEV is slightly negative — catastrophic risk matters)
//  5. Payout calculation no longer double-discounts
// ─────────────────────────────────────────────────────────────────────────────

class _InsuranceEngine {
  final Random _rand = Random(42);

  double _gauss(double mean, double std) {
    var u1 = _rand.nextDouble();
    final u2 = _rand.nextDouble();
    if (u1 == 0) u1 = 1e-10;
    return mean + std * sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }

  _InsuranceResult analyze({
    required _WeatherStats weather,
    required _CropProfile crop,
    required _FarmLocation location,
    required double landAcres,
  }) {
    // Crop value derived from official MSP × national avg yield (no hardcoded ₹/acre)
    final cropValuePerAcre = crop.valuePerAcre;
    // Premium rate from official PMFBY caps — not a user slider
    final premiumRatePct   = crop.pmfbyPremiumPct;
    final totalCropValue   = cropValuePerAcre * landAcres;
    final cv = weather.cvRain.clamp(0.0, 2.0);

    // ── FIX 1: Climate suitability mismatch penalty ───────────────────────────
    // If the crop needs more water than the location provides, this is a
    // STRUCTURAL risk — e.g. Rice in Rajasthan. Penalise heavily.
    final climateMismatch = weather.meanRain < crop.minWaterReqMm
        ? (1.0 - weather.meanRain / crop.minWaterReqMm).clamp(0.0, 1.0)
        : 0.0;

    // ── FIX 2: Drought & flood frequency from historical data ─────────────────
    int droughts = 0, floods = 0;
    for (final r in weather.annualRain) {
      if (r < weather.meanRain * crop.droughtThresholdPct) droughts++;
      if (r > weather.meanRain * crop.floodThresholdPct)   floods++;
    }
    final n = weather.annualRain.length.toDouble();
    final droughtFreq = n > 0 ? (droughts / n).clamp(0.0, 1.0) : 0.10;
    final floodFreq   = n > 0 ? (floods   / n).clamp(0.0, 1.0) : 0.02;

    // Additionally: absolute drought risk = if mean rain < crop minimum,
    // most years are a drought by definition
    final absoluteDroughtRisk = weather.meanRain < crop.minWaterReqMm
        ? (1.0 - weather.meanRain / crop.minWaterReqMm).clamp(0.0, 1.0)
        : droughtFreq;

    // ── FIX 3: Weather volatility — properly scaled ────────────────────────────
    // CV of 0.10 → low (stable), CV of 0.50 → very high
    // Use direct linear scaling clamped to 0–1
    final weatherVolatility = (cv / 0.50).clamp(0.0, 1.0);

    // ── FIX 4: Composite risk score — all components scale 0–1 properly ──────
    // Weights sum to 1.0
    final riskRaw =
          weatherVolatility                      * 0.20   // rainfall variability
        + crop.baseRiskFactor                    * 0.15   // crop sensitivity
        + absoluteDroughtRisk                    * 0.25   // drought risk (biggest weight)
        + (floodFreq / 0.30).clamp(0.0, 1.0)   * 0.10   // flood risk
        + location.districtDisasterScore         * 0.15   // district history
        + climateMismatch                        * 0.15;  // FIX: climate mismatch
    final cropRiskScore = (riskRaw * 100).clamp(0.0, 100.0);

    // ── FIX 5: Monte Carlo — 500 simulated seasons ───────────────────────────
    const sim = 500;
    final lossDistribution = <double>[];
    final effCv = cv.clamp(0.08, 2.0);

    for (int i = 0; i < sim; i++) {
      final rainFactor = _gauss(1.0, effCv).clamp(0.05, 4.0);
      // Simulated absolute rainfall this season (mm)
      final simRainMm = rainFactor * weather.meanRain;

      double loss = 0.0;

      // Absolute water deficit loss: how far below the crop minimum is this year?
      // This is the key fix — even a "normal" Rajasthan year (350mm) is deficient
      // for Wheat (450mm needed). We model that as a yield penalty.
      final absDeficit = simRainMm < crop.minWaterReqMm
          ? (1.0 - simRainMm / crop.minWaterReqMm).clamp(0.0, 1.0)
          : 0.0;
      final absDeficitLoss = absDeficit * crop.baseRiskFactor * 0.90;

      if (rainFactor < crop.droughtThresholdPct) {
        // Severe drought: relative rainfall also very low — compound the deficit
        final severity =
            (1.0 - rainFactor / crop.droughtThresholdPct).clamp(0.0, 1.0);
        loss = (absDeficitLoss + severity * crop.baseRiskFactor * 0.95)
            .clamp(0.0, 1.0);
      } else if (rainFactor > crop.floodThresholdPct) {
        final severity = ((rainFactor - crop.floodThresholdPct) /
            max(3.0 - crop.floodThresholdPct, 0.1)).clamp(0.0, 1.0);
        loss = severity * crop.baseRiskFactor * 0.75;
      } else {
        // "Normal" relative year but absolute deficit may still cause loss
        loss = absDeficitLoss * (0.5 + 0.5 * _rand.nextDouble());
      }

      loss += location.districtDisasterScore * 0.10 * _rand.nextDouble();
      loss += crop.baseRiskFactor * 0.08 * _rand.nextDouble();
      lossDistribution.add(loss.clamp(0.0, 1.0));
    }
    lossDistribution.sort();

    // ── FIX 6: Expected loss & payout (no double-discounting) ─────────────────
    final avgLoss = lossDistribution.fold(0.0, (double a, double b) => a + b) / sim;

    // Lower deductible for high-risk crops in mismatched climates
    final deductible = climateMismatch > 0.15 ? 0.10 : 0.15;

    final payableEvents = lossDistribution.where((l) => l > deductible).toList();
    final payoutProb    = payableEvents.length / sim;

    final avgPayableExcess = payableEvents.isEmpty
        ? 0.0
        : payableEvents
              .map((l) => l - deductible)
              .fold(0.0, (double a, double b) => a + b) /
            payableEvents.length;

    final expectedPayout = payoutProb * avgPayableExcess * totalCropValue;

    // ── Premium & net value ───────────────────────────────────────────────────
    final annualPremium = (premiumRatePct / 100) * totalCropValue;
    final nev = expectedPayout - annualPremium;

    // ── Break-even ────────────────────────────────────────────────────────────
    final breakEvenLoss =
        payoutProb > 0 ? (premiumRatePct / 100) / payoutProb + deductible : 1.0;

    // ── Recommended coverage (95th percentile) ────────────────────────────────
    final p95Loss = lossDistribution[(sim * 0.95).floor().clamp(0, sim - 1)];
    final recommendedCoverage =
        (p95Loss * totalCropValue).clamp(totalCropValue * 0.3, totalCropValue);

    // ── FIX 7: Verdict — accounts for BOTH NEV and catastrophic risk ──────────
    // High risk score (>55) → recommend insurance even if NEV is slightly negative
    // because catastrophic loss risk outweighs average-year math
    String verdict, verdictReason;
    final highRisk = cropRiskScore >= 55;
    final climateRisk = climateMismatch > 0.15; // Catch even small mismatches (e.g. Wheat 450mm vs Rajasthan 350mm = 22%)

    if (nev > 0 || (highRisk && nev > -annualPremium * 0.5)) {
      verdict = 'RECOMMENDED';
      if (climateRisk) {
        verdictReason =
            '⚠️ Growing ${crop.name} in ${location.name} is a HIGH-RISK choice — '
            'this crop needs ${crop.minWaterReqMm.toStringAsFixed(0)}mm of rain/year '
            'but this location only averages ${weather.meanRain.toStringAsFixed(0)}mm. '
            'Insurance is STRONGLY recommended. '
            'On average, insurance would pay back ${_fmt(expectedPayout)}/year vs '
            'your premium of ${_fmt(annualPremium)}/year.';
      } else {
        verdictReason =
            'Based on ${weather.years} years of rainfall data from ${location.name}, '
            'the weather is unpredictable enough that insurance makes sense. '
            'On average, insurance would pay back ₹${_fmt(expectedPayout)}/year, '
            'which justifies the ₹${_fmt(annualPremium)}/year premium. '
            'A single bad season could wipe out your investment.';
      }
    } else if (highRisk || nev > -annualPremium * 0.4) {
      verdict = 'MARGINAL';
      verdictReason = climateRisk
          ? '⚠️ ${crop.name} is not well-suited to ${location.name}\'s rainfall '
            '(${weather.meanRain.toStringAsFixed(0)}mm vs ${crop.minWaterReqMm.toStringAsFixed(0)}mm needed). '
            'The premium may slightly exceed average payouts, but given the climate risk, '
            'insurance is still worth considering for financial protection.'
          : 'The insurance payout (${_fmt(expectedPayout)}/yr average) is close to '
            'the premium (${_fmt(annualPremium)}/yr). '
            'Weather in ${location.name} is moderately risky. '
            'If a bad year would seriously hurt your family, insurance is worthwhile.';
    } else {
      verdict = 'NOT RECOMMENDED';
      verdictReason = climateRisk
          ? '⚠️ ${crop.name} is poorly suited to ${location.name}\'s climate. '
            'However, at this premium rate the math does not favour insurance. '
            'Consider switching to a drought-tolerant crop for this region instead.'
          : 'Rainfall in ${location.name} has been fairly stable over ${weather.years} years. '
            'The premium (${_fmt(annualPremium)}/yr) is likely to exceed what you\'d '
            'claim back (${_fmt(expectedPayout)}/yr). '
            'A savings buffer may be smarter here.';
    }

    // ── Scenarios ─────────────────────────────────────────────────────────────
    // ── Scenario drought frequency: use the LARGER of:
    //   a) raw historical years-below-threshold / total years  (measured from real data)
    //   b) absoluteDroughtRisk (climate mismatch fraction)
    //   c) NDMA historicalDroughtsPerDecade converted to probability
    // This ensures Rajasthan (low rain) shows realistic drought probability,
    // not a near-zero count of years below 65% of its already-low mean.
    final ndmaDroughtProb = (location.historicalDroughtsPerDecade / 10.0).clamp(0.0, 1.0);
    final effectiveDroughtFreq = [
      droughtFreq,
      absoluteDroughtRisk,
      ndmaDroughtProb,
    ].reduce((a, b) => a > b ? a : b).clamp(0.02, 0.85);

    // Similarly for floods — use max of historical count and NDMA data
    final ndmaFloodProb = (location.historicalFloodsPerDecade / 10.0).clamp(0.0, 1.0);
    final effectiveFloodFreq = [
      floodFreq,
      ndmaFloodProb,
    ].reduce((a, b) => a > b ? a : b).clamp(0.01, 0.60);

    final scenarios = [
      _Scenario('Severe Drought / Water Stress', '🔥',
          effectiveDroughtFreq.clamp(0.02, 0.7), 0.75, _kRed,
          climateMismatch > 0.2
              ? '${crop.name} needs ${crop.minWaterReqMm.toStringAsFixed(0)}mm — this area averages only ${weather.meanRain.toStringAsFixed(0)}mm'
              : 'Rainfall below ${(crop.droughtThresholdPct * 100).toStringAsFixed(0)}% of normal'),
      _Scenario('Moderate Drought', '☀️',
          (effectiveDroughtFreq * 1.3).clamp(0.05, 0.70), 0.40, _kAmber,
          'Slightly below normal rainfall — partial crop loss'),
      _Scenario('Good/Normal Season', '🌤',
          (1.0 - effectiveDroughtFreq - effectiveFloodFreq).clamp(0.05, 0.90),
          climateMismatch > 0.3 ? 0.20 : 0.03,
          _kGreen,
          climateMismatch > 0.3
              ? 'Even normal years have some water stress for ${crop.name}'
              : 'Normal rainfall — healthy crop expected'),
      _Scenario('Flash Flood / Excess Rain', '🌊',
          effectiveFloodFreq, 0.60, _kGreenMid,
          'Rainfall exceeds ${(crop.floodThresholdPct * 100).toStringAsFixed(0)}% of normal'),
    ];

    return _InsuranceResult(
      cropName: crop.name, locationName: location.display,
      landAcres: landAcres, cropValuePerAcre: cropValuePerAcre,
      premiumRatePct: premiumRatePct,
      weatherVolatility: weatherVolatility,
      droughtFrequency: effectiveDroughtFreq,
      floodFrequency: effectiveFloodFreq,
      cropRiskScore: cropRiskScore,
      expectedLossPct: avgLoss, expectedPayoutValue: expectedPayout,
      annualPremiumCost: annualPremium, netExpectedValue: nev,
      breakEvenLossPct: breakEvenLoss.clamp(0.0, 1.0),
      payoutProbability: payoutProb,
      recommendedCoverage: recommendedCoverage,
      verdict: verdict, verdictReason: verdictReason,
      scenarios: scenarios, lossDistribution: lossDistribution,
    );
  }

  static String _fmt(double v) {
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)} L';
    if (v >= 1000)   return '₹${(v / 1000).toStringAsFixed(1)} K';
    return '₹${v.toStringAsFixed(0)}';
  }
}

String _fmtMoney(double v) {
  if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)} Cr';
  if (v >= 100000)   return '₹${(v / 100000).toStringAsFixed(2)} L';
  if (v >= 1000)     return '₹${(v / 1000).toStringAsFixed(1)} K';
  return '₹${v.toStringAsFixed(0)}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class InsuranceOptimizerPage extends StatefulWidget {
  const InsuranceOptimizerPage({Key? key}) : super(key: key);

  @override
  State<InsuranceOptimizerPage> createState() => _PageState();
}

class _PageState extends State<InsuranceOptimizerPage>
    with SingleTickerProviderStateMixin {
  _FarmLocation _loc  = _kLocations[0];
  _CropProfile  _crop = _kCrops[0];
  double _acres        = 3.0;
  int    _years        = 15;

  bool   _loadingW  = false;
  bool   _analyzing = false;
  String? _error;

  _WeatherStats?    _weather;
  _InsuranceResult? _result;

  late AnimationController _anim;
  late Animation<double>   _fade;
  final _engine = _InsuranceEngine();

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() { _anim.dispose(); super.dispose(); }

  Future<void> _run() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _loadingW = true; _analyzing = false;
      _weather = null; _result = null; _error = null;
    });
    _anim.reset();
    try {
      final w = await _WeatherService.fetch(
        lat: _loc.lat, lon: _loc.lon,
        locationName: _loc.display, years: _years,
      );
      setState(() { _weather = w; _loadingW = false; _analyzing = true; });
      await Future.delayed(const Duration(milliseconds: 80));

      final r = _engine.analyze(
        weather: w, crop: _crop, location: _loc,
        landAcres: _acres,
      );
      setState(() { _result = r; _analyzing = false; });
      _anim.forward();

      // Fetch AI analysis after showing results (non-blocking)
      _fetchAIAnalysis(r, w);
    } catch (e) {
      setState(() {
        _loadingW = false; _analyzing = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _fetchAIAnalysis(_InsuranceResult result, _WeatherStats weather) {
    // Rule-based engine is synchronous — instant, no network, no API key needed
    final ai = _AIInsuranceAdvisor.analyze(
      result: result, weather: weather,
      crop: _crop, location: _loc,
    );
    if (ai.isNotEmpty && mounted) {
      setState(() {
        _result = result.copyWithAI(
          aiSummary:     ai['summary'],
          aiRiskFactors: ai['riskFactors'],
          aiActionPlan:  ai['actionPlan'],
        );
      });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final busy = _loadingW || _analyzing;
    final hPad = context.hPad;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: _buildAppBar(context),
      body: SafeArea(
        child: LayoutBuilder(builder: (ctx, cs) {
          final maxW = cs.maxWidth >= _kLgBreak ? 720.0 : double.infinity;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: ListView(
                padding: EdgeInsets.fromLTRB(hPad, ctx.sp(14), hPad, 40),
                children: [
                  _configCard(ctx),
                  SizedBox(height: ctx.sp(12)),
                  _analyzeBtn(ctx, busy),
                  SizedBox(height: ctx.sp(16)),
                  if (_loadingW) _loadCard(ctx,
                      '☁️  Loading $_years years of weather…',
                      'Downloading rainfall & temperature data for ${_loc.name}'),
                  if (_analyzing) _loadCard(ctx,
                      '🧮  Calculating your insurance value…',
                      'Simulating 500 growing seasons — just a moment'),
                  if (_error != null) _errorCard(ctx),
                  if (!busy && _result != null && _weather != null)
                    FadeTransition(
                      opacity: _fade,
                      child: Column(children: [
                        _weatherBanner(ctx),
                        SizedBox(height: ctx.sp(12)),
                        _verdictBanner(ctx),
                        SizedBox(height: ctx.sp(12)),
                        _keyMetricsRow(ctx),
                        SizedBox(height: ctx.sp(12)),
                        // AI Card — shows loading then populates
                        _aiAdviceCard(ctx),
                        SizedBox(height: ctx.sp(12)),
                        _riskScoreCard(ctx),
                        SizedBox(height: ctx.sp(12)),
                        _financialCard(ctx),
                        SizedBox(height: ctx.sp(12)),
                        _scenarioCard(ctx),
                        SizedBox(height: ctx.sp(12)),
                        _lossHistogram(ctx),
                        SizedBox(height: ctx.sp(12)),
                        _adviceCard(ctx),
                      ]),
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) => AppBar(
    backgroundColor: _kGreen, elevation: 0,
    toolbarHeight: context.sp(56),
    leading: IconButton(
      icon: Icon(Icons.arrow_back, color: Colors.white, size: context.sp(22)),
      onPressed: () { HapticFeedback.lightImpact(); Navigator.pop(context); },
    ),
    title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Insurance Advisor',
          style: _ts(context.sp(17), color: Colors.white, w: FontWeight.bold),
          overflow: TextOverflow.ellipsis, maxLines: 1),
      Text('Should you insure your crop?',
          style: _ts(context.sp(10.5), color: Colors.white70, w: FontWeight.w400),
          overflow: TextOverflow.ellipsis, maxLines: 1),
    ]),
  );

  // ── Config card ────────────────────────────────────────────────────────────

  Widget _configCard(BuildContext ctx) => _card(ctx, child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Icon(Icons.agriculture_rounded, color: _kGreen, size: ctx.sp(20)),
        SizedBox(width: ctx.sp(6)),
        Expanded(child: Text('Your Farm Details',
            style: _ts(ctx.sp(15), color: _kGreen, w: FontWeight.bold),
            overflow: TextOverflow.ellipsis)),
      ]),
      SizedBox(height: ctx.sp(14)),

      Text('📍 Location', style: _ts(ctx.sp(13), color: _kTextDark)),
      SizedBox(height: ctx.sp(6)),
      _dropdown<_FarmLocation>(
        ctx: ctx,
        value: _loc, items: _kLocations, label: (l) => l.display,
        onChanged: (v) { if (v != null) setState(() => _loc = v); },
      ),

      SizedBox(height: ctx.sp(14)),
      Text('🌾 What do you grow?', style: _ts(ctx.sp(13), color: _kTextDark)),
      SizedBox(height: ctx.sp(8)),
      Wrap(
        spacing: ctx.sp(6), runSpacing: ctx.sp(6),
        children: _kCrops.map((cp) {
          final sel = _crop.name == cp.name;
          return GestureDetector(
            onTap: () { HapticFeedback.selectionClick(); setState(() => _crop = cp); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.symmetric(
                  horizontal: ctx.sp(12), vertical: ctx.sp(8)),
              decoration: BoxDecoration(
                color: sel ? _kGreen : _kGreenLt,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                    color: sel ? _kGreen : _kGreen.withOpacity(0.3)),
              ),
              child: Text('${cp.emoji}  ${cp.name}',
                  style: TextStyle(
                      fontSize: ctx.sp(12), fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : _kGreen)),
            ),
          );
        }).toList(),
      ),

      SizedBox(height: ctx.sp(14)),
      _sliderRow(ctx,
          label: '🏡 Farm Size',
          pill: '${_acres.toStringAsFixed(1)} acres',
          pillColor: _kGreen,
          activeColor: _kGreen,
          value: _acres, min: 0.5, max: 50, divisions: 99,
          onChanged: (v) => setState(() => _acres = v)),

      // ── PMFBY premium info badge (replaces slider — official govt rates) ──
      Container(
        margin: EdgeInsets.only(bottom: ctx.sp(14)),
        padding: EdgeInsets.all(ctx.sp(12)),
        decoration: BoxDecoration(
          color: _kGoldLight,
          borderRadius: BorderRadius.circular(ctx.sp(12)),
          border: Border.all(color: _kGold.withOpacity(0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.verified_outlined, color: _kGold, size: ctx.sp(18)),
            SizedBox(width: ctx.sp(6)),
            Text('Official PMFBY Premium Rates (GoI 2025-26)',
                style: _ts(ctx.sp(12), color: _kGold, w: FontWeight.bold)),
          ]),
          SizedBox(height: ctx.sp(8)),
          Row(children: [
            _pmfbyBadge(ctx, 'Kharif crops', '2.0%', _kGreenMid),
            SizedBox(width: ctx.sp(6)),
            _pmfbyBadge(ctx, 'Rabi crops', '1.5%', _kGreen),
            SizedBox(width: ctx.sp(6)),
            _pmfbyBadge(ctx, 'Commercial', '5.0%', _kAmber),
          ]),
          SizedBox(height: ctx.sp(8)),
          Text(
            'Premium auto-set from official caps. You pay only this %  —  '
            'Govt covers the rest of the actuarial premium.',
            style: _ts(ctx.sp(10), color: Colors.brown.shade400, w: FontWeight.w400, height: 1.5),
          ),
        ]),
      ),

      _sliderRow(ctx,
          label: '📅 Years of weather history to use',
          pill: '$_years yrs',
          pillColor: _kGreenMid,
          activeColor: _kGreenMid,
          value: _years.toDouble(), min: 5, max: 20, divisions: 15,
          onChanged: (v) => setState(() => _years = v.round())),
    ],
  ));

  Widget _sliderRow(BuildContext ctx, {
    required String label, required String pill,
    required Color pillColor, required Color activeColor,
    required double value, required double min,
    required double max, required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    final header = ctx.isXS
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: _ts(ctx.sp(12), color: _kTextDark, w: FontWeight.w500),
                overflow: TextOverflow.ellipsis, maxLines: 2),
            SizedBox(height: ctx.sp(4)),
            _pill(ctx, pill, pillColor, pillColor.withOpacity(0.1)),
          ])
        : Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(child: Text(label,
                style: _ts(ctx.sp(13), color: _kTextDark, w: FontWeight.w500),
                overflow: TextOverflow.ellipsis, maxLines: 2)),
            SizedBox(width: ctx.sp(8)),
            _pill(ctx, pill, pillColor, pillColor.withOpacity(0.1)),
          ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      header,
      SliderTheme(
        data: SliderThemeData(
          activeTrackColor:   activeColor,
          thumbColor:         activeColor,
          inactiveTrackColor: activeColor.withOpacity(0.2),
          overlayColor:       activeColor.withOpacity(0.08),
          trackHeight: ctx.sp(4),
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: ctx.sp(8)),
        ),
        child: Slider(
            value: value, min: min, max: max, divisions: divisions,
            onChanged: onChanged),
      ),
    ]);
  }

  // ── Analyze button ─────────────────────────────────────────────────────────

  Widget _analyzeBtn(BuildContext ctx, bool busy) => SizedBox(
    width: double.infinity,
    height: ctx.sp(56),
    child: ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: _kGreen, foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ctx.sp(14))),
        elevation: 3,
        padding: EdgeInsets.symmetric(horizontal: ctx.sp(12)),
      ),
      icon: busy
          ? SizedBox(width: ctx.sp(18), height: ctx.sp(18),
              child: const CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5))
          : Icon(Icons.calculate_rounded, size: ctx.sp(20)),
      label: Flexible(
        child: Text(
          busy ? 'Calculating…' : '📊  Check If Insurance Is Worth It',
          style: _ts(ctx.sp(14), color: Colors.white, w: FontWeight.w700),
          overflow: TextOverflow.ellipsis, maxLines: 1,
        ),
      ),
      onPressed: busy ? null : _run,
    ),
  );

  // ── Loading ────────────────────────────────────────────────────────────────

  Widget _loadCard(BuildContext ctx, String title, String sub) => Container(
    margin: EdgeInsets.only(bottom: ctx.sp(12)),
    padding: EdgeInsets.all(ctx.sp(16)),
    decoration: _surfaceDec(ctx),
    child: Row(children: [
      SizedBox(width: ctx.sp(30), height: ctx.sp(30),
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(_kGreen), strokeWidth: 3)),
      SizedBox(width: ctx.sp(14)),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: _ts(ctx.sp(13.5), color: _kGreen, w: FontWeight.bold),
            overflow: TextOverflow.ellipsis, maxLines: 2),
        SizedBox(height: ctx.sp(3)),
        Text(sub, style: TextStyle(fontSize: ctx.sp(11.5), color: Colors.grey.shade600),
            overflow: TextOverflow.ellipsis, maxLines: 2),
      ])),
    ]),
  );

  // ── Error ──────────────────────────────────────────────────────────────────

  Widget _errorCard(BuildContext ctx) => Container(
    margin: EdgeInsets.only(bottom: ctx.sp(12)),
    padding: EdgeInsets.all(ctx.sp(16)),
    decoration: BoxDecoration(color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(ctx.sp(14)),
        border: Border.all(color: Colors.red.shade200)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.error_outline_rounded, color: Colors.red.shade600, size: ctx.sp(22)),
      SizedBox(width: ctx.sp(10)),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Could not load weather data',
            style: _ts(ctx.sp(13.5), color: Colors.red.shade700, w: FontWeight.bold),
            overflow: TextOverflow.ellipsis, maxLines: 2),
        SizedBox(height: ctx.sp(4)),
        Text(_error ?? '', style: TextStyle(
            fontSize: ctx.sp(12), color: Colors.red.shade700)),
        SizedBox(height: ctx.sp(4)),
        Text('Please check your internet and try again.',
            style: TextStyle(fontSize: ctx.sp(11), color: Colors.grey.shade600)),
      ])),
    ]),
  );

  // ── Weather banner ─────────────────────────────────────────────────────────

  Widget _weatherBanner(BuildContext ctx) {
    final w = _weather!;
    final r = _result!;
    // Show climate mismatch warning if applicable
    final mismatch = w.meanRain < _crop.minWaterReqMm;
    return Column(children: [
      Container(
        padding: EdgeInsets.symmetric(
            horizontal: ctx.sp(14), vertical: ctx.sp(12)),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_kGreen, _kGreenMid],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(ctx.sp(14)),
        ),
        child: Row(children: [
          Icon(Icons.cloud_done_outlined, color: Colors.white, size: ctx.sp(22)),
          SizedBox(width: ctx.sp(10)),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${w.years}-year weather history loaded  ✓',
                style: TextStyle(color: Colors.white,
                    fontWeight: FontWeight.bold, fontSize: ctx.sp(13)),
                overflow: TextOverflow.ellipsis),
            Text('${w.annualRain.length} annual samples · ${_loc.display}',
                style: TextStyle(color: Colors.white70, fontSize: ctx.sp(11)),
                overflow: TextOverflow.ellipsis),
          ])),
          SizedBox(width: ctx.sp(8)),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${w.meanRain.toStringAsFixed(0)} mm/yr',
                style: TextStyle(color: Colors.white,
                    fontWeight: FontWeight.bold, fontSize: ctx.sp(12))),
            Text('CV: ${(w.cvRain * 100).toStringAsFixed(1)}%',
                style: TextStyle(color: Colors.white70, fontSize: ctx.sp(10.5))),
          ]),
        ]),
      ),
      if (mismatch) ...[
        SizedBox(height: ctx.sp(8)),
        Container(
          padding: EdgeInsets.all(ctx.sp(12)),
          decoration: BoxDecoration(
            color: _kRed.withOpacity(0.08),
            borderRadius: BorderRadius.circular(ctx.sp(12)),
            border: Border.all(color: _kRed.withOpacity(0.35)),
          ),
          child: Row(children: [
            Icon(Icons.warning_amber_rounded, color: _kRed, size: ctx.sp(20)),
            SizedBox(width: ctx.sp(8)),
            Expanded(child: Text(
              '⚠️ Climate Mismatch: ${_crop.name} needs ${_crop.minWaterReqMm.toStringAsFixed(0)}mm/year '
              'but ${_loc.name} only gets ${w.meanRain.toStringAsFixed(0)}mm on average. '
              'This significantly increases crop loss risk.',
              style: _ts(ctx.sp(11.5), color: _kRed, w: FontWeight.w600, height: 1.5),
            )),
          ]),
        ),
      ],
    ]);
  }

  // ── Verdict banner ─────────────────────────────────────────────────────────

  Widget _verdictBanner(BuildContext ctx) {
    final r = _result!;
    Color bg; IconData icon; String label; String subLabel;
    switch (r.verdict) {
      case 'RECOMMENDED':
        bg = _kGreen; icon = Icons.verified_outlined;
        label = '✅  Yes — Get Insurance';
        subLabel = 'The numbers say insurance is worth it for your farm.';
        break;
      case 'MARGINAL':
        bg = _kAmber; icon = Icons.info_outline_rounded;
        label = '⚠️  Maybe — Your Choice';
        subLabel = 'It is close. Think about how much risk you can handle.';
        break;
      default:
        bg = _kRed; icon = Icons.cancel_outlined;
        label = '❌  Skip Insurance This Year';
        subLabel = 'The premium may cost more than what you would get back.';
    }

    return Container(
      padding: EdgeInsets.all(ctx.sp(16)),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(ctx.sp(16)),
        boxShadow: [BoxShadow(color: bg.withOpacity(0.35),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        Icon(icon, color: Colors.white, size: ctx.sp(28)),
        SizedBox(width: ctx.sp(12)),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: _ts(ctx.sp(17), color: Colors.white, w: FontWeight.bold),
              overflow: TextOverflow.ellipsis),
          SizedBox(height: ctx.sp(4)),
          Text(subLabel, style: TextStyle(color: Colors.white.withOpacity(0.85),
              fontSize: ctx.sp(12)),
              overflow: TextOverflow.ellipsis, maxLines: 2),
          SizedBox(height: ctx.sp(4)),
          Text('Risk Score: ${r.cropRiskScore.toStringAsFixed(0)}/100  ·  Based on ${_weather!.years} years of real data',
              style: TextStyle(color: Colors.white70, fontSize: ctx.sp(10.5))),
        ])),
      ]),
    );
  }

  // ── Key metrics row ────────────────────────────────────────────────────────

  Widget _keyMetricsRow(BuildContext ctx) {
    final r = _result!;
    return Row(children: [
      Expanded(child: _metricTile(ctx,
          '${(r.payoutProbability * 100).toStringAsFixed(0)}%',
          'Chance of\nClaiming', '📋', _kGreen)),
      SizedBox(width: ctx.sp(8)),
      Expanded(child: _metricTile(ctx,
          _fmtMoney(r.expectedPayoutValue),
          'Avg Payout\nper Year', '💰', _kGreenMid)),
      SizedBox(width: ctx.sp(8)),
      Expanded(child: _metricTile(ctx,
          _fmtMoney(r.netExpectedValue.abs()),
          r.netExpectedValue >= 0 ? 'Net Savings\nper Year' : 'Net Cost\nper Year',
          r.netExpectedValue >= 0 ? '📈' : '📉',
          r.netExpectedValue >= 0 ? _kGreen : _kRed)),
    ]);
  }

  Widget _metricTile(BuildContext ctx, String value, String label,
      String emoji, Color color) => Container(
    padding: EdgeInsets.all(ctx.sp(11)),
    decoration: BoxDecoration(
      color: _kSurface,
      borderRadius: BorderRadius.circular(ctx.sp(14)),
      border: Border.all(color: color.withOpacity(0.25)),
      boxShadow: [BoxShadow(color: color.withOpacity(0.06),
          blurRadius: 8, offset: const Offset(0, 3))],
    ),
    child: Column(children: [
      Text(emoji, style: TextStyle(fontSize: ctx.sp(20))),
      SizedBox(height: ctx.sp(5)),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(value, style: _ts(ctx.sp(17), color: color, w: FontWeight.bold),
            textAlign: TextAlign.center),
      ),
      SizedBox(height: ctx.sp(3)),
      Text(label,
          style: _ts(ctx.sp(9.5), color: Colors.grey.shade600, w: FontWeight.w500),
          textAlign: TextAlign.center),
    ]),
  );

  // ── AI Advice Card ─────────────────────────────────────────────────────────

  Widget _aiAdviceCard(BuildContext ctx) {
    final r = _result!;
    final hasAI = r.aiSummary != null && r.aiSummary!.isNotEmpty;

    return Container(
      padding: EdgeInsets.all(ctx.cPad),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A237E).withOpacity(0.92),
            const Color(0xFF283593).withOpacity(0.92),
          ],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(ctx.sp(16)),
        boxShadow: [BoxShadow(
            color: const Color(0xFF1A237E).withOpacity(0.3),
            blurRadius: 12, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: EdgeInsets.all(ctx.sp(7)),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(ctx.sp(10)),
              ),
              child: Text('🤖', style: TextStyle(fontSize: ctx.sp(18))),
            ),
            SizedBox(width: ctx.sp(10)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('AI-Powered Analysis',
                  style: _ts(ctx.sp(14), color: Colors.white, w: FontWeight.bold),
                  overflow: TextOverflow.ellipsis),
              Text('Expert Rule-Based Advisor · No API needed',
                  style: TextStyle(
                      color: Colors.white60, fontSize: ctx.sp(11))),
            ])),
          ]),

          SizedBox(height: ctx.sp(14)),

          if (hasAI) ...[
            // Summary
            _aiSection(ctx, '💡 Summary', r.aiSummary!),
            SizedBox(height: ctx.sp(10)),
            // Risk factors
            _aiSection(ctx, '⚠️ Key Risk Factors', r.aiRiskFactors ?? ''),
            SizedBox(height: ctx.sp(10)),
            // Action plan
            _aiSection(ctx, '📋 What To Do', r.aiActionPlan ?? ''),
          ],
        ],
      ),
    );
  }

  Widget _aiSection(BuildContext ctx, String title, String content) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: _ts(ctx.sp(12.5), color: Colors.white70,
            w: FontWeight.bold)),
        SizedBox(height: ctx.sp(5)),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(ctx.sp(12)),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(ctx.sp(10)),
          ),
          child: Text(content,
              style: TextStyle(color: Colors.white,
                  fontSize: ctx.sp(12.5), height: 1.6)),
        ),
      ]);

  // ── Risk score card ────────────────────────────────────────────────────────

  Widget _riskScoreCard(BuildContext ctx) {
    final r = _result!;
    final w = _weather!;
    final score = r.cropRiskScore;
    final scoreColor = score >= 60 ? _kRed : score >= 35 ? _kAmber : _kGreen;
    final scoreLabel = score >= 60 ? 'HIGH RISK'
                     : score >= 35 ? 'MEDIUM RISK' : 'LOW RISK';
    final scorePlain = score >= 60
        ? 'Your crop faces a serious risk of weather damage.'
        : score >= 35
            ? 'Your crop faces a moderate risk. Some caution needed.'
            : 'Your crop is at low risk from weather in this area.';

    final mismatch = w.meanRain < _crop.minWaterReqMm;
    final mismatchPct = mismatch
        ? (1.0 - w.meanRain / _crop.minWaterReqMm).clamp(0.0, 1.0)
        : 0.0;

    return _card(ctx, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(child: Text('🎯 Weather Risk for Your Crop',
              style: _ts(ctx.sp(15), color: _kGreen, w: FontWeight.bold),
              overflow: TextOverflow.ellipsis)),
          SizedBox(width: ctx.sp(6)),
          _pill(ctx, scoreLabel, scoreColor, scoreColor.withOpacity(0.1)),
        ]),
        SizedBox(height: ctx.sp(4)),
        Text(scorePlain,
            style: _ts(ctx.sp(12), color: Colors.grey.shade600, w: FontWeight.w400)),
        SizedBox(height: ctx.sp(14)),

        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(score.toStringAsFixed(0),
                  style: _ts(ctx.sp(48), color: scoreColor,
                      w: FontWeight.w900, family: 'Georgia')),
              Padding(
                padding: EdgeInsets.only(bottom: ctx.sp(8), left: ctx.sp(4)),
                child: Text('/100',
                    style: _ts(ctx.sp(15), color: Colors.grey.shade400,
                        w: FontWeight.w400)),
              ),
            ]),
            Text('Risk Score', style: _ts(ctx.sp(11), color: Colors.grey.shade500,
                w: FontWeight.w400)),
          ]),
          const Spacer(),
          SizedBox(
            width: ctx.sp(74), height: ctx.sp(74),
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(
                value: score / 100,
                strokeWidth: ctx.sp(9),
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(scoreColor),
              ),
              Text('${score.toStringAsFixed(0)}',
                  style: _ts(ctx.sp(13), color: scoreColor, w: FontWeight.bold)),
            ]),
          ),
        ]),

        SizedBox(height: ctx.sp(14)),
        _riskFactor(ctx, '☁️ How unpredictable is the rain?',
            r.weatherVolatility, 1.0,
            'CV ${(w.cvRain * 100).toStringAsFixed(1)}% — higher = more year-to-year variation'),
        SizedBox(height: ctx.sp(8)),
        _riskFactor(ctx, '🌵 How often does drought happen?',
            r.droughtFrequency, 1.0,
            '${(r.droughtFrequency * 100).toStringAsFixed(0)}% of years had insufficient rain for this crop'),
        SizedBox(height: ctx.sp(8)),
        _riskFactor(ctx, '🌊 How often does flooding happen?',
            r.floodFrequency, 0.30,
            '${(r.floodFrequency * 100).toStringAsFixed(0)}% of years had excessive rain for this crop'),
        SizedBox(height: ctx.sp(8)),
        _riskFactor(ctx, '🏘 District disaster history',
            _loc.districtDisasterScore, 1.0,
            'How often this district has had crop disasters in the past'),
        if (mismatch) ...[
          SizedBox(height: ctx.sp(8)),
          _riskFactor(ctx, '💧 Climate mismatch for ${_crop.name}',
              mismatchPct, 1.0,
              '${_crop.name} needs ${_crop.minWaterReqMm.toStringAsFixed(0)}mm but ${_loc.name} gets ${w.meanRain.toStringAsFixed(0)}mm — serious structural risk'),
        ],
      ],
    ));
  }

  Widget _riskFactor(BuildContext ctx, String label, double value,
      double maxVal, String note) {
    final pct = (value / maxVal).clamp(0.0, 1.0);
    final col = pct > 0.6 ? _kRed : pct > 0.35 ? _kAmber : _kGreen;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(child: Text(label,
            style: _ts(ctx.sp(12), color: Colors.grey.shade700, w: FontWeight.w500),
            overflow: TextOverflow.ellipsis)),
        SizedBox(width: ctx.sp(4)),
        Text('${(pct * 100).toStringAsFixed(0)}%',
            style: _ts(ctx.sp(12), color: col, w: FontWeight.bold)),
      ]),
      SizedBox(height: ctx.sp(4)),
      ClipRRect(
        borderRadius: BorderRadius.circular(ctx.sp(5)),
        child: LinearProgressIndicator(
          value: pct, minHeight: ctx.sp(7),
          backgroundColor: Colors.grey.shade200,
          valueColor: AlwaysStoppedAnimation(col),
        ),
      ),
      SizedBox(height: ctx.sp(2)),
      Text(note, style: TextStyle(
          fontSize: ctx.sp(10), color: Colors.grey.shade400)),
    ]);
  }

  // ── Financial breakdown ────────────────────────────────────────────────────

  Widget _financialCard(BuildContext ctx) {
    final r = _result!;
    final totalValue = r.cropValuePerAcre * r.landAcres;
    return _card(ctx, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('💵 What Does Insurance Cost vs Pay?',
            style: _ts(ctx.sp(15), color: _kGreen, w: FontWeight.bold),
            overflow: TextOverflow.ellipsis, maxLines: 2),
        SizedBox(height: ctx.sp(4)),
        Text('For your \${r.landAcres.toStringAsFixed(1)}-acre \${r.cropName} farm, per year',
            style: _ts(ctx.sp(11), color: Colors.grey.shade500, w: FontWeight.w400),
            overflow: TextOverflow.ellipsis),
        SizedBox(height: ctx.sp(8)),
        // MSP data source badge
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: ctx.sp(10), vertical: ctx.sp(5)),
          decoration: BoxDecoration(
            color: _kGreenLt,
            borderRadius: BorderRadius.circular(ctx.sp(8)),
          ),
          child: Row(children: [
            Icon(Icons.info_outline_rounded, color: _kGreen, size: ctx.sp(14)),
            SizedBox(width: ctx.sp(5)),
            Expanded(child: Text(
              'Source: GoI MSP 2025-26 × national avg yield  ·  '
              'Premium: official PMFBY cap ${r.premiumRatePct.toStringAsFixed(1)}%',
              style: TextStyle(fontSize: ctx.sp(9.5), color: _kGreen),
              overflow: TextOverflow.ellipsis, maxLines: 2,
            )),
          ]),
        ),
        SizedBox(height: ctx.sp(12)),

        _finRow(ctx, 'Total crop value (MSP-based)', _fmtMoney(totalValue),
            Colors.grey.shade700, false),
        Divider(color: _kBorder, height: 1),
        _finRow(ctx, 'You pay (annual premium)', _fmtMoney(r.annualPremiumCost),
            _kRed, false),
        _finRow(ctx, 'Average payout per year', _fmtMoney(r.expectedPayoutValue),
            _kGreen, false),
        Divider(color: _kBorder, height: 1),
        _finRow(ctx,
            r.netExpectedValue >= 0 ? 'Net expected gain' : 'Net expected cost',
            _fmtMoney(r.netExpectedValue.abs()),
            r.netExpectedValue >= 0 ? _kGreen : _kRed, true),

        SizedBox(height: ctx.sp(14)),
        Container(
          padding: EdgeInsets.all(ctx.sp(14)),
          decoration: BoxDecoration(
            color: _kGoldLight,
            borderRadius: BorderRadius.circular(ctx.sp(12)),
            border: Border.all(color: _kGold.withOpacity(0.3)),
          ),
          child: Row(children: [
            Text('🏆', style: TextStyle(fontSize: ctx.sp(22))),
            SizedBox(width: ctx.sp(10)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Recommended Coverage Amount',
                  style: _ts(ctx.sp(12), color: _kGold, w: FontWeight.bold)),
              SizedBox(height: ctx.sp(2)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(_fmtMoney(r.recommendedCoverage),
                    style: _ts(ctx.sp(20), color: _kGold, w: FontWeight.bold)),
              ),
              Text('Covers worst-case (95 out of 100) season loss',
                  style: _ts(ctx.sp(10), color: Colors.brown.shade400,
                      w: FontWeight.w400)),
            ])),
          ]),
        ),

        SizedBox(height: ctx.sp(12)),
        Container(
          padding: EdgeInsets.all(ctx.sp(12)),
          decoration: BoxDecoration(
            color: _kGreenLt,
            borderRadius: BorderRadius.circular(ctx.sp(10)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, color: _kGreen, size: ctx.sp(18)),
            SizedBox(width: ctx.sp(8)),
            Expanded(child: Text(
              'Insurance pays when your loss is above '
              '${(r.breakEvenLossPct * 100).toStringAsFixed(0)}% of your crop value. '
              'Below that, the insurance company keeps the premium.',
              style: _ts(ctx.sp(11), color: _kGreen, w: FontWeight.w500, height: 1.5),
            )),
          ]),
        ),
      ],
    ));
  }

  Widget _finRow(BuildContext ctx, String label, String value,
      Color valueColor, bool bold) => Padding(
    padding: EdgeInsets.symmetric(vertical: ctx.sp(7)),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Flexible(child: Text(label,
          style: _ts(ctx.sp(13), color: Colors.grey.shade700,
              w: bold ? FontWeight.bold : FontWeight.w500),
          overflow: TextOverflow.ellipsis)),
      SizedBox(width: ctx.sp(8)),
      Text(value, style: _ts(ctx.sp(14), color: valueColor,
          w: bold ? FontWeight.bold : FontWeight.w600)),
    ]),
  );

  // ── Scenario card ──────────────────────────────────────────────────────────

  Widget _scenarioCard(BuildContext ctx) {
    final r = _result!;
    return _card(ctx, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('🌦 What Might Happen This Season?',
            style: _ts(ctx.sp(15), color: _kGreen, w: FontWeight.bold),
            overflow: TextOverflow.ellipsis, maxLines: 2),
        SizedBox(height: ctx.sp(4)),
        Text('Based on ${_weather!.years} years of real weather in ${_loc.name}',
            style: _ts(ctx.sp(11), color: Colors.grey.shade500, w: FontWeight.w400),
            overflow: TextOverflow.ellipsis),
        SizedBox(height: ctx.sp(14)),
        ...r.scenarios.map((sc) => Padding(
          padding: EdgeInsets.only(bottom: ctx.sp(10)),
          child: _scenarioRow(ctx, sc, r.landAcres * r.cropValuePerAcre),
        )),
      ],
    ));
  }

  Widget _scenarioRow(BuildContext ctx, _Scenario sc, double totalValue) {
    final lossValue = sc.lossMultiplier * totalValue;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(sc.emoji, style: TextStyle(fontSize: ctx.sp(22))),
      SizedBox(width: ctx.sp(8)),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(child: Text(sc.name,
              style: _ts(ctx.sp(13), color: Colors.grey.shade800),
              overflow: TextOverflow.ellipsis)),
          SizedBox(width: ctx.sp(4)),
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: ctx.sp(7), vertical: ctx.sp(2)),
            decoration: BoxDecoration(
                color: sc.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20)),
            child: Text('${(sc.probability * 100).toStringAsFixed(0)}/100 yrs',
                style: TextStyle(fontWeight: FontWeight.bold,
                    fontSize: ctx.sp(11), color: sc.color)),
          ),
        ]),
        SizedBox(height: ctx.sp(4)),
        ClipRRect(
          borderRadius: BorderRadius.circular(ctx.sp(5)),
          child: LinearProgressIndicator(
            value: sc.probability.clamp(0, 1), minHeight: ctx.sp(8),
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(sc.color),
          ),
        ),
        SizedBox(height: ctx.sp(3)),
        Text('${sc.description}. Potential loss: ${_fmtMoney(lossValue)}',
            style: TextStyle(fontSize: ctx.sp(10), color: Colors.grey.shade500),
            overflow: TextOverflow.ellipsis, maxLines: 2),
      ])),
    ]);
  }

  // ── Loss histogram ─────────────────────────────────────────────────────────

  Widget _lossHistogram(BuildContext ctx) {
    final r  = _result!;
    final ld = r.lossDistribution;

    const bins = 10;
    final lo = ld.first, hi = ld.last;
    final bw = hi > lo ? (hi - lo) / bins : 0.01;

    final counts = List.generate(bins, (b) {
      final bLo = lo + b * bw, bHi = bLo + bw;
      return ld.where((v) => v >= bLo &&
          (b == bins - 1 ? v <= bHi : v < bHi)).length;
    });
    final maxC = counts.reduce(max).toDouble();
    final avgLoss  = r.expectedLossPct;
    final meanBin  = ((avgLoss - lo) / (bw > 0 ? bw : 0.01))
        .floor().clamp(0, bins - 1);
    final chartH   = ctx.pick<double>(sm: 110, md: 150, lg: 170);

    return _card(ctx, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('📉 How Often Do Losses Happen?',
            style: _ts(ctx.sp(15), color: _kGreen, w: FontWeight.bold),
            overflow: TextOverflow.ellipsis, maxLines: 2),
        SizedBox(height: ctx.sp(4)),
        Text('Each bar = how many of 500 simulated seasons had that level of loss',
            style: _ts(ctx.sp(11), color: Colors.grey.shade500, w: FontWeight.w400)),
        SizedBox(height: ctx.sp(18)),

        SizedBox(
          height: chartH,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(bins, (i) {
              final hf   = maxC > 0 ? counts[i] / maxC : 0.0;
              final isMn = i == meanBin;
              final col  = i > bins * 0.6 ? _kRed
                         : i > bins * 0.3 ? _kAmber
                         : _kGreen;
              return Expanded(child: Padding(
                padding: EdgeInsets.symmetric(horizontal: ctx.sp(1.5)),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (isMn) Column(children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: ctx.sp(4), vertical: ctx.sp(2)),
                      decoration: BoxDecoration(color: _kGreen,
                          borderRadius: BorderRadius.circular(ctx.sp(4))),
                      child: Text('avg', style: TextStyle(
                          fontSize: ctx.sp(7), color: Colors.white,
                          fontWeight: FontWeight.bold)),
                    ),
                    SizedBox(height: ctx.sp(2)),
                  ]),
                  AnimatedContainer(
                    duration: Duration(milliseconds: 400 + i * 40),
                    curve: Curves.easeOut,
                    height: (chartH * 0.78) * hf,
                    decoration: BoxDecoration(
                      color: isMn ? _kGreen : col.withOpacity(0.5 + 0.5 * hf),
                      borderRadius: BorderRadius.vertical(
                          top: Radius.circular(ctx.sp(4))),
                    ),
                  ),
                ]),
              ));
            }),
          ),
        ),

        SizedBox(height: ctx.sp(6)),
        Row(children: List.generate(bins, (i) => Expanded(
          child: i % 2 == 0
              ? Text('${((lo + i * bw) * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontSize: ctx.sp(7), color: Colors.grey.shade400),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.clip, maxLines: 1)
              : const SizedBox.shrink(),
        ))),
        SizedBox(height: ctx.sp(2)),
        Center(child: Text('Crop loss as % of total value',
            style: TextStyle(
                fontSize: ctx.sp(10), color: Colors.grey.shade500))),
        SizedBox(height: ctx.sp(10)),
        Wrap(spacing: ctx.sp(14), runSpacing: ctx.sp(6), children: [
          _dot(ctx, _kGreen,  'Low loss'),
          _dot(ctx, _kAmber,  'Medium loss'),
          _dot(ctx, _kRed,    'High loss'),
          _dot(ctx, _kGreen,  'Average'),
        ]),
      ],
    ));
  }

  // ── Advice card ────────────────────────────────────────────────────────────

  Widget _adviceCard(BuildContext ctx) {
    final r = _result!;
    Color col; IconData ico;
    switch (r.verdict) {
      case 'RECOMMENDED':
        col = _kGreen; ico = Icons.check_circle_outline_rounded; break;
      case 'MARGINAL':
        col = _kAmber; ico = Icons.info_outline_rounded; break;
      default:
        col = _kRed;   ico = Icons.warning_amber_rounded;
    }

    return Container(
      padding: EdgeInsets.all(ctx.cPad),
      decoration: BoxDecoration(
        color: col.withOpacity(0.06),
        borderRadius: BorderRadius.circular(ctx.sp(14)),
        border: Border.all(color: col.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ico, color: col, size: ctx.sp(22)),
          SizedBox(width: ctx.sp(8)),
          Expanded(child: Text('Our Advice for You',
              style: _ts(ctx.sp(14), color: col, w: FontWeight.bold),
              overflow: TextOverflow.ellipsis)),
        ]),
        SizedBox(height: ctx.sp(10)),
        Text(r.verdictReason,
            style: TextStyle(fontSize: ctx.sp(12.5),
                color: Colors.grey.shade800, height: 1.6)),
        SizedBox(height: ctx.sp(12)),
        Wrap(spacing: ctx.sp(6), runSpacing: ctx.sp(6), children: [
          _infoChip(ctx, '📅 ${_weather!.years}-yr data', _kGreen),
          _infoChip(ctx,
              '🌧 Volatility: ${(r.weatherVolatility * 100).toStringAsFixed(0)}%',
              _kGreen),
          _infoChip(ctx,
              '📋 Claim prob: ${(r.payoutProbability * 100).toStringAsFixed(0)}%',
              col),
          _infoChip(ctx,
              '💰 Break-even: ${(r.breakEvenLossPct * 100).toStringAsFixed(0)}% loss',
              _kGold),
          _infoChip(ctx,
              '🎯 Risk: ${r.cropRiskScore.toStringAsFixed(0)}/100',
              r.cropRiskScore >= 60 ? _kRed : r.cropRiskScore >= 35 ? _kAmber : _kGreen),
        ]),
        SizedBox(height: ctx.sp(12)),
        Container(
          padding: EdgeInsets.all(ctx.sp(12)),
          decoration: BoxDecoration(
            color: _kGreenLt,
            borderRadius: BorderRadius.circular(ctx.sp(10)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.lightbulb_outline_rounded,
                color: _kGold, size: ctx.sp(18)),
            SizedBox(width: ctx.sp(8)),
            Expanded(child: Text(
              'This uses real historical weather data. '
              'For final insurance decisions, talk to your nearest '
              'Krishi Vigyan Kendra (KVK) or bank about PMFBY schemes.',
              style: TextStyle(fontSize: ctx.sp(11),
                  color: Colors.grey.shade700, height: 1.5),
            )),
          ]),
        ),
      ]),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  Widget _card(BuildContext ctx, {required Widget child}) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(ctx.cPad),
    decoration: BoxDecoration(
      color: _kSurface,
      borderRadius: BorderRadius.circular(ctx.sp(16)),
      border: Border.all(color: _kBorder),
      boxShadow: [BoxShadow(color: _kGreen.withOpacity(0.04),
          blurRadius: 10, offset: const Offset(0, 4))],
    ),
    child: child,
  );

  BoxDecoration _surfaceDec(BuildContext ctx) => BoxDecoration(
    color: _kSurface,
    borderRadius: BorderRadius.circular(ctx.sp(14)),
    border: Border.all(color: _kBorder),
    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
        blurRadius: 8, offset: const Offset(0, 3))],
  );

  Widget _pill(BuildContext ctx, String label, Color fg, Color bg) => Container(
    padding: EdgeInsets.symmetric(
        horizontal: ctx.sp(10), vertical: ctx.sp(4)),
    decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withOpacity(0.3))),
    child: Text(label, style: TextStyle(
        fontSize: ctx.sp(11), fontWeight: FontWeight.bold, color: fg)),
  );

  Widget _infoChip(BuildContext ctx, String label, Color color) => Container(
    padding: EdgeInsets.symmetric(
        horizontal: ctx.sp(9), vertical: ctx.sp(5)),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: Text(label, style: TextStyle(
        fontSize: ctx.sp(11), fontWeight: FontWeight.w600, color: color)),
  );

  Widget _pmfbyBadge(BuildContext ctx, String label, String rate, Color color) =>
      Expanded(child: Container(
        padding: EdgeInsets.symmetric(
            vertical: ctx.sp(6), horizontal: ctx.sp(4)),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(ctx.sp(8)),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(children: [
          Text(rate, style: _ts(ctx.sp(14), color: color, w: FontWeight.bold)),
          Text(label, style: TextStyle(
              fontSize: ctx.sp(9.5), color: color,
              fontWeight: FontWeight.w500),
              textAlign: TextAlign.center),
        ]),
      ));

  Widget _dot(BuildContext ctx, Color color, String label) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: ctx.sp(10), height: ctx.sp(10),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        SizedBox(width: ctx.sp(4)),
        Text(label, style: TextStyle(
            fontSize: ctx.sp(10), color: Colors.grey.shade600)),
      ]);

  Widget _dropdown<T>({
    required BuildContext ctx,
    required T value, required List<T> items,
    required String Function(T) label,
    required ValueChanged<T?> onChanged,
  }) => Container(
    padding: EdgeInsets.symmetric(
        horizontal: ctx.sp(12), vertical: ctx.sp(2)),
    decoration: BoxDecoration(
      color: _kGreen.withOpacity(0.04),
      borderRadius: BorderRadius.circular(ctx.sp(12)),
      border: Border.all(color: _kBorder),
    ),
    child: DropdownButton<T>(
      value: value, isExpanded: true,
      underline: const SizedBox.shrink(),
      style: TextStyle(color: Colors.black87,
          fontSize: ctx.sp(14), fontWeight: FontWeight.w500),
      items: items
          .map((i) => DropdownMenuItem(value: i, child: Text(label(i))))
          .toList(),
      onChanged: onChanged,
    ),
  );
}