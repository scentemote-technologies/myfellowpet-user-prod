// lib/screens/Boarding/boarding_servicedetailspage.dart
// ✨ FULLY OPTIMIZED CODE ✨

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_colors.dart';
import '../../main.dart';
import '../../preloaders/PetsInfoProvider.dart';
import '../../preloaders/distance_provider.dart';
import '../../preloaders/favorites_provider.dart';
import '../../preloaders/hidden_services_provider.dart';
import 'boarding_homepage.dart';
import 'boarding_parameters_selection_page.dart';


// Helper function for robust list conversion
List<String> _convertFirestoreDataToList(dynamic data) {
  if (data == null) return [];
  if (data is List) return data.map((e) => e.toString()).toList();
  if (data is String) return data.isNotEmpty ? [data] : [];
  if (data is Map) return data.keys.map((e) => e.toString()).toList();
  return [];
}

Future<List<PetPricing>> _fetchPetPricing(String serviceId) async {
  final snapshot = await FirebaseFirestore.instance
      .collection('users-sp-boarding')
      .doc(serviceId)
      .collection('pet_information')
      .get();
  if (snapshot.docs.isEmpty) {
    return [];
  }
  return snapshot.docs.map((doc) {
    final data = doc.data();
    return PetPricing(
      petName: doc.id,
      ratesDaily: Map<String, String>.from(data['rates_daily'] ?? {}),
      walkingRatesDaily: Map<String, String>.from(data['walking_rates'] ?? {}),
      mealRatesDaily: Map<String, String>.from(data['meal_rates'] ?? {}),
      offerRatesDaily: Map<String, String>.from(data['offer_daily_rates'] ?? {}),
      offerWalkingRatesDaily:
      Map<String, String>.from(data['offer_walking_rates'] ?? {}),
      offerMealRatesDaily:
      Map<String, String>.from(data['offer_meal_rates'] ?? {}),
      feedingDetails: Map<String, dynamic>.from(data['feeding_details'] ?? {}),
      acceptedSizes: _convertFirestoreDataToList(data['accepted_sizes']),
      acceptedBreeds: _convertFirestoreDataToList(data['accepted_breeds']),
    );
  }).toList();
}

// ✨ MOVED fetchRatingStats to be a top-level function so _loadData can use it
Future<Map<String, dynamic>> fetchRatingStats(String serviceId) async {
  final coll = FirebaseFirestore.instance
      .collection('public_review')
      .doc('service_providers')
      .collection('sps')
      .doc(serviceId)
      .collection('reviews');

  final snap = await coll.get();
  final ratings = snap.docs
      .map((d) => (d.data()['rating'] as num?)?.toDouble() ?? 0.0)
      .where((r) => r > 0)
      .toList();

  final count = ratings.length;
  final avg = count > 0 ? ratings.reduce((a, b) => a + b) / count : 0.0;

  return {
    'avg': avg.clamp(0.0, 5.0),
    'count': count,
  };
}

class BoardingServiceDetailPage extends StatefulWidget {
  final String documentId;
  final String shopName;
  final String mode;
  final double distanceKm;
  final List<String> pets;
  final List<String> otherBranches;

  final Map<String, int> rates;
  final String shopImage;
  final String areaName;
  final bool isOfferActive;
  final bool isCertified;
  final String? initialSelectedPet;
  final Map<String, dynamic> preCalculatedStandardPrices;
  final Map<String, dynamic> preCalculatedOfferPrices;


  const BoardingServiceDetailPage({
    Key? key,
    required this.documentId,
    required this.shopName,
    required this.shopImage,
    required this.areaName,
    required this.distanceKm,
    required this.pets,
    required this.mode,
    required this.rates,
    required this.isOfferActive, this.initialSelectedPet, required this.preCalculatedStandardPrices, required this.preCalculatedOfferPrices, required this.otherBranches, required this.isCertified,
  }) : super(key: key);

  @override
  State<BoardingServiceDetailPage> createState() =>
      _BoardingServiceDetailPageState();
}

