import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LivePrice extends StatefulWidget {
  const LivePrice({Key? key}) : super(key: key);

  @override
  State<LivePrice> createState() => _LivePriceState();
}

class _LivePriceState extends State<LivePrice> {
  bool _isLoading = true;
  List<dynamic> _marketData = [];
  List<dynamic> _filteredData = [];
  String _errorMessage = '';
  String _sortBy = 'name';

  final String apiUrl =
      "https://ecoyieldbackend-production.up.railway.app/api/prices";
  final String cacheKey = "cached_market_prices";
  final String cacheTimestampKey = "cache_timestamp";

  @override
  void initState() {
    super.initState();
    _fetchMarketData();
  }

  Future<void> _fetchMarketData({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check cache validity (cache expires after 30 minutes)
      if (!forceRefresh) {
        final cachedString = prefs.getString(cacheKey);
        final cacheTimestamp = prefs.getInt(cacheTimestampKey);
        
        if (cachedString != null && cacheTimestamp != null) {
          final cacheAge = DateTime.now().millisecondsSinceEpoch - cacheTimestamp;
          final thirtyMinutes = 30 * 60 * 1000; // 30 minutes in milliseconds
          
          if (cacheAge < thirtyMinutes) {
            // Use cached data
            final decoded = jsonDecode(cachedString);
            if (mounted) {
              setState(() {
                _marketData = decoded["data"];
                _filteredData = decoded["data"];
                _applySorting();
                _isLoading = false;
              });
            }
            return;
          }
        }
      }

      // Fetch fresh data
      final response = await http.get(Uri.parse(apiUrl)).timeout(
        const Duration(seconds: 15),
      );
      
      if (response.statusCode == 200) {
        // Save to cache with timestamp
        await prefs.setString(cacheKey, response.body);
        await prefs.setInt(cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
        
        final decoded = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _marketData = decoded["data"];
            _filteredData = decoded["data"];
            _applySorting();
            _isLoading = false;
            _errorMessage = '';
          });
        }
      } else {
        throw Exception("Server returned ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _applySorting() {
    _filteredData.sort((a, b) {
      if (_sortBy == 'name') {
        return (a["commodity"] ?? "").compareTo(b["commodity"] ?? "");
      } else if (_sortBy == 'price_asc') {
        final aPrice = double.tryParse(a["modal_price"] ?? "0") ?? 0;
        final bPrice = double.tryParse(b["modal_price"] ?? "0") ?? 0;
        return aPrice.compareTo(bPrice);
      } else {
        final aPrice = double.tryParse(a["modal_price"] ?? "0") ?? 0;
        final bPrice = double.tryParse(b["modal_price"] ?? "0") ?? 0;
        return bPrice.compareTo(aPrice);
      }
    });
  }

  Color _getPriceColor(String? price) {
    final p = double.tryParse(price ?? "0") ?? 0;
    if (p >= 5000) return const Color(0xFF004D40); // Deep Teal
    if (p >= 2000) return const Color(0xFF2E7D32); // Emerald Green
    if (p >= 500) return const Color(0xFF43A047);  // Light Green
    return const Color(0xFF7CB342);                // Lime Green
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBF7),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: isTablet ? 160 : 140,
            floating: false,
            pinned: true,
            elevation: innerBoxIsScrolled ? 4 : 0,
            shadowColor: Colors.black26,
            backgroundColor: const Color(0xFF1B5E20),
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
              title: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Live Market',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (!_isLoading && _errorMessage.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Tracking ${_filteredData.length} commodities',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                ],
              ),
              background: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF004D40), Color(0xFF2E7D32)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  Positioned(
                    right: -20,
                    bottom: -20,
                    child: Icon(
                      Icons.eco_rounded,
                      size: isTablet ? 140 : 120,
                      color: Colors.white.withOpacity(0.08),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              // Sort button in app bar
              Container(
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.tune_rounded, color: Colors.white, size: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  position: PopupMenuPosition.under,
                  onSelected: (val) {
                    setState(() => _sortBy = val);
                    _applySorting();
                  },
                  itemBuilder: (_) => [
                    _sortMenuItem('name', 'Name A–Z', Icons.sort_by_alpha_rounded),
                    _sortMenuItem('price_asc', 'Price: Low → High',
                        Icons.trending_up_rounded),
                    _sortMenuItem('price_desc', 'Price: High → Low',
                        Icons.trending_down_rounded),
                  ],
                ),
              ),
            ],
          ),
        ],
        body: _isLoading
            ? _buildLoader()
            : _errorMessage.isNotEmpty
                ? _buildError()
                : _filteredData.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        color: const Color(0xFF2E7D32),
                        backgroundColor: Colors.white,
                        onRefresh: () => _fetchMarketData(forceRefresh: true),
                        child: isTablet ? _buildGrid() : _buildList(),
                      ),
      ),
    );
  }

  PopupMenuItem<String> _sortMenuItem(
      String value, String label, IconData icon) {
    final selected = _sortBy == value;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon,
              size: 20,
              color: selected ? const Color(0xFF2E7D32) : Colors.grey.shade600),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                  color: selected ? const Color(0xFF2E7D32) : Colors.black87,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500)),
          if (selected) ...[
            const Spacer(),
            const Icon(Icons.check_circle_rounded,
                size: 18, color: Color(0xFF2E7D32)),
          ],
        ],
      ),
    );
  }

  Widget _buildLoader() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Color(0xFF2E7D32), strokeWidth: 3),
          SizedBox(height: 20),
          Text('Fetching latest prices...',
              style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.wifi_off_rounded, size: 48, color: Colors.red.shade300),
            ),
            const SizedBox(height: 20),
            const Text('Connection Lost',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)),
            const SizedBox(height: 8),
            Text(_errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, fontSize: 14, height: 1.4)),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => _fetchMarketData(forceRefresh: true),
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_rounded, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No commodities available',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      itemCount: _filteredData.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildCard(_filteredData[index], false),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.3,
      ),
      itemCount: _filteredData.length,
      itemBuilder: (context, index) => _buildCard(_filteredData[index], true),
    );
  }

  Widget _buildCard(dynamic item, bool isTablet) {
    final commodity = item["commodity"] ?? "Unknown";
    final min = item["min_price"] ?? "—";
    final modal = item["modal_price"] ?? "—";
    final max = item["max_price"] ?? "—";
    final accent = _getPriceColor(modal);
    final initial = commodity.isNotEmpty ? commodity[0].toUpperCase() : "?";

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Header Row
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accent.withOpacity(0.8), accent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    commodity,
                    style: TextStyle(
                      fontSize: isTablet ? 17 : 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Prices Layout
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FBF7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withOpacity(0.1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Min Price
                  _buildSmallPriceInfo('Min', min, Colors.black54),
                  
                  // Modal (Average/Main) Price
                  Column(
                    children: [
                      Text('Avg / Qtl',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: accent.withOpacity(0.8),
                              letterSpacing: 0.5)),
                      const SizedBox(height: 2),
                      Text(
                        '₹$modal',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                  
                  // Max Price
                  _buildSmallPriceInfo('Max', max, Colors.black54),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallPriceInfo(String label, String price, Color color) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey)),
        const SizedBox(height: 2),
        Text('₹$price',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color)),
      ],
    );
  }
}