import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// Unit conversion
// ─────────────────────────────────────────────────────────────────────────────

const double kTHaToKgAcre = 404.686;

double toKgAcre(double tHa) => tHa * kTHaToKgAcre;

String fmtYield(double tHa) =>
    '${toKgAcre(tHa).toStringAsFixed(0)} kg/acre';

// ─────────────────────────────────────────────────────────────────────────────
// Responsive helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Breakpoint thresholds
const double kBreakpointSm = 360;
const double kBreakpointMd = 600;
const double kBreakpointLg = 900;

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;

  /// Scales a value based on screen width relative to a 390px baseline.
  /// Tighter clamp for very small screens to prevent overflow.
  double sp(double size) => size * (screenWidth / 390).clamp(0.65, 1.4);

  /// Returns value based on breakpoints: [sm, md, lg] thresholds.
  T responsive<T>({required T sm, T? md, T? lg}) {
    if (screenWidth >= kBreakpointLg && lg != null) return lg;
    if (screenWidth >= kBreakpointMd && md != null) return md;
    return sm;
  }

  bool get isSmall => screenWidth < kBreakpointSm;
  bool get isMedium => screenWidth >= kBreakpointMd;
  bool get isLarge => screenWidth >= kBreakpointLg;

  /// Horizontal page padding, responsive
  double get hPad => responsive<double>(sm: 10, md: 20, lg: 32);

  /// Card inner padding, responsive
  double get cardPad => responsive<double>(sm: 10, md: 16, lg: 20);
}

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
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
  final double   peakYield;
  final String   bagSizeKg;
  final String   commonName;
  final double rMin, rLow, rHigh, rMax;
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

  double get peakYieldKgAcre => toKgAcre(peakYield);
}

