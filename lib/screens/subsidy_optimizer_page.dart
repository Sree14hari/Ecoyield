import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Responsive helpers (shared with insurance screen)
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

  bool get isXS => sw < _kSmBreak;
  bool get isMd => sw >= _kMdBreak;
  double get hPad => pick<double>(sm: 14, md: 20, lg: 28);
  double get cPad => pick<double>(sm: 12, md: 16, lg: 20);
}

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens — earthy amber/green theme distinct from insurance screen
// ─────────────────────────────────────────────────────────────────────────────

const _kBg = Color(0xFFFAF7F0); // warm parchment
const _kSurface = Color(0xFFFFFFFF);
const _kAmberDeep = Color(0xFFB45309); // deep amber
const _kAmberMid = Color(0xFFD97706);
const _kAmberLt = Color(0xFFFEF3C7);
const _kGreen = Color(0xFF166534); // deep forest green
const _kGreenMid = Color(0xFF16A34A);
const _kGreenLt = Color(0xFFDCFCE7);
const _kBlueDark = Color(0xFF1E3A5F);
const _kBlueLt = Color(0xFFEFF6FF);
const _kRed = Color(0xFFB91C1C);
const _kRedLt = Color(0xFFFEE2E2);
const _kBorder = Color(0xFFE5D9C0);
const _kText = Color(0xFF1C1917);
const _kTextMid = Color(0xFF57534E);

TextStyle _ts(double sz,
        {Color color = _kText,
        FontWeight w = FontWeight.w600,
        double height = 1.2}) =>
    TextStyle(fontSize: sz, fontWeight: w, color: color, height: height);

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

enum IncomeCategory { verySmall, small, marginal, medium, large }

enum LandCategory { landless, micro, small, marginal, medium, large }

enum CropType { kharif, rabi, commercial, horticulture, any }

class _Crop {
  final String name, emoji;
  final CropType type;
  const _Crop(this.name, this.emoji, this.type);
}

const _kCrops = [
  _Crop('Rice', '🌾', CropType.kharif),
  _Crop('Wheat', '🌿', CropType.rabi),
  _Crop('Maize', '🌽', CropType.kharif),
  _Crop('Sugarcane', '🎋', CropType.commercial),
  _Crop('Cotton', '🌸', CropType.commercial),
  _Crop('Groundnut', '🥜', CropType.kharif),
  _Crop('Soybean', '🫘', CropType.kharif),
  _Crop('Onion', '🧅', CropType.horticulture),
  _Crop('Tomato', '🍅', CropType.horticulture),
  _Crop('Chickpea', '🟡', CropType.rabi),
  _Crop('Mustard', '🌻', CropType.rabi),
  _Crop('Millet', '🌾', CropType.kharif),
  _Crop('Vegetables', '🥦', CropType.horticulture),
  _Crop('Fruits', '🍎', CropType.horticulture),
];

// ─────────────────────────────────────────────────────────────────────────────
// Scheme data — sourced from official GoI notifications (2025-26)
// ─────────────────────────────────────────────────────────────────────────────

enum SchemeStatus { active, seasonal, upcoming }

enum BenefitType { cash, loan, insurance, service, subsidy }

class _Scheme {
  final String id, name, emoji, ministry;
  final String description;
  final BenefitType benefitType;
  final SchemeStatus status;

  // Eligibility rules — null means no restriction on that axis
  final double? maxLandAcres; // null = no land cap
  final double? maxAnnualIncomeL; // null = no income cap (in Lakhs)
  final bool requiresOwnLand;
  final List<CropType>? cropTypes; // null = all crops
  final bool excludesGovtEmployee;
  final bool excludesIncomeTaxPayer;

  // Benefit calculation
  final String benefitFormula; // human-readable formula
  final double Function(
      double acres, double cropValuePerAcre, IncomeCategory income) calcBenefit;

  // Deadlines & action
  final String deadlineNote;
  final String applyAt;
  final String officialUrl;
  final String optimizationTip;

  // Urgency: days until next deadline (null = evergreen)
  final int? daysToDeadline;