class _BoardingServiceDetailPageState extends State<BoardingServiceDetailPage>
    with SingleTickerProviderStateMixin {
  GeoPoint _location = const GeoPoint(0.0, 0.0);

  String _companyName = '';
  String _description = '';
  bool _showShareButton = false;

  bool _warningShown = false;
  String _serviceId = '';

  String _spId = '';
  bool _adminApproved = false;
  String _shopName = '';
  String _street = '';
  String _areaName = '';
  String _state = '';
  String _district = '';
  String _postalCode = '';
  String _walkingFee = '0';
  String _currentCountOfPet = '';
  String _maxPetsAllowed = '';
  String _maxPetsAllowedPerHour = '';
  String _closeTime = '';
  String _openTime = '';
  bool isLiked = false;
  List<String> _acceptedSizes = [];
  List<String> _acceptedBreeds = [];
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Set<String> likedServiceIds = {};
  Set<String> _hiddenServiceIds = {};
  final DesignConstants _design = DesignConstants();
  String _fullAddress = '';
  Map<String, int> _refundPolicy = {};
  List<String> _features = [];
  Map<String, String> _ratesDaily = {};
  Map<String, String> _walkingRates = {};
  Map<String, String> _mealRates = {};
  Map<String, String> _offerDailyRates = {};
  Map<String, String> _offerWalkingRates = {};
  Map<String, String> _offerMealRates = {};
  List<String> _petDocIds = [];
  String? _selectedPet;

  late Future<Map<String, dynamic>> _dataFuture;

  Widget _partnerPolicyButton(BuildContext context, String? policyUrl) {
    // 1. Check if URL exists immediately
    if (policyUrl == null || policyUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    final width = MediaQuery.of(context).size.width;

    // Responsive size scaling
    final double vPad = width * 0.025;
    final double fontSize = width * 0.035;
    final double radius = width * 0.03;

    // 2. Return the button directly (Left Aligned)
    return Padding(
      // Matches the 12px padding used in the rest of your UI
      padding: const EdgeInsets.only(bottom: 20.0, top: 10, left: 12, right: 12),
      child: Align(
        alignment: Alignment.centerLeft, // 👈 ALIGN LEFT
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            side: const BorderSide(color: Colors.red, width: 1.2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
            ),
            padding: EdgeInsets.symmetric(vertical: vPad, horizontal: 24),
          ),
          onPressed: () => _launchURL(policyUrl),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.picture_as_pdf_rounded,
                color: Colors.red,
                size: fontSize + 4,
              ),
              const SizedBox(width: 8),
              Text(
                "View Partner Policy",
                style: GoogleFonts.poppins(
                  color: Colors.black87,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchURL(String urlString) async {
    final String encodedUrl = Uri.encodeComponent(urlString);
    final String googleDocsUrl = 'https://docs.google.com/gview?url=$encodedUrl&embedded=true';
    if (!await launchUrl(Uri.parse(googleDocsUrl), mode: LaunchMode.platformDefault)) {
      // handle error
    }
  }


  Widget _buildFeedingInfo(Map<String, dynamic> feedingDetails) {
    if (feedingDetails.isEmpty) {
      return Center(
        child: Text("No feeding information provided.", style: GoogleFonts.poppins(color: Colors.grey.shade600)),
      );
    }
    const desiredOrder = ['Morning Meal (Breakfast)', 'Afternoon Meal (Lunch)', 'Evening Meal (Dinner)', 'Treats', 'Water Availability'];
    final mealEntries = feedingDetails.entries.toList()
      ..sort((a, b) {
        final aIndex = desiredOrder.indexWhere((name) => name.toLowerCase() == a.key.toLowerCase());
        final bIndex = desiredOrder.indexWhere((name) => name.toLowerCase() == b.key.toLowerCase());
        return (aIndex == -1 ? desiredOrder.length : aIndex).compareTo(bIndex == -1 ? desiredOrder.length : bIndex);
      });

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4),
      itemCount: mealEntries.length,
      itemBuilder: (context, index) {
        final entry = mealEntries[index];
        final mealData = entry.value as Map<String, dynamic>? ?? {};
        return _SimpleMealCard(
          mealTitle: entry.key,
          mealData: mealData,
          onDetailsPressed: _showMealDetailsDialog,
        );
      },
    );
  }

  void _showMealDetailsDialog(BuildContext context, String mealTitle, Map<String, dynamic> mealData) {
    final details = <Widget>[];
    String getLabel(String fieldName) => fieldName == 'food_title' ? 'Meal Name' : fieldName.replaceAll('_', ' ').capitalize();

    for (var entry in mealData.entries) {
      if (entry.key == 'image') continue;
      final value = entry.value;
      final isValueMissing = value == null || (value is String && value.isEmpty) || (value is List && value.isEmpty);
      details.add(Padding(
        padding: const EdgeInsets.only(top: 10.0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, color: Colors.grey.shade600, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.poppins(color: Colors.black87, fontSize: 13),
                children: [
                  TextSpan(text: "${getLabel(entry.key)}: ", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                  TextSpan(
                    text: isValueMissing ? "N/A" : (value is List ? value.join(', ') : value.toString()),
                    style: GoogleFonts.poppins(
                        color: isValueMissing ? Colors.grey.shade500 : Colors.grey.shade800,
                        fontStyle: isValueMissing ? FontStyle.italic : FontStyle.normal),
                  ),
                ],
              ),
            ),
          ),
        ]),
      ));
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(mealTitle.capitalize(), style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (mealData['image'] != null && (mealData['image'] as String).isNotEmpty)
              ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: mealData['image'], width: double.infinity, height: 180, fit: BoxFit.cover,
                    placeholder: (context, url) => Container(height: 180, color: Colors.grey.shade200),
                    errorWidget: (context, url, error) => Container(height: 180, color: Colors.grey.shade200, child: Icon(Icons.error)),
                  )
              ),
            if (mealData['image'] != null && (mealData['image'] as String).isNotEmpty) const SizedBox(height: 12),
            ...details.isNotEmpty ? details : [Text("No details to show.", style: GoogleFonts.poppins(color: Colors.grey.shade600))]
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("Close", style: GoogleFonts.poppins(color: Colors.black87))),
        ],
      ),
    );
  }

  void _showFeaturesDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35), // Smooth dim
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // 🏷️ Title
              Row(
                children: [
                  Text(
                    "Features",
                    style: GoogleFonts.poppins(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // 📌 Content
              _features.isEmpty
                  ? Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  "No specific features listed.",
                  style: GoogleFonts.poppins(
                    fontSize: 14.5,
                    color: Colors.grey.shade600,
                  ),
                ),
              )
                  : Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: _features.map((feature) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 8),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_circle_rounded,
                                color: Colors.green.shade600, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                feature,
                                style: GoogleFonts.poppins(
                                  fontSize: 14.5,
                                  color: Colors.black87,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // 🔘 Close Button
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.black87,
                    padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  child: Text(
                    "Close",
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }


  void _showRefundInfoDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35), // soft dim
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Header
              Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: AppColors.primaryColor, size: 26),
                  const SizedBox(width: 10),
                  Text(
                    "Refund Policy",
                    style: GoogleFonts.poppins(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),

              Padding(
                padding: const EdgeInsets.only(top:7,bottom: 5),
                child: Text(
                  "If cancelled:",
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),


              const SizedBox(height: 2),

              // CONTENT AREA
              RefundPolicyChips(
                refundRates: _refundPolicy,
                design: _design,
              ),

              const SizedBox(height: 12),

              // Close button
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.black87,
                    padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  child: Text(
                    "Close",
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  // --- END DIALOG LOGIC ---

  Future<void> _fetchPetDetails(String petId) async {
    if (petId.isEmpty) return;
    try {
      final petSnap = await FirebaseFirestore.instance
          .collection('users-sp-boarding')
          .doc(widget.documentId)
          .collection('pet_information')
          .doc(petId)
          .get();

      if (petSnap.exists) {
        final data = petSnap.data() as Map<String, dynamic>;
        setState(() {
          _acceptedSizes = _convertFirestoreDataToList(data['accepted_sizes']);
          _acceptedBreeds = _convertFirestoreDataToList(data['accepted_breeds']);
        });
      }
    } catch (e) {
      print("Error fetching pet details for $petId: $e");
      setState(() {
        _acceptedSizes = [];
        _acceptedBreeds = [];
      });
    }
  }

  Future<void> toggleLike(String serviceId) async {
    User? user = _auth.currentUser;
    if (user == null) {
      print('No user is logged in');
      return;
    }
    setState(() {
      if (likedServiceIds.contains(serviceId)) {
        likedServiceIds.remove(serviceId);
      } else {
        likedServiceIds.add(serviceId);
      }
    });

    final userPreferencesRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('user_preferences')
        .doc('boarding');
    final userPreferencesDoc = await userPreferencesRef.get();
    List<dynamic> likedServices = userPreferencesDoc.exists
        ? List.from(userPreferencesDoc.get('liked') ?? [])
        : [];
    if (likedServices.contains(serviceId)) {
      likedServices.remove(serviceId);
    } else {
      likedServices.add(serviceId);
    }
    if (userPreferencesDoc.exists) {
      await userPreferencesRef.update({'liked': likedServices});
    } else {
      await userPreferencesRef.set({'liked': [serviceId]});
    }
  }

  Future<void> checkIfLiked(String serviceId) async {
    User? user = _auth.currentUser;
    if (user == null) return;
    final userPreferencesRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('user_preferences')
        .doc('boarding');
    final userPreferencesDoc = await userPreferencesRef.get();
    if (userPreferencesDoc.exists) {
      List<dynamic> likedServices =
      List.from(userPreferencesDoc.get('liked') ?? []);
      setState(() {
        isLiked = likedServices.contains(serviceId);
        print('Service $serviceId liked status: $isLiked');
      });
    } else {
      print('User preferences document does not exist. Creating a new one...');
      await userPreferencesRef.set({'liked': [serviceId]});
      setState(() {
        isLiked = true;
      });
    }
  }

  List<String> _convertFirestoreDataToList(dynamic data) {
    if (data == null) {
      return [];
    }
    if (data is List) {
      return data.map((e) => e.toString()).toList();
    }
    if (data is String) {
      return data.isNotEmpty ? [data] : [];
    }
    if (data is Map) {
      return data.keys.map((e) => e.toString()).toList();
    }
    return [];
  }

  Future<void> _hideService(String serviceId) async {
    User? user = _auth.currentUser;
    if (user == null) return;
    final userPreferencesRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('user_preferences')
        .doc('boarding');
    final userPreferencesDoc = await userPreferencesRef.get();
    List<dynamic> hiddenServices = [];
    if (userPreferencesDoc.exists && userPreferencesDoc.data() != null) {
      final data = userPreferencesDoc.data() as Map<String, dynamic>;
      if (data.containsKey('hidden')) {
        hiddenServices = List.from(data['hidden']);
      }
    }
    if (!hiddenServices.contains(serviceId)) {
      hiddenServices.add(serviceId);
      await userPreferencesRef.set({'hidden': hiddenServices},
          SetOptions(merge: true));
    }
    setState(() {
      _hiddenServiceIds.add(serviceId);
    });
  }

  Future<Map<String, dynamic>> _loadData() async {
    final serviceFuture = FirebaseFirestore.instance
        .collection('users-sp-boarding')
        .doc(widget.documentId)
        .get();

    final petsFuture = _fetchPetPricing(widget.documentId);
    final ratingsFuture = fetchRatingStats(widget.documentId);

    final results = await Future.wait([
      serviceFuture,
      petsFuture,
      ratingsFuture,
    ]);

    return {
      'service': results[0] as DocumentSnapshot,
      'pets': results[1] as List<PetPricing>,
      'ratings': results[2] as Map<String, dynamic>,
    };
  }


  @override
  void initState() {
    super.initState();
    _loadShareButtonStatus();
    _dataFuture = _loadData();
    _fetchPetDocIds().then((_) {
      if (_selectedPet != null) {
        _fetchPetDetails(_selectedPet!);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowPetWarning(context);
    });
  }
  Future<void> _loadShareButtonStatus() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('status')
          .get();

      final data = doc.data() ?? {};
      final flag = data['show_share_boarding_andr'] ?? false;

      if (mounted) {
        setState(() {
          _showShareButton = flag;
        });
      }
    } catch (e) {
      debugPrint("Failed to load share setting: $e");
    }
  }


  void _checkAndShowPetWarning(BuildContext context) {
    if (_warningShown) return;
    _warningShown = true;

    final petProvider = context.read<PetProvider>();
    final userPets = petProvider.pets;

    print('DEBUG T2: Check Warning Running. Total User Pets: ${userPets.length}');

    final acceptedTypes = widget.pets.map((p) => p.toLowerCase()).toSet();
    print('DEBUG T2: Service accepts types: ${acceptedTypes.join(', ')}');

    if (userPets.isEmpty) return;

    final List<Map<String, String>> rejectedPets = [];

    for (final pet in userPets) {
      final petType = pet['pet_type']?.toString().toLowerCase() ?? 'type_missing';
      final petName = pet['name']?.toString() ?? 'Unknown Pet';

      if (!acceptedTypes.contains(petType)) {
        print('DEBUG T2: ❌ REJECTED PET FOUND: $petName (Type: $petType)');
        rejectedPets.add({
          'name': petName,
          'type': petType.capitalize(),
        });
      }
    }

    print('DEBUG T2: Rejected Pet Count: ${rejectedPets.length}. Dialog Should Show: ${rejectedPets.isNotEmpty}');

    if (rejectedPets.isNotEmpty) {
      _showPetWarningDialog(context, rejectedPets);
    }
  }


  void _showPetWarningDialog(BuildContext context, List<Map<String, String>> rejectedPets) {
    const Color brandPrimary = AppColors.primaryColor;
    const Color warningColor = Color(0xFFFF0000);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.black87)),
          titlePadding: EdgeInsets.zero,
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),

          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: brandPrimary.withOpacity(0.1),
                  ),
                  child: const Icon(
                    Icons.pets_outlined,
                    color: brandPrimary,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  "Booking Compatibility Check",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Heads up! Some of your saved pets may not be listed as accepted by this provider. Please confirm with them before finalizing your booking.",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Divider(color: Colors.grey.shade200, height: 1),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Pets Not Accepted:",
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150), // Slightly taller constraint
                  child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: rejectedPets.length,
                      itemBuilder: (context, index) {
                        final p = rejectedPets[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0), // Space between items
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: warningColor, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  p['name']!,
                                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black87,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: warningColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: warningColor.withOpacity(0.3), width: 1),
                                ),
                                child: Text(
                                  p['type']!,
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: warningColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                  ),
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brandPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16), // Slightly larger tap target
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 5, // A bit more elevation for a professional feel
                    ),
                    child: Text(
                      "Proceed to Booking",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _switchBranch(String newBranchId) async {
    if (newBranchId == widget.documentId) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users-sp-boarding')
          .doc(newBranchId)
          .get();

      if (doc.exists && mounted) {
        final data = doc.data() as Map<String, dynamic>;
        final distances = Provider.of<DistanceProvider>(context, listen: false).distances;
        final newDistance = distances[newBranchId] ?? 0.0;

        Navigator.pop(context); // Close loading dialog

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => BoardingServiceDetailPage(
              documentId: newBranchId,
              shopName: data['shop_name'] ?? 'N/A',
              shopImage: data['shop_logo'] ?? '',
              areaName: data['area_name'] ?? 'N/A',
              distanceKm: newDistance,
              pets: List<String>.from(data['pets'] ?? []),
              mode: widget.mode,
              rates: {},
              isOfferActive: data['isOfferActive'] ?? false,
              isCertified: data['mfp_certified'] ?? false,
              otherBranches: List<String>.from(data['other_branches'] ?? []),
              preCalculatedStandardPrices: Map<String, dynamic>.from(data['pre_calculated_standard_prices'] ?? {}),
              preCalculatedOfferPrices: Map<String, dynamic>.from(data['pre_calculated_offer_prices'] ?? {}),
              initialSelectedPet: _selectedPet,
            ),
          ),
        );
      } else {
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Could not load branch details."))
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      print("Error switching branch: $e");
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("An error occurred."))
      );
    }
  }

  void _showBookingConfirmationDialog(BuildContext context, String selectedPetType, VoidCallback onConfirm) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryColor.withOpacity(0.1),
                  ),
                  child: Icon(
                    Icons.pets_rounded,
                    color: AppColors.primaryColor,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Confirm Pet Type',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                    children: [
                      const TextSpan(text: 'You are now proceeding with your booking using the pet type: '),
                      TextSpan(
                        text: selectedPetType, // This holds the pet type (e.g., "Dog")
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryColor,
                        ),
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: Colors.grey.shade300, width: 2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          onConfirm(); // Execute the original navigation
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 3,
                        ),
                        child: Text(
                          'Proceed',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            fontSize: 16,
                          ),
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

  Future<void> _fetchPetDocIds() async {
    final serviceDocRef = FirebaseFirestore.instance.collection('users-sp-boarding').doc(widget.documentId);
    final petCollectionSnap = await serviceDocRef.collection('pet_information').get();

    final docIds = petCollectionSnap.docs.map((doc) => doc.id).toList();
    _petDocIds = docIds;
    _selectedPet = widget.initialSelectedPet ?? (docIds.isNotEmpty ? docIds.first : null);
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _showFeedingInfoDialog(
      BuildContext context,
      Map<String, Map<String, dynamic>> allFeedingDetails,
      String? initialSelectedPet,
      Function(String)? onPetSelected) {

    // Use initialSelectedPet for the *first build* if available, otherwise default to the first pet in the data.
    String selectedPetInDialog = initialSelectedPet ?? allFeedingDetails.keys.first;
    if (!allFeedingDetails.containsKey(selectedPetInDialog)) {
      selectedPetInDialog = allFeedingDetails.keys.first;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // The current pet's feeding details, based on the dialog's state
            final currentFeedingDetails = allFeedingDetails[selectedPetInDialog] ?? {};

            return AlertDialog(
              backgroundColor: Colors.white,   // ← PURE WHITE BG (important)
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.0),
              ),
              title: Row(
                children: [
                  Icon(Icons.restaurant_menu_outlined, color: AppColors.primaryColor.withOpacity(0.7)),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      "Feeding Information",
                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 19),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: MediaQuery.of(context).size.height * 0.6,
                child: Column(
                  children: [
                    // --- Pet Selection Dropdown (Only show if multiple pets exist) ---
                    if (allFeedingDetails.length > 1)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedPetInDialog, // Tracks the currently viewed pet
                            isExpanded: true,
                            items: allFeedingDetails.keys.map((petName) {
                              return DropdownMenuItem<String>(
                                value: petName,
                                child: Text(petName.capitalize(),
                                    style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                              );
                            }).toList(),
                            onChanged: (newValue) {
                              if (newValue != null) {
                                // Update the dialog's state to change the pet
                                setState(() {
                                  selectedPetInDialog = newValue;
                                });
                                // ✨ ADDED: Call the parent callback
                                onPetSelected?.call(newValue);
                              }
                            },
                          ),
                        ),
                      ),
                    // --- Dynamic Meal Cards for the Selected Pet ---
                    Expanded(
                      child: _buildFeedingInfo(currentFeedingDetails),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    "Close",
                    style: GoogleFonts.poppins(color: Colors.black87, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
              titlePadding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              insetPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 24.0),
            );
          },
        );
      },
    );
  }


  Widget _buildQuickAccessButtons(
      BuildContext context,
      Map<String, Map<String, dynamic>> allFeedingDetails,
      String? policyUrl
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Column(
        children: [
          // --- ROW 1: Feeding & Features ---
          Row(
            children: [
              _buildQuickAccessBox(
                "Feeding Info",
                Icons.restaurant_menu_rounded, // 🍽️ Cutlery
                AppColors.accentColor,
                    () => _showFeedingInfoDialog(context, allFeedingDetails, _selectedPet, (newPet) {
                  if (newPet.isNotEmpty) {
                    setState(() {
                      _selectedPet = newPet;
                    });
                  }
                }),
              ),
              const SizedBox(width: 8),
              _buildQuickAccessBox(
                "Features",
                Icons.check_circle_rounded, // ✅ Green Circle
                Colors.green.shade600,
                _showFeaturesDialog,
              ),
            ],
          ),

          const SizedBox(height: 8), // Gap between rows

          // --- ROW 2: Refund & Partner Policy ---
          Row(
            children: [
              _buildQuickAccessBox(
                "Refund Policy",
                Icons.percent_rounded, // % Percent
                Colors.black87,
                _showRefundInfoDialog,
              ),
              // Only show Partner Policy button if URL exists
              if (policyUrl != null && policyUrl.isNotEmpty) ...[
                const SizedBox(width: 8),
                _buildQuickAccessBox(
                  "Partner Policy",
                  Icons.picture_as_pdf_rounded, // 📕 Red PDF
                  Colors.red.shade600,
                      () => _launchURL(policyUrl),
                ),
              ]
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAccessBox(String title, IconData icon, Color iconColor, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 36, // ✨ Reduced height (was 40)
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black87, width: 1.0), // Thinner border
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: iconColor), // ✨ Icon added
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                      fontSize: 12.5, // Slightly smaller font
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMap(double lat, double lng) async {
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw 'Could not launch $url';
    }
  }

  void _openQuickActionsSheet(
      BuildContext context,
      Map<String, dynamic> ratingStats,
      ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Text(
                "Quick Actions",
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),

              const SizedBox(height: 22),

              // GRID
              GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.85,   // perfect balance
                  crossAxisSpacing: 18,
                  mainAxisSpacing: 20,
                ),
                children: [
                  _gridItem(
                    child: _buildLikeButtonForSheet(),
                    label: "Like",
                  ),
                  _gridItem(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(context); // close sheet
                        _showTotalReviews(context, ratingStats);
                      },
                      child: RatingBadge(ratingStats: ratingStats),
                    ),
                    label: "Rating",
                  ),

                  _gridItem(
                    child: _buildLocationButton(),
                    label: "Maps",
                  ),
                  _gridItem(
                    child: GestureDetector(
                      onTap: () {
                        if (widget.isCertified) {
                          _showDialogVB(context, 'mfp_certified_user_app');
                        } else {
                          _showDialogPV(context, 'profile_verified_user_app');
                        }
                      },
                      child: widget.isCertified
                          ? const VerifiedBadge(isCertified: true)
                          : const ProfileVerified(),
                    ),
                    label: "Certified",
                  ),

                  _gridItem(
                    child: Consumer<HiddenServicesProvider>(
                      builder: (context, hideProv, _) {
                        final isHidden = hideProv.hidden.contains(_serviceId);

                        return Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.hide_source,
                                color: Colors.red, size: 22),
                            onPressed: () {
                              Navigator.pop(context);
                              _showHideConfirmationDialog(
                                  context, _serviceId, isHidden, hideProv);
                            },
                          ),
                        );
                      },
                    ),
                    label: "Hide",
                  ),
                ],
              ),

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
  void _showTotalReviews(BuildContext context, Map<String, dynamic> stats) {
    final avg = (stats['avg'] ?? 0.0).toDouble().clamp(0.0, 5.0);
    final count = (stats['count'] ?? 0) as int;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.07),
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ⭐ HEADER
                Text(
                  "Ratings & Reviews",
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),

                const SizedBox(height: 18),

                // ⭐ BIG STAR + AVG
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star, size: 34, color: Color(0xFFFFC100)),
                    const SizedBox(width: 6),
                    Text(
                      avg.toStringAsFixed(1),
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // 🔢 Total Reviews
                Text(
                  "$count review${count == 1 ? '' : 's'}",
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 24),

                // OK BUTTON
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      "Close",
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.teal,
                      ),
                    ),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }


  Widget _gridItem({required Widget child, required String label}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 62,   // FIXED SIZE → perfect alignment
          width: 62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: Colors.black87, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: child, // auto centered
          ),
        ),

        const SizedBox(height: 6),

        Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }


  Widget _buildLikeButton() {
    return Consumer<FavoritesProvider>(
      builder: (ctx, favProv, _) {
        final liked = favProv.liked.contains(_serviceId);

        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 2,
                offset: const Offset(0, 1.5),
              ),
            ],
          ),
          child: IconButton(
            iconSize: 20,
            padding: EdgeInsets.zero,
            icon: Icon(
              liked ? Icons.favorite : Icons.favorite_border,
              color: liked ? Colors.red : Colors.grey,
            ),
            onPressed: () => favProv.toggle(_serviceId),
          ),
        );
      },
    );
  }

  Widget _buildLikeButtonForSheet() {
    return Consumer<FavoritesProvider>(
      builder: (ctx, favProv, _) {
        final liked = favProv.liked.contains(_serviceId);

        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,

          ),
          child: IconButton(
            iconSize: 32,
            padding: EdgeInsets.zero,
            icon: Icon(
              liked ? Icons.favorite : Icons.favorite_border,
              color: liked ? Colors.red : Colors.grey.shade500,
            ),
            onPressed: () => favProv.toggle(_serviceId),
          ),
        );
      },
    );
  }

  Widget _buildLocationButton() {
    return GestureDetector(
      onTap: () => _openMap(_location.latitude, _location.longitude),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,

        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Image.asset(
            "assets/google_maps_logo.png",
            height: 30,
            width: 30,
          ),
        ),
      ),
    );
  }
