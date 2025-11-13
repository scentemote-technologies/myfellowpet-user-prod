// lib/screens/Boarding/boarding_servicedetailspage.dart
// ✨ FULLY OPTIMIZED CODE ✨

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../app_colors.dart';
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
    required this.isOfferActive, this.initialSelectedPet, required this.preCalculatedStandardPrices, required this.preCalculatedOfferPrices, required this.otherBranches, required this.isCertified, // ADD THIS

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
  // Pet & rates
  Map<String, String> _ratesDaily = {};
  Map<String, String> _walkingRates = {};
  Map<String, String> _mealRates = {};
  Map<String, String> _offerDailyRates = {};
  Map<String, String> _offerWalkingRates = {};
  Map<String, String> _offerMealRates = {};
  List<String> _petDocIds = []; // store pet document IDs
  String? _selectedPet;

  late Future<Map<String, dynamic>> _dataFuture;

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

  // ✨ OPTIMIZED: This function now fetches all data in parallel
  Future<Map<String, dynamic>> _loadData() async {
    final serviceFuture = FirebaseFirestore.instance
        .collection('users-sp-boarding')
        .doc(widget.documentId)
        .get();

    final petsFuture = _fetchPetPricing(widget.documentId);

    // ✨ ADDED: Fetch ratings at the same time
    final ratingsFuture = fetchRatingStats(widget.documentId);

    // ✨ MODIFIED: Wait for all three futures
    final results = await Future.wait([
      serviceFuture,
      petsFuture,
      ratingsFuture, // ✨
    ]);

    // ✨ MODIFIED: Return all data in a structured map
    return {
      'service': results[0] as DocumentSnapshot,
      'pets': results[1] as List<PetPricing>,
      'ratings': results[2] as Map<String, dynamic>, // ✨
    };
  }


  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
    // ✨ REMOVED redundant _petPricingFuture
    _fetchPetDocIds().then((_) {
      if (_selectedPet != null) {
        _fetchPetDetails(_selectedPet!);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowPetWarning(context);
    });
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


// Note: If you still need GoogleFonts, uncomment the import below and
// replace 'TextStyle' with 'GoogleFonts.poppins(...)' as in your original code.
// import 'package:google_fonts/google_fonts.dart';

  void _showPetWarningDialog(BuildContext context, List<Map<String, String>> rejectedPets) {
    // Define custom brand color
    const Color brandPrimary = AppColors.primaryColor;
    const Color warningColor = Color(0xFFFF0000); // Light Red/Warning tone

    // Use a modern AlertDialog for better adherence to platform standards
    // and a cleaner, white background look.
    showDialog(
      context: context,
      // ---------------------------------------------------
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          // The default AlertDialog has a clean white background and elevation.
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.black87)),
          titlePadding: EdgeInsets.zero,
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16), // Padding for the content column

          // Wrap content in SingleChildScrollView for responsiveness on small screens
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Icon Header
                Container(
                  padding: const EdgeInsets.all(16), // Increased padding for a bolder look
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

                // 2. Title
                Text(
                  "Booking Compatibility Check",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                    // For GoogleFonts: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87),
                  ),
                ),
                const SizedBox(height: 8),

                // 3. Subtitle/Instruction
                Text(
                  "Heads up! Some of your saved pets may not be listed as accepted by this provider. Please confirm with them before finalizing your booking.",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                    height: 1.4,
                    // For GoogleFonts: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600, height: 1.4),
                  ),
                ),
                const SizedBox(height: 24),

                // 4. Separator
                Divider(color: Colors.grey.shade200, height: 1),
                const SizedBox(height: 16),

                // 5. Rejected Pets List (Refined UI)
                // Added a label for clarity
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

                // 6. Action Button (CTA)
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
                // ✨ MODIFIED: Simplified RichText message
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _dataFuture, // Use the new combined future
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: _design.backgroundColor,
            body: const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
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

        // --- Extract data from the new future ---
        final serviceDoc = snapshot.data!['service'] as DocumentSnapshot;
        final allPetPricing = snapshot.data!['pets'] as List<PetPricing>;
        // ✨ NEW: Extract the ratings we fetched
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

        // ✨ MODIFIED: Safely re-check and reset _selectedPet if it's null OR if the current value is no longer valid in the new list.
        if (_selectedPet == null || !_petDocIds.contains(_selectedPet)) {
          _selectedPet = widget.initialSelectedPet ?? (_petDocIds.isNotEmpty ? _petDocIds.first : null);
        }

        print('DEBUG STATE: Selected Pet: $_selectedPet, Available Pet IDs: $_petDocIds');

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

        return Scaffold(
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
                    Positioned(
                      top: 40,
                      left: 15,
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.arrow_back, color: Colors.black),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 40,
                      right: 15,
                      child: Row(
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(
                                    color: AppColors.accentColor.withOpacity(0.4),
                                    width: 1.5,
                                  ),
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.isCertified)
                                      const VerifiedBadge(isCertified: true)
                                    else
                                      const ProfileVerified(),
                                    const SizedBox(width: 8),
                                    // ✨ MODIFIED: Pass the pre-fetched stats
                                    RatingBadge(ratingStats: ratingStats),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          Consumer<FavoritesProvider>(
                            builder: (ctx, favProv, _) {
                              final isLiked = favProv.liked.contains(_serviceId);
                              return Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: IconButton(
                                  icon: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    transitionBuilder: (child, anim) =>
                                        ScaleTransition(scale: anim, child: child),
                                    child: Icon(
                                      isLiked ? Icons.favorite : Icons.favorite_border,
                                      key: ValueKey(isLiked),
                                      color: isLiked ? Colors.red : Colors.grey,
                                    ),
                                  ),
                                  onPressed: () {
                                    favProv.toggle(_serviceId);
                                  },
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Consumer<HiddenServicesProvider>(
                              builder: (context, hideProv, _) {
                                final isHidden = hideProv.hidden.contains(_serviceId);
                                return IconButton(
                                  icon: const Icon(Icons.more_vert, color: Colors.black87),
                                  iconSize: 20,
                                  padding: EdgeInsets.zero,
                                  onPressed: () {
                                    _showHideConfirmationDialog(context, _serviceId, isHidden, hideProv);
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    "Pets We Service",
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2D3436),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: PetChipsRow(
                    pets: widget.pets,
                    initialSelectedPet: widget.pets.isNotEmpty ? widget.pets[0] : "",
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
                PetPricingTable(
                  isOfferActive: widget.isOfferActive,
                  petDocIds: _petDocIds,
                  ratesDaily: allRatesDaily,
                  walkingRates: allWalkingRates,
                  mealRates: allMealRates,
                  offerRatesDaily: allOfferRatesDaily,
                  offerWalkingRates: allOfferWalkingRates,
                  offerMealRates: allOfferMealRates,
                  initialSelectedPet: _selectedPet,
                  // ✨ ADDED: Callback to update the state variable
                  onPetSelected: (newPetId) {
                    if (newPetId != null) {
                      setState(() {
                        _selectedPet = newPetId;
                        // Also update the accepted sizes/breeds for PetVarietiesTable
                        final newPetData = allPetPricing.firstWhere((p) => p.petName == newPetId);
                        _acceptedSizes = newPetData.acceptedSizes;
                        _acceptedBreeds = newPetData.acceptedBreeds;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                const SizedBox(height: 16),
                FeedingInfoButton(
                  allFeedingDetails: allFeedingDetails,
                  initialSelectedPet: _selectedPet,
                  // ✨ ADDED: Callback to update the state variable
                  onPetSelected: (newPetId) {
                    if (newPetId != null) {
                      setState(() {
                        _selectedPet = newPetId;
                        // Also update the accepted sizes/breeds for PetVarietiesTable
                        final newPetData = allPetPricing.firstWhere((p) => p.petName == newPetId);
                        _acceptedSizes = newPetData.acceptedSizes;
                        _acceptedBreeds = newPetData.acceptedBreeds;
                      });
                    }
                  },
                ),
                SizedBox(height: 8),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      _DetailSection(
                        title: "Description",
                        content: _description,
                        design: _design,
                      ),
                      const SizedBox(height: 13),
                      Text(
                        "Gallery",
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF2D3436),
                        ),
                      ),
                      const SizedBox(height: 2),

                      // ✨ OPTIMIZED: Removed FutureBuilder.
                      // Image.network will handle its own loading.
                      if (imageUrls.isNotEmpty)
                        _GalleryGridSection(
                          imageUrls: imageUrls,
                          design: _design,
                        ),

                      const SizedBox(height: 14),
                      if (_features.isNotEmpty)
                        _DetailSection(
                          title: "Features",
                          content: '',
                          design: _design,
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: _features.map((feature) {
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      feature,
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      const SizedBox(height: 14),
                      if (_refundPolicy.isNotEmpty)
                        RefundPolicyChips(
                          refundRates: _refundPolicy,
                          design: _design,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: _ActionFooter(
            design: _design,
            onPressed: () {
              // Capture navigation logic into a single function
              onConfirmNavigation() {
                final selectedPetPricing = allPetPricing.firstWhere((p) => p.petName == _selectedPet);

                final Map<String, int> dailyRatesToPass = (widget.isOfferActive
                    ? selectedPetPricing.offerRatesDaily
                    : selectedPetPricing.ratesDaily)
                    .map((key, value) =>
                    MapEntry(key, int.tryParse(value.toString()) ?? 0));

                final Map<String, int> mealRatesToPass = (widget.isOfferActive
                    ? selectedPetPricing.offerMealRatesDaily
                    : selectedPetPricing.mealRatesDaily)
                    .map((key, value) =>
                    MapEntry(key, int.tryParse(value.toString()) ?? 0));

                final Map<String, int> walkingRatesToPass = (widget.isOfferActive
                    ? selectedPetPricing.offerWalkingRatesDaily
                    : selectedPetPricing.walkingRatesDaily)
                    .map((key, value) =>
                    MapEntry(key, int.tryParse(value.toString()) ?? 0));

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
                      walkingRates: walkingRatesToPass,
                      feedingDetails: feedingDetailsToPass,
                    ),
                  ),
                );
              }

              // Check if a pet is selected and show confirmation dialog
              if (_selectedPet != null) {
                _showBookingConfirmationDialog(
                  context,
                  _selectedPet!.capitalize(), // Pass the capitalized pet type
                  onConfirmNavigation,        // Pass the navigation function to execute on confirm
                );
              } else {
                // Handle case where no pet is selected (shouldn't happen based on previous logic)
                onConfirmNavigation();
              }
            },
          ),
        );
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
        return 'If cancelled more than 2 days before';
      case 'gt_24h':
        return 'If cancelled 1–2 days before';
      case 'gt_12h':
        return 'If cancelled 12–24 hours before';
      case 'gt_4h':
        return 'If cancelled 4–12 hours before';
      case 'lt_4h':
        return 'If cancelled less than 4 hours before';
      default:
        return key;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.refundRates.entries.toList();
    final displayedEntries = _expanded ? entries : entries.take(2).toList();
    final orderMap = {
      'lt_4h': 0,
      'gt_4h': 1,
      'gt_12h': 2,
      'gt_24h': 3,
      'gt_48h': 4,
    };

    final sortedEntries = displayedEntries.toList()
      ..sort((a, b) => orderMap[a.key]!.compareTo(orderMap[b.key]!));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Refund Policy",
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Column(
          children: sortedEntries.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final refund = entry.value;
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Text(
                    '$idx',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      color: widget.design.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_getRefundLabel(refund.key)}: ${refund.value}%',
                      style: GoogleFonts.poppins(
                        color: Colors.black87,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 5),
        if (entries.length > 2)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _expanded = !_expanded;
                  if (!_expanded) _blinkController.repeat(reverse: true);
                  else _blinkController.stop();
                });
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _expanded ? "Tap to see less" : "Tap to see more",
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: widget.design.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  FadeTransition(
                    opacity:
                    _expanded ? const AlwaysStoppedAnimation(1.0) : _blinkController,
                    child: RotationTransition(
                      turns: AlwaysStoppedAnimation(_expanded ? 0.5 : 0),
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        size: 20,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
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
                        Text(
                          '${widget.distanceKm.toStringAsFixed(1)} km away',
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            color: Colors.black87,
                          ),
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
}

// ✨ OPTIMIZED: This is now a "dumb" widget that just displays data
class RatingBadge extends StatelessWidget {
  final Map<String, dynamic> ratingStats;

  const RatingBadge({Key? key, required this.ratingStats}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final stats = ratingStats;
    final avg = (stats['avg'] as double).clamp(0.0, 5.0);
    final count = stats['count'] as int;
    if (count == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, size: 16, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            "${avg.toStringAsFixed(1)}",
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            "(${count})",
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
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
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF2D3436),
          ),
        ),
        const SizedBox(height: 5),
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

class _RatesSection extends StatelessWidget {
  final String title;
  final Map<String, int> rates;
  final Map<String, int> originalRates;
  final DesignConstants design;
  final bool isOfferActive;

  const _RatesSection({
    Key? key,
    required this.title,
    required this.rates,
    required this.design,
    required this.originalRates,
    this.isOfferActive = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                isOfferActive ? "$title" : title,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2D3436),
                ),
              ),
              if (isOfferActive)
                Container(
                  margin: const EdgeInsets.only(left: 8.0),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Offer',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          const Divider(color: Colors.grey),
          const SizedBox(height: 5),
          Column(
            children: rates.entries.map((offerEntry) {
              final originalPrice = originalRates[offerEntry.key];

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      offerEntry.key,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: design.textDark,
                      ),
                    ),
                    Row(
                      children: [
                        if (isOfferActive && originalPrice != null && originalPrice != offerEntry.value)
                          Text(
                            '₹$originalPrice',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade500,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        if (isOfferActive && originalPrice != null && originalPrice != offerEntry.value)
                          const SizedBox(width: 8),
                        Text(
                          '₹${offerEntry.value}',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: design.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
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
      backgroundColor: Colors.black87,
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
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios,
                  color: Colors.white, size: 30),
              onPressed: _previousImage,
            ),
          ),
          Positioned(
            right: 10,
            child: IconButton(
              icon: const Icon(Icons.arrow_forward_ios,
                  color: Colors.white, size: 30),
              onPressed: _nextImage,
            ),
          ),
          Positioned(
            top: 30,
            right: 10,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.of(context).pop(),
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

  Future<void> _showDialog(BuildContext context, String field) async {
    final doc = await FirebaseFirestore.instance
        .collection('settings')
        .doc('testaments')
        .get();

    final message = doc.data()?[field] ?? 'No info available';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        backgroundColor: Colors.white,
        title: Text(
          "MFP Certified",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: AppColors.accentColor,
          ),
        ),
        content: Text(
          message,
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: Colors.grey.shade800,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Close",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
                color: AppColors.accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isCertified) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => _showDialog(context, 'mfp_certified_user_app'),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.accentColor,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.verified,
          color: Colors.white,
          size: 26,
        ),
      ),
    );
  }
}

class ProfileVerified extends StatelessWidget {
  const ProfileVerified({Key? key}) : super(key: key);

  Future<void> _showDialog(BuildContext context, String field) async {
    final doc = await FirebaseFirestore.instance
        .collection('settings')
        .doc('testaments')
        .get();

    final message = doc.data()?[field] ?? 'No info available';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        backgroundColor: Colors.white,
        title: Text(
          "Profile Verified",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: AppColors.primaryColor,
          ),
        ),
        content: Text(
          message,
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: Colors.grey.shade800,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Close",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
                color: AppColors.primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDialog(context, 'profile_verified_user_app'),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.primaryColor,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.check_circle,
          color: Colors.white,
          size: 26,
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
    Key? key,
    required this.isOfferActive,
    required this.petDocIds,
    required this.ratesDaily,
    required this.walkingRates,
    required this.mealRates,
    required this.offerRatesDaily,
    required this.offerWalkingRates,
    required this.offerMealRates,
    this.initialSelectedPet, this.onPetSelected,
  }) : super(key: key);

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

  // ✨ ADDED didUpdateWidget to handle branch switching
  @override
  void didUpdateWidget(covariant PetPricingTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the initial pet changes (e.g., from branch switch)
    // or if the available pets change, reset the state.
    if (oldWidget.initialSelectedPet != widget.initialSelectedPet ||
        !widget.petDocIds.contains(_selectedPet)) {
      setState(() {
        _selectedPet = widget.initialSelectedPet ?? widget.petDocIds.first;
      });
    }
  }

  int _getTotal(int boarding, int walking, int meal) => boarding + walking + meal;

  Widget _buildPriceCell(int standardPrice, int? offerPrice) {
    if (widget.isOfferActive && offerPrice != null && offerPrice != standardPrice) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '₹$standardPrice',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Colors.grey.shade600,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '₹$offerPrice',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
        ],
      );
    }
    return Text(
      '₹$standardPrice',
      style: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✨ SAFETY CHECK: Ensure _selectedPet is valid
    if (!widget.petDocIds.contains(_selectedPet)) {
      if (widget.petDocIds.isNotEmpty) {
        _selectedPet = widget.petDocIds.first;
      } else {
        return Container(child: Text("No pricing data available.")); // Handle no pets
      }
    }

    // ✨ SAFETY CHECK: Ensure maps are not null before accessing keys
    final ratesDailyForPet = widget.ratesDaily[_selectedPet] ?? {};
    final walkingRatesForPet = widget.walkingRates[_selectedPet] ?? {};
    final mealRatesForPet = widget.mealRates[_selectedPet] ?? {};

    final offerRatesDailyForPet = widget.offerRatesDaily[_selectedPet] ?? {};
    final offerWalkingRatesForPet = widget.offerWalkingRates[_selectedPet] ?? {};
    final offerMealRatesForPet = widget.offerMealRates[_selectedPet] ?? {};


    final sizes = {
      ...ratesDailyForPet.keys,
      ...walkingRatesForPet.keys,
      ...mealRatesForPet.keys
    }.toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Price Details",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(width: 25),
                  if (widget.isOfferActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.accentColor, const Color(0xFFD96D0B)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.local_offer, color: Colors.white, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            "SPECIAL OFFER",
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            DataTable(
              columnSpacing: 16,
              headingRowHeight: 36,
              dataRowMinHeight: 38,
              dataRowMaxHeight: 42,
              border: TableBorder(
                horizontalInside: BorderSide(color: Colors.grey.shade300, width: 1),
                verticalInside: BorderSide(color: Colors.grey.shade300, width: 1),
                top: BorderSide(color: Colors.grey.shade400, width: 1),
                bottom: BorderSide(color: Colors.grey.shade400, width: 1),
                left: BorderSide(color: Colors.grey.shade400, width: 1),
                right: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              columns: [
                DataColumn(
                  label: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedPet,
                        items: widget.petDocIds
                            .map((petId) => DropdownMenuItem(
                          value: petId,
                          child: Text(
                            petId.capitalize(), // ✨ Capitalize
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ))
                            .toList(),
                        onChanged: (newPet) {
                          if (newPet != null) {
                            setState(() {
                              _selectedPet = newPet;
                            });
                            // ✨ MODIFIED: Call the parent callback
                            widget.onPetSelected?.call(newPet);
                          }
                        },
                      ),
                    ),
                  ),
                ),
                ...sizes.map(
                      (size) => DataColumn(
                    label: Text(
                      size,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
              rows: [
                DataRow(
                  cells: [
                    DataCell(
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                        child: Text(
                          "Boarding",
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                    ),
                    ...sizes.map((size) {
                      final standard = ratesDailyForPet[size] ?? 0;
                      final offer = offerRatesDailyForPet[size] ?? standard;
                      return DataCell(_buildPriceCell(standard, widget.isOfferActive ? offer : null));
                    }),
                  ],
                ),
                DataRow(
                  cells: [
                    DataCell(
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                        child: Text(
                          "Walking",
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                    ),
                    ...sizes.map((size) {
                      final standard = walkingRatesForPet[size] ?? 0;
                      final offer = offerWalkingRatesForPet[size] ?? standard;
                      return DataCell(_buildPriceCell(standard, widget.isOfferActive ? offer : null));
                    }),
                  ],
                ),
                DataRow(
                  cells: [
                    DataCell(
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                        child: Text(
                          "Meal",
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                    ),
                    ...sizes.map((size) {
                      final standard = mealRatesForPet[size] ?? 0;
                      final offer = offerMealRatesForPet[size] ?? standard;
                      return DataCell(_buildPriceCell(standard, widget.isOfferActive ? offer : null));
                    }),
                  ],
                ),
                DataRow(
                  color: MaterialStateProperty.resolveWith<Color?>(
                        (Set<MaterialState> states) => Colors.yellow.shade100,
                  ),
                  cells: [
                    DataCell(
                      Container(
                        color: Colors.yellow.shade200,
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                        child: Text(
                          "Total",
                          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                    ...sizes.map((size) {
                      final boarding = ratesDailyForPet[size] ?? 0;
                      final walking = walkingRatesForPet[size] ?? 0;
                      final meal = mealRatesForPet[size] ?? 0;
                      final oldTotal = boarding + walking + meal;

                      int? newTotal;
                      if (widget.isOfferActive) {
                        final offerBoarding = offerRatesDailyForPet[size] ?? boarding;
                        final offerWalking = offerWalkingRatesForPet[size] ?? walking;
                        final offerMeal = offerMealRatesForPet[size] ?? meal;
                        newTotal = offerBoarding + offerWalking + offerMeal;
                      }

                      if (widget.isOfferActive && newTotal != null && newTotal != oldTotal) {
                        return DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '₹$oldTotal',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '₹$newTotal',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return DataCell(
                        Text(
                          '₹$oldTotal',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      );
                    }),
                  ],
                ),
              ],
            )
          ],
        ),
      ),
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
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: const BorderRadius.only(
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
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade400),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        onTap: () => onDetailsPressed(context, mealTitle, mealData),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 80,
                  height: 80,
                  color: Colors.grey.shade100,
                  child: (imageUrl != null && imageUrl.isNotEmpty)
                      ? CachedNetworkImage( // ✨ Use CachedNetworkImage
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(color: Colors.grey.shade100),
                    errorWidget: (context, url, error) => const Icon(Icons.restaurant_outlined, color: Colors.grey),
                  )
                      : const Icon(Icons.restaurant_outlined, color: Colors.grey),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      mealTitle.capitalize(),
                      style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Tap to see details",
                      style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
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
        child: Text(
          "No feeding information provided for this pet.",
          style: GoogleFonts.poppins(color: Colors.grey.shade600),
        ),
      );
    }

    const desiredOrder = [
      'Morning Meal (Breakfast)', 'Afternoon Meal (Lunch)', 'Evening Meal (Dinner)', 'Treats', 'Water Availability'
    ];

    final mealEntries = feedingDetails.entries.toList()
      ..sort((a, b) {
        final aIndex = desiredOrder.indexWhere((name) => name.toLowerCase() == a.key.toLowerCase());
        final bIndex = desiredOrder.indexWhere((name) => name.toLowerCase() == b.key.toLowerCase());
        return (aIndex == -1 ? desiredOrder.length : aIndex)
            .compareTo(bIndex == -1 ? desiredOrder.length : bIndex);
      });

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4),
      itemCount: mealEntries.length,
      itemBuilder: (context, index) {
        final entry = mealEntries[index];
        final mealData = entry.value as Map<String, dynamic>? ?? {}; // ✨ Safety check
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

    IconData getIconForDetail(String fieldName) {
      switch (fieldName) {
        case 'food_title': return Icons.label_outline;
        case 'food_type': return Icons.category_outlined;
        case 'brand': return Icons.storefront_outlined;
        case 'ingredients': return Icons.list_alt_outlined;
        case 'quantity_grams': return Icons.scale_outlined;
        case 'feeding_time': return Icons.access_time_outlined;
        default: return Icons.info_outline;
      }
    }

    String getLabel(String fieldName) {
      if (fieldName == 'food_title') return 'Meal Name';
      return fieldName.replaceAll('_', ' ').capitalize();
    }

    for (var entry in mealData.entries) {
      if (entry.key == 'image') continue;
      final value = entry.value;
      final isValueMissing = value == null || (value is String && value.isEmpty) || (value is List && value.isEmpty);
      details.add(Padding(
        padding: const EdgeInsets.only(top: 10.0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(getIconForDetail(entry.key), color: Colors.grey.shade600, size: 18),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(mealTitle.capitalize(), style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (mealData['image'] != null && (mealData['image'] as String).isNotEmpty)
              ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage( // ✨ Use CachedNetworkImage
                    imageUrl: mealData['image'],
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(height: 180, color: Colors.grey.shade200),
                    errorWidget: (context, url, error) => Container(height: 180, color: Colors.grey.shade200, child: Icon(Icons.error)),
                  )
              ),
            if (mealData['image'] != null && (mealData['image'] as String).isNotEmpty) const SizedBox(height: 12),
            ...details.isNotEmpty ? details : [Text("No details to show.", style: GoogleFonts.poppins(color: Colors.grey.shade600))]
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text("Close", style: GoogleFonts.poppins(color: Colors.black87))),
        ],
      ),
    );
  }
}