  const _Scheme({
    required this.id,
    required this.name,
    required this.emoji,
    required this.ministry,
    required this.description,
    required this.benefitType,
    required this.status,
    this.maxLandAcres,
    this.maxAnnualIncomeL,
    required this.requiresOwnLand,
    this.cropTypes,
    required this.excludesGovtEmployee,
    required this.excludesIncomeTaxPayer,
    required this.benefitFormula,
    required this.calcBenefit,
    required this.deadlineNote,
    required this.applyAt,
    required this.officialUrl,
    required this.optimizationTip,
    this.daysToDeadline,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Scheme registry — 8 central government schemes with real 2025-26 data
// ─────────────────────────────────────────────────────────────────────────────

List<_Scheme> _kSchemes() => [
      // 1. PM-KISAN ───────────────────────────────────────────────────────────────
      // Source: pmkisan.gov.in — ₹6,000/yr fixed regardless of land size
      // 22nd installment expected Feb/Mar 2026
      _Scheme(
        id: 'pmkisan',
        name: 'PM-KISAN',
        emoji: '💰',
        ministry: 'Ministry of Agriculture & Farmers Welfare',
        description:
            'Pradhan Mantri Kisan Samman Nidhi — direct income support of ₹6,000/year '
            'in 3 installments of ₹2,000 each (Apr–Jul, Aug–Nov, Dec–Mar), '
            'transferred directly to Aadhaar-linked bank accounts.',
        benefitType: BenefitType.cash,
        status: SchemeStatus.active,
        maxLandAcres: null, // All land sizes eligible since June 2019
        maxAnnualIncomeL: 2.0, // Income tax payers excluded
        requiresOwnLand: true,
        cropTypes: null, // All crops
        excludesGovtEmployee: true,
        excludesIncomeTaxPayer: true,
        benefitFormula: '₹6,000 fixed per year (3 × ₹2,000 installments)',
        calcBenefit: (acres, cropVal, income) => 6000,
        deadlineNote:
            '22nd installment releasing Feb/Mar 2026 (₹2,000 per farmer). Complete eKYC at pmkisan.gov.in NOW to avoid missing it.',
        applyAt:
            'pmkisan.gov.in → New Farmer Registration, or nearest CSC/bank',
        officialUrl: 'https://pmkisan.gov.in',
        optimizationTip:
            'Complete eKYC immediately on pmkisan.gov.in to avoid installment delays. '
            'If you have land in multiple family members\' names, each eligible member '
            'can register separately for ₹6,000 each.',
        daysToDeadline: 20,
      ),

      // 2. PMFBY — Kharif ─────────────────────────────────────────────────────────
      // Source: pmfby.gov.in — farmer pays max 2% Kharif; govt pays actuarial balance
      _Scheme(
        id: 'pmfby_kharif',
        name: 'PMFBY Kharif Insurance',
        emoji: '🛡️',
        ministry: 'Ministry of Agriculture & Farmers Welfare',
        description:
            'Pradhan Mantri Fasal Bima Yojana for Kharif crops — farmer pays only 2% '
            'of crop value as premium; government pays the rest of the actuarial rate. '
            'Covers drought, flood, pest, cyclone, and post-harvest losses.',
        benefitType: BenefitType.insurance,
        status: SchemeStatus.seasonal,
        maxLandAcres: null,
        maxAnnualIncomeL: null, // No income cap
        requiresOwnLand: false, // Tenant farmers & sharecroppers eligible
        cropTypes: [CropType.kharif, CropType.commercial],
        excludesGovtEmployee: false,
        excludesIncomeTaxPayer: false,
        benefitFormula:
            'Coverage = MSP × avg yield × acreage. You pay 2% premium; '
            'claim up to full crop value on failure.',
        calcBenefit: (acres, cropVal, income) {
          // Farmer saves: actuarial rate (est. 12%) minus 2% they pay = 10% subsidy
          // Benefit shown = govt subsidy value + full coverage potential
          final coverage = cropVal * acres;
          final farmerPremium = coverage * 0.02;
          final govtSubsidy = coverage * 0.10; // est. 10% govt subsidy portion
          return govtSubsidy;
        },
        deadlineNote:
            'Kharif enrollment: apply within 2 weeks of sowing (June–July). '
            'Rabi enrollment: November–December.',
        applyAt:
            'pmfby.gov.in, nearest bank branch, CSC, or insurance company office',
        officialUrl: 'https://pmfby.gov.in',
        optimizationTip:
            'If you have a KCC (Kisan Credit Card), you are AUTO-ENROLLED in PMFBY '
            'for loanee crops — verify your enrollment. Non-KCC holders must enroll manually. '
            'Opt-out is possible; opting-IN is the smart move for risky seasons.',
        daysToDeadline: 130, // Next Kharif June 2026
      ),

      // 3. PMFBY — Rabi ───────────────────────────────────────────────────────────
      _Scheme(
        id: 'pmfby_rabi',
        name: 'PMFBY Rabi Insurance',
        emoji: '🌿',
        ministry: 'Ministry of Agriculture & Farmers Welfare',
        description:
            'PMFBY for Rabi crops (Wheat, Mustard, Chickpea, etc.) — farmer pays '
            'only 1.5% premium; government pays the actuarial balance. '
            'Covers frost, unseasonal rains, hailstorm, pest & disease.',
        benefitType: BenefitType.insurance,
        status: SchemeStatus.seasonal,
        maxLandAcres: null,
        maxAnnualIncomeL: null,
        requiresOwnLand: false,
        cropTypes: [CropType.rabi],
        excludesGovtEmployee: false,
        excludesIncomeTaxPayer: false,
        benefitFormula:
            'Coverage = MSP × avg yield × acreage. You pay 1.5%; govt subsidises rest.',
        calcBenefit: (acres, cropVal, income) {
          final coverage = cropVal * acres;
          return coverage * 0.105; // est. 10.5% govt subsidy portion
        },
        deadlineNote:
            'Rabi 2025-26 enrollment: November 15 – December 31, 2025. '
            'Check your district Agriculture Office for exact cutoff.',
        applyAt: 'pmfby.gov.in, nearest bank, or PMFBY mobile app',
        officialUrl: 'https://pmfby.gov.in',
        optimizationTip:
            'For Rabi wheat, the sum insured is based on the MSP (₹2,425/qtl for 2025-26). '
            'Ensure your land records are updated — coverage is calculated per notified area. '
            'File claims within 72 hours of crop damage using the PMFBY app.',
        daysToDeadline: null,
      ),

      // 4. KCC — Kisan Credit Card ─────────────────────────────────────────────────
      // Source: RBI/NABARD — 7% interest, 4% with PRI; limit up to ₹5L under MISS 2025-26
      _Scheme(
        id: 'kcc',
        name: 'Kisan Credit Card (KCC)',
        emoji: '💳',
        ministry: 'Ministry of Finance / NABARD / RBI',
        description:
            'Short-term revolving credit up to ₹5 lakh. GoI provides 2% interest subvention + 3% Prompt Repayment Incentive (PRI). '
            'Effective rate: 4% p.a. if you repay on time (7% base − 2% subvention − 3% PRI). '
            'Collateral-free up to ₹2 lakh. Covers seeds, fertilisers, equipment, '
            'post-harvest, and allied activities (dairy, fisheries).',
        benefitType: BenefitType.loan,
        status: SchemeStatus.active,
        maxLandAcres: null,
        maxAnnualIncomeL: null,
        requiresOwnLand: false, // Tenant farmers & sharecroppers eligible
        cropTypes: null,
        excludesGovtEmployee: false,
        excludesIncomeTaxPayer: false,
        benefitFormula:
            'Interest saving vs market rate (18%): saves 14% p.a. on up to ₹5L. '
            'On ₹3L loan: saves ~₹42,000/yr vs private moneylender.',
        calcBenefit: (acres, cropVal, income) {
          // Estimate typical loan need = ~40% of annual crop input cost
          // Input cost ≈ 30% of crop value per acre
          final inputCost = cropVal * acres * 0.30;
          final loanNeed = (inputCost * 0.80).clamp(10000, 300000);
          // Interest saving: 18% (moneylender) − 4% (KCC with PRI) = 14%
          return loanNeed * 0.14;
        },
        deadlineNote:
            'Year-round — apply anytime. KCC is valid for 5 years with annual review. '
            'New limit of ₹5L applies from FY 2025-26 onwards.',
        applyAt:
            'Any nationalised bank (SBI, Bank of India, etc.), RRB, PACS, or cooperative bank',
        officialUrl: 'https://www.nabard.org/content1.aspx?id=572',
        optimizationTip:
            'Apply for KCC BEFORE the sowing season — processing takes 3–4 weeks. '
            'Having a KCC auto-enrolls you in PMFBY (crop insurance). '
            'Repay on time to get the 3% PRI, reducing rate to 4% p.a. '
            'KCC also covers personal accident insurance (PAIS) worth ₹50,000.',
        daysToDeadline: null,
      ),

      // 5. Soil Health Card ────────────────────────────────────────────────────────
      // Source: soilhealth.dac.gov.in — free soil testing + NPK recommendations
      _Scheme(
        id: 'shc',
        name: 'Soil Health Card (SHC)',
        emoji: '🌱',
        ministry: 'Ministry of Agriculture & Farmers Welfare',
        description:
            'Free soil testing every 2 years with detailed NPK and micro-nutrient '
            'analysis. Includes crop-specific fertiliser recommendations. '
            'Reduces fertiliser overuse, lowering input costs by 10–20%.',
        benefitType: BenefitType.service,
        status: SchemeStatus.active,
        maxLandAcres: null,
        maxAnnualIncomeL: null,
        requiresOwnLand: true,
        cropTypes: null,
        excludesGovtEmployee: false,
        excludesIncomeTaxPayer: false,
        benefitFormula:
            'Fertiliser savings: 10–20% of annual input cost (~₹2,000–₹8,000/acre/yr). '
            'Yield improvement: 5–10% from balanced nutrition.',
        calcBenefit: (acres, cropVal, income) {
          // Fertiliser cost ≈ 15% of crop value; SHC saves ~15% of that
          final fertCost = cropVal * acres * 0.15;
          return fertCost * 0.15; // 15% saving on fertiliser
        },
        deadlineNote: 'Year-round — soil samples tested at govt labs for free. '
            'Card issued within 30–60 days. Valid for 2 years.',
        applyAt: 'soilhealth.dac.gov.in or local Krishi Vigyan Kendra (KVK)',
        officialUrl: 'https://soilhealth.dac.gov.in',
        optimizationTip:
            'Get your SHC before each sowing season. Follow the NPK recommendation '
            'precisely — most farmers over-apply urea by 30–40%, wasting ₹3,000–₹6,000/acre. '
            'Link SHC recommendations with your PMFBY claim to show good agronomic practices.',
        daysToDeadline: null,
      ),

      // 6. PM Kusum Yojana ─────────────────────────────────────────────────────────
      // Source: mnre.gov.in — 60% subsidy on solar pump (up to 7.5 HP)
      _Scheme(
        id: 'pmkusum',
        name: 'PM Kusum – Solar Pump',
        emoji: '☀️',
        ministry: 'Ministry of New & Renewable Energy',
        description:
            'Up to 60% total subsidy on solar-powered irrigation pumps (30% Central + 30% State). '
            'Farmer pays only 10% upfront (remaining 30% available as bank loan). '
            'Replaces diesel pump: saves ₹60,000+/yr in fuel costs. Surplus power sold to DISCOM. Extended till March 2026.',
        benefitType: BenefitType.subsidy,
        status: SchemeStatus.active,
        maxLandAcres: null,
        maxAnnualIncomeL: null,
        requiresOwnLand: true,
        cropTypes: null,
        excludesGovtEmployee: false,
        excludesIncomeTaxPayer: false,
        benefitFormula: 'Subsidy = 60% of pump cost (Central 30% + State 30%). '
            'Farmer pays only 10%. Diesel saving: ~₹60,000/yr for 5HP pump.',
        calcBenefit: (acres, cropVal, income) {
          // Diesel pump cost ≈ ₹12/hr × ~2000 hrs/yr = ₹24,000 + maint
          // Solar pump saves ≈ ₹35,000/yr for a 5 HP pump on 3+ acres
          if (acres >= 2) return 35000;
          return acres * 12000; // Proportional for smaller holdings
        },
        deadlineNote: 'State-wise quotas — apply early in FY (April–June). '
            'Many states exhaust quota within 2–3 months.',
        applyAt:
            'State DISCOM portal or state renewable energy development agency',
        officialUrl: 'https://pmkusum.mnre.gov.in',
        optimizationTip:
            'PM Kusum is FIRST-COME-FIRST-SERVED in most states. Apply at the start '
            'of April each year. Combine with PM Kusum Component-B (solarise existing pumps) '
            'if you already have a pump. On 5+ acres, payback period is just 2–3 years.',
        daysToDeadline: 55, // Next April quota opening
      ),

      // 7. PMKSY — Micro Irrigation ────────────────────────────────────────────────
      // Source: pmksy.gov.in — 55% subsidy for small/marginal, 45% for others
      _Scheme(
        id: 'pmksy',
        name: 'PMKSY Micro-Irrigation',
        emoji: '💧',
        ministry: 'Ministry of Agriculture & Farmers Welfare',
        description:
            'Pradhan Mantri Krishi Sinchai Yojana — 55% subsidy on drip/sprinkler '
            'irrigation for small & marginal farmers (45% for others). '
            'Reduces water use by 40–50%, increases yield by 20–40%.',
        benefitType: BenefitType.subsidy,
        status: SchemeStatus.active,
        maxLandAcres: 12.35, // 5 hectares max for small/marginal rate
        maxAnnualIncomeL: null,
        requiresOwnLand: true,
        cropTypes: null,
        excludesGovtEmployee: false,
        excludesIncomeTaxPayer: false,
        benefitFormula:
            'Subsidy = 55% of drip installation (est. ₹35,000–₹80,000/acre). '
            'Water saving: 40–50%. Yield gain: 20–40% with drip.',
        calcBenefit: (acres, cropVal, income) {
          // Drip cost ≈ ₹50,000/acre, 55% subsidy = ₹27,500/acre
          final subsidyRate = acres <= 12.35 ? 0.55 : 0.45;
          return acres * 50000 * subsidyRate;
        },
        deadlineNote:
            'Year-round, but state funds are limited. Apply early in FY. '
            'Check your state\'s Per Drop More Crop implementation portal.',
        applyAt: 'State Agriculture Department or DBT Agriculture portal',
        officialUrl: 'https://pmksy.gov.in',
        optimizationTip:
            'Drip irrigation gives the HIGHEST ROI of any subsidy for crops like sugarcane, '
            'vegetables, and fruits. On 3 acres, the ₹82,500 subsidy pays for itself in '
            '1–2 seasons through reduced water bills and higher yields. '
            'Combine with PM Kusum solar pump for a completely off-grid irrigation system.',
        daysToDeadline: null,
      ),

      // 8. eNAM ────────────────────────────────────────────────────────────────────
      // Source: enam.gov.in — online mandi access, better price discovery
      _Scheme(
        id: 'enam',
        name: 'e-NAM Digital Market',
        emoji: '📱',
        ministry: 'Ministry of Agriculture & Farmers Welfare',
        description:
            'National Agriculture Market — sell crops online to buyers across India. '
            'Better price discovery eliminates middlemen. '
            'Farmers get 5–20% higher prices vs local mandi. Over 1.75 crore farmers enrolled.',
        benefitType: BenefitType.service,
        status: SchemeStatus.active,
        maxLandAcres: null,
        maxAnnualIncomeL: null,
        requiresOwnLand: false,
        cropTypes: null,
        excludesGovtEmployee: false,
        excludesIncomeTaxPayer: false,
        benefitFormula:
            'Price gain: 5–15% above local mandi × your annual produce value.',
        calcBenefit: (acres, cropVal, income) {
          // Avg price premium 8% over local mandi
          return cropVal * acres * 0.08;
        },
        deadlineNote: 'Year-round — register once, use throughout the year.',
        applyAt:
            'enam.gov.in — register with Aadhaar + bank account + produce details',
        officialUrl: 'https://enam.gov.in',
        optimizationTip:
            'Register on e-NAM during the off-season (no pressure). '
            'List produce 2–3 days before harvest for best discovery. '
            'Use the Warehouse Receipt System to sell stored grain when prices are higher — '
            'typically 3–4 months after harvest when prices rise 10–20%.',
        daysToDeadline: null,
      ),
    ];

// ─────────────────────────────────────────────────────────────────────────────
// Eligibility Engine — rule-based, no API, instant
// ─────────────────────────────────────────────────────────────────────────────

class _EligibilityResult {
  final _Scheme scheme;
  final bool eligible;
  final List<String> reasons; // why eligible / ineligible
  final double estimatedBenefit; // ₹/yr
  final int priorityScore; // 0–100 for sorting
  final String? blockingReason; // if ineligible, main reason

  const _EligibilityResult({
    required this.scheme,
    required this.eligible,
    required this.reasons,
    required this.estimatedBenefit,
    required this.priorityScore,
    this.blockingReason,
  });
}

class _SubsidyEngine {
  static List<_EligibilityResult> evaluate({
    required double landAcres,
    required _Crop crop,
    required IncomeCategory income,
    required bool isGovtEmployee,
    required bool filesIncomeTax,
    required bool ownsLand,
    required bool hasBankAccount,
    required bool hasAadhaar,
  }) {
    final schemes = _kSchemes();
    final results = <_EligibilityResult>[];
    final cropValuePerAcre = _estimateCropValue(crop);

    for (final scheme in schemes) {
      final reasons = <String>[];
      String? blockingReason;

      // ── Eligibility checks ────────────────────────────────────────────────

      // 1. Land ownership
      if (scheme.requiresOwnLand && !ownsLand) {
        blockingReason = 'Requires land ownership in your name';
      }

      // 2. Land size cap
      if (scheme.maxLandAcres != null && landAcres > scheme.maxLandAcres!) {
        final hectares = (scheme.maxLandAcres! * 0.405).toStringAsFixed(1);
        blockingReason ??=
            'Land holding exceeds scheme limit (${scheme.maxLandAcres!.toStringAsFixed(1)} acres / $hectares ha)';
      }

      // 3. Income / govt employee exclusions
      if (scheme.excludesGovtEmployee && isGovtEmployee) {
        blockingReason ??= 'Central/State government employees are excluded';
      }
      if (scheme.excludesIncomeTaxPayer && filesIncomeTax) {
        blockingReason ??=
            'Income tax filers are excluded (annual income > ₹2L)';
      }

      // 4. Crop type match
      if (scheme.cropTypes != null) {
        final matches = scheme.cropTypes!.contains(crop.type) ||
            scheme.cropTypes!.contains(CropType.any);
        if (!matches) {
          blockingReason ??=
              '${crop.name} (${_cropTypeName(crop.type)}) not covered — '
              'scheme covers ${scheme.cropTypes!.map(_cropTypeName).join(", ")}';
        }
      }

      // 5. Infrastructure checks
      if (scheme.id == 'pmkisan' || scheme.id == 'kcc') {
        if (!hasBankAccount) {
          blockingReason ??=
              'Bank account required — open a Jan Dhan account first';
        }
        if (!hasAadhaar) {
          blockingReason ??= 'Aadhaar card mandatory for this scheme';
        }
      }

      final eligible = blockingReason == null;

      // ── Build positive reasons if eligible ─────────────────────────────────
      if (eligible) {
        if (landAcres <= 2.47) {
          reasons.add(
              '✓ Small/marginal farmer — maximum priority for this scheme');
        } else if (landAcres <= 4.94) {
          reasons.add('✓ Semi-medium holding — eligible at standard rate');
        } else {
          reasons.add('✓ Landholding within eligible range');
        }

        if (scheme.cropTypes == null) {
          reasons.add('✓ ${crop.name} is covered under this scheme');
        } else {
          reasons.add(
              '✓ ${crop.name} qualifies as ${_cropTypeName(crop.type)} crop');
        }

        switch (income) {
          case IncomeCategory.verySmall:
          case IncomeCategory.small:
            reasons.add(
                '✓ Low income category — may qualify for enhanced benefits');
            break;
          case IncomeCategory.marginal:
            reasons.add('✓ Income category eligible');
            break;
          default:
            reasons.add('✓ Income within eligible range');
        }

        if (scheme.id == 'kcc' && landAcres <= 2.47) {
          reasons
              .add('✓ Collateral-free loan up to ₹2L as small/marginal farmer');
        }
        if (scheme.id == 'pmksy' && landAcres <= 12.35) {
          reasons.add(
              '✓ Qualifies for enhanced 55% subsidy (small/marginal rate)');
        }
      }

      // ── Calculate benefit ─────────────────────────────────────────────────
      final benefit = eligible
          ? scheme.calcBenefit(landAcres, cropValuePerAcre, income)
          : 0.0;

      // ── Priority score ─────────────────────────────────────────────────────
      // Based on: benefit size, urgency, ease of enrollment
      int priority = 0;
      if (eligible) {
        // Base from benefit magnitude
        if (benefit >= 50000)
          priority += 40;
        else if (benefit >= 20000)
          priority += 30;
        else if (benefit >= 10000)
          priority += 20;
        else if (benefit >= 5000)
          priority += 10;
        else
          priority += 5;

        // Urgency boost
        if (scheme.daysToDeadline != null && scheme.daysToDeadline! <= 30) {
          priority += 35;
        } else if (scheme.daysToDeadline != null &&
            scheme.daysToDeadline! <= 60) {
          priority += 20;
        } else if (scheme.daysToDeadline != null) {
          priority += 10;
        }

        // Ease (cash & service schemes are easier to enroll)
        if (scheme.benefitType == BenefitType.cash) priority += 15;
        if (scheme.benefitType == BenefitType.service) priority += 10;
        if (scheme.benefitType == BenefitType.insurance) priority += 8;

        // Small farmer bonus
        if (landAcres <= 2.47) priority += 10;
      }

      results.add(_EligibilityResult(
        scheme: scheme,
        eligible: eligible,
        reasons: reasons,
        estimatedBenefit: benefit,
        priorityScore: priority.clamp(0, 100),
        blockingReason: blockingReason,
      ));
    }

    // Sort: eligible first (by priority desc), then ineligible
    results.sort((a, b) {
      if (a.eligible && !b.eligible) return -1;
      if (!a.eligible && b.eligible) return 1;
      return b.priorityScore.compareTo(a.priorityScore);
    });

    return results;
  }

  static double _estimateCropValue(_Crop crop) {
    // MSP-based 2025-26 × avg yield/acre (matches insurance screen logic)
    const vals = <String, double>{
      'Rice': 33641,
      'Wheat': 43165,
      'Maize': 23363,
      'Sugarcane': 95200,
      'Cotton': 44150,
      'Groundnut': 39341,
      'Soybean': 26417,
      'Onion': 30000,
      'Tomato': 35000,
      'Chickpea': 42000,
      'Mustard': 38000,
      'Millet': 22000,
      'Vegetables': 45000,
      'Fruits': 60000,
    };
    return vals[crop.name] ?? 30000;
  }

  static String _cropTypeName(CropType t) {
    switch (t) {
      case CropType.kharif:
        return 'Kharif';
      case CropType.rabi:
        return 'Rabi';
      case CropType.commercial:
        return 'Commercial';
      case CropType.horticulture:
        return 'Horticulture';
      case CropType.any:
        return 'Any';
    }
  }
}

// Alias for external use

// ─────────────────────────────────────────────────────────────────────────────
// Formatters
// ─────────────────────────────────────────────────────────────────────────────

String _fmtMoney(double v) {
  if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)} Cr';
  if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(2)} L';
  if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)} K';
  return '₹${v.toStringAsFixed(0)}';
}

