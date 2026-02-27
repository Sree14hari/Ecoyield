import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// Unit conversion
// 1 tonne/hectare = 404.686 kg/acre
// ─────────────────────────────────────────────────────────────────────────────

const double kTHaToKgAcre = 404.686;

double toKgAcre(double tHa) => tHa * kTHaToKgAcre;

String fmtYield(double tHa) =>
    '${toKgAcre(tHa).toStringAsFixed(0)} kg/acre';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens — warm earthy palette
// ─────────────────────────────────────────────────────────────────────────────

const kBg          = Color(0xFFFAF6EF);
const kSurface     = Color(0xFFFFFFFF);
const kBrown       = Color(0xFF7C4B2A);
const kOlive       = Color(0xFF5C6E2E);
const kAmber       = Color(0xFFD4860A);
const kRed         = Color(0xFFB83232);
const kSky         = Color(0xFF2F78B4);
const kBorderLight = Color(0xFFE8DFD0);

TextStyle _label(double sz, {Color color = kBrown, FontWeight w = FontWeight.w600}) =>
    TextStyle(fontSize: sz, fontWeight: w, color: color, fontFamily: 'Georgia');

// ─────────────────────────────────────────────────────────────────────────────
// Open-Meteo historical weather 
// ─────────────────────────────────────────────────────────────────────────────

class HistoricalWeatherService {
  static String? injectedLocationName;

  static Future<HistoricalWeatherData> fetch({
    required double lat,
    required double lon,
    int years = 5,
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

    final res = await http.get(url).timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) throw Exception('Weather API error ${res.statusCode}');

    final body  = jsonDecode(res.body) as Map<String, dynamic>;
    final daily = body['daily'] as Map<String, dynamic>;

    final rain = (daily['precipitation_sum']   as List<dynamic>)
        .whereType<num>().map((v) => v.toDouble()).toList();
    final temp = (daily['temperature_2m_mean'] as List<dynamic>)
        .whereType<num>().map((v) => v.toDouble()).toList();

    if (rain.isEmpty || temp.isEmpty) {
      throw Exception('No weather data returned for this location.');
    }

    return HistoricalWeatherData(
      dailyRainfall:    rain,
      dailyTemperature: temp,
      locationName:     injectedLocationName ?? '$lat°, $lon°',
      yearsOfData:      years,
    );
  }

  static String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Historical weather data + statistics
// ─────────────────────────────────────────────────────────────────────────────

class HistoricalWeatherData {
  final List<double> dailyRainfall;
  final List<double> dailyTemperature;
  final String locationName;
  final int yearsOfData;

  const HistoricalWeatherData({
    required this.dailyRainfall,
    required this.dailyTemperature,
    required this.locationName,
    required this.yearsOfData,
  });

  List<double> get annualRainfallSamples {
    final list = <double>[];
    const dpy = 365;
    for (int i = 0; i + dpy <= dailyRainfall.length; i += dpy) {
      list.add(_sum(dailyRainfall.sublist(i, i + dpy)));
    }
    if (list.isEmpty) {
      list.add(_sum(dailyRainfall) / dailyRainfall.length * 365);
    }
    return list;
  }

  List<double> get annualMeanTempSamples {
    final list = <double>[];
    const dpy = 365;
    for (int i = 0; i + dpy <= dailyTemperature.length; i += dpy) {
      list.add(_mean(dailyTemperature.sublist(i, i + dpy)));
    }
    if (list.isEmpty) list.add(_mean(dailyTemperature));
    return list;
  }

  double get meanRainfall => _mean(annualRainfallSamples);
  double get stdRainfall  => _std(annualRainfallSamples);
  double get meanTemp     => _mean(annualMeanTempSamples);
  double get stdTemp      => _std(annualMeanTempSamples);