const kCropProfiles = <CropProfile>[
  CropProfile(
    name: 'Rice', emoji: '🌾',
    color: Color(0xFF10B981), icon: Icons.rice_bowl_outlined,
    peakYield: 5.5, bagSizeKg: '50', commonName: 'Paddy / Chawal',
    rMin: 400,  rLow: 1200, rHigh: 3500, rMax: 6000,
    tMin: 20,   tLow: 24,   tHigh: 32,   tMax: 38,
  ),
  CropProfile(
    name: 'Wheat', emoji: '🌿',
    color: Color(0xFFD4860A), icon: Icons.grass,
    peakYield: 4.5, bagSizeKg: '50', commonName: 'Gehun',
    rMin: 200,  rLow: 450,  rHigh: 900,  rMax: 1400,
    tMin: 5,    tLow: 10,   tHigh: 20,   tMax: 28,
  ),
  CropProfile(
    name: 'Maize', emoji: '🌽',
    color: Color(0xFFF97316), icon: Icons.eco,
    peakYield: 6.0, bagSizeKg: '50', commonName: 'Makka / Corn',
    rMin: 250,  rLow: 500,  rHigh: 1100, rMax: 1800,
    tMin: 8,    tLow: 12,   tHigh: 24,   tMax: 32,
  ),
  CropProfile(
    name: 'Sugarcane', emoji: '🎋',
    color: Color(0xFF8B5CF6), icon: Icons.local_florist,
    peakYield: 80.0, bagSizeKg: '100', commonName: 'Ganna / Ikshu',
    rMin: 700,  rLow: 1500, rHigh: 4000, rMax: 6000,
    tMin: 18,   tLow: 22,   tHigh: 32,   tMax: 40,
  ),
  CropProfile(
    name: 'Cotton', emoji: '🌸',
    color: Color(0xFF06B6D4), icon: Icons.cloud_outlined,
    peakYield: 2.2, bagSizeKg: '170', commonName: 'Kapas / Karpas',
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
  final List<double> yields;
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
      yields: yields,
      mean: mean, p5: pct(0.05),
      p25: pct(0.25), p50: pct(0.50),
      p75: pct(0.75), p95: pct(0.95),
      stdDev: sqrt(variance),
      histogram: histogram,
      crop: crop,
      inputMeanRain: meanRain, inputMeanTemp: meanTemp,
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

  FarmLocation _loc  = kLocations[0];
  CropProfile  _crop = kCropProfiles[0];
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

  // ── Responsive font size helpers ──────────────────────────────────────────

  double _fs(BuildContext ctx, double base) => ctx.sp(base);

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final busy = _loadingW || _loadingS;
    final hPad = context.hPad;

    return Scaffold(
      backgroundColor: kBg,
      appBar: _buildAppBar(context),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final maxW = constraints.maxWidth >= kBreakpointLg ? 700.0 : double.infinity;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(hPad, ctx.sp(14), hPad, 40),
                  children: [
                    _configCard(ctx),
                    SizedBox(height: ctx.sp(12)),
                    _runBtn(ctx, busy),
                    SizedBox(height: ctx.sp(16)),
                    if (_loadingW) _loadCard(ctx,
                        '☁️  Checking the weather history…',
                        'Looking at $_yrs years of rain & temperature for ${_loc.name}'),
                    if (_loadingS) _loadCard(ctx,
                        '🌾  Working out your harvest…',
                        'Trying 500 different weather outcomes'),
                    if (_error != null) _errorCard(ctx),
                    if (!busy && _result != null && _weather != null)
                      FadeTransition(opacity: _fade, child: Column(children: [
                        _weatherBanner(ctx),
                        SizedBox(height: ctx.sp(12)),
                        _heroCard(ctx),
                        SizedBox(height: ctx.sp(12)),
                        _quickFactsRow(ctx),
                        SizedBox(height: ctx.sp(12)),
                        _scenarioStrip(ctx),
                        SizedBox(height: ctx.sp(12)),
                        _histChart(ctx),
                        SizedBox(height: ctx.sp(12)),
                        _adviceCard(ctx),
                      ])),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.green,
      elevation: 0,
      toolbarHeight: context.sp(56),
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: Colors.white, size: context.sp(22)),
        onPressed: () { HapticFeedback.lightImpact(); Navigator.pop(context); },
      ),
      // FIX: Wrap title in Flexible to prevent horizontal overflow in AppBar
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'My Harvest Forecast',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: _fs(context, 17),
            fontFamily: 'Georgia',
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        Text(
          'What will I get this season?',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: _fs(context, 10.5),
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ]),
    );
  }

  // ── Config card ─────────────────────────────────────────────────────────

  Widget _configCard(BuildContext ctx) {
    final isLg = ctx.isMedium;

    return _card(ctx, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.agriculture_rounded, color: kBrown, size: ctx.sp(20)),
          SizedBox(width: ctx.sp(6)),
          Expanded(
            child: Text('Tell us about your farm',
                style: _label(_fs(ctx, 15), color: kBrown, w: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        SizedBox(height: ctx.sp(14)),

        Text('📍 Where is your farm?',
            style: _label(_fs(ctx, 13), color: Colors.green.shade700)),
        SizedBox(height: ctx.sp(6)),
        _dropdown<FarmLocation>(
          ctx: ctx,
          value: _loc, items: kLocations, label: (l) => l.display,
          onChanged: (v) { if (v != null) setState(() => _loc = v); },
        ),

        SizedBox(height: ctx.sp(14)),
        Text('🌾 What do you grow?',
            style: _label(_fs(ctx, 13), color: Colors.brown.shade700)),
        SizedBox(height: ctx.sp(8)),

        // Crop chips — wrap naturally
        Wrap(
          spacing: ctx.sp(6),
          runSpacing: ctx.sp(6),
          children: kCropProfiles.map((cp) {
            final sel = _crop.name == cp.name;
            return GestureDetector(
              onTap: () { HapticFeedback.selectionClick(); setState(() => _crop = cp); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: EdgeInsets.symmetric(
                  horizontal: ctx.sp(isLg ? 14 : 10),
                  vertical:   ctx.sp(isLg ? 9  : 7),
                ),
                decoration: BoxDecoration(
                  color:  sel ? cp.color : cp.color.withOpacity(0.09),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: sel ? cp.color : cp.color.withOpacity(0.3)),
                ),
                child: Text('${cp.emoji}  ${cp.name}',
                    style: TextStyle(
                      fontSize: _fs(ctx, isLg ? 13 : 12),
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : cp.color,
                    )),
              ),
            );
          }).toList(),
        ),

        SizedBox(height: ctx.sp(14)),

        _sliderSection(
          ctx: ctx,
          label: '🏡 How many acres do you farm?',
          pill: '${_acres.toStringAsFixed(1)} acres',
          pillFg: kBrown,
          pillBg: kBrown.withOpacity(0.1),
          activeColor: kBrown,
          value: _acres, min: 0.5, max: 20, divisions: 39,
          onChanged: (v) => setState(() => _acres = v),
        ),

        SizedBox(height: ctx.sp(4)),

        _sliderSection(
          ctx: ctx,
          label: '📅 Years of weather history:',
          pill: '$_yrs years',
          pillFg: kOlive,
          pillBg: kOlive.withOpacity(0.1),
          activeColor: kOlive,
          value: _yrs.toDouble(), min: 2, max: 10, divisions: 8,
          onChanged: (v) => setState(() => _yrs = v.round()),
        ),
      ],
    ));
  }

  /// Responsive slider section — always stacks vertically to prevent overflow.
  Widget _sliderSection({
    required BuildContext ctx,
    required String label,
    required String pill,
    required Color pillFg, required Color pillBg,
    required Color activeColor,
    required double value, required double min,
    required double max, required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    // FIX: Always use Column layout to prevent label+pill Row overflow.
    // On medium+ screens we use a Row but guard with Flexible.
    final header = ctx.isSmall
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: _label(_fs(ctx, 12), color: Colors.brown.shade700),
                overflow: TextOverflow.ellipsis, maxLines: 2),
            SizedBox(height: ctx.sp(4)),
            _pill(ctx, pill, pillFg, pillBg),
          ])
        : Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(
              child: Text(label,
                  style: _label(_fs(ctx, 13), color: Colors.brown.shade700),
                  overflow: TextOverflow.ellipsis, maxLines: 2),
            ),
            SizedBox(width: ctx.sp(8)),
            _pill(ctx, pill, pillFg, pillBg),
          ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      header,
      SliderTheme(
        data: SliderThemeData(
          activeTrackColor:   activeColor,
          thumbColor:         activeColor,
          inactiveTrackColor: activeColor.withOpacity(0.2),
          overlayColor:       activeColor.withOpacity(0.08),
          trackHeight:        ctx.sp(4),
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: ctx.sp(8)),
        ),
        child: Slider(
          value: value, min: min, max: max, divisions: divisions,
          onChanged: onChanged,
        ),
      ),
    ]);
  }

  // ── Run button ────────────────────────────────────────────────────────────

  Widget _runBtn(BuildContext ctx, bool busy) => SizedBox(
    width: double.infinity,
    height: ctx.sp(56),
    child: ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: kOlive, foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ctx.sp(14))),
        elevation: 3,
        padding: EdgeInsets.symmetric(horizontal: ctx.sp(12)),
      ),
      icon: busy
          ? SizedBox(width: ctx.sp(18), height: ctx.sp(18),
              child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
          : Icon(Icons.search_rounded, size: ctx.sp(20)),
      label: Flexible(
        child: Text(
          busy ? 'Working out your forecast…' : '🔍  Show Me My Harvest Forecast',
          style: TextStyle(
            fontSize: _fs(ctx, 13.5),
            fontWeight: FontWeight.w700,
            fontFamily: 'Georgia',
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
      onPressed: busy ? null : _run,
    ),
  );

  // ── Loading ───────────────────────────────────────────────────────────────

  Widget _loadCard(BuildContext ctx, String title, String sub) => Container(
    margin: EdgeInsets.only(bottom: ctx.sp(12)),
    padding: EdgeInsets.all(ctx.sp(16)),
    decoration: BoxDecoration(color: kSurface,
        borderRadius: BorderRadius.circular(ctx.sp(14)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 8, offset: const Offset(0, 3))]),
    child: Row(children: [
      SizedBox(width: ctx.sp(32), height: ctx.sp(32),
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(kBrown), strokeWidth: 3)),
      SizedBox(width: ctx.sp(14)),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: _label(_fs(ctx, 13.5), color: kBrown, w: FontWeight.bold),
            overflow: TextOverflow.ellipsis, maxLines: 2),
        SizedBox(height: ctx.sp(3)),
        Text(sub,
            style: TextStyle(fontSize: _fs(ctx, 11.5), color: Colors.grey.shade600),
            overflow: TextOverflow.ellipsis, maxLines: 2),
      ])),
    ]),
  );

  // ── Error ─────────────────────────────────────────────────────────────────

  Widget _errorCard(BuildContext ctx) => Container(
    margin: EdgeInsets.only(bottom: ctx.sp(12)),
    padding: EdgeInsets.all(ctx.sp(16)),
    decoration: BoxDecoration(color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(ctx.sp(14)),
        border: Border.all(color: Colors.red.shade200)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.wifi_off_rounded, color: Colors.red.shade600, size: ctx.sp(22)),
      SizedBox(width: ctx.sp(10)),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Could not load weather data',
            style: _label(_fs(ctx, 13.5), color: Colors.red.shade700, w: FontWeight.bold),
            overflow: TextOverflow.ellipsis, maxLines: 2),
        SizedBox(height: ctx.sp(4)),
        Text(_error ?? '',
            style: TextStyle(fontSize: _fs(ctx, 11.5), color: Colors.red.shade700)),
        SizedBox(height: ctx.sp(6)),
        Text('Please check your internet connection and try again.',
            style: TextStyle(fontSize: _fs(ctx, 11), color: Colors.grey.shade600)),
      ])),
    ]),
  );

  // ── Weather banner ────────────────────────────────────────────────────────

  Widget _weatherBanner(BuildContext ctx) {
    final w = _weather!;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: ctx.sp(14), vertical: ctx.sp(12)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kSky.withOpacity(0.85), kSky],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(ctx.sp(14)),
      ),
      // FIX: Use crossAxisAlignment.start and constrain the right column
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Icon(Icons.cloud_done_outlined, color: Colors.white, size: ctx.sp(22)),
        SizedBox(width: ctx.sp(10)),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Real weather data loaded ✓',
              style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.bold, fontSize: _fs(ctx, 13)),
              overflow: TextOverflow.ellipsis, maxLines: 1),
          Text('${w.dailyRainfall.length} days · ${_loc.display}',
              style: TextStyle(color: Colors.white70, fontSize: _fs(ctx, 10.5)),
              overflow: TextOverflow.ellipsis, maxLines: 1),
        ])),
        SizedBox(width: ctx.sp(8)),
        // FIX: Constrain right column so it doesn't push others off-screen
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${w.meanRainfall.toStringAsFixed(0)} mm/yr',
              style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.bold, fontSize: _fs(ctx, 11.5))),
          Text('${w.meanTemp.toStringAsFixed(1)}°C avg',
              style: TextStyle(color: Colors.white70, fontSize: _fs(ctx, 10.5))),
        ]),
      ]),
    );
  }

  // ── Hero card ─────────────────────────────────────────────────────────────

  Widget _heroCard(BuildContext ctx) {
    final r   = _result!;
    final cp  = _crop;
    final meanKg = toKgAcre(r.mean);
    final pct = (r.mean / cp.peakYield * 100).clamp(0.0, 100.0);
    final col = pct >= 65 ? kOlive : pct >= 40 ? kAmber : kRed;
    final totalFarmKg = meanKg * _acres;

    return Container(
      padding: EdgeInsets.all(ctx.cardPad),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(ctx.sp(18)),
        border: Border.all(color: col.withOpacity(0.3), width: 1.5),
        boxShadow: [BoxShadow(color: kBrown.withOpacity(0.06),
            blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Column(children: [
        // FIX: Wrap entire header row with overflow protection
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            padding: EdgeInsets.all(ctx.sp(8)),
            decoration: BoxDecoration(
              color: col.withOpacity(0.12),
              borderRadius: BorderRadius.circular(ctx.sp(12)),
            ),
            child: Text(cp.emoji, style: TextStyle(fontSize: ctx.sp(26))),
          ),
          SizedBox(width: ctx.sp(12)),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Expected ${cp.name} Harvest',
                style: _label(_fs(ctx, 12.5), color: Colors.grey.shade600, w: FontWeight.w500),
                overflow: TextOverflow.ellipsis, maxLines: 1),
            SizedBox(height: ctx.sp(2)),
            // FIX: Use LayoutBuilder + FittedBox so the number never overflows
            LayoutBuilder(builder: (_, bc) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        meanKg.toStringAsFixed(0),
                        style: TextStyle(
                          // Use a responsive base size; FittedBox will scale down further if needed
                          fontSize: ctx.responsive<double>(sm: 28, md: 38, lg: 44),
                          fontWeight: FontWeight.w900,
                          color: col,
                          fontFamily: 'Georgia',
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(bottom: ctx.sp(4), left: ctx.sp(4)),
                    child: Text('kg/acre',
                        style: _label(_fs(ctx, 12), color: Colors.grey.shade500, w: FontWeight.w500)),
                  ),
                ],
              );
            }),
          ])),
        ]),

        SizedBox(height: ctx.sp(16)),

        // Progress bar section
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(child: Text('How well is your land doing?',
                style: TextStyle(fontSize: _fs(ctx, 11.5), color: Colors.grey.shade600),
                overflow: TextOverflow.ellipsis)),
            SizedBox(width: ctx.sp(6)),
            _pill(ctx, '${pct.toStringAsFixed(0)}% of best', col, col.withOpacity(0.1)),
          ]),
          SizedBox(height: ctx.sp(8)),
          ClipRRect(
            borderRadius: BorderRadius.circular(ctx.sp(8)),
            child: LinearProgressIndicator(
              value: pct / 100, minHeight: ctx.sp(13),
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(col),
            ),
          ),
          SizedBox(height: ctx.sp(4)),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('0', style: TextStyle(fontSize: _fs(ctx, 9.5), color: Colors.grey.shade400)),
            Flexible(
              child: Text('Best: ${cp.peakYieldKgAcre.toStringAsFixed(0)} kg/acre',
                  style: TextStyle(fontSize: _fs(ctx, 9.5), color: Colors.grey.shade400),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end),
            ),
          ]),
        ]),

        SizedBox(height: ctx.sp(16)),
        _divider(),
        SizedBox(height: ctx.sp(14)),

        // Farm total box
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(ctx.sp(14)),
          decoration: BoxDecoration(
            color: kBrown.withOpacity(0.06),
            borderRadius: BorderRadius.circular(ctx.sp(12)),
            border: Border.all(color: kBrown.withOpacity(0.15)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('🏡', style: TextStyle(fontSize: ctx.sp(22))),
            SizedBox(width: ctx.sp(10)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your ${_acres.toStringAsFixed(1)}-acre farm total',
                  style: _label(_fs(ctx, 12), color: kBrown, w: FontWeight.w500),
                  overflow: TextOverflow.ellipsis, maxLines: 1),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Flexible(child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(totalFarmKg.toStringAsFixed(0),
                      style: _label(ctx.sp(20), color: kBrown, w: FontWeight.bold)),
                )),
                SizedBox(width: ctx.sp(5)),
                Padding(
                  padding: EdgeInsets.only(bottom: ctx.sp(2)),
                  child: Text('kg total',
                      style: _label(_fs(ctx, 11), color: Colors.brown.shade400, w: FontWeight.w500)),
                ),
              ]),
            ])),
          ]),
        ),

        SizedBox(height: ctx.sp(14)),

        // Good / bad season — always stacks vertically on small screens
        ctx.isSmall
            ? Column(children: [
                _seasonBox(ctx, icon: '☀️', label: 'Good Season',
                    kg: toKgAcre(r.p75), color: kOlive, bg: kOlive.withOpacity(0.08), note: '1 in 4 years'),
                SizedBox(height: ctx.sp(8)),
                _seasonBox(ctx, icon: '🌧', label: 'Tough Season',
                    kg: toKgAcre(r.p25), color: kRed,  bg: kRed.withOpacity(0.07),   note: '1 in 4 years'),
              ])
            : Row(children: [
                Expanded(child: _seasonBox(ctx, icon: '☀️', label: 'Good Season',
                    kg: toKgAcre(r.p75), color: kOlive, bg: kOlive.withOpacity(0.08), note: '1 in 4 years')),
                SizedBox(width: ctx.sp(10)),
                Expanded(child: _seasonBox(ctx, icon: '🌧', label: 'Tough Season',
                    kg: toKgAcre(r.p25), color: kRed,  bg: kRed.withOpacity(0.07),   note: '1 in 4 years')),
              ]),
      ]),
    );
  }

  Widget _seasonBox(BuildContext ctx, {
    required String icon, required String label,
    required double kg, required Color color,
    required Color bg, required String note,
  }) => Container(
    padding: EdgeInsets.all(ctx.sp(12)),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(ctx.sp(12)),
        border: Border.all(color: color.withOpacity(0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(icon, style: TextStyle(fontSize: ctx.sp(20))),
      SizedBox(height: ctx.sp(6)),
      // FIX: FittedBox prevents kg number from overflowing the season box
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(kg.toStringAsFixed(0),
            style: _label(_fs(ctx, 18), color: color, w: FontWeight.bold)),
      ),
      Text('kg/acre', style: _label(_fs(ctx, 10), color: color.withOpacity(0.7), w: FontWeight.w500)),
      SizedBox(height: ctx.sp(2)),
      Text(label, style: _label(_fs(ctx, 12), color: Colors.grey.shade700)),
      Text(note, style: TextStyle(fontSize: _fs(ctx, 10), color: Colors.grey.shade500)),
    ]),
  );

  // ── Quick facts row ───────────────────────────────────────────────────────

  Widget _quickFactsRow(BuildContext ctx) {
    final r  = _result!;
    final cp = _crop;
    final meanKg     = toKgAcre(r.mean);
    final bagSz      = double.tryParse(cp.bagSizeKg) ?? 50.0;
    final bags       = (meanKg / bagSz).floor();
    final totalKg    = meanKg * _acres;
    final totalBags  = (totalKg / bagSz).floor();

    final tiles = [
      _factTile(ctx, '${bags.toString()} bags',
          'Per acre (${cp.bagSizeKg} kg bags)', '🎒', kOlive),
      _factTile(ctx, '${totalBags.toString()} bags',
          'Your whole farm', '🏡', kBrown),
      _factTile(ctx, '${totalKg.toStringAsFixed(0)} kg',
          'Total from your farm', '⚖️', kAmber),
      _factTile(ctx,
          _riskLabel(r.mean, cp.peakYield),
          'Season risk level',
          _riskEmoji(r.mean, cp.peakYield), kRed),
    ];

    return _card(ctx, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('📦 In Simple Numbers',
            style: _label(_fs(ctx, 15), color: kBrown, w: FontWeight.bold)),
        SizedBox(height: ctx.sp(4)),
        Text('What does your harvest actually look like?',
            style: TextStyle(fontSize: _fs(ctx, 11), color: Colors.grey.shade500)),
        SizedBox(height: ctx.sp(14)),
        // FIX: Use a more conservative aspectRatio and clamp to avoid tile overflow
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: ctx.sp(8),
          mainAxisSpacing: ctx.sp(8),
          // FIX: Smaller aspect ratio so tiles have more height on tiny screens
          childAspectRatio: ctx.responsive<double>(sm: 1.35, md: 1.6, lg: 1.8),
          children: tiles,
        ),
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

  Widget _factTile(BuildContext ctx, String value, String label, String icon, Color color) =>
    Container(
      padding: EdgeInsets.all(ctx.sp(10)),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(ctx.sp(12)),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(icon, style: TextStyle(fontSize: ctx.sp(18))),
        SizedBox(height: ctx.sp(4)),
        // FIX: FittedBox ensures value text never overflows tile width
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: _label(_fs(ctx, 16), color: color, w: FontWeight.bold)),
          ),
        ),
        SizedBox(height: ctx.sp(2)),
        Text(label,
            style: TextStyle(fontSize: _fs(ctx, 10), color: Colors.grey.shade600),
            overflow: TextOverflow.ellipsis, maxLines: 2),
      ]),
    );

  // ── Scenario strip ────────────────────────────────────────────────────────

  Widget _scenarioStrip(BuildContext ctx) {
    final r = _result!;
    final n = r.yields.length.toDouble();
    final great = r.yields.where((y) => y >= r.p75).length;
    final ok    = r.yields.where((y) => y >= r.p25 && y < r.p75).length;
    final bad   = r.yields.where((y) => y < r.p25).length;

    return _card(ctx, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('🎲 If we ran through 100 growing seasons…',
            style: _label(_fs(ctx, 14), color: kBrown, w: FontWeight.bold),
            overflow: TextOverflow.ellipsis, maxLines: 2),
        SizedBox(height: ctx.sp(4)),
        Text('Based on $_yrs years of real weather in ${_loc.name}',
            style: TextStyle(fontSize: _fs(ctx, 11), color: Colors.grey.shade500),
            overflow: TextOverflow.ellipsis, maxLines: 1),
        SizedBox(height: ctx.sp(16)),

        _scenarioRow(ctx, '☀️', 'Great harvest',
            'More than ${toKgAcre(r.p75).toStringAsFixed(0)} kg/acre',
            (great / n * 100).round(), kOlive),
        SizedBox(height: ctx.sp(10)),
        _scenarioRow(ctx, '🌤', 'Normal harvest',
            '${toKgAcre(r.p25).toStringAsFixed(0)} – ${toKgAcre(r.p75).toStringAsFixed(0)} kg/acre',
            (ok / n * 100).round(), kAmber),
        SizedBox(height: ctx.sp(10)),
        _scenarioRow(ctx, '🌧', 'Difficult harvest',
            'Less than ${toKgAcre(r.p25).toStringAsFixed(0)} kg/acre',
            (bad / n * 100).round(), kRed),

        SizedBox(height: ctx.sp(14)),
        Container(
          padding: EdgeInsets.all(ctx.sp(12)),
          decoration: BoxDecoration(
            color: _crop.color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(ctx.sp(10)),
            border: Border.all(color: _crop.color.withOpacity(0.2)),
          ),
          child: Row(children: [
            Text(_crop.emoji, style: TextStyle(fontSize: ctx.sp(20))),
            SizedBox(width: ctx.sp(10)),
            Expanded(child: Text(
              'Typical ${_crop.name} harvest: '
              '${toKgAcre(r.p25).toStringAsFixed(0)} – ${toKgAcre(r.p75).toStringAsFixed(0)} kg/acre',
              style: TextStyle(fontSize: _fs(ctx, 12),
                  fontWeight: FontWeight.w600, color: _crop.color),
              overflow: TextOverflow.ellipsis, maxLines: 2,
            )),
          ]),
        ),
      ],
    ));
  }

  Widget _scenarioRow(BuildContext ctx, String emoji, String label,
      String desc, int pct, Color color) => Row(children: [
    Text(emoji, style: TextStyle(fontSize: ctx.sp(20))),
    SizedBox(width: ctx.sp(8)),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // FIX: Wrap label row so the badge never gets pushed off-screen
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
        Flexible(child: Text(label,
            style: _label(_fs(ctx, 12), color: Colors.grey.shade800),
            overflow: TextOverflow.ellipsis, maxLines: 1)),
        SizedBox(width: ctx.sp(4)),
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: ctx.sp(7), vertical: ctx.sp(2)),
          decoration: BoxDecoration(color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20)),
          child: Text('$pct / 100',
              style: TextStyle(fontWeight: FontWeight.bold,
                  fontSize: _fs(ctx, 11), color: color)),
        ),
      ]),
      SizedBox(height: ctx.sp(5)),
      ClipRRect(
        borderRadius: BorderRadius.circular(ctx.sp(6)),
        child: LinearProgressIndicator(
          value: pct / 100, minHeight: ctx.sp(9),
          backgroundColor: Colors.grey.shade200,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
      SizedBox(height: ctx.sp(3)),
      Text(desc,
          style: TextStyle(fontSize: _fs(ctx, 10), color: Colors.grey.shade500),
          overflow: TextOverflow.ellipsis, maxLines: 1),
    ])),
  ]);

  // ── Histogram ─────────────────────────────────────────────────────────────

  Widget _histChart(BuildContext ctx) {
    final r = _result!;
    final maxF = r.histogram.map((b) => b.freq).reduce(max);
    final meanKg = toKgAcre(r.mean);
    final meanBinIdx = r.histogram.indexWhere((b) => meanKg >= b.lo && meanKg < b.hi);
    final chartH = ctx.responsive<double>(sm: 110, md: 150, lg: 170);

    return _card(ctx, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('📊 What Range of Harvests Should You Expect?',
            style: _label(_fs(ctx, 14), color: kBrown, w: FontWeight.bold),
            overflow: TextOverflow.ellipsis, maxLines: 2),
        SizedBox(height: ctx.sp(4)),
        Text('Each bar shows how common that harvest level is across 500 simulated seasons',
            style: TextStyle(fontSize: _fs(ctx, 11), color: Colors.grey.shade500)),
        SizedBox(height: ctx.sp(20)),

        SizedBox(
          height: chartH,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(r.histogram.length, (i) {
              final b    = r.histogram[i];
              final hf   = maxF > 0 ? b.freq / maxF : 0.0;
              final isMn = i == (meanBinIdx < 0 ? 0 : meanBinIdx);
              return Expanded(child: Padding(
                padding: EdgeInsets.symmetric(horizontal: ctx.sp(1.5)),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (isMn) Column(children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: ctx.sp(4), vertical: ctx.sp(2)),
                      decoration: BoxDecoration(color: kAmber,
                          borderRadius: BorderRadius.circular(ctx.sp(4))),
                      child: Text('avg',
                          style: TextStyle(fontSize: ctx.sp(7), color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                    SizedBox(height: ctx.sp(2)),
                  ]),
                  AnimatedContainer(
                    duration: Duration(milliseconds: 400 + i * 40),
                    curve: Curves.easeOut,
                    height: (chartH * 0.78) * hf,
                    decoration: BoxDecoration(
                      color: isMn
                          ? kAmber
                          : _crop.color.withOpacity(0.5 + 0.5 * hf),
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
        // FIX: x-axis labels — clip text so they never overflow bar columns
        Row(children: List.generate(r.histogram.length, (i) => Expanded(
          child: i % 2 == 0
              ? Text(r.histogram[i].lo.toStringAsFixed(0),
                  style: TextStyle(fontSize: ctx.sp(7), color: Colors.grey.shade400),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.clip,
                  maxLines: 1)
              : const SizedBox.shrink(),
        ))),
        SizedBox(height: ctx.sp(2)),
        Center(child: Text('Harvest (kg/acre)',
            style: TextStyle(fontSize: _fs(ctx, 10), color: Colors.grey.shade500))),

        SizedBox(height: ctx.sp(12)),
        Wrap(spacing: ctx.sp(14), runSpacing: ctx.sp(6), children: [
          _dot(ctx, _crop.color, '${_crop.name} harvest'),
          _dot(ctx, kAmber, 'Your expected average'),
        ]),
      ],
    ));
  }

  // ── Advice card ───────────────────────────────────────────────────────────

  Widget _adviceCard(BuildContext ctx) {
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
      hColor   = kOlive; hIcon = Icons.check_circle_outline_rounded;
      body     = 'The weather in ${_loc.name} is well suited for ${cp.name}. '
                 'You should get strong, reliable harvests most years. '
                 'Keep up good farming practices and you are on the right track!';
    } else if (pct >= 35) {
      headline = '⚠️ Decent results — but some risk';
      hColor   = kAmber; hIcon = Icons.info_outline_rounded;
      body     = '${_loc.name} can grow ${cp.name}, but conditions are not perfect. '
                 '${!rFit ? "The rainfall here is outside the ideal range for this crop. " : ""}'
                 '${!tFit ? "The temperature is not ideal for this crop. " : ""}'
                 'Consider drip irrigation or asking your local agriculture officer for advice on suitable varieties.';
    } else {
      headline = '❌ This crop is a difficult fit for your area';
      hColor   = kRed; hIcon = Icons.warning_amber_rounded;
      body     = '${_loc.name}\'s climate is not well suited for ${cp.name}. '
                 '${!rFit ? "Rainfall here (${w.meanRainfall.toStringAsFixed(0)} mm/year) is outside the ideal range. " : ""}'
                 '${!tFit ? "The average temperature (${w.meanTemp.toStringAsFixed(1)}°C) is not right for this crop. " : ""}'
                 'You may get much better results by switching to a crop that suits your local weather.';
    }

    return Container(
      padding: EdgeInsets.all(ctx.cardPad),
      decoration: BoxDecoration(
        color: hColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(ctx.sp(14)),
        border: Border.all(color: hColor.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // FIX: headline row — icon + Flexible text to prevent overflow
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(hIcon, color: hColor, size: ctx.sp(22)),
          SizedBox(width: ctx.sp(8)),
          Expanded(child: Text(headline,
              style: _label(_fs(ctx, 13), color: hColor, w: FontWeight.bold))),
        ]),
        SizedBox(height: ctx.sp(10)),
        Text(body,
            style: TextStyle(fontSize: _fs(ctx, 12),
                color: Colors.grey.shade700, height: 1.6)),
        SizedBox(height: ctx.sp(14)),

        // Chips always wrap — no overflow risk
        Wrap(spacing: ctx.sp(6), runSpacing: ctx.sp(6), children: [
          _chip(ctx,
            '💧 Rain: ${w.meanRainfall.toStringAsFixed(0)} mm ${rFit ? "✓" : "✗"}',
            rFit ? kOlive : kRed, rFit ? kOlive.withOpacity(0.08) : kRed.withOpacity(0.07)),
          _chip(ctx,
            '🌡 Temp: ${w.meanTemp.toStringAsFixed(1)}°C ${tFit ? "✓" : "✗"}',
            tFit ? kOlive : kRed, tFit ? kOlive.withOpacity(0.08) : kRed.withOpacity(0.07)),
          _chip(ctx,
            '${cp.emoji} Rain: ${cp.rLow.toStringAsFixed(0)}–${cp.rHigh.toStringAsFixed(0)} mm',
            kSky, kSky.withOpacity(0.08)),
          _chip(ctx,
            '${cp.emoji} Temp: ${cp.tLow}–${cp.tHigh}°C',
            kSky, kSky.withOpacity(0.08)),
        ]),
      ]),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  Widget _card(BuildContext ctx, {required Widget child}) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(ctx.cardPad),
    decoration: BoxDecoration(
      color: kSurface,
      borderRadius: BorderRadius.circular(ctx.sp(16)),
      border: Border.all(color: kBorderLight),
      boxShadow: [BoxShadow(color: kBrown.withOpacity(0.04),
          blurRadius: 10, offset: const Offset(0, 4))],
    ),
    child: child,
  );

  Widget _divider() => Divider(color: kBorderLight, height: 1);

  Widget _pill(BuildContext ctx, String label, Color fg, Color bg) => Container(
    padding: EdgeInsets.symmetric(horizontal: ctx.sp(10), vertical: ctx.sp(4)),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Text(label,
        style: TextStyle(fontSize: ctx.sp(11), fontWeight: FontWeight.bold, color: fg)),
  );

  Widget _chip(BuildContext ctx, String label, Color fg, Color bg) => Container(
    padding: EdgeInsets.symmetric(horizontal: ctx.sp(9), vertical: ctx.sp(5)),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withOpacity(0.25))),
    child: Text(label,
        style: TextStyle(fontSize: ctx.sp(11), fontWeight: FontWeight.w600, color: fg)),
  );

  Widget _dot(BuildContext ctx, Color color, String label) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: ctx.sp(10), height: ctx.sp(10),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        SizedBox(width: ctx.sp(5)),
        Text(label, style: TextStyle(fontSize: ctx.sp(11), color: Colors.grey.shade600)),
      ]);

  Widget _dropdown<T>({
    required BuildContext ctx,
    required T value, required List<T> items,
    required String Function(T) label, required ValueChanged<T?> onChanged,
  }) => Container(
    padding: EdgeInsets.symmetric(horizontal: ctx.sp(12), vertical: ctx.sp(2)),
    decoration: BoxDecoration(
      color: kBrown.withOpacity(0.05),
      borderRadius: BorderRadius.circular(ctx.sp(12)),
      border: Border.all(color: kBorderLight),
    ),
    child: DropdownButton<T>(
      value: value, isExpanded: true,
      underline: const SizedBox.shrink(),
      style: TextStyle(color: Colors.black87,
          fontSize: _fs(ctx, 14), fontWeight: FontWeight.w500),
      items: items.map((i) =>
          DropdownMenuItem(value: i, child: Text(label(i)))).toList(),
      onChanged: onChanged,
    ),
  );
}