// --------------------------------------------------------------
// 🔗 SHARE FEATURE — Opens Native Android/IOS Share Sheet
// --------------------------------------------------------------
// This function:
//
// 1️⃣ Shows a tiny toast-like SnackBar for instant feedback
// 2️⃣ Builds a clean, professional share message
// 3️⃣ Safely fetches the widget's render box (for tablets/iPads)
// 4️⃣ Opens the native OS share sheet using "share_plus"
// --------------------------------------------------------------
  String buildShareSubject(ServiceShareData data) {
    return "MyFellowPet • ${data.shopName}";
  }

  String buildShareMessage(ServiceShareData data) {
    final deepLink =
        "https://myfellowpet-prod.web.app/boarding/${data.documentId}"; // <-- CHANGE THIS HOST
    final storeLink =
        "https://play.google.com/store/apps/details?id=com.myfellowpet.app";

    final petList = buildPetList(data);
    final startingPrice = extractStartingPrice(data); // auto from "Small"

    return """
    *${data.shopName}* is now on *MyFellowPet!*

🏡 Service Name: *${data.shopName}*
📍 Area Name: *${data.areaName}*

🐶 Pets Catered To: *$petList* 
💸 Starting From: *₹$startingPrice/- per day*

Elevate your pet’s comfort and safety with verified service providers.

👉 *View Service:* 
$deepLink

👉 *Download MyFellowPet App:*  
$storeLink
""";
  }

  String extractStartingPrice(ServiceShareData data) {
    if (data.pets.isEmpty) return "0";

    final firstPet = data.pets.first; // e.g. "dog"
    final petPrices = data.preCalculatedStandardPrices[firstPet];

    if (petPrices == null) return "0";

    final smallPrice = petPrices["Small"] ?? 0;

    return smallPrice.toString();
  }

  String buildPetList(ServiceShareData data) {
    if (data.pets.isEmpty) return "No pets listed";

    // Convert: ["dog", "cat"] → "Dog, Cat"
    return data.pets.map((p) => p[0].toUpperCase() + p.substring(1)).join(", ");
  }

  Future<XFile> _loadBrandImage() async {
    final byteData = await rootBundle.load("assets/mobile_application_logo.png");

    return XFile.fromData(
      byteData.buffer.asUint8List(),
      name: "myfellowpet.png",
      mimeType: "image/png",
    );
  }

  Future<void> _shareService(ServiceShareData data) async {
    HapticFeedback.mediumImpact();

    final box = context.findRenderObject() as RenderBox?;
    final message = buildShareMessage(data);
    final subject = buildShareSubject(data);

    final XFile brandImage = await _loadBrandImage();

    try {


    } catch (e) {
      debugPrint("⚠ Failed to load image for sharing: $e");
    }

    await SharePlus.instance.share(
      ShareParams(
        text: message,
        subject: subject,
        files: [brandImage], // 🔥 ONLY your brand asset
        sharePositionOrigin: box!.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  // lib/screens/Boarding/boarding_servicedetailspage.dart (inside _BoardingServiceDetailPageState)

  /// Handles all back navigation (native gesture/button or custom arrow).
  /// If a previous page exists, it pops once. If not, it navigates to the home screen.
  Future<void> _handleBackNavigation() async {
    if (!mounted) return;

    final nav = Navigator.of(context);

    if (nav.canPop()) {
      // Usual Case: A previous page exists, so pop once.
      nav.pop();
    } else {
      // Edge Case: No previous page (cleared stack or deep link).
      // Go to HomeWithTabs (assuming this is the root) and clear the stack.
      nav.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => HomeWithTabs(),
        ),
            (Route<dynamic> route) => false, // Clear all previous routes
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: const CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFF2CB4B6), // your teal theme
              ),
            ),
          );
        }


        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: _design.backgroundColor,
            body: Center(
              child: Text(
                'Error loading data: ${snapshot.error}',
                style: GoogleFonts.poppins(
                  color: _design.primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return Scaffold(
            backgroundColor: _design.backgroundColor,
            body: Center(
              child: Text(
                'Data not found.',
                style: GoogleFonts.poppins(
                  color: _design.primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          );
        }

        final serviceDoc = snapshot.data!['service'] as DocumentSnapshot;
        final allPetPricing = snapshot.data!['pets'] as List<PetPricing>;
        final ratingStats = snapshot.data!['ratings'] as Map<String, dynamic>;

        if (!serviceDoc.exists) {
          return Scaffold(
            backgroundColor: _design.backgroundColor,
            body: Center(
              child: Text(
                'Service not found.',
                style: GoogleFonts.poppins(
                  color: _design.primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          );
        }

        final serviceData = serviceDoc.data() as Map<String, dynamic>;

        _shopName = serviceData['shop_name'] ?? 'No Shop Name';
        _street = serviceData['street'] ?? 'No Street';
        _areaName = serviceData['area_name'] ?? 'No Area';
        _state = serviceData['state'] ?? 'No State';
        _district = serviceData['district'] ?? 'No District';
        _postalCode = serviceData['postal_code'] ?? 'No Postal Code';
        _companyName = serviceData['company_name'] ?? 'No Company Name';
        _adminApproved = serviceData['adminApproved'] as bool? ?? false;
        _serviceId = serviceData['service_id'] ?? 'No Service ID';
        _maxPetsAllowed = serviceData['max_pets_allowed']?.toString() ?? '0';
        _maxPetsAllowedPerHour =
            serviceData['max_pets_allowed_per_hour']?.toString() ?? '0';
        _currentCountOfPet =
            serviceData['current_count_of_pet']?.toString() ?? '0';
        _description = serviceData['description'] ?? 'No Description';
        _location = serviceData['shop_location'] as GeoPoint;
        _openTime = serviceData['open_time'] ?? '09:00';
        _closeTime = serviceData['close_time'] ?? '18:00';
        _walkingFee = (serviceData['walkingFee'] ?? '0').toString();
        _spId = serviceData['service_id'] ?? 'No ID';
        final petList = List<String>.from(serviceData['pets'] ?? []);
        final imageUrls = List<String>.from(serviceData['image_urls'] ?? []);
        _fullAddress = serviceData['full_address'] ?? 'No address provided';

        _petDocIds = allPetPricing.map((p) => p.petName).toList();

        if (_selectedPet == null || !_petDocIds.contains(_selectedPet)) {
          _selectedPet = widget.initialSelectedPet ?? (_petDocIds.isNotEmpty ? _petDocIds.first : null);
        }

        if (_selectedPet == null) {
          return Scaffold(
            backgroundColor: _design.backgroundColor,
            body: const Center(child: Text("No pets available for this service.")),
          );
        }

        PetPricing? selectedPetData;
        try {
          selectedPetData = allPetPricing.firstWhere((p) => p.petName == _selectedPet);
        } catch (e) {
          if (_petDocIds.isNotEmpty) {
            _selectedPet = _petDocIds.first;
            selectedPetData = allPetPricing.first;
          }
        }

        if (selectedPetData == null) {
          return Scaffold(
            backgroundColor: _design.backgroundColor,
            body: const Center(child: Text("Selected pet data not found.")),
          );
        }

        _acceptedSizes = selectedPetData.acceptedSizes;
        _acceptedBreeds = selectedPetData.acceptedBreeds;

        final allRatesDaily = {
          for (var p in allPetPricing)
            p.petName: p.ratesDaily.map((k, v) => MapEntry(k, int.tryParse(v) ?? 0))
        };
        final allWalkingRates = {
          for (var p in allPetPricing)
            p.petName: p.walkingRatesDaily.map((k, v) => MapEntry(k, int.tryParse(v) ?? 0))
        };
        final allMealRates = {
          for (var p in allPetPricing)
            p.petName: p.mealRatesDaily.map((k, v) => MapEntry(k, int.tryParse(v) ?? 0))
        };
        final allOfferRatesDaily = {
          for (var p in allPetPricing)
            p.petName: p.offerRatesDaily.map((k, v) => MapEntry(k, int.tryParse(v) ?? 0))
        };
        final allOfferWalkingRates = {
          for (var p in allPetPricing)
            p.petName: p.offerWalkingRatesDaily.map((k, v) => MapEntry(k, int.tryParse(v) ?? 0))
        };
        final allOfferMealRates = {
          for (var p in allPetPricing)
            p.petName: p.offerMealRatesDaily.map((k, v) => MapEntry(k, int.tryParse(v) ?? 0))
        };

        final allFeedingDetails = {
          for (var pet in allPetPricing) pet.petName: pet.feedingDetails
        };

        _refundPolicy = Map<String, int>.fromEntries(
          (serviceData['refund_policy'] as Map<String, dynamic>? ?? {})
              .entries
              .map(
                (e) => MapEntry(
              e.key,
              e.value is int
                  ? e.value
                  : int.tryParse(e.value.toString()) ?? 0,
            ),
          ),
        );

        _features = List<String>.from(serviceData['features'] ?? []);
        final fullAddress = '''
$_shopName,
$_street,
$_areaName,
$_district, $_state - $_postalCode
''';

        return PopScope(
            // 1. Block the default back behavior (mandatory for custom handling)
            canPop: false,

            // 2. Dictate the native back behavior
            onPopInvokedWithResult: (didPop, result) async {
          // We only act if the system tried to pop but couldn't (because canPop is false).
          if (!didPop) {
            // Call the function that handles all back navigation scenarios.
            await _handleBackNavigation();
          }
        },

        child: Scaffold(
          backgroundColor: _design.backgroundColor,
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    SizedBox(height: 5),
                    Container(
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 80, 0, 0),
                        child: _ServiceOverviewCard(
                          serviceId: _serviceId,
                          distanceKm: widget.distanceKm,
                          shopName: widget.shopName,
                          areaName: widget.areaName,
                          shopImage: widget.shopImage,
                          openTime: _openTime,
                          maxPetsAllowed: _maxPetsAllowed,
                          closeTime: _closeTime,
                          onBranchSelected: _switchBranch,
                          design: _design,
                          rates: widget.rates,
                          pets: petList,
                          isOfferActive: widget.isOfferActive,
                          isCertified: widget.isCertified,
                          originalRates: allRatesDaily[_selectedPet] ?? {},
                          otherBranches: widget.otherBranches,
                        ),
                      ),
                    ),
//----------------------------------------------
// TOP OVERLAY — CLEAN + SMALLER VERSION
//----------------------------------------------
                    Positioned(
                      top: 48, // lowered height
                      left: 12,
                      child: GestureDetector(
                        onTap: () {
                          // 👇 NEW NAVIGATION LOGIC STARTS HERE
                          final canPop = Navigator.of(context).canPop();

                          if (canPop) {
                            // Usual case: A previous page exists, so just pop.
                            Navigator.of(context).pop();
                          } else {
                            // Edge case: No previous page (e.g., deep link or cleared stack).
                            // Go to HomeWithTabs(1) - assuming HomeWithTabs(1) is the entry point
                            // and the tab index for Boarding is 1.
                            // Assuming HomeWithTabs is defined elsewhere.
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (context) => HomeWithTabs(), // Go to the Home with Boarding tab (index 1)
                              ),
                                  (Route<dynamic> route) => false, // Clear all previous routes
                            );
                          }
                          // 👆 NEW NAVIGATION LOGIC ENDS HERE
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6), // smaller
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 3, // smaller
                                offset: const Offset(0, 1.5),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.arrow_back, size: 26, color: Colors.black), // smaller icon
                        ),
                      ),
                    ),

                    Positioned(
                      top: 42,
                      right: 16,
                      child: Row(
                        children: [

                          // ❤️ Favorite Button
                          Consumer<FavoritesProvider>(
                            builder: (ctx, favProv, _) {
                              final isLiked = favProv.liked.contains(_serviceId);

                              return GestureDetector(
                                onTap: () => favProv.toggle(_serviceId),
                                child: Container(
                                  margin: const EdgeInsets.only(right: 10),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 5,
                                        offset: Offset(0, 3),
                                      ),
                                    ],
                                    border: Border.all(
                                      color: Colors.black87,
                                      width: 0.8,
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(10),
                                  child: Icon(
                                    isLiked ? Icons.favorite : Icons.favorite_border,
                                    size: 22,
                                    color: isLiked ? Colors.red : Colors.grey.shade500,
                                  ),
                                ),
                              );
                            },
                          ),

                          // 🔗 Share Button (dummy)
                          if (_showShareButton)
                            GestureDetector(
                              onTap: () => _shareService(
                                ServiceShareData(
                                  shopName: widget.shopName,
                                  areaName: widget.areaName,
                                  documentId: widget.documentId,
                                  serviceId: _serviceId,
                                  pets: petList,
                                  preCalculatedStandardPrices:
                                  serviceData['pre_calculated_standard_prices'] ?? {},
                                ),
                              ),
                              child: Container(
                                margin: const EdgeInsets.only(right: 10),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 5,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                  border: Border.all(
                                    color: Colors.black87,
                                    width: 0.8,
                                  ),
                                ),
                                padding: const EdgeInsets.all(10),
                                child: const Icon(
                                  Icons.share,
                                  size: 22,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          // 🗂 Categories (Quick Actions) Button
                          GestureDetector(
                            onTap: () => _openQuickActionsSheet(context, ratingStats),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 5,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                                border: Border.all(
                                  color: Colors.black87,
                                  width: 0.8,
                                ),
                              ),
                              padding: const EdgeInsets.all(10),
                              child: Image.asset(
                                "assets/categories.jpg",
                                height: 26,
                                width: 26,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )



                  ],
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ✨ NEW QUICK ACCESS BUTTONS ADDED HERE
                      _buildQuickAccessButtons(context, allFeedingDetails, serviceData['partner_policy_url'] as String?),

                      if (imageUrls.isNotEmpty)
                        _GalleryGridSection(
                          imageUrls: imageUrls,
                          design: _design,
                        ),

                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: PetPricingTable(
                    isOfferActive: widget.isOfferActive,
                    petDocIds: _petDocIds,
                    ratesDaily: allRatesDaily,
                    walkingRates: allWalkingRates,
                    mealRates: allMealRates,
                    offerRatesDaily: allOfferRatesDaily,
                    offerWalkingRates: allOfferWalkingRates,
                    offerMealRates: allOfferMealRates,
                    initialSelectedPet: _selectedPet,

                    onPetSelected: (newPetId) {
                      if (newPetId != null) {
                        setState(() {
                          _selectedPet = newPetId;

                          final newPetData = allPetPricing.firstWhere(
                                (p) => p.petName == newPetId,
                          );

                          _acceptedSizes = newPetData.acceptedSizes;
                          _acceptedBreeds = newPetData.acceptedBreeds;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(height: 5),
                PetVarietiesTable(
                  petDocIds: _petDocIds,
                  selectedPet: _selectedPet,
                  acceptedSizes: _acceptedSizes,
                  acceptedBreeds: _acceptedBreeds,
                  onPetSelected: (newPetId) {
                    if (newPetId != null) {
                      setState(() {
                        _selectedPet = newPetId;
                        final newPetData = allPetPricing.firstWhere((p) => p.petName == newPetId);
                        _acceptedSizes = newPetData.acceptedSizes;
                        _acceptedBreeds = newPetData.acceptedBreeds;
                      });
                    }
                  },
                ),

                const SizedBox(height: 16),

                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      _DetailSection(
                        title: "Description",
                        content: _description,
                        design: _design,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: _ActionFooter(
              design: _design,
              onPressed: () {
                onConfirmNavigation() {
                  final selectedPetPricing = allPetPricing.firstWhere((p) => p.petName == _selectedPet);

                  final Map<String, int> dailyRatesToPass = (widget.isOfferActive
                      ? selectedPetPricing.offerRatesDaily
                      : selectedPetPricing.ratesDaily)
                      .map((key, value) => MapEntry(key, int.tryParse(value.toString()) ?? 0));

                  final Map<String, int> mealRatesToPass = (widget.isOfferActive
                      ? selectedPetPricing.offerMealRatesDaily
                      : selectedPetPricing.mealRatesDaily)
                      .map((key, value) => MapEntry(key, int.tryParse(value.toString()) ?? 0));

                  final Map<String, int> walkingRatesToPass = (widget.isOfferActive
                      ? selectedPetPricing.offerWalkingRatesDaily
                      : selectedPetPricing.walkingRatesDaily)
                      .map((key, value) => MapEntry(key, int.tryParse(value.toString()) ?? 0));

                  final feedingDetailsToPass = Map<String, dynamic>.from(selectedPetPricing.feedingDetails);

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => BoardingParametersSelectionPage(
                        max_pets_allowed: int.parse(_maxPetsAllowed),
                        mode: widget.mode,
                        open_time: _openTime,
                        close_time: _closeTime,
                        current_count_of_pet: _currentCountOfPet,
                        initialSelectedPet: _selectedPet,
                        shopName: widget.shopName,
                        shopImage: widget.shopImage,
                        sp_location: _location,
                        companyName: _companyName,
                        sp_id: _spId,
                        walkingFee: _walkingFee,
                        serviceId: _serviceId,
                        rates: dailyRatesToPass,
                        mealRates: mealRatesToPass,
                        refundPolicy: _refundPolicy,
                        fullAddress: _fullAddress,
                        areaName: widget.areaName,
                        walkingRates: walkingRatesToPass,
                        feedingDetails: feedingDetailsToPass,
                      ),
                    ),
                  );
                }

                if (_selectedPet != null) {
                  _showBookingConfirmationDialog(
                    context,
                    _selectedPet!.capitalize(),
                    onConfirmNavigation,
                  );
                } else {
                  onConfirmNavigation();
                }
              },
            ),
          ),

        ),);
      },
    );
  }
}
class RefundPolicyChips extends StatefulWidget {
  final Map<String, int> refundRates;
  final DesignConstants design;

  const RefundPolicyChips({
    Key? key,
    required this.refundRates,
    required this.design,
  }) : super(key: key);

  @override
  State<RefundPolicyChips> createState() => _RefundPolicyChipsState();
}

class _RefundPolicyChipsState extends State<RefundPolicyChips>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }
  String _getRefundLabel(String key) {
    switch (key) {
      case 'gt_48h':
        return 'More than 48 hours before the start time';
      case 'gt_24h':
        return '24–48 hours before the start time';
      case 'gt_12h':
        return '12–24 hours before the start time';
      case 'gt_4h':
        return '4–12 hours before the start time';
      case 'lt_4h':
        return 'Less than 4 hours before the start time';
      default:
        return key;
    }
  }



  @override
  Widget build(BuildContext context) {
    final entries = widget.refundRates.entries.toList();
    final showEntries = _expanded ? entries : entries.take(2).toList();

    final orderMap = {
      'lt_4h': 0,
      'gt_4h': 1,
      'gt_12h': 2,
      'gt_24h': 3,
      'gt_48h': 4,
    };

    final sorted = showEntries.toList()
      ..sort((a, b) => orderMap[a.key]!.compareTo(orderMap[b.key]!));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Cards ---
        Column(
          children: sorted.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final refund = entry.value;

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [

                  // Number Badge
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: widget.design.primaryColor.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      "$idx",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        color: widget.design.primaryColor,
                        fontSize: 13,
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Text Content
                  Expanded(
                    child: Text(
                      "${_getRefundLabel(refund.key)} — ${refund.value}%",
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),

        // Expand / Collapse
        if (entries.length > 2)
          GestureDetector(
            onTap: () {
              setState(() {
                _expanded = !_expanded;
                if (!_expanded) _blinkController.repeat(reverse: true);
                else _blinkController.stop();
              });
            },
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Text(
                    _expanded ? "See less" : "See all refund slabs",
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: widget.design.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  FadeTransition(
                    opacity: _expanded
                        ? const AlwaysStoppedAnimation(1)
                        : _blinkController,
                    child: RotationTransition(
                      turns: AlwaysStoppedAnimation(_expanded ? 0.5 : 0),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: Colors.black54,
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),

        const SizedBox(height: 10),
      ],
    );
  }
}

class AnimatedLocationButton extends StatefulWidget {
  final double distanceKm;
  final AnimationController controller;

  const AnimatedLocationButton({
    Key? key,
    required this.distanceKm,
    required this.controller,
  }) : super(key: key);

  @override
  _AnimatedLocationButtonState createState() => _AnimatedLocationButtonState();
}

class _AnimatedLocationButtonState extends State<AnimatedLocationButton> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _expanded = true;
      });
      Future.delayed(const Duration(seconds: 4), () {
        setState(() {
          _expanded = false;
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    const double collapsedSize = 50;
    const double expandedWidth = 250;
    const double buttonHeight = 50;

    return Positioned(
      right: 16,
      bottom: 120,
      child: GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("Location Info"),
              content: RichText(
                text: TextSpan(
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                  children: [
                    const TextSpan(text: "Your location is "),
                    TextSpan(
                      text: "${widget.distanceKm.toStringAsFixed(1)} km",
                      style: const TextStyle(
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const TextSpan(text: " far from this place"),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Close"),
                ),
              ],
            ),
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 1200),
          curve: Curves.fastOutSlowIn,
          width: _expanded ? expandedWidth : collapsedSize,
          height: buttonHeight,
          padding: EdgeInsets.symmetric(horizontal: _expanded ? 16 : 0),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: const Color(0xFFF9D443),
              width: 4.0,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 6,
                offset: Offset(0, 3),
              )
            ],
          ),
          child: _expanded
              ? RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.black87,
              ),
              children: [
                const TextSpan(text: "Your location is "),
                TextSpan(
                  text: "${widget.distanceKm.toStringAsFixed(1)} km",
                  style: const TextStyle(
                    decoration: TextDecoration.underline,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const TextSpan(text: " far from this place"),
              ],
            ),
          )
              : Icon(
            Icons.location_on,
            size: 24,
            color: const Color(0xFFBE8F00).withOpacity(0.7),
          ),
        ),
      ),
    );
  }
}

class DesignConstants {
  final contentPadding =
  const EdgeInsets.symmetric(horizontal: 24.0, vertical: 0);
  final primaryColor = const Color(0xFF2BCECE);
  final accentColor = const Color(0xFFF9D443);
  final backgroundColor = const Color(0xFFFFFFFF);
  final textDark = const Color(0xFF2D3436);
  final textLight = const Color(0xFF636E72);
  final shadowColor = Colors.black12;

  final titleStyle = const TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    color: Color(0xFF2D3436),
  );

  final subtitleStyle = const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: Color(0xFF636E72),
    height: 1.5,
  );

  final priceStyle = const TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: Color(0xFF6C5CE7),
  );
}

