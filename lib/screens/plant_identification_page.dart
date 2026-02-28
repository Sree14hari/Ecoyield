import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

// Plant model to store identified plants
class Plant {
  final String name;
  final File? image;
  final String referenceImage;
  final double confidence;
  final DateTime dateAdded;
  final String? imagePath; // Add this to store the path to the saved image

  Plant({
    required this.name,
    this.image,
    required this.referenceImage,
    required this.confidence,
    required this.dateAdded,
    this.imagePath,
  });

  // Convert Plant to JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'referenceImage': referenceImage,
      'confidence': confidence,
      'dateAdded': dateAdded.toIso8601String(),
      'imagePath': imagePath,
    };
  }

  // Create Plant from JSON
  factory Plant.fromJson(Map<String, dynamic> json) {
    return Plant(
      name: json['name'],
      referenceImage: json['referenceImage'],
      confidence: json['confidence'],
      dateAdded: DateTime.parse(json['dateAdded']),
      imagePath: json['imagePath'],
      image: json['imagePath'] != null ? File(json['imagePath']) : null,
    );
  }
}

// Singleton class to manage plant collection
class PlantCollection {
  static final PlantCollection _instance = PlantCollection._internal();
  static PlantCollection get instance => _instance;

  PlantCollection._internal() {
    // Load saved plants when instance is created
    _loadPlants();
  }

  final List<Plant> _plants = [];

  List<Plant> get plants => _plants;

  // Add a plant and save to persistent storage
  Future<void> addPlant(Plant plant) async {
    // If the plant has an image, save it to app documents directory
    Plant plantToSave = plant;
    if (plant.image != null) {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = '${directory.path}/$fileName';

      // Copy the image to the app's documents directory
      await plant.image!.copy(path);

      // Create a new plant with the saved image path
      plantToSave = Plant(
        name: plant.name,
        referenceImage: plant.referenceImage,
        confidence: plant.confidence,
        dateAdded: plant.dateAdded,
        imagePath: path,
      );
    }

    _plants.add(plantToSave);
    await _savePlants();
  }

  // Save plants to SharedPreferences
  Future<void> _savePlants() async {
    final prefs = await SharedPreferences.getInstance();
    final plantsJson = _plants.map((plant) => plant.toJson()).toList();
    await prefs.setString('plants', jsonEncode(plantsJson));
  }

  // Load plants from SharedPreferences
  Future<void> _loadPlants() async {
    final prefs = await SharedPreferences.getInstance();
    final plantsString = prefs.getString('plants');

    if (plantsString != null) {
      final plantsJson = jsonDecode(plantsString) as List;
      _plants.clear();
      _plants.addAll(plantsJson.map((json) => Plant.fromJson(json)).toList());
    }
  }
}

class PlantIdentificationPage extends StatefulWidget {
  const PlantIdentificationPage({Key? key}) : super(key: key);

  @override
  _PlantIdentificationPageState createState() =>
      _PlantIdentificationPageState();
}

