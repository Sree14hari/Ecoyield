// ignore_for_file: unused_element

import 'package:cropmate/screens/GlobalReach.dart';
import 'package:cropmate/screens/livenarketprice.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/material.dart';

import 'package:cropmate/screens/disease_detection_page.dart';
import 'package:cropmate/screens/plant_identification_page.dart';
import 'package:cropmate/screens/plants_page.dart';
// Add this import
import 'package:cropmate/screens/watering_page.dart';

import 'package:cropmate/services/weather_service.dart';
import 'package:cropmate/services/groq_service.dart';
import 'package:flutter/services.dart';

import 'package:cropmate/screens/monte_carlo_simulation_page.dart';


class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _page = 0;
  final WeatherService _weatherService = WeatherService();
  Map<String, dynamic>? _weatherData;
  String _currentDate = '';
  bool _isLoading = true;
  String _errorMessage = '';
  @override
  void initState() {
    super.initState();
    _loadWeatherData();
    _currentDate = _getCurrentDate();
  }

  String _getCurrentDate() {
    final now = DateTime.now();
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  Future<void> _loadWeatherData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
      final weatherData = await _weatherService.getCurrentWeather();
      setState(() {
        _weatherData = weatherData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not load weather data';
        _isLoading = false;
      });
      print('Error loading weather: $e');
    }
  }

  Widget _buildCircularButton({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(40),
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.3), width: 2),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: color,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildSquareButton({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.3), width: 2),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                icon,
                color: color,
                size: 32,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(65),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(color: Colors.white),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 6, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.eco, color: Colors.green, size: 24),
                              const SizedBox(width: 8),
                              const Text(
                                "Ecoyield",
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                    Spacer(),
                    IconButton(
                      icon: const Icon(Icons.monochrome_photos), // The icon to display
                      onPressed: () {
                        // Code to execute when the button is pressed
                        Navigator.of(context).push(
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) =>
                                const GlobalReach(),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
                              var curve = Curves.easeInOut;
                              var curveTween = CurveTween(curve: curve);

                              var fadeAnimation = Tween<double>(
                                begin: 0.0,
                                end: 1.0,
                              ).animate(animation.drive(curveTween));

                              return FadeTransition(
                                opacity: fadeAnimation,
                                child: child,
                              );
                            },
                            transitionDuration:
                                const Duration(milliseconds: 500),
                          ),
                        );
                        print('Icon button pressed!');
                      },
                    )
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: _getPage(_page),
      bottomNavigationBar: CurvedNavigationBar(
        backgroundColor: Colors.transparent,
        color: Colors.white,
        buttonBackgroundColor: Colors.green,
        height: 60,
        index: _page,
        items: const [
          Icon(Icons.home_outlined, size: 30, color: Colors.black),
          Icon(Icons.local_florist_outlined, size: 30, color: Colors.black),
          Icon(Icons.currency_rupee, size: 30, color: Colors.black),
        ],
        onTap: (index) {
          HapticFeedback.mediumImpact(); // Add haptic feedback
          setState(() {
            _page = index;
          });
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showChatbotDialog(context);
        },
        backgroundColor: Colors.green,
        tooltip: 'Chatbot',
        child: const Icon(Icons.chat, color: Colors.white),
      ),
    );
  }

  Widget _getPage(int page) {
    switch (page) {
      case 0:
        return _buildHomePage();
      case 1:
        return _buildPlantsPage();
      case 2:
        return _buildLivePricePage();
      default:
        return _buildHomePage();
    }
  }

  Widget _buildLivePricePage() {
    return const LivePrice();
  }

  Widget _buildPlantsPage() {
    // Import the PlantsPage from plant_identification_page.dart
    return const PlantsPage();
  }

  Widget _buildHomePage() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          // Weather section
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF43A047), Color(0xFF66BB6A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : _errorMessage.isNotEmpty
                    ? Center(
                        child: Text(
                          _errorMessage,
                          style: const TextStyle(color: Colors.white),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _weatherData?['location']?['name'] ??
                                        'Unknown Location',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _currentDate,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                child: const Icon(
                                  Icons.wb_sunny,
                                  size: 40,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 25),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_weatherData?['data']?['values']?['temperature'] ?? 'N/A'}°C',
                                style: const TextStyle(
                                  fontSize: 42,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.water_drop,
                                          color: Colors.white70, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Humidity: ${_weatherData?['data']?['values']?['humidity'] ?? 'N/A'}%',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.air,
                                          color: Colors.white70, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Wind: ${_weatherData?['data']?['values']?['windSpeed'] ?? 'N/A'} km/h',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),
                          Center(
                            child: TextButton.icon(
                              onPressed: _loadWeatherData,
                              icon: const Icon(
                                Icons.refresh,
                                color: Colors.white,
                              ),
                              label: const Text(
                                'Refresh',
                                style: TextStyle(color: Colors.white),
                              ),
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.white24,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
          ),
          Divider(
            color: Colors.lightGreen.withOpacity(0.9),
            thickness: 2.0,
            indent: 100.0,
            endIndent: 100.0,
          ),
          // Features Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // const Text(
                //   'Plant Care Tools',
                //   style: TextStyle(
                //     fontSize: 20,
                //     fontWeight: FontWeight.bold,
                //     color: Colors.black87,
                //   ),
                // ),
                const SizedBox(height: 16),
                // Circular buttons for plant care tools
                Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildSquareButton(
                      title: 'Disease Detection',
                      icon: Icons.local_hospital_rounded,
                      color: Colors.redAccent,
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        Navigator.of(context).push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    DiseaseDetectionPage(),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
                              var curve = Curves.easeOutBack;
                              var curveTween = CurveTween(curve: curve);

                              var fadeAnimation = Tween<double>(
                                begin: 0.0,
                                end: 1.0,
                              ).animate(animation.drive(curveTween));

                              var scaleAnimation = Tween<double>(
                                begin: 0.5,
                                end: 1.0,
                              ).animate(animation.drive(curveTween));

                              return FadeTransition(
                                opacity: fadeAnimation,
                                child: ScaleTransition(
                                  scale: scaleAnimation,
                                  child: child,
                                ),
                              );
                            },
                            transitionDuration:
                                const Duration(milliseconds: 500),
                          ),
                        );
                      },
                    ),
                    _buildSquareButton(
                      title: 'Identify',
                      icon: Icons.eco,
                      color: Colors.green,
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        Navigator.of(context).push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    PlantIdentificationPage(),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
                              var curve = Curves.easeOutBack;
                              var curveTween = CurveTween(curve: curve);

                              var fadeAnimation = Tween<double>(
                                begin: 0.0,
                                end: 1.0,
                              ).animate(animation.drive(curveTween));

                              var scaleAnimation = Tween<double>(
                                begin: 0.5,
                                end: 1.0,
                              ).animate(animation.drive(curveTween));

                              return FadeTransition(
                                opacity: fadeAnimation,
                                child: ScaleTransition(
                                  scale: scaleAnimation,
                                  child: child,
                                ),
                              );
                            },
                            transitionDuration:
                                const Duration(milliseconds: 500),
                          ),
                        );
                      },
                    ),
                    _buildSquareButton(
                      title: 'Watering',
                      icon: Icons.water_drop,
                      color: Colors.blueAccent,
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        Navigator.of(context).push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    const WateringPage(),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
                              var curve = Curves.easeOutBack;
                              var curveTween = CurveTween(curve: curve);

                              var fadeAnimation = Tween<double>(
                                begin: 0.0,
                                end: 1.0,
                              ).animate(animation.drive(curveTween));

                              var scaleAnimation = Tween<double>(
                                begin: 0.5,
                                end: 1.0,
                              ).animate(animation.drive(curveTween));

                              return FadeTransition(
                                opacity: fadeAnimation,
                                child: ScaleTransition(
                                  scale: scaleAnimation,
                                  child: child,
                                ),
                              );
                            },
                            transitionDuration:
                                const Duration(milliseconds: 500),
                          ),
                        );
                      },
                    ),
                    _buildSquareButton(
                      title: 'Yield Sim',
                      icon: Icons.show_chart_rounded,
                      color: Colors.deepPurple,
                      onTap: () => _navigateTo(
                          context, const MonteCarloSimulationPage()),
                    ),
                    
                  ],
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
          Divider(
            color: Colors.lightGreen.withOpacity(0.9),
            thickness: 2.0,
            indent: 100.0,
            endIndent: 100.0,
          ),
        ],
      ),
    );
  }

  Widget _buildGridCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 36),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateTo(BuildContext context, Widget page) {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          var curve = Curves.easeOutBack;
          var curveTween = CurveTween(curve: curve);

          var fadeAnimation = Tween<double>(
            begin: 0.0,
            end: 1.0,
          ).animate(animation.drive(curveTween));

          var scaleAnimation = Tween<double>(
            begin: 0.5,
            end: 1.0,
          ).animate(animation.drive(curveTween));

          return FadeTransition(
            opacity: fadeAnimation,
            child: ScaleTransition(
              scale: scaleAnimation,
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  void _showChatbotDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final TextEditingController messageController = TextEditingController();
        final GroqService groqService = GroqService();
        // Use a ValueNotifier/stream or setstate inside StatefulBuilder
        // We'll use a local state list for simplicity within the builder
        List<Map<String, String>> messages = [
          {
            'sender': 'bot',
            'text': 'Hello! I am ecoyield. Ask me anything about your plants!'
          }
        ];
        bool isLoading = false;
        final ScrollController scrollController = ScrollController();

        return StatefulBuilder(
          builder: (context, setState) {
            void scrollToBottom() {
              if (scrollController.hasClients) {
                scrollController.animateTo(
                  scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            }

            Future<void> sendMessage() async {
              if (messageController.text.trim().isEmpty) return;

              final userMessage = messageController.text.trim();
              setState(() {
                messages.add({'sender': 'user', 'text': userMessage});
                isLoading = true;
                messageController.clear();
              });

              // Scroll to bottom after user message
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => scrollToBottom());

              final response = await groqService.sendMessage(userMessage);

              if (context.mounted) {
                setState(() {
                  isLoading = false;
                  messages.add({'sender': 'bot', 'text': response ?? 'Error'});
                });
                // Scroll to bottom after bot response
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => scrollToBottom());
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              contentPadding: EdgeInsets.zero,
              content: Container(
                width: double.maxFinite,
                height: 500,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white,
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.smart_toy, color: Colors.white),
                          const SizedBox(width: 8),
                          const Text(
                            'ecoyield Assistant',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),

                    // Chat Area
                    Expanded(
                      child: Container(
                        color: Colors.grey[50],
                        child: ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final message = messages[index];
                            final isUser = message['sender'] == 'user';
                            return Align(
                              alignment: isUser
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.7,
                                ),
                                decoration: BoxDecoration(
                                  color: isUser ? Colors.green : Colors.white,
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft:
                                        Radius.circular(isUser ? 16 : 0),
                                    bottomRight:
                                        Radius.circular(isUser ? 0 : 16),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 5,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  message['text'] ?? '',
                                  style: TextStyle(
                                    color:
                                        isUser ? Colors.white : Colors.black87,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    if (isLoading)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        color: Colors.grey[50],
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Thinking...',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Input Area
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          top: BorderSide(color: Colors.grey[200]!),
                        ),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(20),
                          bottomRight: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: messageController,
                              decoration: InputDecoration(
                                hintText: 'Ask about crops...',
                                filled: true,
                                fillColor: Colors.grey[100],
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                              ),
                              onSubmitted: (_) => sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          CircleAvatar(
                            backgroundColor: Colors.green,
                            child: IconButton(
                              icon: const Icon(Icons.send,
                                  color: Colors.white, size: 20),
                              onPressed: sendMessage,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