String _incomeName(IncomeCategory i) {
  switch (i) {
    case IncomeCategory.verySmall:
      return 'Very Low (< ₹50K/yr)';
    case IncomeCategory.small:
      return 'Low (₹50K–₹1L/yr)';
    case IncomeCategory.marginal:
      return 'Medium (₹1L–₹2L/yr)';
    case IncomeCategory.medium:
      return 'Above ₹2L/yr';
    case IncomeCategory.large:
      return 'High (files Income Tax)';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class SubsidyOptimizerPage extends StatefulWidget {
  const SubsidyOptimizerPage({Key? key}) : super(key: key);

  @override
  State<SubsidyOptimizerPage> createState() => _SubsidyPageState();
}

class _SubsidyPageState extends State<SubsidyOptimizerPage>
    with SingleTickerProviderStateMixin {
  // ── Form state ──────────────────────────────────────────────────────────────
  double _acres = 2.0;
  _Crop _crop = _kCrops[0];
  IncomeCategory _income = IncomeCategory.small;
  bool _ownsLand = true;
  bool _isGovtEmp = false;
  bool _filesTax = false;
  bool _hasBankAcct = true;
  bool _hasAadhaar = true;

  // ── Results state ────────────────────────────────────────────────────────────
  List<_EligibilityResult>? _results;
  bool _hasAnalyzed = false;
  bool _showAll = false;

  late AnimationController _anim;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _analyze() {
    HapticFeedback.mediumImpact();
    _anim.reset();
    final r = _SubsidyEngine.evaluate(
      landAcres: _acres,
      crop: _crop,
      income: _income,
      isGovtEmployee: _isGovtEmp,
      filesIncomeTax: _filesTax || _income == IncomeCategory.large,
      ownsLand: _ownsLand,
      hasBankAccount: _hasBankAcct,
      hasAadhaar: _hasAadhaar,
    );
    setState(() {
      _results = r;
      _hasAnalyzed = true;
      _showAll = false;
    });
    _anim.forward();
  }

  // ── Derived stats ────────────────────────────────────────────────────────────

  // ── Optimization insights — the "AI" that makes this more than a list ──────
  // Returns smart observations that most apps never surface
  List<Map<String, String>> get _optimizationInsights {
    if (_results == null) return [];
    final insights = <Map<String, String>>[];
    final eligible = _results!.where((r) => r.eligible).toList();
    final ids = eligible.map((r) => r.scheme.id).toSet();

    // Stack synergy: KCC + PMFBY auto-enrollment
    if (ids.contains('kcc') &&
        (ids.contains('pmfby_kharif') || ids.contains('pmfby_rabi'))) {
      insights.add({
        'icon': '🔗',
        'title': 'Stack KCC + PMFBY for free insurance',
        'body': 'Getting a Kisan Credit Card auto-enrolls you in PMFBY crop insurance '
            'for your loanee crops — no separate application needed. Do KCC first.',
        'type': 'synergy',
      });
    }

    // PM-KISAN + family stacking
    if (ids.contains('pmkisan') && _acres >= 2.0) {
      insights.add({
        'icon': '👨‍👩‍👧',
        'title': 'Register every eligible family member separately',
        'body': 'PM-KISAN is per landholding family unit. If land is split between '
            'husband, wife, or adult children, each can claim ₹6,000 separately = '
            '₹${(6000 * (_acres / 1.5).floor()).toStringAsFixed(0)}+ potential.',
        'type': 'maximize',
      });
    }

    // Drip + solar combo ROI
    if (ids.contains('pmksy') && ids.contains('pmkusum')) {
      insights.add({
        'icon': '☀️💧',
        'title': 'Combine drip irrigation + solar pump for maximum ROI',
        'body': 'PMKSY drip (55% subsidy) + PM Kusum solar pump (60% subsidy) together '
            'eliminate both water waste and energy cost. Payback period: 2–3 seasons.',
        'type': 'synergy',
      });
    }

    // eNAM timing strategy
    if (ids.contains('enam')) {
      insights.add({
        'icon': '📈',
        'title': 'Sell on e-NAM 3–4 months after harvest for 10–20% more',
        'body': 'Prices typically rise 10–20% post-harvest. Use the Warehouse Receipt '
            'System to store grain and sell online when prices peak — not at harvest time.',
        'type': 'timing',
      });
    }

    // Soil Health Card + fertiliser savings
    if (ids.contains('shc')) {
      insights.add({
        'icon': '🌱',
        'title': 'Get Soil Health Card before the season — not during',
        'body': 'Most farmers get it too late to act on. Apply now (takes 30 days). '
            'Following NPK recommendations saves ₹2,000–₹8,000/acre on fertiliser '
            'by eliminating over-application (30–40% of urea is typically wasted).',
        'type': 'timing',
      });
    }

    // PM-KISAN eKYC urgency (22nd installment ~30 days away)
    if (ids.contains('pmkisan')) {
      insights.add({
        'icon': '⚡',
        'title': '22nd PM-KISAN installment due in days — complete eKYC NOW',
        'body': 'The 22nd installment (₹2,000) is releasing in the last week of Feb / '
            'early March 2026. Missing eKYC = missed payment. Visit pmkisan.gov.in '
            'or nearest CSC immediately. Takes 5 minutes with Aadhaar OTP.',
        'type': 'urgent',
      });
    }

    return insights;
  }

  int get _eligibleCount => _results?.where((r) => r.eligible).length ?? 0;
  double get _totalBenefit =>
      _results
          ?.where((r) => r.eligible)
          .fold(0.0, (s, r) => s! + r.estimatedBenefit) ??
      0;
  int get _urgentCount =>
      _results
          ?.where((r) =>
              r.eligible &&
              r.scheme.daysToDeadline != null &&
              r.scheme.daysToDeadline! <= 30)
          .length ??
      0;

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
                padding:
                    EdgeInsets.fromLTRB(ctx.hPad, ctx.sp(14), ctx.hPad, 50),
                children: [
                  _heroCard(ctx),
                  SizedBox(height: ctx.sp(14)),
                  _inputCard(ctx),
                  SizedBox(height: ctx.sp(14)),
                  _analyzeButton(ctx),
                  if (_hasAnalyzed && _results != null) ...[
                    SizedBox(height: ctx.sp(18)),
                    FadeTransition(
                      opacity: _fade,
                      child: Column(children: [
                        _summaryBanner(ctx),
                        SizedBox(height: ctx.sp(14)),
                        if (_urgentCount > 0) ...[
                          _urgentAlert(ctx),
                          SizedBox(height: ctx.sp(14)),
                        ],
                        _totalValueCard(ctx),
                        SizedBox(height: ctx.sp(14)),
                        if (_optimizationInsights.isNotEmpty) ...[
                          _optimizationCard(ctx),
                          SizedBox(height: ctx.sp(14)),
                        ],
                        ..._buildSchemeCards(ctx),
                        if (!_showAll && (_results!.length > 4)) ...[
                          SizedBox(height: ctx.sp(10)),
                          _showMoreBtn(ctx),
                        ],
                        SizedBox(height: ctx.sp(14)),
                        _ineligibleSection(ctx),
                        SizedBox(height: ctx.sp(14)),
                        _actionChecklist(ctx),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(BuildContext context) => AppBar(
        backgroundColor: _kAmberDeep,
        elevation: 0,
        toolbarHeight: context.sp(56),
        leading: IconButton(
          icon:
              Icon(Icons.arrow_back, color: Colors.white, size: context.sp(22)),
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          },
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Subsidy Optimizer',
              style:
                  _ts(context.sp(17), color: Colors.white, w: FontWeight.bold),
              overflow: TextOverflow.ellipsis),
          Text('Find every rupee you\'re owed',
              style: _ts(context.sp(10.5),
                  color: Colors.white70, w: FontWeight.w400),
              overflow: TextOverflow.ellipsis),
        ]),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: context.sp(12)),
            child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: context.sp(10), vertical: context.sp(4)),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('8 Schemes',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: context.sp(11),
                      fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      );

  // ── Hero card ─────────────────────────────────────────────────────────────

  Widget _heroCard(BuildContext ctx) => Container(
        padding: EdgeInsets.all(ctx.sp(16)),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_kAmberDeep, _kAmberMid],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(ctx.sp(16)),
          boxShadow: [
            BoxShadow(
                color: _kAmberDeep.withOpacity(0.35),
                blurRadius: 12,
                offset: const Offset(0, 5))
          ],
        ),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Most farmers miss 3–4 schemes',
                    style: _ts(ctx.sp(15),
                        color: Colors.white, w: FontWeight.bold, height: 1.3)),
                SizedBox(height: ctx.sp(6)),
                Text(
                  'We check PM-KISAN, PMFBY, KCC, Solar Pump, '
                  'Drip Irrigation, Soil Health Card, e-NAM and more '
                  'against your exact profile — instantly.',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.88),
                      fontSize: ctx.sp(11.5),
                      height: 1.5),
                ),
                SizedBox(height: ctx.sp(10)),
                Row(children: [
                  _heroBadge(ctx, '₹ Benefit', 'Estimated ₹'),
                  SizedBox(width: ctx.sp(6)),
                  _heroBadge(ctx, '⚡ Instant', 'No API'),
                  SizedBox(width: ctx.sp(6)),
                  _heroBadge(ctx, '📋 8 Schemes', '2025-26'),
                ]),
              ])),
          SizedBox(width: ctx.sp(12)),
          Text('🌾', style: TextStyle(fontSize: ctx.sp(52))),
        ]),
      );

  Widget _heroBadge(BuildContext ctx, String top, String bot) => Container(
        padding:
            EdgeInsets.symmetric(horizontal: ctx.sp(8), vertical: ctx.sp(5)),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(ctx.sp(8)),
        ),
        child: Column(children: [
          Text(top,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: ctx.sp(10),
                  fontWeight: FontWeight.bold)),
          Text(bot,
              style: TextStyle(color: Colors.white70, fontSize: ctx.sp(9))),
        ]),
      );

  // ── Input card ────────────────────────────────────────────────────────────

  Widget _inputCard(BuildContext ctx) => _card(ctx,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.tune_rounded, color: _kAmberDeep, size: ctx.sp(20)),
            SizedBox(width: ctx.sp(6)),
            Text('Your Farm Profile',
                style: _ts(ctx.sp(15), color: _kAmberDeep, w: FontWeight.bold)),
          ]),
          SizedBox(height: ctx.sp(16)),

          // Land size slider
          _sliderSection(ctx,
              label: '🏡 Land Size',
              pill: '${_acres.toStringAsFixed(1)} acres '
                  '(${(_acres * 0.405).toStringAsFixed(2)} ha)',
              color: _kAmberDeep,
              value: _acres,
              min: 0.5,
              max: 25,
              divisions: 49,
              onChanged: (v) => setState(() => _acres = v),
              note: _landCategoryNote(_acres)),

          SizedBox(height: ctx.sp(14)),

          // Crop selector
          Text('🌾 Primary Crop', style: _ts(ctx.sp(13), color: _kText)),
          SizedBox(height: ctx.sp(8)),
          Wrap(
            spacing: ctx.sp(6),
            runSpacing: ctx.sp(6),
            children: _kCrops.map((c) {
              final sel = _crop.name == c.name;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _crop = c);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: EdgeInsets.symmetric(
                      horizontal: ctx.sp(11), vertical: ctx.sp(7)),
                  decoration: BoxDecoration(
                    color: sel ? _kAmberDeep : _kAmberLt,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                        color:
                            sel ? _kAmberDeep : _kAmberDeep.withOpacity(0.3)),
                  ),
                  child: Text('${c.emoji}  ${c.name}',
                      style: TextStyle(
                          fontSize: ctx.sp(12),
                          fontWeight: FontWeight.w600,
                          color: sel ? Colors.white : _kAmberDeep)),
                ),
              );
            }).toList(),
          ),

          SizedBox(height: ctx.sp(16)),

          // Income category
          Text('💼 Annual Household Income',
              style: _ts(ctx.sp(13), color: _kText)),
          SizedBox(height: ctx.sp(8)),
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: ctx.sp(12), vertical: ctx.sp(2)),
            decoration: BoxDecoration(
              color: _kAmberDeep.withOpacity(0.04),
              borderRadius: BorderRadius.circular(ctx.sp(12)),
              border: Border.all(color: _kBorder),
            ),
            child: DropdownButton<IncomeCategory>(
              value: _income,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              style: TextStyle(
                  color: _kText,
                  fontSize: ctx.sp(13.5),
                  fontWeight: FontWeight.w500),
              items: IncomeCategory.values
                  .map((i) => DropdownMenuItem(
                        value: i,
                        child: Text(_incomeName(i)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null)
                  setState(() {
                    _income = v;
                    if (v == IncomeCategory.large) _filesTax = true;
                  });
              },
            ),
          ),

          SizedBox(height: ctx.sp(16)),
          Divider(color: _kBorder, height: 1),
          SizedBox(height: ctx.sp(14)),

          // Boolean flags
          Text('📋 A few quick questions',
              style: _ts(ctx.sp(13), color: _kText)),
          SizedBox(height: ctx.sp(10)),
          _toggle(ctx, '🏠 Land is in your name (own land)', _ownsLand,
              (v) => setState(() => _ownsLand = v)),
          _toggle(ctx, '🏛 Central/State govt employee or pensioner',
              _isGovtEmp, (v) => setState(() => _isGovtEmp = v)),
          _toggle(ctx, '📄 You file Income Tax (ITR)', _filesTax,
              (v) => setState(() => _filesTax = v)),
          _toggle(ctx, '🏦 Have a bank account (any bank)', _hasBankAcct,
              (v) => setState(() => _hasBankAcct = v)),
          _toggle(ctx, '🪪 Have Aadhaar card', _hasAadhaar,
              (v) => setState(() => _hasAadhaar = v)),
        ],
      ));

  String _landCategoryNote(double acres) {
    if (acres < 0.01) return 'Landless — limited schemes available';
    if (acres <= 2.47) return 'Marginal farmer (≤ 1 ha) — maximum benefits';
    if (acres <= 4.94) return 'Small farmer (1–2 ha) — high priority';
    if (acres <= 12.35) return 'Semi-medium (2–5 ha) — standard benefits';
    if (acres <= 24.7) return 'Medium farmer (5–10 ha)';
    return 'Large farmer (> 10 ha) — fewer central schemes';
  }

  Widget _sliderSection(
    BuildContext ctx, {
    required String label,
    required String pill,
    required Color color,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    String? note,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: _ts(ctx.sp(13), color: _kText, w: FontWeight.w500)),
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: ctx.sp(9), vertical: ctx.sp(4)),
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(pill,
                style: TextStyle(
                    fontSize: ctx.sp(11),
                    fontWeight: FontWeight.bold,
                    color: color)),
          ),
        ]),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: color,
            thumbColor: color,
            inactiveTrackColor: color.withOpacity(0.2),
            overlayColor: color.withOpacity(0.08),
            trackHeight: ctx.sp(4),
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: ctx.sp(8)),
          ),
          child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged),
        ),
        if (note != null)
          Padding(
            padding: EdgeInsets.only(top: ctx.sp(2)),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, color: color, size: ctx.sp(13)),
              SizedBox(width: ctx.sp(4)),
              Text(note,
                  style: TextStyle(
                      fontSize: ctx.sp(11),
                      color: color,
                      fontWeight: FontWeight.w500)),
            ]),
          ),
      ]);

  Widget _toggle(BuildContext ctx, String label, bool value,
          ValueChanged<bool> onChanged) =>
      Padding(
        padding: EdgeInsets.only(bottom: ctx.sp(6)),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: _ts(ctx.sp(12.5), color: _kText, w: FontWeight.w500))),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: _kAmberDeep,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ]),
      );

  // ── Analyze button ────────────────────────────────────────────────────────

  Widget _analyzeButton(BuildContext ctx) => SizedBox(
        width: double.infinity,
        height: ctx.sp(58),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _kAmberDeep,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ctx.sp(14))),
            elevation: 4,
          ),
          icon: Icon(Icons.search_rounded, size: ctx.sp(22)),
          label: Text(
            '🎯  Find My Eligible Schemes',
            style: _ts(ctx.sp(15), color: Colors.white, w: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
          onPressed: _analyze,
        ),
      );

  // ── Summary banner ────────────────────────────────────────────────────────

  Widget _summaryBanner(BuildContext ctx) => Container(
        padding: EdgeInsets.all(ctx.sp(16)),
        decoration: BoxDecoration(
          color: _kGreen,
          borderRadius: BorderRadius.circular(ctx.sp(16)),
          boxShadow: [
            BoxShadow(
                color: _kGreen.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(children: [
          Text('🎉', style: TextStyle(fontSize: ctx.sp(32))),
          SizedBox(width: ctx.sp(12)),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('$_eligibleCount schemes eligible for you!',
                    style: _ts(ctx.sp(17),
                        color: Colors.white, w: FontWeight.bold)),
                SizedBox(height: ctx.sp(3)),
                Text('Estimated combined annual benefit:',
                    style: TextStyle(
                        color: Colors.white70, fontSize: ctx.sp(11.5))),
                Text(_fmtMoney(_totalBenefit) + ' / year',
                    style: _ts(ctx.sp(20),
                        color: Colors.white, w: FontWeight.w900)),
                SizedBox(height: ctx.sp(4)),
                Text(
                  '${_results!.length - _eligibleCount} schemes not applicable — see why below.',
                  style:
                      TextStyle(color: Colors.white60, fontSize: ctx.sp(10.5)),
                ),
              ])),
        ]),
      );

  // ── Urgent alert ──────────────────────────────────────────────────────────

  Widget _urgentAlert(BuildContext ctx) => Container(
        padding: EdgeInsets.all(ctx.sp(14)),
        decoration: BoxDecoration(
          color: _kRedLt,
          borderRadius: BorderRadius.circular(ctx.sp(14)),
          border: Border.all(color: _kRed.withOpacity(0.4)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.alarm_rounded, color: _kRed, size: ctx.sp(22)),
          SizedBox(width: ctx.sp(10)),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('⚠️ Act within 30 days!',
                    style: _ts(ctx.sp(13.5), color: _kRed, w: FontWeight.bold)),
                SizedBox(height: ctx.sp(4)),
                ..._results!
                    .where((r) =>
                        r.eligible &&
                        r.scheme.daysToDeadline != null &&
                        r.scheme.daysToDeadline! <= 30)
                    .map((r) => Padding(
                          padding: EdgeInsets.only(bottom: ctx.sp(4)),
                          child: Row(children: [
                            Text(r.scheme.emoji,
                                style: TextStyle(fontSize: ctx.sp(14))),
                            SizedBox(width: ctx.sp(6)),
                            Expanded(
                                child: Text(
                              '${r.scheme.name} — deadline in ~${r.scheme.daysToDeadline} days',
                              style: TextStyle(
                                  color: _kRed,
                                  fontSize: ctx.sp(12),
                                  fontWeight: FontWeight.w600),
                            )),
                          ]),
                        )),
              ])),
        ]),
      );

  // ── Total value card ──────────────────────────────────────────────────────

  Widget _totalValueCard(BuildContext ctx) {
    final eligible = _results!.where((r) => r.eligible).toList();
    return _card(ctx,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('💎 Your Subsidy Breakdown',
                style: _ts(ctx.sp(15), color: _kAmberDeep, w: FontWeight.bold)),
            SizedBox(height: ctx.sp(4)),
            Text('Estimated annual value of each scheme',
                style: _ts(ctx.sp(11), color: _kTextMid, w: FontWeight.w400)),
            SizedBox(height: ctx.sp(14)),
            ...eligible.map((r) => Padding(
                  padding: EdgeInsets.only(bottom: ctx.sp(8)),
                  child: Row(children: [
                    Text(r.scheme.emoji,
                        style: TextStyle(fontSize: ctx.sp(18))),
                    SizedBox(width: ctx.sp(8)),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                    child: Text(r.scheme.name,
                                        style: _ts(ctx.sp(12.5), color: _kText),
                                        overflow: TextOverflow.ellipsis)),
                                Text(_fmtMoney(r.estimatedBenefit),
                                    style: _ts(ctx.sp(13),
                                        color: _kGreen, w: FontWeight.bold)),
                              ]),
                          SizedBox(height: ctx.sp(4)),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(ctx.sp(4)),
                            child: LinearProgressIndicator(
                              value: _totalBenefit > 0
                                  ? (r.estimatedBenefit / _totalBenefit)
                                      .clamp(0, 1)
                                  : 0,
                              minHeight: ctx.sp(6),
                              backgroundColor: _kBorder,
                              valueColor: AlwaysStoppedAnimation(
                                  _benefitColor(r.scheme.benefitType)),
                            ),
                          ),
                        ])),
                  ]),
                )),
            Divider(color: _kBorder, height: ctx.sp(16)),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Total estimated annual benefit',
                  style: _ts(ctx.sp(13), color: _kText, w: FontWeight.bold)),
              Text(_fmtMoney(_totalBenefit),
                  style: _ts(ctx.sp(16), color: _kGreen, w: FontWeight.w900)),
            ]),
          ],
        ));
  }

  Color _benefitColor(BenefitType t) {
    switch (t) {
      case BenefitType.cash:
        return _kGreen;
      case BenefitType.insurance:
        return _kAmberDeep;
      case BenefitType.loan:
        return _kBlueDark;
      case BenefitType.service:
        return _kGreenMid;
      case BenefitType.subsidy:
        return _kAmberMid;
    }
  }

  // ── Scheme cards ──────────────────────────────────────────────────────────

  List<Widget> _buildSchemeCards(BuildContext ctx) {
    final eligible = _results!.where((r) => r.eligible).toList();
    final toShow = _showAll ? eligible : eligible.take(4).toList();
    return toShow.asMap().entries.map((e) {
      final i = e.key;
      final r = e.value;
      return Padding(
        padding: EdgeInsets.only(bottom: ctx.sp(12)),
        child: _schemeCard(ctx, r, rank: i + 1),
      );
    }).toList();
  }

  Widget _schemeCard(BuildContext ctx, _EligibilityResult r, {int rank = 0}) {
    final isUrgent =
        r.scheme.daysToDeadline != null && r.scheme.daysToDeadline! <= 30;
    final accentColor = _benefitColor(r.scheme.benefitType);

    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(ctx.sp(16)),
        border: Border.all(
            color: isUrgent
                ? _kRed.withOpacity(0.5)
                : accentColor.withOpacity(0.25),
            width: isUrgent ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
              color: accentColor.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: EdgeInsets.all(ctx.sp(14)),
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.06),
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(ctx.sp(16))),
          ),
          child: Row(children: [
            // Rank badge
            Container(
              width: ctx.sp(28),
              height: ctx.sp(28),
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                  child: Text('$rank',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: ctx.sp(12)))),
            ),
            SizedBox(width: ctx.sp(10)),
            Text(r.scheme.emoji, style: TextStyle(fontSize: ctx.sp(22))),
            SizedBox(width: ctx.sp(6)),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(r.scheme.name,
                      style:
                          _ts(ctx.sp(14.5), color: _kText, w: FontWeight.bold),
                      overflow: TextOverflow.ellipsis),
                  Text(r.scheme.ministry,
                      style: TextStyle(fontSize: ctx.sp(10), color: _kTextMid),
                      overflow: TextOverflow.ellipsis),
                ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _typeBadge(ctx, r.scheme.benefitType),
              SizedBox(height: ctx.sp(4)),
              if (isUrgent)
                _urgencyChip(ctx, r.scheme.daysToDeadline!)
              else if (r.scheme.daysToDeadline != null)
                _deadlineChip(ctx, r.scheme.daysToDeadline!),
            ]),
          ]),
        ),

        Padding(
          padding: EdgeInsets.all(ctx.sp(14)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Description
            Text(r.scheme.description,
                style: TextStyle(
                    fontSize: ctx.sp(12), color: _kTextMid, height: 1.5)),
            SizedBox(height: ctx.sp(12)),

            // Benefit value
            Container(
              padding: EdgeInsets.all(ctx.sp(12)),
              decoration: BoxDecoration(
                color: _kGreenLt,
                borderRadius: BorderRadius.circular(ctx.sp(10)),
              ),
              child: Row(children: [
                Icon(Icons.account_balance_wallet_outlined,
                    color: _kGreen, size: ctx.sp(20)),
                SizedBox(width: ctx.sp(8)),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Estimated annual benefit',
                          style: TextStyle(
                              fontSize: ctx.sp(10.5), color: _kGreen)),
                      Text(_fmtMoney(r.estimatedBenefit),
                          style: _ts(ctx.sp(18),
                              color: _kGreen, w: FontWeight.w900)),
                      Text(r.scheme.benefitFormula,
                          style: TextStyle(
                              fontSize: ctx.sp(10),
                              color: _kGreen.withOpacity(0.7)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ])),
              ]),
            ),

            SizedBox(height: ctx.sp(10)),

            // Why eligible
            ...r.reasons.map((reason) => Padding(
                  padding: EdgeInsets.only(bottom: ctx.sp(3)),
                  child: Text(reason,
                      style: TextStyle(
                          fontSize: ctx.sp(11.5),
                          color: _kGreenMid,
                          fontWeight: FontWeight.w500)),
                )),

            SizedBox(height: ctx.sp(10)),

            // Optimization tip
            Container(
              padding: EdgeInsets.all(ctx.sp(11)),
              decoration: BoxDecoration(
                color: _kAmberLt,
                borderRadius: BorderRadius.circular(ctx.sp(10)),
                border: Border.all(color: _kAmberMid.withOpacity(0.3)),
              ),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('💡', style: TextStyle(fontSize: ctx.sp(14))),
                SizedBox(width: ctx.sp(6)),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Optimization Tip',
                          style: _ts(ctx.sp(11),
                              color: _kAmberDeep, w: FontWeight.bold)),
                      SizedBox(height: ctx.sp(3)),
                      Text(r.scheme.optimizationTip,
                          style: TextStyle(
                              fontSize: ctx.sp(11.5),
                              color: _kAmberDeep,
                              height: 1.5)),
                    ])),
              ]),
            ),

            SizedBox(height: ctx.sp(10)),

            // Deadline & apply
            _infoRow(ctx, Icons.calendar_today_outlined, _kText,
                r.scheme.deadlineNote),
            SizedBox(height: ctx.sp(6)),
            _infoRow(ctx, Icons.location_on_outlined, _kAmberDeep,
                'Apply at: ${r.scheme.applyAt}'),
            SizedBox(height: ctx.sp(6)),
            _infoRow(ctx, Icons.link_rounded, _kBlueDark, r.scheme.officialUrl),
          ]),
        ),
      ]),
    );
  }

  Widget _typeBadge(BuildContext ctx, BenefitType t) {
    final col = _benefitColor(t);
    String label;
    switch (t) {
      case BenefitType.cash:
        label = 'CASH';
        break;
      case BenefitType.insurance:
        label = 'INSURANCE';
        break;
      case BenefitType.loan:
        label = 'CREDIT';
        break;
      case BenefitType.service:
        label = 'SERVICE';
        break;
      case BenefitType.subsidy:
        label = 'SUBSIDY';
        break;
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: ctx.sp(7), vertical: ctx.sp(3)),
      decoration: BoxDecoration(
        color: col.withOpacity(0.12),
        borderRadius: BorderRadius.circular(ctx.sp(5)),
        border: Border.all(color: col.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: ctx.sp(9),
              color: col,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5)),
    );
  }

  Widget _urgencyChip(BuildContext ctx, int days) => Container(
        padding:
            EdgeInsets.symmetric(horizontal: ctx.sp(7), vertical: ctx.sp(3)),
        decoration: BoxDecoration(
          color: _kRed,
          borderRadius: BorderRadius.circular(ctx.sp(5)),
        ),
        child: Text('⚡ $days days',
            style: TextStyle(
                fontSize: ctx.sp(9.5),
                color: Colors.white,
                fontWeight: FontWeight.bold)),
      );

  Widget _deadlineChip(BuildContext ctx, int days) => Container(
        padding:
            EdgeInsets.symmetric(horizontal: ctx.sp(7), vertical: ctx.sp(3)),
        decoration: BoxDecoration(
          color: _kAmberLt,
          borderRadius: BorderRadius.circular(ctx.sp(5)),
          border: Border.all(color: _kAmberMid.withOpacity(0.5)),
        ),
        child: Text('📅 ~$days d',
            style: TextStyle(
                fontSize: ctx.sp(9.5),
                color: _kAmberDeep,
                fontWeight: FontWeight.bold)),
      );

  Widget _infoRow(BuildContext ctx, IconData icon, Color color, String text) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: ctx.sp(14)),
        SizedBox(width: ctx.sp(6)),
        Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: ctx.sp(11.5), color: _kTextMid, height: 1.4),
                maxLines: 3,
                overflow: TextOverflow.ellipsis)),
      ]);

  Widget _showMoreBtn(BuildContext ctx) => GestureDetector(
        onTap: () => setState(() => _showAll = true),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: ctx.sp(12)),
          decoration: BoxDecoration(
            color: _kAmberLt,
            borderRadius: BorderRadius.circular(ctx.sp(12)),
            border: Border.all(color: _kAmberMid.withOpacity(0.4)),
          ),
          child: Center(
              child: Text(
            '▼  Show all ${_results!.where((r) => r.eligible).length} eligible schemes',
            style: _ts(ctx.sp(13), color: _kAmberDeep, w: FontWeight.bold),
          )),
        ),
      );

  // ── Ineligible section ────────────────────────────────────────────────────

  // ── Optimization insights card ─────────────────────────────────────────────

  Widget _optimizationCard(BuildContext ctx) => Container(
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(ctx.sp(16)),
          border: Border.all(color: _kAmberMid.withOpacity(0.35)),
          boxShadow: [
            BoxShadow(
                color: _kAmberDeep.withOpacity(0.07),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: EdgeInsets.all(ctx.sp(14)),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_kAmberDeep.withOpacity(0.08), _kAmberLt],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(ctx.sp(16))),
            ),
            child: Row(children: [
              Text('🧠', style: TextStyle(fontSize: ctx.sp(22))),
              SizedBox(width: ctx.sp(8)),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Smart Optimization Tips',
                        style: _ts(ctx.sp(15),
                            color: _kAmberDeep, w: FontWeight.bold)),
                    Text('What most apps won\'t tell you',
                        style:
                            TextStyle(fontSize: ctx.sp(11), color: _kAmberMid)),
                  ])),
              Container(
                padding: EdgeInsets.symmetric(
                    horizontal: ctx.sp(8), vertical: ctx.sp(4)),
                decoration: BoxDecoration(
                  color: _kAmberDeep,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${_optimizationInsights.length} tips',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: ctx.sp(10.5),
                        fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
          Padding(
            padding: EdgeInsets.all(ctx.sp(14)),
            child: Column(children: [
              ..._optimizationInsights.asMap().entries.map((e) {
                final i = e.key;
                final tip = e.value;
                final isLast = i == _optimizationInsights.length - 1;
                final typeColor = tip['type'] == 'urgent'
                    ? _kRed
                    : tip['type'] == 'synergy'
                        ? _kGreen
                        : tip['type'] == 'maximize'
                            ? _kBlueDark
                            : _kAmberDeep;
                return Column(children: [
                  Container(
                    padding: EdgeInsets.all(ctx.sp(12)),
                    decoration: BoxDecoration(
                      color: typeColor.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(ctx.sp(12)),
                      border: Border.all(color: typeColor.withOpacity(0.2)),
                    ),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tip['icon']!,
                              style: TextStyle(fontSize: ctx.sp(20))),
                          SizedBox(width: ctx.sp(10)),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Row(children: [
                                  Expanded(
                                      child: Text(tip['title']!,
                                          style: _ts(ctx.sp(13),
                                              color: typeColor,
                                              w: FontWeight.bold))),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: ctx.sp(6),
                                        vertical: ctx.sp(2)),
                                    decoration: BoxDecoration(
                                      color: typeColor.withOpacity(0.1),
                                      borderRadius:
                                          BorderRadius.circular(ctx.sp(4)),
                                    ),
                                    child: Text(
                                      tip['type'] == 'urgent'
                                          ? 'URGENT'
                                          : tip['type'] == 'synergy'
                                              ? 'STACK'
                                              : tip['type'] == 'maximize'
                                                  ? 'MAXIMIZE'
                                                  : 'TIMING',
                                      style: TextStyle(
                                          fontSize: ctx.sp(8.5),
                                          color: typeColor,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5),
                                    ),
                                  ),
                                ]),
                                SizedBox(height: ctx.sp(5)),
                                Text(tip['body']!,
                                    style: TextStyle(
                                        fontSize: ctx.sp(12),
                                        color: _kTextMid,
                                        height: 1.5)),
                              ])),
                        ]),
                  ),
                  if (!isLast) SizedBox(height: ctx.sp(8)),
                ]);
              }).toList(),
            ]),
          ),
        ]),
      );

  Widget _ineligibleSection(BuildContext ctx) {
    final ineligible = _results!.where((r) => !r.eligible).toList();
    if (ineligible.isEmpty) return const SizedBox.shrink();

    return _card(ctx,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.cancel_outlined, color: _kTextMid, size: ctx.sp(18)),
              SizedBox(width: ctx.sp(6)),
              Text('Not Eligible (${ineligible.length} schemes)',
                  style: _ts(ctx.sp(14), color: _kTextMid, w: FontWeight.bold)),
            ]),
            SizedBox(height: ctx.sp(4)),
            Text('Understand why — and what to change to qualify',
                style: TextStyle(fontSize: ctx.sp(11), color: _kTextMid)),
            SizedBox(height: ctx.sp(12)),
            ...ineligible.map((r) => Padding(
                  padding: EdgeInsets.only(bottom: ctx.sp(10)),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.scheme.emoji,
                            style: TextStyle(fontSize: ctx.sp(18))),
                        SizedBox(width: ctx.sp(8)),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(r.scheme.name,
                                  style: _ts(ctx.sp(13), color: _kText),
                                  overflow: TextOverflow.ellipsis),
                              SizedBox(height: ctx.sp(3)),
                              Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.block_rounded,
                                        color: _kRed, size: ctx.sp(13)),
                                    SizedBox(width: ctx.sp(4)),
                                    Expanded(
                                        child: Text(
                                            r.blockingReason ?? 'Not eligible',
                                            style: TextStyle(
                                                fontSize: ctx.sp(11.5),
                                                color: _kRed,
                                                height: 1.4))),
                                  ]),
                            ])),
                      ]),
                )),
          ],
        ));
  }

  // ── Action checklist ──────────────────────────────────────────────────────

  Widget _actionChecklist(BuildContext ctx) {
    final eligible = _results!.where((r) => r.eligible).toList();
    if (eligible.isEmpty) return const SizedBox.shrink();

    // Build prioritized action steps
    final steps = <Map<String, String>>[];

    if (eligible.any((r) => r.scheme.id == 'pmkisan')) {
      steps.add({
        'step': '1',
        'action': 'Register on pmkisan.gov.in with Aadhaar + land records',
        'note': 'Takes 10 min. Next installment due within 30 days.',
        'urgency': 'high',
      });
    }
    if (eligible.any((r) => r.scheme.id == 'kcc')) {
      steps.add({
        'step': '${steps.length + 1}',
        'action': 'Apply for Kisan Credit Card at your nearest bank',
        'note':
            'Bring land records, Aadhaar, passport photo. 3–4 week processing.',
        'urgency': 'high',
      });
    }
    if (eligible.any(
        (r) => r.scheme.id == 'pmfby_kharif' || r.scheme.id == 'pmfby_rabi')) {
      steps.add({
        'step': '${steps.length + 1}',
        'action': 'Enroll in PMFBY at pmfby.gov.in or your bank',
        'note': 'Kharif: June–July. Rabi: Nov–Dec. KCC holders auto-enrolled.',
        'urgency': 'medium',
      });
    }
    if (eligible.any((r) => r.scheme.id == 'shc')) {
      steps.add({
        'step': '${steps.length + 1}',
        'action': 'Get Soil Health Card at soilhealth.dac.gov.in or KVK',
        'note': 'Free, takes 30–60 days. Saves ₹2K–₹8K/acre on fertilisers.',
        'urgency': 'low',
      });
    }
    if (eligible.any((r) => r.scheme.id == 'pmkusum')) {
      steps.add({
        'step': '${steps.length + 1}',
        'action': 'Apply for PM Kusum solar pump before April quota opens',
        'note': 'State quota fills up fast. Apply in first week of April.',
        'urgency': 'medium',
      });
    }
    if (eligible.any((r) => r.scheme.id == 'pmksy')) {
      steps.add({
        'step': '${steps.length + 1}',
        'action': 'Register for PMKSY drip irrigation at state agri portal',
        'note': '55% subsidy for small/marginal. Highest ROI after KCC.',
        'urgency': 'low',
      });
    }
    if (eligible.any((r) => r.scheme.id == 'enam')) {
      steps.add({
        'step': '${steps.length + 1}',
        'action': 'Register on enam.gov.in for online mandi access',
        'note': '5–15% better prices. Takes 5 min with Aadhaar.',
        'urgency': 'low',
      });
    }

    return Container(
      padding: EdgeInsets.all(ctx.cPad),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_kBlueDark, const Color(0xFF2D5A8E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(ctx.sp(16)),
        boxShadow: [
          BoxShadow(
              color: _kBlueDark.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.checklist_rounded, color: Colors.white, size: ctx.sp(22)),
          SizedBox(width: ctx.sp(8)),
          Text('Your Action Plan',
              style: _ts(ctx.sp(15), color: Colors.white, w: FontWeight.bold)),
        ]),
        SizedBox(height: ctx.sp(4)),
        Text('Do these in order to claim all eligible benefits:',
            style: TextStyle(color: Colors.white70, fontSize: ctx.sp(11.5))),
        SizedBox(height: ctx.sp(14)),
        ...steps.map((s) {
          final color = s['urgency'] == 'high'
              ? const Color(0xFFFCA5A5)
              : s['urgency'] == 'medium'
                  ? const Color(0xFFFCD34D)
                  : const Color(0xFF86EFAC);
          return Padding(
            padding: EdgeInsets.only(bottom: ctx.sp(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: ctx.sp(26),
                height: ctx.sp(26),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: color)),
                child: Center(
                    child: Text(s['step']!,
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: ctx.sp(12)))),
              ),
              SizedBox(width: ctx.sp(10)),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(s['action']!,
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: ctx.sp(13),
                            height: 1.3)),
                    SizedBox(height: ctx.sp(3)),
                    Text(s['note']!,
                        style: TextStyle(
                            color: Colors.white60,
                            fontSize: ctx.sp(11),
                            height: 1.4)),
                  ])),
            ]),
          );
        }),
        SizedBox(height: ctx.sp(4)),
        Container(
          padding: EdgeInsets.all(ctx.sp(10)),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(ctx.sp(10)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded,
                color: Colors.white54, size: ctx.sp(14)),
            SizedBox(width: ctx.sp(6)),
            Expanded(
                child: Text(
              'Benefits are estimates based on official 2025-26 GoI data. '
              'Verify exact eligibility at your local CSC, KVK, or block agriculture office.',
              style: TextStyle(
                  color: Colors.white54, fontSize: ctx.sp(10.5), height: 1.5),
            )),
          ]),
        ),
      ]),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  Widget _card(BuildContext ctx, {required Widget child}) => Container(
        width: double.infinity,
        padding: EdgeInsets.all(ctx.cPad),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(ctx.sp(16)),
          border: Border.all(color: _kBorder),
          boxShadow: [
            BoxShadow(
                color: _kAmberDeep.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: child,
      );
}