class _PlantIdentificationPageState extends State<PlantIdentificationPage>
    with SingleTickerProviderStateMixin {
  File? _image;
  bool _isLoading = false;
  Map<String, dynamic>? _identificationResult;
  late AnimationController _animationController;
  late Animation<double> _animation;

  final ImagePicker _picker = ImagePicker();

  // Kindwise API credentials
  final String _apiUrl =
      "https://plant.id/api/v3/identification"; // Correct endpoint for identification
  final String _apiKey =
      "TLgi10Mq2GVRn1kmGBcta3KhjcaDRRyHfSwoO9EP4aWvTqjr4c"; // Your Kindwise API key

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _getImage(ImageSource source) async {
    // Trigger light haptic feedback when selecting image source
    HapticFeedback.lightImpact();

    final XFile? pickedFile = await _picker.pickImage(
      source: source,
      imageQuality: 90,
    );

    if (pickedFile != null) {
      // Trigger medium haptic feedback when image is selected
      HapticFeedback.mediumImpact();

      setState(() {
        _image = File(pickedFile.path);
        _identificationResult = null;
      });
    }
  }

  Future<void> _identifyPlant() async {
    if (_image == null) {
      // Trigger error haptic feedback
      HapticFeedback.vibrate();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image first')),
      );
      return;
    }

    // Trigger heavy haptic feedback when starting identification
    HapticFeedback.heavyImpact();

    setState(() {
      _isLoading = true;
    });

    try {
      // Get image bytes and encode as Base64
      final imageBytes = await _image!.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      // Create JSON payload
      final payload = jsonEncode({
        "images": [base64Image],
        "similar_images": true,
        // Add other optional attributes here
      });

      // Send request
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Api-Key': _apiKey,
        },
        body: payload,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonResponse = jsonDecode(response.body);
        setState(() {
          _identificationResult = jsonResponse;
          _isLoading = false;
        });
        print('Response: ${response.body}');
        // Show results in popup dialog
        _showResultsDialog();
      } else {
        throw Exception(
            'Server error: ${response.statusCode} - ${response.reasonPhrase}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
      print('Error details: $e');
    }
  }

  // Add this method to show the results dialog
  void _showResultsDialog() {
    // Trigger success haptic feedback when showing results
    HapticFeedback.mediumImpact();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Colors.white,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Identification Results',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 20),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.4,
                  ),
                  child: SingleChildScrollView(
                    child: _buildResultsContent(),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: const Text(
                        'Close',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        // Add haptic feedback
                        HapticFeedback.mediumImpact();

                        // Get the top suggestion
                        final suggestions = _identificationResult?['result']
                            ['classification']['suggestions'] as List<dynamic>?;

                        if (suggestions != null && suggestions.isNotEmpty) {
                          final topSuggestion = suggestions.first;
                          final name = topSuggestion['name'] ?? 'Unknown Plant';
                          final probability =
                              topSuggestion['probability'] ?? 0.0;
                          final similarImages = topSuggestion['similar_images']
                                  as List<dynamic>? ??
                              [];
                          String imageUrl = '';

                          if (similarImages.isNotEmpty) {
                            imageUrl = similarImages.first['url_small'] ?? '';
                          }

                          // Add the plant to the collection
                          final plant = Plant(
                            name: name,
                            image: _image,
                            referenceImage: imageUrl,
                            confidence: probability,
                            dateAdded: DateTime.now(),
                          );

                          // Add to plant collection
                          PlantCollection.instance.addPlant(plant);

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Plant saved to your collection'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not save plant information'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }

                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add to My Plants'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helper method to build the content of the results dialog
  Widget _buildResultsContent() {
    final suggestions = _identificationResult?['result']['classification']
        ['suggestions'] as List<dynamic>?;

    if (suggestions == null || suggestions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          'No plants identified. Try with a clearer image.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: suggestions
          .map((suggestion) => _buildSuggestionItem(suggestion))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Weed Identification'),
        backgroundColor: const Color.fromARGB(255, 255, 255, 255),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
      ),
      body: FadeTransition(
        opacity: _animation,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header with gradient background
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green.shade50, Colors.green.shade100],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Weed Identification',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Take or select a photo of a plant to identify it',
                        style: TextStyle(fontSize: 16, color: Colors.green),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Image preview with improved styling
                Container(
                  height: 300,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: _image == null
                      ? Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.green.withOpacity(0.05),
                                Colors.green.withOpacity(0.15),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate,
                                  size: 80,
                                  color: Colors.green,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'No image selected',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Tap the buttons below to add a photo',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(
                            _image!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 300,
                          ),
                        ),
                ),

                const SizedBox(height: 24),

                // Image selection buttons with improved styling
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildActionButton(
                      icon: Icons.camera_alt,
                      label: 'Take Photo',
                      color: Colors.blue,
                      onTap: () => _getImage(ImageSource.camera),
                    ),
                    _buildActionButton(
                      icon: Icons.photo_library,
                      label: 'Gallery',
                      color: Colors.purple,
                      onTap: () => _getImage(ImageSource.gallery),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Identify button with gradient and animation
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isLoading || _image == null
                          ? [Colors.grey, Colors.grey.shade400]
                          : [Colors.green.shade600, Colors.green.shade400],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: _isLoading || _image == null
                        ? []
                        : [
                            BoxShadow(
                              color: Colors.green.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap:
                          _isLoading || _image == null ? null : _identifyPlant,
                      borderRadius: BorderRadius.circular(28),
                      child: Center(
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              )
                            : const Text(
                                'Identify Plant',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                // Remove the results section from here since we're showing it in a popup
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionItem(dynamic suggestion) {
    final name = suggestion['name'] ?? 'Unknown';
    final probability = suggestion['probability'] ?? 0.0;
    final similarImages = suggestion['similar_images'] as List<dynamic>? ?? [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Probability: ${(probability * 100).toStringAsFixed(2)}%',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          if (similarImages.isNotEmpty)
            Wrap(
              spacing: 8.0,
              runSpacing: 4.0,
              children: similarImages.map((image) {
                return Image.network(
                  image['url_small'],
                  width: 50,
                  height: 50,
                );
              }).toList(),
            ),
          const Divider(),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: () {
            // Trigger light haptic feedback when tapping action button
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
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
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