  static double _sum(List<double> s) =>
      s.fold(0.0, (double a, double b) => a + b);
  static double _mean(List<double> s) =>
      s.isEmpty ? 0.0 : _sum(s) / s.length;
  static double _std(List<double> s) {
    if (s.length < 2) return 0.0;
    final m = _mean(s);
    return sqrt(s.map((v) => pow(v - m, 2) as double)
        .fold(0.0, (double a, double b) => a + b) / s.length);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Crop profiles
// ─────────────────────────────────────────────────────────────────────────────

class CropProfile {
  final String   name, emoji;
  final Color    color;
  final IconData icon;
  final double   peakYield;   // t/ha at ideal conditions
  final String   bagSizeKg;   // typical market bag size label
  final String   commonName;  // farmer-friendly local name

  // Rainfall thresholds (annual mm)
  final double rMin, rLow, rHigh, rMax;

  // Temperature thresholds (annual mean °C)
  final double tMin, tLow, tHigh, tMax;

  final double noiseCv;

  const CropProfile({
    required this.name,
    required this.emoji,
    required this.color,
    required this.icon,
    required this.peakYield,
    required this.bagSizeKg,
    required this.commonName,
    required this.rMin, required this.rLow,
    required this.rHigh, required this.rMax,
    required this.tMin, required this.tLow,
    required this.tHigh, required this.tMax,
    this.noiseCv = 0.08,
  });

  static double _ps(double v, double mn, double lo, double hi, double mx) {
    if (v <= mn || v >= mx) return 0.0;
    if (v >= lo && v <= hi) return 1.0;
    if (v < lo) return (v - mn) / (lo - mn);
    return (mx - v) / (mx - hi);
  }

  double rainStress(double annualMm) => _ps(annualMm, rMin, rLow, rHigh, rMax);
  double tempStress(double annualMeanC) => _ps(annualMeanC, tMin, tLow, tHigh, tMax);

  double yieldAt(double rain, double temp, double noise) =>
      (peakYield * rainStress(rain) * tempStress(temp) * (1 + noise))
          .clamp(0.0, peakYield * 1.2);

  /// Peak yield in kg/acre
  double get peakYieldKgAcre => toKgAcre(peakYield);
}

const kCropProfiles = <CropProfile>[
  CropProfile(
    name: 'Rice', emoji: '🌾',
    color: Color(0xFF10B981), icon: Icons.rice_bowl_outlined,
    peakYield: 5.5,
    bagSizeKg: '50',
    commonName: 'Paddy / Chawal',
    rMin: 400,  rLow: 1200, rHigh: 3500, rMax: 6000,
    tMin: 20,   tLow: 24,   tHigh: 32,   tMax: 38,
  ),
  CropProfile(
    name: 'Wheat', emoji: '🌿',
    color: Color(0xFFD4860A), icon: Icons.grass,
    peakYield: 4.5,
    bagSizeKg: '50',
    commonName: 'Gehun',
    rMin: 200,  rLow: 450,  rHigh: 900,  rMax: 1400,
    tMin: 5,    tLow: 10,   tHigh: 20,   tMax: 28,
  ),
  CropProfile(
    name: 'Maize', emoji: '🌽',
    color: Color(0xFFF97316), icon: Icons.eco,
    peakYield: 6.0,
    bagSizeKg: '50',
    commonName: 'Makka / Corn',
    rMin: 250,  rLow: 500,  rHigh: 1100, rMax: 1800,
    tMin: 8,    tLow: 12,   tHigh: 24,   tMax: 32,
  ),
  CropProfile(
    name: 'Sugarcane', emoji: '🎋',
    color: Color(0xFF8B5CF6), icon: Icons.local_florist,
    peakYield: 80.0,
    bagSizeKg: '100',
    commonName: 'Ganna / Ikshu',
    rMin: 700,  rLow: 1500, rHigh: 4000, rMax: 6000,
    tMin: 18,   tLow: 22,   tHigh: 32,   tMax: 40,
  ),
  CropProfile(
    name: 'Cotton', emoji: '🌸',
    color: Color(0xFF06B6D4), icon: Icons.cloud_outlined,
    peakYield: 2.2,
    bagSizeKg: '170',
    commonName: 'Kapas / Karpas',
    rMin: 300,  rLow: 550,  rHigh: 950,  rMax: 1500,
    tMin: 15,   tLow: 20,   tHigh: 32,   tMax: 40,
  ),
];

CropProfile cropByName(String n) =>
    kCropProfiles.firstWhere((c) => c.name == n, orElse: () => kCropProfiles[0]);

// ─────────────────────────────────────────────────────────────────────────────
// Monte Carlo engine
// ─────────────────────────────────────────────────────────────────────────────

class SimulationResult {
  final List<double> yields;  // sorted ascending, in t/ha internally
  final double mean, p5, p25, p50, p75, p95, stdDev;
  final List<_Bin> histogram;
  final CropProfile crop;
  final double inputMeanRain, inputMeanTemp;

  const SimulationResult({
    required this.yields,
    required this.mean,  required this.p5,
    required this.p25,   required this.p50,
    required this.p75,   required this.p95,
    required this.stdDev,
    required this.histogram,
    required this.crop,
    required this.inputMeanRain, required this.inputMeanTemp,
  });
}

class _Bin {
  final double lo, hi, freq;
  final int count;
  const _Bin(this.lo, this.hi, this.count, this.freq);
}

class MonteCarloEngine {
  final _rng = Random();

  double _gauss(double mean, double std) {
    var u1 = _rng.nextDouble();
    final u2 = _rng.nextDouble();
    if (u1 == 0) u1 = 1e-10;
    return mean + std * sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }

  SimulationResult run({
    required double meanRain, required double stdRain,
    required double meanTemp, required double stdTemp,
    required CropProfile crop,
  }) {
    const n = 500;
    final effStdRain = stdRain.clamp(meanRain * 0.05, double.infinity);
    final effStdTemp = stdTemp.clamp(0.3,             double.infinity);

    final yields = <double>[];
    for (var i = 0; i < n; i++) {
      final rain  = _gauss(meanRain, effStdRain).clamp(0.0, 8000.0);
      final temp  = _gauss(meanTemp, effStdTemp);
      final noise = _gauss(0, crop.noiseCv);
      yields.add(crop.yieldAt(rain, temp, noise));
    }
    yields.sort();

    double pct(double p) => yields[(n * p).floor().clamp(0, n - 1)];
    final mean = yields.fold(0.0, (double a, double b) => a + b) / n;
    final variance = yields
        .map((y) => pow(y - mean, 2) as double)
        .fold(0.0, (double a, double b) => a + b) / n;

    // Build histogram in kg/acre for display
    const bins = 10;
    final yieldsKg = yields.map(toKgAcre).toList();
    final lo = yieldsKg.first, hi = yieldsKg.last;
    final bw = hi > lo ? (hi - lo) / bins : 1.0;
    final histogram = List.generate(bins, (b) {
      final bLo = lo + b * bw, bHi = bLo + bw;
      final cnt = yieldsKg
          .where((y) => y >= bLo && (b == bins - 1 ? y <= bHi : y < bHi))
          .length;
      return _Bin(bLo, bHi, cnt, cnt / n);
    });

    return SimulationResult(
      yields:         yields,
      mean:           mean,
      p5:             pct(0.05),
      p25:            pct(0.25),
      p50:            pct(0.50),
      p75:            pct(0.75),
      p95:            pct(0.95),
      stdDev:         sqrt(variance),
      histogram:      histogram,
      crop:           crop,
      inputMeanRain:  meanRain,
      inputMeanTemp:  meanTemp,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Locations
// ─────────────────────────────────────────────────────────────────────────────

class FarmLocation {
  final String name, region;
  final double lat, lon;
  const FarmLocation(this.name, this.region, this.lat, this.lon);
  String get display => '$name, $region';
}

const kLocations = <FarmLocation>[
  FarmLocation('Kerala',         'India',    10.85,  76.27),
  FarmLocation('Punjab',         'India',    31.15,  75.34),
  FarmLocation('Maharashtra',    'India',    19.75,  75.71),
  FarmLocation('Uttar Pradesh',  'India',    26.85,  80.91),
  FarmLocation('Andhra Pradesh', 'India',    15.91,  79.74),
  FarmLocation('Midwest (Iowa)', 'USA',      41.87, -93.10),
  FarmLocation('São Paulo',      'Brazil',  -22.25, -48.30),
  FarmLocation('East Anglia',    'UK',       52.24,   0.90),
  FarmLocation('Punjab',         'Pakistan', 31.55,  72.31),
  FarmLocation('Kano',           'Nigeria',  12.00,   8.52),
];

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class MonteCarloSimulationPage extends StatefulWidget {
  const MonteCarloSimulationPage({Key? key}) : super(key: key);

  @override
  State<MonteCarloSimulationPage> createState() => _PageState();
}

class _PageState extends State<MonteCarloSimulationPage>
    with SingleTickerProviderStateMixin {

  FarmLocation _loc  = kLocations[0];   // Kerala
  CropProfile  _crop = kCropProfiles[0]; // Rice
  int          _yrs  = 5;
  double       _acres = 2.0;

  HistoricalWeatherData? _weather;
  SimulationResult?      _result;
  bool   _loadingW = false;
  bool   _loadingS = false;
  String? _error;

  late AnimationController _anim;
  late Animation<double>   _fade;
  final _engine = MonteCarloEngine();

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
      _loadingW = true; _loadingS = false;
      _result = null;   _weather  = null; _error = null;
    });
    _anim.reset();

    try {
      HistoricalWeatherService.injectedLocationName = _loc.display;
      final w = await HistoricalWeatherService.fetch(
          lat: _loc.lat, lon: _loc.lon, years: _yrs);

      setState(() { _weather = w; _loadingW = false; _loadingS = true; });
      await Future.delayed(const Duration(milliseconds: 60));

      final r = _engine.run(
        meanRain: w.meanRainfall, stdRain: w.stdRainfall,
        meanTemp: w.meanTemp,     stdTemp: w.stdTemp,
        crop:     _crop,
      );

      setState(() { _result = r; _loadingS = false; });
      _anim.forward();
    } catch (e) {
      setState(() {
        _loadingW = false; _loadingS = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loadingW || _loadingS;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.green, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () { HapticFeedback.lightImpact(); Navigator.pop(context); },
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('My Harvest Forecast',
              style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.bold, fontSize: 18, fontFamily: 'Georgia')),
          Text('What will I get this season?',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11)),
        ]),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
          children: [
            _configCard(),
            const SizedBox(height: 12),
            _runBtn(busy),
            const SizedBox(height: 16),
            if (_loadingW) _loadCard('☁️  Checking the weather history…',
                'Looking at $_yrs years of rain & temperature for ${_loc.name}'),
            if (_loadingS) _loadCard('🌾  Working out your harvest…',
                'Trying 500 different weather outcomes'),
            if (_error != null) _errorCard(),
            if (!busy && _result != null && _weather != null)
              FadeTransition(opacity: _fade, child: Column(children: [
                _weatherBanner(),
                const SizedBox(height: 12),
                _heroCard(),
                const SizedBox(height: 12),
                _quickFactsRow(),
                const SizedBox(height: 12),
                _scenarioStrip(),
                const SizedBox(height: 12),
                _histChart(),
                const SizedBox(height: 12),
                _adviceCard(),
              ])),
          ],
        ),
      ),
    );
  }

  // ── Config card ────────────────────────────────────────────────────────────

  Widget _configCard() => _card(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Icon(Icons.agriculture_rounded, color: kBrown, size: 20),
        const SizedBox(width: 6),
        Text('Tell us about your farm', style: _label(15, color: kBrown, w: FontWeight.bold)),
      ]),
      const SizedBox(height: 14),

      Text('📍 Where is your farm?',
          style: _label(13, color: Colors.green.shade700)),
      const SizedBox(height: 6),
      _dropdown<FarmLocation>(
        value: _loc, items: kLocations, label: (l) => l.display,
        onChanged: (v) { if (v != null) setState(() => _loc = v); },
      ),

      const SizedBox(height: 14),
      Text('🌾 What do you grow?',
          style: _label(13, color: Colors.brown.shade700)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: kCropProfiles.map((cp) {
        final sel = _crop.name == cp.name;
        return GestureDetector(
          onTap: () { HapticFeedback.selectionClick(); setState(() => _crop = cp); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: sel ? cp.color : cp.color.withOpacity(0.09),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: sel ? cp.color : cp.color.withOpacity(0.3)),
            ),
            child: Text('${cp.emoji}  ${cp.name}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : cp.color)),
          ),
        );
      }).toList()),

      const SizedBox(height: 14),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('🏡 How many acres do you farm?',
            style: _label(13, color: Colors.brown.shade700)),
        _pill('${_acres.toStringAsFixed(1)} acres', kBrown, kBrown.withOpacity(0.1)),
      ]),
      SliderTheme(
        data: SliderThemeData(
          activeTrackColor: kBrown,
          thumbColor: kBrown,
          inactiveTrackColor: kBrown.withOpacity(0.2),
          overlayColor: kBrown.withOpacity(0.08),
          trackHeight: 4,
        ),
        child: Slider(
          value: _acres, min: 0.5, max: 20, divisions: 39,
          onChanged: (v) => setState(() => _acres = v),
        ),
      ),

      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('📅 Years of weather history to use:',
            style: _label(13, color: Colors.brown.shade700)),
        _pill('$_yrs years', kOlive, kOlive.withOpacity(0.1)),
      ]),
      SliderTheme(
        data: SliderThemeData(
          activeTrackColor: kOlive,
          thumbColor: kOlive,
          inactiveTrackColor: kOlive.withOpacity(0.2),
          overlayColor: kOlive.withOpacity(0.08),
          trackHeight: 4,
        ),
        child: Slider(
          value: _yrs.toDouble(), min: 2, max: 10, divisions: 8,
          onChanged: (v) => setState(() => _yrs = v.round()),
        ),
      ),
    ],
  ));

  // ── Run button ─────────────────────────────────────────────────────────────

  Widget _runBtn(bool busy) => SizedBox(
    width: double.infinity, height: 56,
    child: ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: kOlive, foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 3,
      ),
      icon: busy
          ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
          : const Icon(Icons.search_rounded, size: 22),
      label: Text(
        busy ? 'Working out your forecast…' : '🔍  Show Me My Harvest Forecast',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'Georgia'),
      ),
      onPressed: busy ? null : _run,
    ),
  );

  // ── Loading ────────────────────────────────────────────────────────────────

  Widget _loadCard(String title, String sub) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: kSurface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 8, offset: const Offset(0, 3))]),
    child: Row(children: [
      SizedBox(width: 34, height: 34,
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(kBrown), strokeWidth: 3)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: _label(14, color: kBrown, w: FontWeight.bold)),
        const SizedBox(height: 3),
        Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ])),
    ]),
  );

  // ── Error ──────────────────────────────────────────────────────────────────

  Widget _errorCard() => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade200)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.wifi_off_rounded, color: Colors.red.shade600, size: 22),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Could not load weather data',
            style: _label(14, color: Colors.red.shade700, w: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(_error ?? '', style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
        const SizedBox(height: 6),
        Text('Please check your internet connection and try again.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ])),
    ]),
  );

  // ── Weather banner ─────────────────────────────────────────────────────────

  Widget _weatherBanner() {
    final w = _weather!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kSky.withOpacity(0.85), kSky],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        const Icon(Icons.cloud_done_outlined, color: Colors.white, size: 22),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Real weather data loaded ✓',
              style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.bold, fontSize: 13)),
          Text('${w.dailyRainfall.length} days of history · ${_loc.display}',
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${w.meanRainfall.toStringAsFixed(0)} mm rain/yr',
              style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.bold, fontSize: 12)),
          Text('${w.meanTemp.toStringAsFixed(1)}°C average',
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ]),
      ]),
    );
  }

  // ── Hero card — main result ────────────────────────────────────────────────

  Widget _heroCard() {
    final r   = _result!;
    final cp  = _crop;
    final meanKg = toKgAcre(r.mean);
    final pct = (r.mean / cp.peakYield * 100).clamp(0.0, 100.0);
    final col = pct >= 65 ? kOlive : pct >= 40 ? kAmber : kRed;
    final totalFarmKg = meanKg * _acres;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: col.withOpacity(0.3), width: 1.5),
        boxShadow: [BoxShadow(color: kBrown.withOpacity(0.06),
            blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Column(children: [
        // Title
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: col.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(cp.emoji, style: const TextStyle(fontSize: 28)),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Expected ${cp.name} Harvest',
                style: _label(13, color: Colors.grey.shade600, w: FontWeight.w500)),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(meanKg.toStringAsFixed(0),
                  style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900,
                      color: col, fontFamily: 'Georgia')),
              Padding(
                padding: const EdgeInsets.only(bottom: 7, left: 5),
                child: Text('kg/acre',
                    style: _label(14, color: Colors.grey.shade500, w: FontWeight.w500)),
              ),
            ]),
          ])),
        ]),

        const SizedBox(height: 16),

        // Potential bar
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('How well is your land doing?',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            _pill('${pct.toStringAsFixed(0)}% of best possible', col, col.withOpacity(0.1)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct / 100, minHeight: 14,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(col),
            ),
          ),
          const SizedBox(height: 5),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('0', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
            Text('Best ever: ${cp.peakYieldKgAcre.toStringAsFixed(0)} kg/acre',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
          ]),
        ]),

        const SizedBox(height: 16),
        _divider(),
        const SizedBox(height: 14),

        // Your whole farm total
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kBrown.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBrown.withOpacity(0.15)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('🏡', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your ${_acres.toStringAsFixed(1)}-acre farm total',
                  style: _label(12, color: kBrown, w: FontWeight.w500)),
              Row(children: [
                Text(totalFarmKg.toStringAsFixed(0),
                    style: _label(22, color: kBrown, w: FontWeight.bold)),
                const SizedBox(width: 5),
                Text('kg total', style: _label(12, color: Colors.brown.shade400, w: FontWeight.w500)),
              ]),
            ])),
          ]),
        ),

        const SizedBox(height: 14),

        // Good vs bad season
        Row(children: [
          Expanded(child: _seasonBox(
            icon: '☀️', label: 'Good Season',
            kg: toKgAcre(r.p75), color: kOlive, bg: kOlive.withOpacity(0.08),
            note: '1 in 4 years',
          )),
          const SizedBox(width: 10),
          Expanded(child: _seasonBox(
            icon: '🌧', label: 'Tough Season',
            kg: toKgAcre(r.p25), color: kRed, bg: kRed.withOpacity(0.07),
            note: '1 in 4 years',
          )),
        ]),
      ]),
    );
  }

  Widget _seasonBox({
    required String icon, required String label,
    required double kg, required Color color,
    required Color bg, required String note,
  }) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(icon, style: const TextStyle(fontSize: 20)),
      const SizedBox(height: 6),
      Text(kg.toStringAsFixed(0),
          style: _label(18, color: color, w: FontWeight.bold)),
      Text('kg/acre', style: _label(10, color: color.withOpacity(0.7), w: FontWeight.w500)),
      const SizedBox(height: 2),
      Text(label, style: _label(12, color: Colors.grey.shade700)),
      Text(note, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
    ]),
  );

  // ── Quick facts row ────────────────────────────────────────────────────────

  Widget _quickFactsRow() {
    final r  = _result!;
    final cp = _crop;
    final meanKg     = toKgAcre(r.mean);
    final bagSz      = double.tryParse(cp.bagSizeKg) ?? 50.0;
    final bags       = (meanKg / bagSz).floor();
    final totalKg    = meanKg * _acres;
    final totalBags  = (totalKg / bagSz).floor();

    return _card(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('📦 In Simple Numbers', style: _label(15, color: kBrown, w: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('What does your harvest actually look like?',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _factTile(
            '${bags.toString()} bags',
            'Per acre (${cp.bagSizeKg} kg bags)',
            '🎒', kOlive,
          )),
          const SizedBox(width: 10),
          Expanded(child: _factTile(
            '${totalBags.toString()} bags',
            'Your whole farm',
            '🏡', kBrown,
          )),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _factTile(
            '${totalKg.toStringAsFixed(0)} kg',
            'Total from your farm',
            '⚖️', kAmber,
          )),
          const SizedBox(width: 10),
          Expanded(child: _factTile(
            _riskLabel(r.mean, cp.peakYield),
            'Season risk level',
            _riskEmoji(r.mean, cp.peakYield), kRed,
          )),
        ]),
      ],
    ));
  }

  String _riskLabel(double mean, double peak) {
    final pct = mean / peak * 100;
    if (pct >= 65) return 'Low Risk';
    if (pct >= 40) return 'Medium Risk';
    return 'High Risk';
  }

  String _riskEmoji(double mean, double peak) {
    final pct = mean / peak * 100;
    if (pct >= 65) return '🟢';
    if (pct >= 40) return '🟡';
    return '🔴';
  }

  Widget _factTile(String value, String label, String icon, Color color) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withOpacity(0.07),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(icon, style: const TextStyle(fontSize: 20)),
      const SizedBox(height: 6),
      Text(value, style: _label(17, color: color, w: FontWeight.bold)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
    ]),
  );

  // ── Scenario strip ─────────────────────────────────────────────────────────

  Widget _scenarioStrip() {
    final r = _result!;
    final n = r.yields.length.toDouble();
    final great = r.yields.where((y) => y >= r.p75).length;
    final ok    = r.yields.where((y) => y >= r.p25 && y < r.p75).length;
    final bad   = r.yields.where((y) => y < r.p25).length;

    return _card(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('🎲 If we ran through 100 growing seasons…',
            style: _label(15, color: kBrown, w: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Based on $_yrs years of real weather in ${_loc.name}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 16),

        _scenarioRow('☀️', 'Great harvest',
            'More than ${toKgAcre(r.p75).toStringAsFixed(0)} kg/acre',
            (great / n * 100).round(), kOlive),
        const SizedBox(height: 10),
        _scenarioRow('🌤', 'Normal harvest',
            '${toKgAcre(r.p25).toStringAsFixed(0)} – ${toKgAcre(r.p75).toStringAsFixed(0)} kg/acre',
            (ok / n * 100).round(), kAmber),
        const SizedBox(height: 10),
        _scenarioRow('🌧', 'Difficult harvest',
            'Less than ${toKgAcre(r.p25).toStringAsFixed(0)} kg/acre',
            (bad / n * 100).round(), kRed),

        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _crop.color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _crop.color.withOpacity(0.2)),
          ),
          child: Row(children: [
            Text(_crop.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Typical ${_crop.name} harvest for your location: '
              '${toKgAcre(r.p25).toStringAsFixed(0)} – ${toKgAcre(r.p75).toStringAsFixed(0)} kg/acre',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _crop.color),
            )),
          ]),
        ),
      ],
    ));
  }

  Widget _scenarioRow(String emoji, String label, String desc,
      int pct, Color color) => Row(children: [
    Text(emoji, style: const TextStyle(fontSize: 22)),
    const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: _label(13, color: Colors.grey.shade800)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20)),
          child: Text('$pct out of 100',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color)),
        ),
      ]),
      const SizedBox(height: 5),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: pct / 100, minHeight: 10,
          backgroundColor: Colors.grey.shade200,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
      const SizedBox(height: 3),
      Text(desc, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
    ])),
  ]);

  // ── Histogram ──────────────────────────────────────────────────────────────

  Widget _histChart() {
    final r = _result!;
    final maxF = r.histogram.map((b) => b.freq).reduce(max);

    // Find which bin the mean falls into (histogram is already in kg/acre)
    final meanKg = toKgAcre(r.mean);
    final meanBinIdx = r.histogram.indexWhere(
        (b) => meanKg >= b.lo && meanKg < b.hi);

    return _card(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('📊 What Range of Harvests Should You Expect?',
            style: _label(15, color: kBrown, w: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Each bar shows how common that harvest level is across 500 simulated seasons',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 20),

        SizedBox(
          height: 140,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(r.histogram.length, (i) {
              final b    = r.histogram[i];
              final hf   = maxF > 0 ? b.freq / maxF : 0.0;
              final isMn = i == (meanBinIdx < 0 ? 0 : meanBinIdx);
              return Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (isMn) Column(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(color: kAmber,
                          borderRadius: BorderRadius.circular(4)),
                      child: const Text('avg',
                          style: TextStyle(fontSize: 7, color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 2),
                  ]),
                  AnimatedContainer(
                    duration: Duration(milliseconds: 400 + i * 40),
                    curve: Curves.easeOut,
                    height: 110 * hf,
                    decoration: BoxDecoration(
                      color: isMn
                          ? kAmber
                          : _crop.color.withOpacity(0.5 + 0.5 * hf),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                    ),
                  ),
                ]),
              ));
            }),
          ),
        ),

        const SizedBox(height: 6),
        // X-axis labels — show every other bin in kg/acre
        Row(children: List.generate(r.histogram.length, (i) => Expanded(
          child: i % 2 == 0
              ? Text(r.histogram[i].lo.toStringAsFixed(0),
                  style: TextStyle(fontSize: 7, color: Colors.grey.shade400),
                  textAlign: TextAlign.center)
              : const SizedBox.shrink(),
        ))),
        const SizedBox(height: 2),
        Center(child: Text('Harvest (kg/acre)',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500))),

        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 6, children: [
          _dot(_crop.color, '${_crop.name} harvest'),
          _dot(kAmber, 'Your expected average'),
        ]),
      ],
    ));
  }

  // ── Advice card ────────────────────────────────────────────────────────────

  Widget _adviceCard() {
    final r  = _result!;
    final cp = _crop;
    final w  = _weather!;
    final pct = (r.mean / cp.peakYield * 100).clamp(0.0, 100.0);

    final rFit = w.meanRainfall >= cp.rLow && w.meanRainfall <= cp.rHigh;
    final tFit = w.meanTemp     >= cp.tLow && w.meanTemp     <= cp.tHigh;

    String headline, body;
    Color  hColor;
    IconData hIcon;

    if (pct >= 65) {
      headline = '✅ Great news — ${cp.name} grows well here!';
      hColor   = kOlive;
      hIcon    = Icons.check_circle_outline_rounded;
      body     = 'The weather in ${_loc.name} is well suited for ${cp.name}. '
                 'You should get strong, reliable harvests most years. '
                 'Keep up good farming practices and you are on the right track!';
    } else if (pct >= 35) {
      headline = '⚠️ Decent results — but some risk';
      hColor   = kAmber;
      hIcon    = Icons.info_outline_rounded;
      body     = '${_loc.name} can grow ${cp.name}, but conditions are not perfect. '
                 '${!rFit ? "The rainfall here is outside the ideal range for this crop. " : ""}'
                 '${!tFit ? "The temperature is not ideal for this crop. " : ""}'
                 'Consider using drip irrigation or asking your local agriculture officer for advice on suitable varieties.';
    } else {
      headline = '❌ This crop is a difficult fit for your area';
      hColor   = kRed;
      hIcon    = Icons.warning_amber_rounded;
      body     = '${_loc.name}\'s climate is not well suited for ${cp.name}. '
                 '${!rFit ? "Rainfall here (${w.meanRainfall.toStringAsFixed(0)} mm/year) is outside the ideal range. " : ""}'
                 '${!tFit ? "The average temperature (${w.meanTemp.toStringAsFixed(1)}°C) is not right for this crop. " : ""}'
                 'You may get much better results by switching to a crop that suits your local weather.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hColor.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(hIcon, color: hColor, size: 24),
          const SizedBox(width: 8),
          Expanded(child: Text(headline,
              style: _label(14, color: hColor, w: FontWeight.bold))),
        ]),
        const SizedBox(height: 10),
        Text(body, style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.6)),
        const SizedBox(height: 14),

        // Climate match chips — plain language
        Wrap(spacing: 8, runSpacing: 6, children: [
          _chip(
            '💧 Rain: ${w.meanRainfall.toStringAsFixed(0)} mm/year ${rFit ? "✓ Good" : "✗ Not ideal"}',
            rFit ? kOlive : kRed, rFit ? kOlive.withOpacity(0.08) : kRed.withOpacity(0.07)),
          _chip(
            '🌡 Temp: ${w.meanTemp.toStringAsFixed(1)}°C ${tFit ? "✓ Good" : "✗ Not ideal"}',
            tFit ? kOlive : kRed, tFit ? kOlive.withOpacity(0.08) : kRed.withOpacity(0.07)),
          _chip(
            '${cp.emoji} Ideal rain: ${cp.rLow.toStringAsFixed(0)}–${cp.rHigh.toStringAsFixed(0)} mm',
            kSky, kSky.withOpacity(0.08)),
          _chip(
            '${cp.emoji} Ideal temp: ${cp.tLow}–${cp.tHigh}°C',
            kSky, kSky.withOpacity(0.08)),
        ]),
      ]),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: kSurface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: kBorderLight),
      boxShadow: [BoxShadow(color: kBrown.withOpacity(0.04),
          blurRadius: 10, offset: const Offset(0, 4))],
    ),
    child: child,
  );

  Widget _divider() => Divider(color: kBorderLight, height: 1);

  Widget _pill(String label, Color fg, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg)),
  );

  Widget _chip(String label, Color fg, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withOpacity(0.25))),
    child: Text(label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
  );

  Widget _dot(Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 5),
    Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
  ]);

  Widget _dropdown<T>({
    required T value, required List<T> items,
    required String Function(T) label, required ValueChanged<T?> onChanged,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    decoration: BoxDecoration(
      color: kBrown.withOpacity(0.05),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: kBorderLight),
    ),
    child: DropdownButton<T>(
      value: value, isExpanded: true,
      underline: const SizedBox.shrink(),
      style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w500),
      items: items.map((i) =>
          DropdownMenuItem(value: i, child: Text(label(i)))).toList(),
      onChanged: onChanged,
    ),
  );
}