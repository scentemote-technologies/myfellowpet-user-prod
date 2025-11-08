import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Needed for Factory
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Initializes the Android map renderer to the latest renderer (if applicable).
Future<AndroidMapRenderer?> initializeMapRenderer() async {
  final Completer<AndroidMapRenderer?> completer =
  Completer<AndroidMapRenderer?>();
  final GoogleMapsFlutterPlatform mapsImplementation =
      GoogleMapsFlutterPlatform.instance;
  if (mapsImplementation is GoogleMapsFlutterAndroid) {
    await mapsImplementation
        .initializeWithRenderer(AndroidMapRenderer.latest)
        .then((AndroidMapRenderer renderer) {
      completer.complete(renderer);
    });
  } else {
    completer.complete(null);
  }
  return completer.future;
}

/// Updates the current user's locations map by:
/// - Setting all existing locations' current_location to false.
/// - Adding the new location with current_location set to true.
Future<void> updateUserLocations(Map<String, dynamic> newLocationData) async {
  // Get the current user's UID.
  final String userId = FirebaseAuth.instance.currentUser!.uid;
  final DocumentReference userDocRef =
  FirebaseFirestore.instance.collection('users').doc(userId);

  // Fetch the current user document.
  final docSnapshot = await userDocRef.get();

  // If the document exists and has a 'locations' field, get it.
  Map<String, dynamic> locations = {};
  if (docSnapshot.exists && docSnapshot.data() != null) {
    final data = docSnapshot.data() as Map<String, dynamic>;
    if (data.containsKey('locations')) {
      locations = Map<String, dynamic>.from(data['locations']);
    }
  }

  // Prepare an update map.
  // First, set current_location to false for all existing locations.
  final Map<String, dynamic> updates = {};
  for (final key in locations.keys) {
    updates['locations.$key.current_location'] = false;
  }

  // Generate a new location key.
  final newLocationKey = 'location_${locations.length + 1}';

  // Add the new location to the updates map.
  updates['locations.$newLocationKey'] = newLocationData;

  // Update the Firestore document.
  await userDocRef.update(updates);
}

/// This page shows a Google Map with a fixed center pin.
/// The map’s center represents the location selected by the user.
/// Below the map, a form lets the user enter additional details (tag, area, city, state).
/// When "Save Location" is tapped, the new location is saved in Firestore.
class AddLocationPage extends StatefulWidget {
  const AddLocationPage({Key? key}) : super(key: key);
  @override
  _AddLocationPageState createState() => _AddLocationPageState();
}

class _AddLocationPageState extends State<AddLocationPage> {
  // The selected latitude and longitude; will be set after fetching location.
  LatLng? _selectedLatLng;
  GoogleMapController? _mapController;

  // Predefined location tag values.
  final List<String> _predefinedTags = ["Home", "Work", "College", "School"];
  String? _selectedPredefinedTag;

  // Controllers for form fields.
  final TextEditingController _tagController = TextEditingController();
  final TextEditingController _areaController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  // Colors for the UI.
  final Color _primaryColor = const Color(0xFF6C5CE7);
  final Color _secondaryColor = const Color(0xFFA8A5E6);
  final Color _accentColor = const Color(0xFF00C2CB);

  // Store the location future so it's not re-created every build.
  late final Future<LatLng> _locationFuture;

  @override
  void initState() {
    super.initState();
    _locationFuture = _fetchLocation();
  }