class _ServiceOverviewCard extends StatefulWidget {
  final String shopName;
  final String areaName;
  final String shopImage;
  final String openTime;
  final String serviceId;
  final String closeTime;
  final double distanceKm;
  final bool isCertified;
  final DesignConstants design;
  final String maxPetsAllowed;
  final List<String> pets;
  final Map<String, int> rates;
  final List<String> otherBranches;
  final bool isOfferActive;
  final Map<String, int> originalRates;
  final Function(String) onBranchSelected;

  const _ServiceOverviewCard({
    Key? key,
    required this.shopName,
    required this.shopImage,
    required this.openTime,
    required this.closeTime,
    required this.design,
    required this.distanceKm,
    required this.maxPetsAllowed,
    required this.pets,
    required this.rates,
    required this.serviceId,
    required this.isOfferActive,
    required this.originalRates,
    required this.areaName,
    required this.isCertified,
    required this.otherBranches,
    required this.onBranchSelected,
  }) : super(key: key);

  @override
  __ServiceOverviewCardState createState() => __ServiceOverviewCardState();
}

class __ServiceOverviewCardState extends State<_ServiceOverviewCard> {
  String _selectedSize = '';
  bool _isOfferActive = false;

  int _minPrice() {
    final prices = widget.rates.values.where((p) => p > 0).toList();
    return prices.isEmpty ? 0 : prices.reduce((a, b) => a < b ? a : b);
  }

  // ✨ REMOVED unused fetchRatingStats function

  void _showFullShopNameDialog(BuildContext context, String shopName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          "Service Provider",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w500,
            fontSize: 16,
            color: Colors.grey.shade700,
          ),
        ),
        content: Text(
          shopName,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              "Close",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    String shortId = widget.serviceId.length > 8
        ? widget.serviceId.substring(0, 8) + "…"
        : widget.serviceId;

    final bool isImageValid = widget.shopImage.isNotEmpty && widget.shopImage.startsWith('http');

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 20, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(0),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  image: isImageValid
                      ? DecorationImage(
                    image: NetworkImage(widget.shopImage),
                    fit: BoxFit.cover,
                  )
                      : null,
                  color: isImageValid ? null : Colors.grey.shade200,
                ),
                child: isImageValid ? null : Icon(Icons.store, color: Colors.grey.shade400),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      children: [
                        GestureDetector(
                          onTap: () => _showFullShopNameDialog(context, widget.shopName),
                          child: Text(
                            widget.shopName,
                            style: GoogleFonts.poppins(
                              textStyle: widget.design.titleStyle,
                              fontSize: 22,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Service ID: ",
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          shortId,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: widget.serviceId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Service ID copied")),
                            );
                          },
                          child: const Icon(Icons.copy, size: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 0.0),
                          child: BranchSelector(
                            currentServiceId: widget.serviceId,
                            currentAreaName: widget.areaName,
                            otherBranches: widget .otherBranches,
                            onBranchSelected: (newBranchId) {
                              if (newBranchId != null) {
                                widget.onBranchSelected(newBranchId);
                              }
                            },
                          ),
                        ),
                        // lib/screens/Boarding/boarding_homepage.dart (Inside _BoardingServiceCardState.build, around line 1475)
// Replace the existing Row that handles distance with this one:
                        // Replace the Row inside BoardingServiceCard.build with this one:
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center, // Crucial for vertical alignment
                          children: [
                            Text(
                              // dKm is 0.0 if not fetched, and double.infinity if error/no location
                              widget.distanceKm.isInfinite || widget.distanceKm == 0.0 // Check for both
                                  ? 'Location services disabled. Enable to view'
                                  : '${widget.distanceKm.toStringAsFixed(1)} km away',
                              style: const TextStyle(fontSize: 9),
                            ),

                            // 🚨 STABILITY FIX: Reserve space for the button regardless of its visibility
                            SizedBox(
                              width: 24, // Fixed width (e.g., 24px)
                              height: 16, // Fixed height (to match text height)
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 4.0),
                                  child: (widget.distanceKm.isInfinite || widget.distanceKm == 0.0)
                                      ? IconButton(
                                    onPressed: () async {
                                      // 1. Check current app permission status
                                      LocationPermission permissionStatus = await Geolocator.checkPermission();

                                      // 2. If denied, try to request the native OS dialog again.
                                      if (permissionStatus == LocationPermission.denied) {
                                        // This attempt shows the native dialog if possible.
                                        permissionStatus = await Geolocator.requestPermission();
                                      }

                                      // --- HANDLE PERMANENT BLOCKAGE ---
                                      if (permissionStatus == LocationPermission.deniedForever) {
                                        // Permission is permanently blocked by the OS. Cannot ask again.
                                        _showManualPermissionDialog(context);
                                        return;
                                      }

                                      // --- HANDLE GRANTED PERMISSION (but service might be off) ---
                                      if (permissionStatus == LocationPermission.whileInUse ||
                                          permissionStatus == LocationPermission.always) {

                                        // Check if the device's main location service (GPS) is enabled
                                        bool isServiceEnabled = await Geolocator.isLocationServiceEnabled();

                                        if (isServiceEnabled) {
                                          // ✅ SUCCESS: Permission granted AND GPS is ON.
                                          // The stream listener in BoardingHomepage will handle the distance update.
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Location access granted! Refreshing distances...'),
                                              duration: Duration(seconds: 2),
                                            ),
                                          );

                                        } else {
                                          // ⚠️ WARNING: Permission granted, but GPS is OFF.
                                          // 🎯 MODIFIED: Show the specialized dialog for GPS disabled.
                                          _showGpsDisabledDialog(context);
                                        }
                                        return;
                                      }

                                      // --- HANDLE REMAINING DENIED STATUS (User denied during the immediate request) ---
                                      if (permissionStatus == LocationPermission.denied) {
                                        // User was presented the native dialog in step 2 and hit DENY.
                                        // Notify them and rely on them to tap the button again later.
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Location permission denied.'),
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    },
                                    icon: Icon(Icons.refresh, size: 14, color: Colors.red.shade700), // Button slightly bigger (14)
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  )
                                      : const SizedBox.shrink(), // Show an empty box if location is working
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _InfoGridRow(
            distanceKm: widget.distanceKm,
            openTime: widget.openTime,
            closeTime: widget.closeTime,
            maxPetsAllowed: widget.maxPetsAllowed,
            design: widget.design,
          ),

        ],
      ),
    );
  }


  void _showGpsDisabledDialog(BuildContext context) {
    // Define colors and responsiveness
    const Color primaryColor = Color(0xFF25ADAD);
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Dialog(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 25, 20, 15),
              width: isSmallScreen ? screenWidth * 0.85 : 400,

              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // 1. Header and Icon
                  Row(
                    children: [
                      Icon(Icons.location_disabled, color: Colors.orange.shade700, size: isSmallScreen ? 24 : 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Device Location is Off",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: isSmallScreen ? 17 : 20,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const Divider(height: 25), // Clean separator

                  // 2. Main Content and Instruction
                  Text(
                    "We have permission to access your location, but your device's GPS (Location Services) is currently disabled.",
                    style: GoogleFonts.poppins(
                      fontSize: isSmallScreen ? 14 : 15,
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 15),

                  // 3. Highlighted Action Instruction
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50.withOpacity(0.5), // Light orange background
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.settings, size: isSmallScreen ? 18 : 20, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: GoogleFonts.poppins(fontSize: isSmallScreen ? 13 : 14, color: Colors.black87, height: 1.4),
                              children: [
                                TextSpan(
                                  text: "To view distances:\n",
                                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: Colors.orange.shade700),
                                ),
                                const TextSpan(
                                  text: "Please tap 'Open Settings' below to enable Location Services.",
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 4. Action Buttons (Right Aligned)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Close Button
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(
                          "Cancel",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: isSmallScreen ? 14 : 15,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),

                      // Open Settings Button
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          Geolocator.openLocationSettings(); // 🎯 Action: Redirect to OS settings
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 12 : 16, vertical: isSmallScreen ? 10 : 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          "Open Settings",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: isSmallScreen ? 14 : 15,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  // lib/screens/Boarding/boarding_homepage.dart (or wherever your dialog functions are)

  void _showManualPermissionDialog(BuildContext context) {
    // Determine screen width for responsiveness
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Dialog(
          // Use ClipRRect for clean, rounded corners
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              // Use white background
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 25, 20, 15),
              width: isSmallScreen ? screenWidth * 0.85 : 400, // Responsive width

              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // 1. Header and Icon
                  Row(
                    children: [
                      Icon(Icons.location_off, color: Colors.red.shade700, size: isSmallScreen ? 24 : 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Location Access Required",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: isSmallScreen ? 17 : 20,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const Divider(height: 25), // Clean separator

                  // 2. Main Content and Instruction
                  Text(
                    "We need your location to accurately calculate distances to services.",
                    style: GoogleFonts.poppins(
                      fontSize: isSmallScreen ? 14 : 15,
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 15),


// 3. Highlighted Manual Instruction
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: isSmallScreen ? 18 : 20, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: GoogleFonts.poppins(
                                fontSize: isSmallScreen ? 13 : 14,
                                color: Colors.black87,
                                height: 1.4,
                              ),
                              children: [

                                // Title
                                TextSpan(
                                  text: "Permission Denied:\n",
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.red.shade700,
                                  ),
                                ),

                                // 👇 ADD THIS for a blank line
                                const TextSpan(text: "\n"),

                                // Explanation
                                const TextSpan(
                                  text:
                                  "You have permanently denied location access. \n\n",
                                ),
                                // Explanation
                                const TextSpan(
                                  text:
                                  "The app is blocked from showing the permission request again.\n\n",
                                ),




                                // Second paragraph
                                const TextSpan(
                                  text:
                                  "Please go to your device settings to manually enable location access for MyFellowPet.",
                                ),
                              ],
                            ),

                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 4. Action Buttons (Right Aligned)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Close Button
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(
                          "Close",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: isSmallScreen ? 14 : 15,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),

                      // Action Button (Could be "Go to Settings" if using permission_handler)
                      // We'll keep it as "OK" for simplicity without adding a new dependency.
                      ElevatedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                          padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 12 : 16, vertical: isSmallScreen ? 10 : 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          "OK, I Understand",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: isSmallScreen ? 14 : 15,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
class RatingBadge extends StatelessWidget {
  final Map<String, dynamic> ratingStats;

  const RatingBadge({Key? key, required this.ratingStats}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final stats = ratingStats;

    // avg and count safe defaults
    final avg = (stats['avg'] ?? 0.0).toDouble().clamp(0.0, 5.0);
    final count = (stats['count'] ?? 0) as int;

    return Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.star,
            size: 21,
            color: Color(0xffffc100),
          ),

          const SizedBox(height: 3),

          Text(
            avg.toStringAsFixed(1), // show "0.0" if no data
            style: GoogleFonts.poppins(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),

          // Optional: show review count below in tiny font
          // if you want:
          // Text("($count)", style: GoogleFonts.poppins(fontSize: 8, color: Colors.grey)),
        ],
      ),
    );
  }
}


class _InfoGridRow extends StatelessWidget {
  final double distanceKm;
  final String openTime;
  final String closeTime;
  final DesignConstants design;
  final String maxPetsAllowed;

  const _InfoGridRow({
    Key? key,
    required this.openTime,
    required this.closeTime,
    required this.design,
    required this.maxPetsAllowed,
    required this.distanceKm,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _InfoPill(
              icon: Icons.access_time_rounded,
              label: 'Open Time',
              value: openTime,
              design: design,
            ),
            _InfoPill(
              icon: Icons.access_time_rounded,
              label: 'Close Time',
              value: closeTime,
              design: design,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Center(
          child: _InfoPill(
            icon: Icons.filter_list,
            label: 'Daily pet limit',
            value: (maxPetsAllowed == null || maxPetsAllowed == "0")
                ? "No limit"
                : maxPetsAllowed,
            design: design,
          ),
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final DesignConstants design;

  const _InfoPill({
    Key? key,
    required this.icon,
    required this.label,
    required this.value,
    required this.design,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, weight: 10, color: design.primaryColor),
          const SizedBox(width: 8),
          Row(
            children: [
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: design.textLight,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: design.textDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

}

class _DetailSection extends StatelessWidget {
  final String title;
  final String content;
  final DesignConstants design;
  final Widget? child;

  const _DetailSection({
    Key? key,
    required this.title,
    required this.content,
    required this.design,
    this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        if (child != null)
          child!
        else
          ExpandableText(
            text: content,
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.black87),
            expandText: "Show more",
            collapseText: "Show less",
            maxLines: 2,
            linkStyle: GoogleFonts.poppins(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}


class ExpandableText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final int maxLines;
  final String expandText;
  final String collapseText;
  final TextStyle? linkStyle;

  const ExpandableText({
    Key? key,
    required this.text,
    required this.style,
    this.maxLines = 3,
    this.expandText = 'Show more',
    this.collapseText = 'Show less', this.linkStyle,
  }) : super(key: key);

  @override
  _ExpandableTextState createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _expanded = false;
  bool _needsToggle = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final span = TextSpan(text: widget.text, style: widget.style);
      final tp = TextPainter(
        maxLines: widget.maxLines,
        text: span,
        textDirection: TextDirection.ltr,
      );
      tp.layout(maxWidth: MediaQuery.of(context).size.width - 48);
      if (tp.didExceedMaxLines != _needsToggle) {
        setState(() {
          _needsToggle = tp.didExceedMaxLines;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final textWidget = Text(
        widget.text,
        style: widget.style,
        maxLines: _expanded ? null : widget.maxLines,
        overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        textAlign: TextAlign.justify,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          textWidget,
          if (_needsToggle)
            GestureDetector(
              onTap: () {
                setState(() {
                  _expanded = !_expanded;
                });
              },
              child: Text(
                _expanded ? widget.collapseText : widget.expandText,
                style: widget.linkStyle ??
                    GoogleFonts.poppins(
                      color: const Color(0xFF209696),
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
        ],
      );
    });
  }
}

class _GalleryGridSection extends StatelessWidget {
  final List<String> imageUrls;
  final DesignConstants design;

  const _GalleryGridSection({
    Key? key,
    required this.imageUrls,
    required this.design,
  }) : super(key: key);

  void _openImageViewer(BuildContext context, int initialIndex) {
    showDialog(
      context: context,
      builder: (_) => _ImageViewerDialog(
        imageUrls: imageUrls,
        initialIndex: initialIndex,
        design: design,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 5),
        GridView.builder(
          padding: EdgeInsets.zero,
          primary: false,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: imageUrls.length > 3 ? 3 : imageUrls.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemBuilder: (context, index) {
            if (index < 2) {
              return GestureDetector(
                onTap: () => _openImageViewer(context, index),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage( // ✨ Use CachedNetworkImage
                    imageUrl: imageUrls[index],
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(color: Colors.grey.shade200),
                    errorWidget: (context, url, error) => Icon(Icons.error),
                  ),
                ),
              );
            }

            if (imageUrls.length > 3 && index == 2) {
              final remaining = imageUrls.length - 3;
              return GestureDetector(
                onTap: () => _openImageViewer(context, index),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage( // ✨ Use CachedNetworkImage
                        imageUrl: imageUrls[index],
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: Colors.grey.shade200),
                        errorWidget: (context, url, error) => Icon(Icons.error),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    Text(
                      "+$remaining",
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              );
            }

            return GestureDetector(
              onTap: () => _openImageViewer(context, index),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage( // ✨ Use CachedNetworkImage
                  imageUrl: imageUrls[index],
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: Colors.grey.shade200),
                  errorWidget: (context, url, error) => Icon(Icons.error),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ImageViewerDialog extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  final DesignConstants design;

  const _ImageViewerDialog({
    Key? key,
    required this.imageUrls,
    required this.initialIndex,
    required this.design,
  }) : super(key: key);

  @override
  __ImageViewerDialogState createState() => __ImageViewerDialogState();
}

class __ImageViewerDialogState extends State<_ImageViewerDialog> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  void _previousImage() {
    if (_currentIndex > 0) {
      _currentIndex--;
      _pageController.animateToPage(_currentIndex,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _nextImage() {
    if (_currentIndex < widget.imageUrls.length - 1) {
      _currentIndex++;
      _pageController.animateToPage(_currentIndex,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.imageUrls.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return InteractiveViewer(
                child: CachedNetworkImage( // ✨ Use CachedNetworkImage
                  imageUrl: widget.imageUrls[index],
                  fit: BoxFit.contain,
                  placeholder: (context, url) => Center(child: CircularProgressIndicator(color: AppColors.primary)),
                  errorWidget: (context, url, error) => Icon(Icons.error, color: Colors.white),
                ),
              );
            },
          ),
          Positioned(
            left: 10,
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.black),
                onPressed: _previousImage,
              ),
            ),
          ),

          Positioned(
            right: 10,
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black),
                onPressed: _nextImage,
              ),
            ),
          ),

          Positioned(
            top: 30,
            right: 10,
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.close, size: 16, color: Colors.black),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),

        ],
      ),
    );
  }
}

class _SectionSpacer extends StatelessWidget {
  const _SectionSpacer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 1),
        Divider(color: Colors.grey.shade300),
        const SizedBox(height: 1),
      ],
    );
  }
}

class _ActionFooter extends StatelessWidget {
  final DesignConstants design;
  final VoidCallback onPressed;

  const _ActionFooter({
    Key? key,
    required this.design,
    required this.onPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: design.shadowColor,
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(
              color: design.primaryColor.withOpacity(0.9),
              width: 4.0,
            ),
          ),
          elevation: 0,
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Continue Booking',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
            ),
            const SizedBox(width: 10),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 20,
              color: Colors.black,
            ),
          ],
        ),
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return "";
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}

class PetPricing {
  final String petName;
  final Map<String, String> ratesDaily;
  final Map<String, String> walkingRatesDaily;
  final Map<String, String> mealRatesDaily;
  final Map<String, String> offerRatesDaily;
  final Map<String, String> offerWalkingRatesDaily;
  final Map<String, String> offerMealRatesDaily;
  final Map<String, dynamic> feedingDetails;
  final List<String> acceptedSizes;
  final List<String> acceptedBreeds;

  PetPricing( {
    required this.petName,
    required this.ratesDaily,
    required this.walkingRatesDaily,
    required this.mealRatesDaily,
    required this.offerRatesDaily,
    required this.offerWalkingRatesDaily,
    required this.offerMealRatesDaily,
    required this.feedingDetails,
    required this.acceptedSizes,
    required this.acceptedBreeds,
  });
}



class VerifiedBadge extends StatelessWidget {
  final bool isCertified;
  const VerifiedBadge({Key? key, required this.isCertified}) : super(key: key);




  @override
  Widget build(BuildContext context) {
    if (!isCertified) return const SizedBox.shrink();

    return GestureDetector(
      child: Container(
        width: 47,
        height: 47,
        decoration: BoxDecoration(
          color: AppColors.accentColor,
          shape: BoxShape.circle,

        ),
        child: const Icon(
          Icons.verified,
          color: Colors.white,
          size: 38,
        ),
      ),
    );
  }
}
Future<void> _showDialogVB(BuildContext context, String field) async {
  final doc = await FirebaseFirestore.instance
      .collection('settings')
      .doc('testaments')
      .get();

  final message = doc.data()?[field] ?? 'No info available';

  showGeneralDialog(
    context: context,
    barrierLabel: "Info",
    barrierDismissible: true,
    barrierColor: Colors.black.withOpacity(0.45), // soft dim
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: 320,
            ),
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // 🔥 HEADER
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Information",
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey.shade100,
                        ),
                        child: const Icon(Icons.close, size: 18),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                Divider(color: Colors.grey.shade300, height: 1),

                const SizedBox(height: 16),

                // 🔥 MESSAGE BODY
                Text(
                  message,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    color: Colors.black87,
                    height: 1.6,
                  ),
                ),

                const SizedBox(height: 26),

                // 🔥 MODERN BUTTON
                Align(
                  alignment: Alignment.center,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: AppColors.accentColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 36,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      "Got it",
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },

    // 🎬 Smooth Fade + Scale Animation
    transitionBuilder: (_, anim, __, child) {
      return Transform.scale(
        scale: 0.95 + (anim.value * 0.05),
        child: Opacity(
          opacity: anim.value,
          child: child,
        ),
      );
    },
  );
}

Future<void> _showDialogPV(BuildContext context, String field) async {
  final doc = await FirebaseFirestore.instance
      .collection('settings')
      .doc('testaments')
      .get();

  final message = doc.data()?[field] ?? 'No info available';

  showGeneralDialog(
    context: context,
    barrierLabel: "Info",
    barrierDismissible: true,
    barrierColor: Colors.black.withOpacity(0.45),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, __, ___) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ⭐ TITLE
                Text(
                  "Information",
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),

                const SizedBox(height: 14),
                Divider(color: Colors.grey.shade300, height: 1),

                const SizedBox(height: 14),

                // 📜 MESSAGE
                Text(
                  message,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    color: Colors.grey.shade900,
                    height: 1.55,
                  ),
                ),

                const SizedBox(height: 22),

                // ⭐ MODERN CLOSE BUTTON
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    child: Text(
                      "Close",
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },

    // 🎬 SMOOTH SCALE + FADE ANIMATION
    transitionBuilder: (_, anim, __, child) {
      return Transform.scale(
        scale: 0.95 + (anim.value * 0.05),
        child: Opacity(
          opacity: anim.value,
          child: child,
        ),
      );
    },
  );
}

class ProfileVerified extends StatelessWidget {
  const ProfileVerified({Key? key}) : super(key: key);




  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      child: Container(
        width: 47,
        height: 47,

        decoration: BoxDecoration(
          color: AppColors.primaryColor,
          shape: BoxShape.circle,

        ),
        child: const Icon(
          Icons.check_circle,
          color: Colors.white,
          size: 38,
        ),
      ),
    );
  }
}
class PetPricingTable extends StatefulWidget {
  final bool isOfferActive;
  final List<String> petDocIds;