  /// Fetches the device’s current location and prints it to the terminal.
  Future<LatLng> _fetchLocation() async {
    print("Requesting location permissions...");
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print("Location services are disabled.");
      throw Exception("Location services are disabled");
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      print("Requesting location permission...");
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        print("Location permissions are denied.");
        throw Exception("Location permissions are required");
      }
    }

    print("Fetching current position...");
    Position position = await Geolocator.getCurrentPosition();
    print("Fetched position: Latitude: ${position.latitude}, Longitude: ${position.longitude}");
    return LatLng(position.latitude, position.longitude);
  }

  /// Updates the selected coordinates as the camera moves.
  void _onCameraMove(CameraPosition position) {
    setState(() {
      _selectedLatLng = position.target;
    });
    print("Camera moved to: Latitude: ${position.target.latitude}, Longitude: ${position.target.longitude}");
  }

  /// Called when the user taps "Save Location".
  void _onSave() async {
    if (_formKey.currentState!.validate() && _selectedLatLng != null) {
      final tag = _tagController.text.trim();

      final newLocationData = {
        'tag': tag,
        'street': _areaController.text.trim(),
        'city': _cityController.text.trim(),
        'state': _stateController.text.trim(),
        'user_location': GeoPoint(
          _selectedLatLng!.latitude,
          _selectedLatLng!.longitude,
        ),
        'current_location': true,
      };

      print("Saving new location data: $newLocationData");

      await updateUserLocations(newLocationData);
      if (mounted) Navigator.pop(context, newLocationData);
    }
  }

  @override
  void dispose() {
    _tagController.dispose();
    _areaController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LatLng>(
      future: _locationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text("Error: ${snapshot.error}")),
          );
        }
        if (snapshot.hasData) {
          _selectedLatLng ??= snapshot.data;
          return _buildMainScaffold();
        }
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  Widget _buildMainScaffold() {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Add New Location",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_primaryColor, _secondaryColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      // Wrap the entire content in a SingleChildScrollView.
      // The map is in a fixed-size container with its own gesture recognizers,
      // so it will capture pinch/zoom and pan gestures without the parent scrolling.
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Map Container
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    height: 300,
                    child: Stack(
                      children: [
                        GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: _selectedLatLng!,
                            zoom: 14,
                          ),
                          onMapCreated: (controller) {
                            _mapController = controller;
                            controller.animateCamera(
                              CameraUpdate.newLatLng(_selectedLatLng!),
                            );
                            print("Map created. Camera set to: Latitude: ${_selectedLatLng!.latitude}, Longitude: ${_selectedLatLng!.longitude}");
                          },
                          onCameraMove: _onCameraMove,
                          myLocationEnabled: true,
                          myLocationButtonEnabled: true,
                          mapType: MapType.normal,
                          // Adding gesture recognizers so the map captures pinch and pan gestures.
                          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                            Factory<OneSequenceGestureRecognizer>(
                                  () => EagerGestureRecognizer(),
                            ),
                          },
                        ),
                        // Fixed center pin
                        Center(
                          child: TweenAnimationBuilder(
                            tween: Tween(begin: 1.0, end: 1.2),
                            duration: const Duration(milliseconds: 800),
                            builder: (context, value, child) => Transform.scale(
                              scale: value,
                              child: const Icon(
                                Icons.location_pin,
                                size: 50,
                                color: Color(0xFF00C2CB),
                                shadows: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Form Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "TAG YOUR SPOT",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 50,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _predefinedTags.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(_predefinedTags[index]),
                            selected: _selectedPredefinedTag == _predefinedTags[index],
                            labelStyle: TextStyle(
                              color: _selectedPredefinedTag == _predefinedTags[index] ? Colors.white : _primaryColor,
                            ),
                            selectedColor: _primaryColor,
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: _primaryColor),
                            ),
                            onSelected: (selected) => setState(() {
                              _selectedPredefinedTag = selected ? _predefinedTags[index] : null;
                              _tagController.text = selected ? _predefinedTags[index] : '';
                            }),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildModernTextField(controller: _tagController, label: "Custom Tag", icon: Icons.tag_rounded),
                    const SizedBox(height: 16),
                    _buildModernTextField(controller: _areaController, label: "Area", icon: Icons.location_city_rounded),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _buildModernTextField(controller: _cityController, label: "City", icon: Icons.landscape_rounded)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildModernTextField(controller: _stateController, label: "State", icon: Icons.map_rounded)),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Center(
                      child: Material(
                        elevation: 6,
                        borderRadius: BorderRadius.circular(15),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                            gradient: LinearGradient(
                              colors: [_primaryColor, _accentColor],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                          ),
                          child: ElevatedButton(
                            onPressed: _onSave,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.save_rounded, color: Colors.white),
                                SizedBox(width: 12),
                                Text(
                                  "SAVE LOCATION",
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a modern styled text field.
  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextFormField(
      controller: controller,
      style: TextStyle(color: Colors.grey.shade800),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade600),
        prefixIcon: Icon(icon, color: _primaryColor),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _primaryColor, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        floatingLabelBehavior: FloatingLabelBehavior.never,
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return "Please enter $label";
        }
        return null;
      },
    );
  }
}