  final Map<String, Map<String, int>> ratesDaily;
  final Map<String, Map<String, int>> walkingRates;
  final Map<String, Map<String, int>> mealRates;

  final Map<String, Map<String, int>> offerRatesDaily;
  final Map<String, Map<String, int>> offerWalkingRates;
  final Map<String, Map<String, int>> offerMealRates;

  final String? initialSelectedPet;
  final Function(String)? onPetSelected;

  const PetPricingTable({
    super.key,
    required this.isOfferActive,
    required this.petDocIds,
    required this.ratesDaily,
    required this.walkingRates,
    required this.mealRates,
    required this.offerRatesDaily,
    required this.offerWalkingRates,
    required this.offerMealRates,
    this.initialSelectedPet,
    this.onPetSelected,
  });

  @override
  State<PetPricingTable> createState() => _PetPricingTableState();
}

class _PetPricingTableState extends State<PetPricingTable> {
  late String _selectedPet;

  @override
  void initState() {
    super.initState();
    _selectedPet = widget.initialSelectedPet ?? widget.petDocIds.first;
  }

  @override
  void didUpdateWidget(covariant PetPricingTable oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✨ FIX: If the parent sends a new pet (from Feeding/Varieties), update local state
    if (widget.initialSelectedPet != oldWidget.initialSelectedPet &&
        widget.initialSelectedPet != null) {
      setState(() {
        _selectedPet = widget.initialSelectedPet!;
      });
    }

    // Safety check (existing logic)
    if (!widget.petDocIds.contains(_selectedPet)) {
      if (widget.petDocIds.isNotEmpty) {
        setState(() {
          _selectedPet = widget.petDocIds.first;
        });
      }
    }
  }

  Widget _buildNA() {
    return Text(
      "NA",
      style: GoogleFonts.poppins(
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade500,
      ),
    );
  }

  Widget _cell(dynamic std, dynamic offer) {
    if (std == null) return _buildNA();

    if (widget.isOfferActive && offer != null && offer != std) {
      return Row(
        children: [
          Text("₹$std",
              style: GoogleFonts.poppins(
                  color: Colors.grey, fontSize: 12, decoration: TextDecoration.lineThrough)),
          const SizedBox(width: 4),
          Text("₹$offer",
              style: GoogleFonts.poppins(
                  fontSize: 14, color: Colors.green, fontWeight: FontWeight.w600)),
        ],
      );
    }

    return Text("₹$std",
        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500));
  }

  @override
  Widget build(BuildContext context) {
    final sizes = ["Small", "Medium", "Large", "Giant"];

    final daily = widget.ratesDaily[_selectedPet] ?? {};
    final walk = widget.walkingRates[_selectedPet] ?? {};
    final meal = widget.mealRates[_selectedPet] ?? {};

    final dailyOffer = widget.offerRatesDaily[_selectedPet] ?? {};
    final walkOffer = widget.offerWalkingRates[_selectedPet] ?? {};
    final mealOffer = widget.offerMealRates[_selectedPet] ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),

        Container(
          // ✨ 1. Combined Outer Container
          margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300), // The main border
          ),
          child: Column(
            children: [
              // -----------------------------------------------------
              // 🟦 HEADER SECTION (Attached Top)
              // -----------------------------------------------------
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // Compact padding
                decoration: BoxDecoration(
                  color: Colors.white, // Subtle header bg
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(11),
                    topRight: Radius.circular(11),
                  ),
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300), // Divider line
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Per-Day Pricing",
                        style: GoogleFonts.poppins(
                            fontSize: 14, // ✨ Smaller font
                            fontWeight: FontWeight.w700,
                            color: Colors.black87)),

                    // Compact Dropdown
                    Container(
                      height: 28, // ✨ Reduced height
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(6), // ✨ Smaller radius
                        border: Border.all(color: Colors.black87, width: 0.8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedPet,
                          isDense: true,
                          iconSize: 18,
                          style: GoogleFonts.poppins(
                            fontSize: 12, // ✨ Smaller font
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          items: widget.petDocIds.map((id) {
                            return DropdownMenuItem(
                              value: id,
                              child: Text(
                                id.capitalize(),
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (v) {
                            setState(() => _selectedPet = v!);
                            widget.onPetSelected?.call(v!);
                          },
                          dropdownColor: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // -----------------------------------------------------
              // 📊 TABLE SECTION (Attached Bottom)
              // -----------------------------------------------------
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 22, // ✨ Tighter spacing
                  headingRowHeight: 38, // ✨ Shorter header
                  dataRowMinHeight: 40, // ✨ Shorter rows
                  dataRowMaxHeight: 44,

                  // ✨ Restored Grid Lines like before
                  border: TableBorder(
                    horizontalInside: BorderSide(color: Colors.grey.shade200, width: 1),
                    verticalInside: BorderSide(color: Colors.grey.shade200, width: 1),
                    bottom: BorderSide.none,
                    top: BorderSide.none,
                    left: BorderSide.none,
                    right: BorderSide.none,
                  ),

                  headingTextStyle: GoogleFonts.poppins(
                    fontSize: 13, // ✨ Smaller
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),

                  dataTextStyle: GoogleFonts.poppins(
                    fontSize: 12.5, // ✨ Smaller
                    color: Colors.black87,
                  ),

                  columns: [
                    const DataColumn(label: Text("Type")),
                    ...sizes.map((s) => DataColumn(label: Text(s))),
                  ],

                  rows: [
                    // Boarding
                    DataRow(
                      cells: [
                        DataCell(Text("Boarding", style: GoogleFonts.poppins(fontWeight: FontWeight.w600))),
                        ...sizes.map((s) => DataCell(_cell(daily[s], dailyOffer[s]))),
                      ],
                    ),
                    // Walking
                    DataRow(
                      cells: [
                        DataCell(Text("Walking", style: GoogleFonts.poppins(fontWeight: FontWeight.w600))),
                        ...sizes.map((s) => DataCell(_cell(walk[s], walkOffer[s]))),
                      ],
                    ),
                    // Meal
                    DataRow(
                      cells: [
                        DataCell(Text("Meal", style: GoogleFonts.poppins(fontWeight: FontWeight.w600))),
                        ...sizes.map((s) => DataCell(_cell(meal[s], mealOffer[s]))),
                      ],
                    ),
                    // ⭐ TOTAL ROW (Kept Yellow)
                    DataRow(
                      color: MaterialStateProperty.all(Colors.yellow.shade100),
                      cells: [
                        DataCell(Text("Total", style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 13))),
                        ...sizes.map((s) {
                          final b = daily[s];
                          final w = walk[s];
                          final m = meal[s];

                          if (b == null || w == null || m == null) {
                            return DataCell(_buildNA());
                          }
                          return DataCell(
                            Text(
                              "₹${b + w + m}",
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.black87,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class PetChipsRow extends StatefulWidget {
  final List<String> pets;
  final String initialSelectedPet;

  const PetChipsRow({
    Key? key,
    required this.pets,
    required this.initialSelectedPet,
  }) : super(key: key);

  @override
  State<PetChipsRow> createState() => _PetChipsRowState();
}

class _PetChipsRowState extends State<PetChipsRow> {
  late String _selectedPet;

  @override
  void initState() {
    super.initState();
    _selectedPet = widget.initialSelectedPet;
  }

  // ✨ ADDED: Update state if the widget rebuilds with new pets
  @override
  void didUpdateWidget(covariant PetChipsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSelectedPet != oldWidget.initialSelectedPet) {
      setState(() {
        _selectedPet = widget.initialSelectedPet;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: widget.pets.map((pet) {
          final isSelected = pet == _selectedPet;
          final displayName =
          pet.isNotEmpty ? pet[0].toUpperCase() + pet.substring(1) : pet;

          return Padding(
            padding: const EdgeInsets.only(right: 10.0),
            child: GestureDetector(
              onTap: () {
                // This widget only manages its visual state
                // The actual logic is handled by PetVarietiesTable
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.primaryColor,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.pets,
                      size: 16,
                      color:  AppColors.primaryColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      displayName,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class PetVarietiesTable extends StatefulWidget {
  final List<String> petDocIds;
  final String? selectedPet;
  final List<String> acceptedSizes;
  final List<String> acceptedBreeds;
  final Function(String?) onPetSelected;

  const PetVarietiesTable({
    Key? key,
    required this.petDocIds,
    required this.selectedPet,
    required this.acceptedSizes,
    required this.acceptedBreeds,
    required this.onPetSelected,
  }) : super(key: key);

  @override
  State<PetVarietiesTable> createState() => _PetVarietiesTableState();
}

class _PetVarietiesTableState extends State<PetVarietiesTable>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _arrowAnimation;
  late AnimationController _blinkController;
  bool _expanded = false;
  String? _currentSelectedPet;

  @override
  void initState() {
    super.initState();
    _currentSelectedPet = widget.selectedPet;

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _arrowAnimation = Tween<double>(begin: 0, end: 0.5).animate(_controller);

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..repeat(reverse: true);
  }

  // ✨ ADDED: Ensure dropdown reflects changes from parent
  @override
  void didUpdateWidget(covariant PetVarietiesTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedPet != oldWidget.selectedPet) {
      setState(() {
        _currentSelectedPet = widget.selectedPet;
      });
    }
  }


  @override
  void dispose() {
    _controller.dispose();
    _blinkController.dispose();
    super.dispose();
  }

  int? extractMinWeight(String size) {
    final regExp = RegExp(r'\((\d+)');
    final match = regExp.firstMatch(size);
    if (match != null && match.groupCount >= 1) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final sizeOrder = {
      'small': 1,
      'medium': 2,
      'large': 3,
      'giant': 4,
    };
    final sortedAcceptedSizes = List<String>.from(widget.acceptedSizes);
    sortedAcceptedSizes.sort((a, b) {
      final keyA = sizeOrder.keys.firstWhere((k) => a.toLowerCase().contains(k), orElse: () => '');
      final keyB = sizeOrder.keys.firstWhere((k) => b.toLowerCase().contains(k), orElse: () => '');

      final orderA = sizeOrder[keyA] ?? 99;
      final orderB = sizeOrder[keyB] ?? 99;

      if (orderA == orderB) {
        return a.compareTo(b);
      }

      return orderA.compareTo(orderB);
    });

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0), // ✨ Match padding
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black87),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.shade300, // subtle bottom line
                  width: 1,
                ),
              ),              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Text(
                  "Pet Sizes & Breeds",
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF2D3436),
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black87),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _currentSelectedPet,
                      items: widget.petDocIds
                          .map(
                            (petId) => DropdownMenuItem(
                          value: petId,
                          child: Text(
                            petId.capitalize(), // ✨ Capitalize
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )
                          .toList(),
                      onChanged: (newPet) {
                        setState(() {
                          _currentSelectedPet = newPet;
                        });
                        widget.onPetSelected(newPet);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                _expanded = !_expanded;
                if (_expanded) {
                  _controller.forward();
                  _blinkController.stop();
                } else {
                  _controller.reverse();
                  _blinkController.repeat(reverse: true);
                }
              });
            },
            child: Container( // ✨ Make tap target larger
              color: Colors.transparent, //
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center, // ✨ Center it
                children: [
                  Text(
                    _expanded ? "Tap to see less" : "Tap to see more",
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 3),
                  FadeTransition(
                    opacity: _expanded
                        ? const AlwaysStoppedAnimation(1.0)
                        : _blinkController,
                    child: RotationTransition(
                      turns: _arrowAnimation,
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        size: 28,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0), // ✨ Give it width
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12.0, 0, 12.0, 12.0), // ✨ Adjust padding
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExpandableChipList(
                    title: 'Accepted Sizes',
                    items: sortedAcceptedSizes,
                    color: AppColors.primaryColor,
                  ),
                  const Divider(height: 24),
                  ExpandableChipList(
                    title: 'Accepted Breeds',
                    items: widget.acceptedBreeds,
                    color: AppColors.accentColor,
                    showSearchBar: widget.acceptedBreeds.length > 10, // ✨ Show search if many
                  ),
                ],
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),

        ],
      ),
    );
  }
}

class ExpandableChipList extends StatefulWidget {
  final String title;
  final List<String> items;
  final Color color;
  final bool showSearchBar;

  const ExpandableChipList({
    Key? key,
    required this.title,
    required this.items,
    required this.color,
    this.showSearchBar = false,
  }) : super(key: key);

  @override
  State<ExpandableChipList> createState() => _ExpandableChipListState();
}

class _ExpandableChipListState extends State<ExpandableChipList> {
  String _searchQuery = '';
  bool _isExpanded = false; // ✨ Add expansion state

  @override
  Widget build(BuildContext context) {
    final filteredItems = widget.items
        .where((item) => item.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    // ✨ Determine which items to show
    final bool isOverflowing = filteredItems.length > 6;
    final itemsToShow = (_isExpanded || !isOverflowing)
        ? filteredItems
        : filteredItems.take(6).toList();


    final wrapWidget = Wrap(
      spacing: 8,
      runSpacing: 6,
      children: itemsToShow // ✨ Use itemsToShow
          .map((item) => Chip(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.black87, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        label: Text(
          item.capitalize(),
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ))
          .toList(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.title,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: widget.color,
              ),
            ),
            if (widget.showSearchBar)
              SizedBox(
                width: 150,
                height: 38,
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: 'Search',
                    isDense: true, // ✨ Make it tighter
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder( // ✨ Add focused border
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: widget.color, width: 1.5),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        if (filteredItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              _searchQuery.isNotEmpty ? "No matches found." : "Not specified.", // ✨
              style: GoogleFonts.poppins(color: Colors.grey, fontSize: 12),
            ),
          )
        else
          wrapWidget, // ✨ This now contains the correct number of items

        // ✨ Show more/less toggle
        if (isOverflowing)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: GestureDetector(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Text(
                _isExpanded ? "Show less" : "Show more... (+${filteredItems.length - 6})",
                style: GoogleFonts.poppins(
                  color: widget.color,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ),

      ],
    );
  }
}

void _showHideConfirmationDialog(
    BuildContext context,
    String serviceId,
    bool isHidden,
    HiddenServicesProvider provider,
    ) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext dialogContext) {
      return Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isHidden ? Icons.refresh_rounded : Icons.block_rounded,
                size: 48,
                color: isHidden ? AppColors.primaryColor : Colors.red.shade700,
              ),
              const SizedBox(height: 20),
              Text(
                isHidden ? 'Make Service Visible?' : 'Hide This Service?',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isHidden
                    ? 'This service will reappear in your search results.'
                    : 'You won\'t see this service in your feed anymore. You can un-hide it later from your account settings.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: Colors.grey.shade700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        provider.toggle(serviceId);
                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.grey.shade800,
                            behavior: SnackBarBehavior.floating,
                            content: Text(
                              isHidden ? 'Service is now visible.' : 'Service has been hidden.',
                              style: GoogleFonts.poppins(color: Colors.white),
                            ),
                            action: SnackBarAction(
                              label: 'Undo',
                              textColor: AppColors.accentColor,
                              onPressed: () => provider.toggle(serviceId),
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isHidden ? AppColors.primaryColor : Colors.red.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(
                        isHidden ? 'Yes, Show' : 'Yes, Hide',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white),
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
class _SimpleMealCard extends StatelessWidget {
  final String mealTitle;
  final Map<String, dynamic> mealData;
  final Function(BuildContext, String, Map<String, dynamic>) onDetailsPressed;

  const _SimpleMealCard({
    Key? key,
    required this.mealTitle,
    required this.mealData,
    required this.onDetailsPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final imageUrl = mealData['image'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,         // ✔ FULL WHITE BG
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04), // soft shadow effect
            blurRadius: 10,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Material(
        color: Colors.white,         // ✔ WHITE MATERIAL (ripple stays clean)
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onDetailsPressed(context, mealTitle, mealData),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              children: [
                // 🍽 White image box
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 82,
                    height: 82,
                    color: Colors.white,     // ✔ WHITE IMAGE BG
                    child: (imageUrl != null && imageUrl.isNotEmpty)
                        ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          Container(color: Colors.white),
                      errorWidget: (context, url, error) =>
                      const Icon(Icons.restaurant_outlined,
                          color: Colors.grey),
                    )
                        : const Icon(Icons.restaurant_outlined,
                        color: Colors.grey, size: 30),
                  ),
                ),

                const SizedBox(width: 16),

                // 📝 Text Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mealTitle.capitalize(),
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),

                      Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            "Tap to see details",
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 4),

                Icon(Icons.chevron_right_rounded,
                    size: 26, color: Colors.grey.shade500),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class FeedingInfoButton extends StatelessWidget {
  final Map<String, Map<String, dynamic>> allFeedingDetails;
  final String? initialSelectedPet;
  final Function(String)? onPetSelected;

  const FeedingInfoButton({
    Key? key,
    required this.allFeedingDetails,
    required this.initialSelectedPet, this.onPetSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: AppColors.primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          minimumSize: const Size(double.infinity, 50),
        ),
        onPressed: () {
          _showFeedingInfoDialog(context, allFeedingDetails, initialSelectedPet, onPetSelected);        },
        icon: const Icon(Icons.restaurant_menu_outlined, color: Colors.white),
        label: Text(
          "View Feeding Information",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  // lib/screens/Boarding/boarding_servicedetailspage.dart -> in FeedingInfoButton

  void _showFeedingInfoDialog(
      BuildContext context, Map<String, Map<String, dynamic>> allFeedingDetails, String? initialSelectedPet,Function(String)? onPetSelected) {
    // Use initialSelectedPet for the *first build* if available, otherwise default to the first pet in the data.
    String selectedPetInDialog = initialSelectedPet ?? allFeedingDetails.keys.first;
    if (!allFeedingDetails.containsKey(selectedPetInDialog)) {
      selectedPetInDialog = allFeedingDetails.keys.first;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // The current pet's feeding details, based on the dialog's state
            final currentFeedingDetails = allFeedingDetails[selectedPetInDialog] ?? {};

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.0),
              ),
              title: Row(
                children: [
                  Icon(Icons.restaurant_menu_outlined, color: AppColors.primaryColor),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      "Feeding Information",
                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 19),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: MediaQuery.of(context).size.height * 0.6,
                child: Column(
                  children: [
                    // --- Pet Selection Dropdown (Only show if multiple pets exist) ---
                    if (allFeedingDetails.length > 1)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedPetInDialog, // Tracks the currently viewed pet
                            isExpanded: true,
                            items: allFeedingDetails.keys.map((petName) {
                              return DropdownMenuItem<String>(
                                value: petName,
                                child: Text(petName.capitalize(),
                                    style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                              );
                            }).toList(),
                            onChanged: (newValue) {
                              if (newValue != null) {
                                // Update the dialog's state to change the pet
                                setState(() {
                                  selectedPetInDialog = newValue;
                                });
                                // ✨ ADDED: Call the parent callback
                                onPetSelected?.call(newValue);
                              }
                            },
                          ),
                        ),
                      ),
                    // --- Dynamic Meal Cards for the Selected Pet ---
                    Expanded(
                      child: _buildFeedingInfo(currentFeedingDetails),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    "Close",
                    style: GoogleFonts.poppins(color: Colors.black87, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
              titlePadding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              insetPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 24.0),
            );
          },
        );
      },
    );
  }

  Widget _buildFeedingInfo(Map<String, dynamic> feedingDetails) {
    if (feedingDetails.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.pets, size: 40, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                "No feeding information available.",
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    const desiredOrder = [
      'Morning Meal (Breakfast)',
      'Afternoon Meal (Lunch)',
      'Evening Meal (Dinner)',
      'Treats',
      'Water Availability',
    ];

    // Sort feeding sections cleanly
    final mealEntries = feedingDetails.entries.toList()
      ..sort((a, b) {
        final aIndex = desiredOrder.indexWhere(
                (name) => name.toLowerCase() == a.key.toLowerCase());
        final bIndex = desiredOrder.indexWhere(
                (name) => name.toLowerCase() == b.key.toLowerCase());
        return (aIndex == -1 ? desiredOrder.length : aIndex)
            .compareTo(bIndex == -1 ? desiredOrder.length : bIndex);
      });

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: mealEntries.length,
      itemBuilder: (context, index) {
        final entry = mealEntries[index];
        final mealData = entry.value as Map<String, dynamic>? ?? {};

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🍽 Section Header
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
              child: Text(
                entry.key,
                style: GoogleFonts.poppins(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ),

            // Meal Card (full white upgraded)
            _SimpleMealCard(
              mealTitle: entry.key,
              mealData: mealData,
              onDetailsPressed: _showMealDetailsDialog,
            ),

            const SizedBox(height: 2),
          ],
        );
      },
    );
  }


  void _showMealDetailsDialog(
      BuildContext context,
      String mealTitle,
      Map<String, dynamic> mealData,
      ) {
    IconData getIcon(String field) {
      switch (field) {
        case 'food_title': return Icons.fastfood_outlined;
        case 'food_type': return Icons.category_outlined;
        case 'brand': return Icons.storefront_outlined;
        case 'ingredients': return Icons.list_alt_rounded;
        case 'quantity_grams': return Icons.scale_outlined;
        case 'feeding_time': return Icons.access_time_filled;
        default: return Icons.info_outline;
      }
    }

    String getLabel(String field) {
      if (field == 'food_title') return "Meal Name";
      return field.replaceAll("_", " ").capitalize();
    }

    // 🔥 Detail row widget with better UI
    Widget detailRow(String label, String value, IconData icon) {
      final isNA = value.isEmpty;

      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: Colors.grey.shade700),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isNA ? "N/A" : value,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: isNA ? Colors.grey.shade500 : Colors.black87,
                      fontStyle: isNA ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final List<Widget> detailWidgets = [];

    mealData.forEach((key, value) {
      if (key == "image") return;

      final cleanValue = (value == null ||
          (value is String && value.trim().isEmpty) ||
          (value is List && value.isEmpty))
          ? ""
          : value is List
          ? value.join(", ")
          : value.toString();

      detailWidgets.add(detailRow(
        getLabel(key),
        cleanValue,
        getIcon(key),
      ));
    });

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🖼️ Image Header
              if (mealData['image'] != null &&
                  (mealData['image'] as String).isNotEmpty)
                CachedNetworkImage(
                  imageUrl: mealData['image'],
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🔥 Title
                    Text(
                      mealTitle.capitalize(),
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Details Body
                    detailWidgets.isEmpty
                        ? Text(
                      "No details available.",
                      style: GoogleFonts.poppins(
                          color: Colors.grey.shade500, fontSize: 13),
                    )
                        : Column(children: detailWidgets),
                  ],
                ),
              ),

              // CLOSE BUTTON
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    "Close",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}


class ServiceShareData {
  final String shopName;
  final String areaName;
  final String documentId;
  final String serviceId;

  final List<String> pets;   // ✅ Add this
  final Map<String, dynamic> preCalculatedStandardPrices; // ✅ Add this

  ServiceShareData({
    required this.shopName,
    required this.areaName,
    required this.documentId,
    required this.serviceId,
    required this.pets,                         // <—
    required this.preCalculatedStandardPrices,  // <—
  });
}
