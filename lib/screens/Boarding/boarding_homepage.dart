// lib/screens/Boarding/boarding_homepage.dart
import 'dart:math';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../app_colors.dart';
import '../../main.dart';
import '../../models/boarding_shop_details.dart';
import '../../preloaders/BoardingCardsForBoardingHomePage.dart';
import '../../preloaders/BoardingCardsProvider.dart';
import '../../preloaders/PetsInfoProvider.dart';
import '../../preloaders/distance_provider.dart';
import '../../preloaders/favorites_provider.dart';
import '../../preloaders/hidden_services_provider.dart';
import '../AppBars/greeting_service.dart';
import '../Search Bars/live_searchbar.dart';
import '../Search Bars/search_bar.dart';
import 'HeaderMedia.dart';
import 'boarding_servicedetailspage.dart';
import 'hidden_boarding_services_page.dart';

// Helper function to calculate distance in km outside of Geolocator
double _distanceBetween(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371; // Radius of earth in km
  final latDistance = (lat2 - lat1) * (pi / 180);
  final lonDistance = (lon2 - lon1) * (pi / 180);
  final a = sin(latDistance / 2) * sin(latDistance / 2) +
      cos(lat1 * (pi / 180)) * cos(lat2 * (pi / 180)) *
          sin(lonDistance / 2) * sin(lonDistance / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return R * c; // Distance in km
}


// 🎯 TOP-LEVEL ISOLATE FUNCTION
// Runs all filter checks in the background to prevent UI blocking.
List<Map<String, dynamic>> _filterCardsInBackground(Map<String, dynamic> payload) {
  // --- 1. Deserialize Inputs (CRUCIAL STEP) ---
  final List<Map<String, dynamic>> cards = payload['cards'].cast<Map<String, dynamic>>();
  final Set<String> hidden = (payload['hidden'] as List<dynamic>).cast<String>().toSet();
  final Set<String> liked = (payload['liked'] as List<dynamic>).cast<String>().toSet();
  final Map<String, double> distances = payload['distances'].cast<String, double>();
  final List<String> selectedPetTypes = (payload['selectedPetTypes'] as List<dynamic>).cast<String>().map((s) => s.toLowerCase()).toSet().toList();

  final double filterMinPrice = payload['selectedPriceRange'][0];
  final double filterMaxPrice = payload['selectedPriceRange'][1];
  final double stateMinPrice = payload['minPrice'];
  final double stateMaxPrice = payload['maxPrice'];
  final String selectedDistanceOption = payload['selectedDistanceOption'];
  final bool showOffersOnly = payload['showOffersOnly'];
  final bool showFavoritesOnly = payload['showFavoritesOnly'];
  final bool showCertifiedOnly = payload['showCertifiedOnly'];
  final Set<String> selectedRunTypes = (payload['selectedRunTypes'] as List<dynamic>).cast<String>().toSet();
  final String searchQuery = payload['searchQuery'].toLowerCase();

  // Availability Data Deserialization
  final List<DateTime> filterDates = (payload['filterDates'] as List<dynamic>).map((s) => DateTime.parse(s.toString())).toList();
  final int filterPetCount = payload['filterPetCount'];

  final Map<String, Map<DateTime, int>> allBookingCounts = (payload['allBookingCounts'] as Map<String, dynamic>).map((sid, dateMap) {
    final Map<DateTime, int> counts = {};
    (dateMap as Map<String, dynamic>).forEach((dateString, count) {
      counts[DateTime.parse(dateString)] = count as int;
    });
    return MapEntry(sid, counts);
  });
  final Map<String, int> serviceMaxAllowed = payload['serviceMaxAllowed'].cast<String, int>();

  // --- 2. Heavy Filtering Logic ---
  final filteredList = cards.where((service) {
    final id = service['service_id']?.toString() ?? '';
    final shopName = service['shopName']?.toString().toLowerCase() ?? '';
    final areaName = service['areaName']?.toString().toLowerCase() ?? '';
    final isOfferActive = service['isOfferActive'] as bool? ?? false;
    final certified = service['mfp_certified'] as bool? ?? false;
    final runType = service['type'] as String? ?? '';
    final serviceMinPrice = (service['min_price'] as num?)?.toDouble() ?? 0.0;
    final serviceMaxPrice = (service['max_price'] as num?)?.toDouble() ?? 0.0;
    final dKm = distances[id] ?? double.infinity;

    // 1. Search Query Filter
    if (searchQuery.isNotEmpty && !shopName.contains(searchQuery) && !areaName.contains(searchQuery)) {
      return false;
    }

    // 2. Hidden Service Filter
    if (hidden.contains(id)) {
      return false;
    }

    // 3. Offer Filter
    if (showOffersOnly && !isOfferActive) {
      return false;
    }

    // 4. Favorites Filter
    if (showFavoritesOnly && !liked.contains(id)) {
      return false;
    }

    // 5. Species Filter
    if (selectedPetTypes.isNotEmpty) {
      final acceptedPetsLower = (service['pets'] as List<dynamic>? ?? [])
          .map((p) => p.toString().toLowerCase())
          .toList();
      if (!selectedPetTypes.any((selectedPet) => acceptedPetsLower.contains(selectedPet))) {
        return false;
      }
    }

    // 6. Price Filter
    if (filterMaxPrice < stateMaxPrice || filterMinPrice > stateMinPrice) {
      final priceMatches = (filterMaxPrice >= serviceMinPrice) && (filterMinPrice <= serviceMaxPrice);
      if (!priceMatches) {
        return false;
      }
    }

    // 7. Distance Filter
    if (selectedDistanceOption.isNotEmpty) {
      final maxKm = double.tryParse(selectedDistanceOption.replaceAll(RegExp(r'[^0-9.]'), '')) ?? double.infinity;
      if (dKm > maxKm) {
        return false;
      }
    }

    // 8. Availability Filter (The GC heavy check)
    if (filterDates.isNotEmpty && filterPetCount > 0) {
      final bookingCounts = allBookingCounts[id] ?? {};
      final maxAllowed = serviceMaxAllowed[id] ?? 0;

      for (final date in filterDates) {
        final usedSlots = bookingCounts[date] ?? 0;
        if (usedSlots + filterPetCount > maxAllowed) {
          return false;
        }
      }
    }

    // 9. Certified & Run Type Filters
    if (showCertifiedOnly && !certified) {
      return false;
    }
    if (selectedRunTypes.isNotEmpty && !selectedRunTypes.contains(runType)) {
      return false;
    }

    return true;
  }).toList();

  return filteredList;
}

// -------------------------------------------------------------------------
// --- TOP LEVEL DIALOGS AND HELPERS (Unchanged functionality) ---
// -------------------------------------------------------------------------

void _showHideConfirmationDialog(
    BuildContext context,
    String serviceId,
    bool isHidden,
    HiddenServicesProvider provider,
    ) {
  showDialog(
    context: context,
    barrierDismissible: true, // Allow dismissing by tapping outside
    builder: (BuildContext dialogContext) {
      return Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Icon
              Icon(
                isHidden ? Icons.refresh_rounded : Icons.block_rounded,
                size: 48,
                color: isHidden ? AppColors.primaryColor : Colors.red.shade700,
              ),
              const SizedBox(height: 20),

              // 2. Title
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

              // 3. Subtitle
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

              // 4. Action Buttons
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
                        // Dismiss the dialog first
                        Navigator.of(dialogContext).pop();

                        // Then, perform the action
                        provider.toggle(serviceId);

                        // And finally, show the SnackBar feedback
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

Gradient _runTypeGradient(String type) {
  // ... (Function code remains the same)
  switch (type) {
    case 'Home Run':
      return LinearGradient(
        colors: [
          const Color(0xFF556B2F),
          const Color(0xFFBADE7D),
        ],
      );
    case 'Business Run':
      return LinearGradient(
        colors: [
          const Color(0xFF4682B4),
          const Color(0xFF7EB6E5),
        ],
      );
    case 'NGO Run':
      return LinearGradient(
        colors: [
          const Color(0xFFFF5252),
          const Color(0xFFFF8A80),
        ],
      );
    case 'Govt Run':
      return LinearGradient(
        colors: [
          const Color(0xFFB0BEC5),
          const Color(0xFF90A4AE),
        ],
      );
    case 'Vet Run':
      return LinearGradient(
        colors: [
          const Color(0xFFCE93D8).withOpacity(0.85),
          const Color(0xFFBA68C8).withOpacity(0.85),
        ],
      );
    default:
      return LinearGradient(colors: [Colors.grey.shade300, Colors.grey.shade400]);
  }
}


String _runTypeLabel(String type) {
  // ... (Function code remains the same)
  switch (type) {
    case 'Home Run':      return 'Home Run';
    case 'Business Run':  return 'Business';
    case 'NGO Run':       return 'NGO';
    case 'Govt Run':      return 'Govt Run';
    case 'Vet Run':       return 'Vet Run';
    default:               return type;
  }
}


Widget _buildInfoRow(String text, IconData icon, Color color) {
  // ... (Widget code remains the same)
  return Row(
    children: [
      Icon(icon, size: 14, color: color), // was 16
      const SizedBox(width: 4),
      Expanded( // ⬅️ makes sure the text uses remaining space
        child: Text(
          text,
          maxLines: 1, // single line only
          overflow: TextOverflow.ellipsis, // show "..." if too long
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade800,
          ),
        ),
      ),
    ],
  );
}

Widget _buildPetChip(String pet) {
  // ... (Widget code remains the same)
  String displayText = pet.isNotEmpty
      ? pet[0].toUpperCase() + pet.substring(1).toLowerCase()
      : '';

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: // In your _buildPetChip widget's decoration
    BoxDecoration(
      color: AppColors.primaryColor.withOpacity(0.1), // Light teal background
      border: Border.all(color: AppColors.primaryColor.withOpacity(0.5)),
      borderRadius: BorderRadius.circular(8),
    ),

    child: Text(
        displayText,
        style: const // And for the chip's text style
        TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600, // Slightly bolder
          color: AppColors.primaryColor, // Teal text
        )
    ),
  );
}

Future<Map<String, dynamic>> fetchRatingStats(String serviceId) async {
  // ... (Function code remains the same)
  final coll = FirebaseFirestore.instance
      .collection('public_review')
      .doc('service_providers')
      .collection('sps')
      .doc(serviceId)
      .collection('reviews');

  final snap = await coll.get();
  // Extract only ratings > 0
  final ratings = snap.docs
      .map((d) => (d.data()['rating'] as num?)?.toDouble() ?? 0.0)
      .where((r) => r > 0)
      .toList();

  final count = ratings.length;
  final avg = count > 0
      ? ratings.reduce((a, b) => a + b) / count
      : 0.0;

  return {
    'avg': avg.clamp(0.0, 5.0),
    'count': count,
  };
}


class PetType {
  final String id;
  final bool display;

  PetType({required this.id, required this.display});
}

class BoardingHomepage extends StatefulWidget {
  final bool initialSearchFocus;
  final Map<String, dynamic>? initialBoardingFilter;

  const BoardingHomepage({
    Key? key,
    this.initialSearchFocus = false,
    this.initialBoardingFilter, // 💡 CORRECTED: Use initialBoardingFilter here.// 💡 ADD THIS LINE to the constructor list
  }) : super(key: key);

  @override
  _BoardingHomepageState createState() => _BoardingHomepageState();
}

class _BoardingHomepageState extends State<BoardingHomepage> with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _locationPermissionDenied = false;
  bool _showOffersOnly = false; // New state variable
  List<String> pets = [];
  final FocusNode _searchFocusNode = FocusNode();

  late TabController _tabController; // ADD THIS LINE

  // ① NEW: store each service’s max_pets_allowed (from the parent doc)
  final Map<String, int> _serviceMaxAllowed = {};

  bool _showCertifiedOnly = false;
  Set<String> _selectedRunTypes = {};

  late String _greeting;
  late String _mediaUrl;

  // No longer needed
  // final TextEditingController _searchController = TextEditingController();

  String _searchQuery = ''; // The state variable for the search query

  // 🎯 NEW STATE FOR ISOLATE FILTERING
  List<Map<String, dynamic>> _filteredServices = [];
  bool _isFiltering = false;

  // 🛠️ MODIFIED: Call _startFiltering() instead of setting state directly
  void _handleSearch(String query) {
    setState(() {
      _searchQuery = query;
      _startFiltering(); // 🚨 Call filtering whenever search changes
    });
  }

  // 🛠️ MODIFIED: Call _startFiltering() inside reset
  void _resetFilters() {
    setState(() {
      _searchQuery = '';
      _showFavoritesOnly = false;
      _selectedPetTypes.clear();
      _selectedDistanceOption = '';
      _selectedPriceRange = RangeValues(_minPrice, _maxPrice);
      _filterPetCount = 0;
      _filterDates.clear();
      _showCertifiedOnly = false;
      _selectedRunTypes.clear();
      _showOffersOnly = false;
      _startFiltering(); // 🚨 Call filtering whenever filters reset
    });
  }

  // 🎯 NEW METHOD: Collects data and initiates the background filter
  void _startFiltering() async {
    // Prevent starting a new filter if one is already running or provider isn't ready
    if (_isFiltering) return;

    final cardsProv = context.read<BoardingCardsProvider>();
    if (!cardsProv.ready) return; // Wait for cards to load

    setState(() => _isFiltering = true);

    final favProv = context.read<FavoritesProvider>();
    final hideProv = context.read<HiddenServicesProvider>();
    final distProv = context.read<DistanceProvider>();

    // Convert DateTime objects to strings for serialization
    final allBookingCountsSerializable = _allBookingCounts.map((sid, dateMap) => MapEntry(
        sid,
        dateMap.map((dt, count) => MapEntry(dt.toIso8601String(), count))
    ));
    final filterDatesStrings = _filterDates.map((d) => d.toIso8601String()).toList();

    // Convert RangeValues to list of doubles
    final selectedPriceRangeList = [_selectedPriceRange.start, _selectedPriceRange.end];

    // 1. Prepare the serializable payload
    final payload = {
      // --- Card & Filter Data ---
      'cards': cardsProv.cards,
      'liked': favProv.liked.toList(),
      'hidden': hideProv.hidden.toList(),
      'distances': distProv.distances,
      'selectedPetTypes': _selectedPetTypes.toList(),
      'selectedPriceRange': selectedPriceRangeList,
      'selectedDistanceOption': _selectedDistanceOption,
      'showOffersOnly': _showOffersOnly,
      'showFavoritesOnly': _showFavoritesOnly,
      'showCertifiedOnly': _showCertifiedOnly,
      'selectedRunTypes': _selectedRunTypes.toList(),
      'searchQuery': _searchQuery,
      'minPrice': _minPrice,
      'maxPrice': _maxPrice,

      // --- Availability Data (Converted to String/Int) ---
      'filterDates': filterDatesStrings,
      'filterPetCount': _filterPetCount,
      'allBookingCounts': allBookingCountsSerializable,
      'serviceMaxAllowed': _serviceMaxAllowed,
    };

    // 2. Execute the heavy lifting in a background isolate
    // We use compute from 'flutter/foundation.dart'
    final List<Map<String, dynamic>> result = await compute(
      _filterCardsInBackground,
      payload,
    );

    // 3. Update the UI state with the result
    if (mounted) {
      setState(() {
        _filteredServices = result;
        _isFiltering = false;
      });
    }
  }


  late Timer _timer;
  late Future<void> _videoInit;
  FilterTab _filterTab = FilterTab.price;

  // ─── New: Price‐range state ──────────────────────────────────
  double _minPrice = 0;
  double _maxPrice = 1000;
  RangeValues _selectedPriceRange = const RangeValues(0, 1000);
  late ScrollController _filterScrollController;

  int _filterPetCount = 0;
  List<DateTime> _filterDates = [];

  bool _priceFilterLoaded = false;

  final List<String> _placeholders = [
    "Multispeciality Hospitals",
    "Vaccines",
    "Best Vets",
    "Pet Clinics",
  ];
  double km = 0.0;

  int _currentIndex = 1;

  void _onTap(int newIndex) {
    if (newIndex == _currentIndex) return;
    setState(() => _currentIndex = newIndex);
  }

  bool _showFavoritesOnly = false;

  String address = '';
  Position? _currentPosition;
  List<PetType> _petTypes = [];
  final ScrollController _drawerScrollController = ScrollController();

  Set<String> _selectedPetTypes = {};
  String _selectedDistanceOption = ''; // New distance filter selection
  bool isLiked = false;
  Set<String> likedServiceIds = {};
  Set<String> _hiddenServiceIds = {};
  final FirebaseAuth _auth = FirebaseAuth.instance;
  double distanceKm = 0.0;

  final List<String> _priceOptions = ['<1000', '3000>=1000', '>3000'];

  List<String> get _petOptions =>
      _petTypes.map((pt) => _capitalize(pt.id)).toList();

  final List<String> _distanceOptions = [
    '<5 km',
    '<10 km',
    '<15 km',
    '>15 km'
  ]; // New filter options

  int _placeholderIndex = 0;

  final ValueNotifier<int> _placeholderNotifier = ValueNotifier<int>(0);

  String _speciesSearchQuery = '';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _loadPriceFilter() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('company_documents')
          .doc('fees')
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;

        // The image you attached shows:
        //   boarding_price_filter: { min: "300", max: "10000" }
        final bpFilter = data['boarding_price_filter'] as Map<String, dynamic>?;

        if (bpFilter != null) {
          // parse min / max as ints
          final minStr = bpFilter['min']?.toString() ?? '0';
          final maxStr = bpFilter['max']?.toString() ?? '0';

          final parsedMin = int.tryParse(minStr) ?? 0;
          final parsedMax = int.tryParse(maxStr) ?? 0;

          if (parsedMax > parsedMin) {
            setState(() {
              _minPrice = parsedMin.toDouble();
              _maxPrice = parsedMax.toDouble();
              _selectedPriceRange = RangeValues(
                _minPrice,
                _maxPrice,
              );
              _priceFilterLoaded = true;
            });
          } else {
            setState(() {
              _minPrice = 0;
              _maxPrice = 0;
              _selectedPriceRange = const RangeValues(0, 0);
              _priceFilterLoaded = false;
            });
          }
        }
      }
    } catch (e) {
      // In case of error, we can leave _priceFilterLoaded as false.
      setState(() {
        _priceFilterLoaded = false;
      });
      debugPrint('Error loading price filter: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final header = Provider.of<HeaderData>(context);
    _greeting = header.greeting;
    _mediaUrl = header.mediaUrl;
    // 🚨 TWEAK: Call filtering here to ensure it runs when providers update (like Distance)

  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // ⬅️ Register observer
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadAllBookingCounts();
    });

    final initialFilter = (widget.initialBoardingFilter as Map<String, dynamic>?);
    if (initialFilter != null && initialFilter.isNotEmpty) {
      final petCount = initialFilter['petCount'] as int? ?? 0;
      final dates = initialFilter['dates'] as List<DateTime>? ?? [];

      if (petCount > 0 && dates.isNotEmpty) {
        // 💡 ACTION: Setting the state variables applies the filter immediately
        // because the main build method depends on these state variables.
        setState(() {
          _filterPetCount = petCount;
          _filterDates = dates;
        });

        // ❌ REMOVED: The following block that opened the dialog is removed:
        // WidgetsBinding.instance.addPostFrameCallback((_) {
        //   _showAvailabilityFilterDialog();
        // });
      }
    }
    // 🚨 FINAL TRIGGER: Start filtering after all initial data is set.


    _tabController = TabController(length: 2, vsync: this);

    _tabController = TabController(length: 2, vsync: this);

    _filterScrollController = ScrollController();

    _loadPriceFilter();
    _fetchCurrentLocation();
    _fetchPetTypes();

    if (widget.initialSearchFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchFocusNode.requestFocus();
      });
    }

    // The listener on _searchController is no longer needed here
    // as the new PetSearchBar widget will manage it and pass the value
    // via the _handleSearch callback.

    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _placeholderIndex = (_placeholderIndex + 1) % _placeholders.length;
      _placeholderNotifier.value = _placeholderIndex;
    });
  }



  Future<void> _fetchPetTypes() async {
    final snap = await _firestore.collection('pet_types').get();
    setState(() {
      _petTypes = snap.docs.map((d) {
        final data = d.data();
        return PetType(
          id: d.id,
          display: (data['display'] ?? false) as bool,
        );
      }).toList();
    });
  }

  // helper to uppercase first letter
  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // In _BoardingHomepageState class

  // In _BoardingHomepageState class



  // lib/screens/Boarding/boarding_homepage.dart

  // lib/screens/Boarding/boarding_homepage.dart

  // lib/screens/Boarding/boarding_homepage.dart

  Future<void> _fetchCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if(mounted) setState(() => _locationPermissionDenied = true);
        _startFiltering(); // 🚨 CORRECT: Call filter even if location is denied
        return;
      }

      // Check if location services are enabled (often a separate failure point)
      bool isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isServiceEnabled) {
        // 💡 NEW: Handle case where permission is granted, but GPS is off
        if(mounted) setState(() => _locationPermissionDenied = true);
        _startFiltering();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      if(mounted) {
        setState(() {
          _currentPosition = position;
          _locationPermissionDenied = false; // Reset the flag on success
        });

        // ✅ CRITICAL: Recalculate and update the DistanceProvider
        context.read<BoardingCardsProvider>().recalculateCardDistances(position);

        // ✨ CRITICAL: Start filtering only after distances are updated.
        _startFiltering();
      }

    } catch (e) {
      // This catches GPS timeouts or platform errors
      if(mounted) setState(() => _locationPermissionDenied = true);
      _startFiltering(); // Still filter the cards, just without distance
      debugPrint('Location Fetch Error: $e'); // Log the actual error
    }
  }

  Future<void> toggleLike(String serviceId) async {
    User? user = _auth.currentUser;
    if (user == null) return;
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
      await userPreferencesRef.set({
        'liked': [serviceId]
      });
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
      await userPreferencesRef.set({
        'liked': [serviceId]
      });
      setState(() {
        isLiked = true;
      });
    }
  }

  void _showWarningDialog({required String message}) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 48, color: Color(0xFF00C2CB)),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF00C2CB)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('OK',
                    style: TextStyle(color: Color(0xFF00C2CB))),
              ),
            ],
          ),
        ),
      ),
    );
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
      await userPreferencesRef
          .set({'hidden': hiddenServices}, SetOptions(merge: true));
    }
    setState(() {
      _hiddenServiceIds.add(serviceId);
    });
    // Show the popup message immediately once service is hidden.
    _showWarningDialog(
      message:
      'This service has been hidden.\nTo un-hide, go to Accounts → Hidden Services.',
    );
  }

  // New method: Distance Filter Dialog.
  Future<void> _showDistanceFilterDialog() async {
    double tempMaxKm = _selectedDistanceOption.isNotEmpty
        ? double.parse(_selectedDistanceOption.replaceAll(' km', ''))
        : 10.0;

    await showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: // ← wrap the entire content in StatefulBuilder
          StatefulBuilder(
            builder: (context, setStateDialog) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white, Color(0xFFF5F3FF)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Radius Filter',
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF4F46E5),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: Colors.grey[600]),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Slider + value
                    Text(
                      '${tempMaxKm.toStringAsFixed(0)} km',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[800],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Slider(
                      min: 1,
                      max: 100,
                      divisions: 99,
                      value: tempMaxKm,
                      label: '${tempMaxKm.toStringAsFixed(0)} km',
                      onChanged: (v) => setStateDialog(() => tempMaxKm = v),
                    ),

                    const SizedBox(height: 24),

                    // Buttons
                    Row(
                      children: [
                        // ─── Default (clears filter) ───────────────────────
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              side: const BorderSide(color: Color(0xFF4F46E5)),
                            ),
                            onPressed: () {
                              // Clear the distance filter and close
                              setState(() => _selectedDistanceOption = '');
                              Navigator.pop(context);
                            },
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Default',
                                  style: GoogleFonts.poppins(
                                    color: const Color(0xFF4F46E5),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(width: 16),

                        // ─── Apply Button ────────────────────────────
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 16, horizontal: 24),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                              // match the flat look of Default
                              alignment: Alignment.center,
                            ),
                            onPressed: () {
                              setState(() => _selectedDistanceOption =
                              '${tempMaxKm.toStringAsFixed(0)} km');
                              Navigator.pop(context);
                            },
                            child: Text(
                              'Apply',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                // white on blue so it’s readable
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _getPriceEmoji(String priceRange) {
    final value = priceRange.toLowerCase();
    if (value.contains('under')) return '💰';
    if (value.contains('-')) return '💸';
    if (value.contains('over')) return '🤑';
    return '₹';
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // When the app resumes (e.g., from settings), re-check the location.
      _fetchCurrentLocation();
    }
  }


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // ⬅️ Unregister observer
    _tabController.dispose();
    _timer.cancel();
    _drawerScrollController.dispose(); // ← dispose the drawer’s controller here
    _placeholderNotifier.dispose();
    _searchFocusNode.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final availabilityActive = _filterPetCount > 0 && _filterDates.isNotEmpty;

    final filteredPetTypes = _petTypes.where((pt) {
      final name = _capitalize(pt.id).toLowerCase();
      return name.contains(_speciesSearchQuery.toLowerCase());
    }).toList();

    return DefaultTabController(
      length: 2, // We have two tabs: Overnight and Day Care
      child:  Scaffold(
        backgroundColor: Color(0xffffffff),
        resizeToAvoidBottomInset: true,

        // ─── Filter Drawer ─────────────────────────────────
        endDrawer: Drawer(
          backgroundColor: Colors.white,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.horizontal(left: Radius.circular(0)),
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ─── HEADER ───────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Filters',
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        IconButton(
                          icon: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey.shade100,
                            ),
                            child: Icon(Icons.close_rounded,
                                size: 22, color: Colors.grey.shade700),
                          ),
                          onPressed: () => Navigator.pop(context),
                          splashRadius: 24,
                        ),
                      ],
                    ),
                  ),
                ),

                // ─── SCROLLABLE CONTENT ───────────────────────────
                Expanded(
                  child: Scrollbar(
                    controller: _filterScrollController,
                    thumbVisibility: true,
                    thickness: 4,
                    radius: const Radius.circular(2),
                    child: ListView(
                      controller: _filterScrollController,
                      primary: false,
                      padding: const EdgeInsets.only(top: 8),
                      physics: const ClampingScrollPhysics(),
                      children: [
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 0, horizontal: 0),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              // ⭐️ REMOVED Favorites Only ListTile
                              ListTile(
                                leading: Icon(Icons.verified_user_outlined, color: _showCertifiedOnly ? const Color(0xFF25ADAD) : Colors.grey.shade700),
                                title: Text(
                                  'MFP Certified Only',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    color: _showCertifiedOnly ? const Color(0xFF25ADAD) : Colors.grey.shade800,
                                  ),
                                ),
                                trailing: Switch(
                                  value: _showCertifiedOnly,
                                  onChanged: (val) => setState(() => _showCertifiedOnly = val),
                                  activeColor: const Color(0xFF25ADAD),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ─ Hidden Services Section ─
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 0),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 0),
                            title: Text(
                              'Hidden Services',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            trailing: Icon(Icons.chevron_right,
                                color: Colors.grey.shade800),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => HiddenServicesPage()),
                              );
                            },
                          ),
                        ),

                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 0, horizontal: 0),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(horizontal: 24),
                            title: Text(
                              'Run Type',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: _selectedRunTypes.isNotEmpty ? const Color(0xFF25ADAD) : Colors.grey.shade800,
                              ),
                            ),
                            trailing: _selectedRunTypes.isNotEmpty
                                ? CircleAvatar(
                              backgroundColor: const Color(0xFF25ADAD),
                              radius: 12,
                              child: Text(
                                _selectedRunTypes.length.toString(),
                                style: GoogleFonts.poppins(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            )
                                : null,
                            childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
                            children: [
                              ...['Home Run', 'Business Run', 'NGO Run', 'Govt Run', 'Vet Run'].map((type) {
                                return CheckboxListTile(
                                  activeColor: const Color(0xFF25ADAD),
                                  title: Text(type, style: GoogleFonts.poppins()),
                                  value: _selectedRunTypes.contains(type),
                                  onChanged: (selected) {
                                    setState(() {
                                      if (selected == true) {
                                        _selectedRunTypes.add(type);
                                      } else {
                                        _selectedRunTypes.remove(type);
                                      }
                                    });
                                  },
                                );
                              }),
                            ],
                          ),
                        ),

                        // ─ Price Section (with dynamic RangeSlider) ─
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 0),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ExpansionTile(
                            tilePadding:
                            const EdgeInsets.symmetric(horizontal: 24),
                            // Show a badge/icon on the right if price range has been modified
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Price',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: (_selectedPriceRange.start.toInt() !=
                                        _minPrice.toInt() ||
                                        _selectedPriceRange.end.toInt() !=
                                            _maxPrice.toInt())
                                        ? const Color(
                                        0xFF25ADAD) // highlight if active
                                        : Colors.grey.shade800,
                                  ),
                                ),
                                if (_selectedPriceRange.start.toInt() !=
                                    _minPrice.toInt() ||
                                    _selectedPriceRange.end.toInt() !=
                                        _maxPrice.toInt())
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF25ADAD),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${_selectedPriceRange.start.toInt()} - ${_selectedPriceRange.end.toInt()}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            childrenPadding:
                            const EdgeInsets.fromLTRB(24, 8, 24, 16),
                            iconColor: const Color(0xFF25ADAD),
                            children: [
                              // Show loader while Firestore fetch is in progress:
                              if (!_priceFilterLoaded)
                                Padding(
                                  padding:
                                  const EdgeInsets.symmetric(vertical: 16.0),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      color: AppColors.primary,
                                    ),
                                  ),
                                )
                              else ...[
                                // Show RangeSlider once min/max are loaded
                                Text(
                                  'Select price range:',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // Display current numeric labels above slider
                                Row(
                                  mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '₹${_minPrice.toInt()}',
                                      style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: Colors.grey.shade700),
                                    ),
                                    Text(
                                      '₹${_maxPrice.toInt()}',
                                      style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: Colors.grey.shade700),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                RangeSlider(
                                  values: _selectedPriceRange,
                                  min: _minPrice.toDouble(),
                                  max: _maxPrice.toDouble(),
                                  divisions:
                                  ((_maxPrice - _minPrice) ~/ 100).toInt(),
                                  // Each tick represents ₹100
                                  labels: RangeLabels(
                                    '₹${_selectedPriceRange.start.toInt()}',
                                    '₹${_selectedPriceRange.end.toInt()}',
                                  ),
                                  activeColor: const Color(0xFF25ADAD),
                                  inactiveColor: Colors.grey.shade300,
                                  onChanged: (newRange) {
                                    setState(() {
                                      _selectedPriceRange = RangeValues(
                                        newRange.start.clamp(_minPrice.toDouble(),
                                            _maxPrice.toDouble()),
                                        newRange.end.clamp(_minPrice.toDouble(),
                                            _maxPrice.toDouble()),
                                      );
                                    });
                                  },
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                                  children: [
                                    // “Clear” button resets to full-range
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(
                                            color: const Color(0xFF25ADAD)
                                                .withOpacity(0.5)),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8, horizontal: 16),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _selectedPriceRange = RangeValues(
                                            _minPrice.toDouble(),
                                            _maxPrice.toDouble(),
                                          );
                                        });
                                      },
                                      child: Text(
                                        'Clear',
                                        style: GoogleFonts.poppins(
                                            color: const Color(0xFF25ADAD)),
                                      ),
                                    ),
                                    // “Apply” closes drawer and keeps the selected range
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF25ADAD),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8, horizontal: 16),
                                      ),
                                      onPressed: () {
                                        // _selectedPriceRange already holds the chosen min/max.
                                        Navigator.pop(
                                            context); // close the drawer
                                      },
                                      child: Text(
                                        'Apply',
                                        style: GoogleFonts.poppins(
                                            color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),

                        // ─ Species Section ─
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 0),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ExpansionTile(
                            tilePadding:
                            const EdgeInsets.symmetric(horizontal: 24),
                            // Show a badge/icon on the right if any species are selected
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Species',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: _selectedPetTypes.isNotEmpty
                                        ? const Color(
                                        0xFF25ADAD) // highlight if active
                                        : Colors.grey.shade800,
                                  ),
                                ),
                                if (_selectedPetTypes.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF25ADAD),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${_selectedPetTypes.length}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            childrenPadding: const EdgeInsets.only(
                                left: 24, right: 24, bottom: 8),
                            iconColor: const Color(0xFF25ADAD),
                            children: [
                              // ─── Search Field ───────────────────────────────
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                child: TextField(
                                  onChanged: (v) =>
                                      setState(() => _speciesSearchQuery = v),
                                  decoration: InputDecoration(
                                    hintText: 'Search species',
                                    prefixIcon: Icon(Icons.search,
                                        color: const Color(0xFF25ADAD)),
                                    filled: true,
                                    fillColor: Colors.white,
                                    isDense: true,
                                    contentPadding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  style: GoogleFonts.poppins(fontSize: 14),
                                ),
                              ),

                              // ─── Filtered List ───────────────────────────────
                              ...filteredPetTypes.map((pt) {
                                final name = _capitalize(pt.id);
                                final available = pt.display;
                                final sel = _selectedPetTypes.contains(name);

                                if (!available) {
                                  return Padding(
                                    padding:
                                    const EdgeInsets.symmetric(vertical: 6.0),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: GoogleFonts.poppins(
                                                fontSize: 15,
                                                color: Colors.grey.shade500),
                                          ),
                                        ),
                                        Chip(
                                          label: Text(
                                            'Coming Soon',
                                            style: GoogleFonts.poppins(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.black, // Teal text
                                            ),
                                          ),
                                          backgroundColor: Colors.white, // White background
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            side: BorderSide(
                                              color: AppColors.primaryColor, // Teal border
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                return CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    name,
                                    style: GoogleFonts.poppins(
                                        fontSize: 15,
                                        color: Colors.grey.shade800),
                                  ),
                                  value: sel,
                                  activeColor: const Color(0xFF25ADAD),
                                  checkColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6)),
                                  side: BorderSide(
                                      color: const Color(0xFF25ADAD)
                                          .withOpacity(0.5)),
                                  onChanged: (_) {
                                    setState(() {
                                      if (sel)
                                        _selectedPetTypes.remove(name);
                                      else
                                        _selectedPetTypes.add(name);
                                    });
                                  },
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                        // ─ New: At Offer Price Section ─
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 0),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                            title: Text(
                              'At Offer Price',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: _showOffersOnly ? const Color(0xFF25ADAD) : Colors.grey.shade800,
                              ),
                            ),
                            trailing: Icon(
                              _showOffersOnly ? Icons.check_box : Icons.check_box_outline_blank,
                              color: _showOffersOnly ? const Color(0xFF25ADAD) : Colors.grey.shade600,
                            ),
                            onTap: () {
                              setState(() {
                                _showOffersOnly = !_showOffersOnly;
                                _startFiltering(); // 🚨 Call filtering when offer filter changes
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ─── FOOTER BUTTONS ───────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade200, width: 1.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      // ─── Clear All ─────────────────────────────────────────
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(
                                color: Colors.grey.shade400, width: 1.2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            _resetFilters(); // _resetFilters calls _startFiltering
                            Navigator.pop(context);
                          },
                          child: Text(
                            'Clear All',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 16),

                      // ─── Apply ────────────────────────────────────────────────
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: const Color(0xFF25ADAD),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                            shadowColor: Colors.transparent,
                          ),
                          onPressed: () {
                            // Close drawer and rely on didChangeDependencies or other triggers
                            _startFiltering(); // 🚨 Call filtering explicitly on apply
                            Navigator.pop(context);
                          },
                          child: Text(
                            'Apply',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ─── Main Content ───────────────────────────────────
        body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [

              // 1) Your existing header
              SliverToBoxAdapter(
                child:           HeaderImageCarousel(),
              ),

              // 3) New Control Row (Filters, Reset, and Availability)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(5, 8, 5, 0),
                  child: Row(
                    children: [
                      // Filter Button
                      Builder(
                          builder: (context) {
                            return OutlinedButton(
                              onPressed: () => Scaffold.of(context).openEndDrawer(),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(42, 42), // Make it square
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                              child: Icon(Icons.filter_list_rounded, size: 20, color: Colors.grey.shade700),
                            );
                          }
                      ),
                      const SizedBox(width: 2),

                      // ⭐️ NEW Favorite Button
                      OutlinedButton(
                        onPressed: () {
                          setState(() => _showFavoritesOnly = !_showFavoritesOnly);
                          _startFiltering(); // 🚨 Call filtering when favorites filter changes
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(42, 42),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          side: BorderSide(color: _showFavoritesOnly ? Colors.red.shade200 : Colors.grey.shade300),
                          backgroundColor: _showFavoritesOnly ? Colors.red.withOpacity(0.05) : Colors.transparent,
                        ),
                        child: Icon(
                          _showFavoritesOnly ? Icons.favorite : Icons.favorite_border_rounded,
                          size: 20,
                          color: _showFavoritesOnly ? Colors.redAccent : Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(width: 2),

                      // RIGHT SIDE: Check Availability button
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final bool isFilterActive = _filterPetCount > 0 && _filterDates.isNotEmpty;
                            return GestureDetector(
                              onTap: () => _showAvailabilityFilterDialog(),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                                width: double.infinity,
                                height: 42, // Set a fixed compact height
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: isFilterActive ? Colors.white : const Color(0xFF25ADAD),
                                  borderRadius: BorderRadius.circular(12),
                                  border: isFilterActive ? Border.all(color: const Color(0xFF25ADAD), width: 1.5) : null,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.08),
                                      blurRadius: 5,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: isFilterActive ? _buildActiveState() : _buildInactiveState(),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 2),
                      OutlinedButton(
                        onPressed: _resetFilters,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(42, 42), // Make it square
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        child: Icon(Icons.restart_alt_rounded, size: 20, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ),
              // 3) NEW: The sticky TabBar
              SliverPersistentHeader(
                delegate: _SliverTabBarDelegate(
                  TabBar(
                    controller: _tabController,
                    labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    unselectedLabelStyle: GoogleFonts.poppins(),
                    labelColor: const Color(0xFF25ADAD),
                    unselectedLabelColor: Colors.grey.shade600,
                    indicatorColor: const Color(0xFF25ADAD),
                    indicatorWeight: 3.0,
                    tabs: const [
                      Tab(text: 'Overnight'),
                      Tab(text: 'Day Care'),
                    ],
                  ),
                ),
                pinned: true, // This makes the tab bar stick to the top when you scroll
              ),
            ],

            // 4) Single ListView content
            // --- CORRECTED CODE FOR TabBarView BUILDER ---
            body: TabBarView(
              controller: _tabController,
              children: [
                Builder(builder: (context) {
                  final cardsProv = context.watch<BoardingCardsProvider>();

                  // 1. --- SHOW LOADING STATE ---
                  // If the provider isn't ready OR the isolate is busy, show spinner.
                  if (!cardsProv.ready || _isFiltering) {
                    print('DEBUG: Showing loading state. Ready: ${cardsProv.ready}, Filtering: $_isFiltering');
                    return const Center(child: CircularProgressIndicator(color: AppColors.primary,));
                  }

                  // 2. --- DETERMINE FINAL DISPLAY LIST ---
                  // Logic to check if any filters are actively applied:
                  final bool filtersAreActive = _searchQuery.isNotEmpty ||
                      _filterPetCount > 0 ||
                      _showFavoritesOnly ||
                      _showCertifiedOnly ||
                      _showOffersOnly ||
                      _selectedRunTypes.isNotEmpty ||
                      _selectedDistanceOption.isNotEmpty ||
                      _selectedPriceRange.start > _minPrice ||
                      _selectedPriceRange.end < _maxPrice;

                  final List<Map<String, dynamic>> displayList;

                  // If no filters were changed, use the full list as the display list will be empty on startup.
                  if (!filtersAreActive && _filteredServices.isEmpty) {
                    displayList = cardsProv.cards;
                  } else {
                    // Otherwise, show the list calculated by the background isolate
                    displayList = _filteredServices;
                  }

                  // 3. --- SHOW EMPTY STATE ---
                  if (displayList.isEmpty) {
                    print('DEBUG: Showing empty state. Total services checked: ${cardsProv.cards.length}');
                    return const Center(child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Text("No services match your current filters. Try clearing some filters."),
                    ));
                  }

                  // 4. --- SHOW FILTERED RESULTS ---
                  print('DEBUG: Displaying ${displayList.length} filtered services.');
                  return ListView(
                    padding: const EdgeInsets.all(8),
                    children: displayList.map((data) => BoardingServiceCard(
                        key: ValueKey(data['id']),
                        service: data,
                        mode: 1
                    )).toList(),
                  );
                }),
                ComingSoonPage()
              ],
            )
        ),
      ),);
  }

  // Add this new method anywhere inside the _BoardingHomepageState class

  void _showInfoDialog(BuildContext context, {required String title, required String content}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(content, style: GoogleFonts.poppins()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _buildInactiveState() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.event_available, size: 18, color: Colors.white),
        const SizedBox(width: 8),
        Text(
          'Check Availability',
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildActiveState() {
    String getDatesSummary() {
      if (_filterDates.isEmpty) return '';
      if (_filterDates.length == 1) return DateFormat('dd MMM').format(_filterDates.first);
      return '${_filterDates.length} days';
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              Icon(Icons.pets, size: 16, color: const Color(0xFF00695C)),
              const SizedBox(width: 4),
              Text(
                '$_filterPetCount Pet${_filterPetCount > 1 ? 's' : ''}',
                style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF00695C)),
              ),
              const VerticalDivider(width: 16, indent: 8, endIndent: 8),
              Icon(Icons.date_range, size: 16, color: const Color(0xFF00695C)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  getDatesSummary(),
                  style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF00695C)),
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
        // Clear button
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: const Icon(Icons.close , size: 20, color: Colors.redAccent),
          onPressed: () {
            setState(() {
              _filterPetCount = 0;
              _filterDates.clear();
            });
          },
        ),
      ],
    );
  }

  // Replace the old method with this one

  Widget _buildFilterDetailChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF25ADAD).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min, // This tells the Row to shrink-wrap its children
        children: [
          Icon(icon, size: 16, color: const Color(0xFF00695C)),
          const SizedBox(width: 8),
          Flexible( // Using Flexible instead of Expanded allows it to take up space but not force an infinite width
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF00695C),
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              softWrap: false, // Prevents wrapping to keep it chip-like
            ),
          ),
        ],
      ),
    );
  }

  Map<String, Map<DateTime, int>> _allBookingCounts = {};


  // lib/screens/Boarding/boarding_homepage.dart

  Future<void> _preloadAllBookingCounts() async {
    // Wait for the provider to be ready before trying to access cards
    final provider = context.read<BoardingCardsProvider>();
    if (!provider.ready) {
      // If not ready, wait a moment and try again.
      await Future.delayed(const Duration(milliseconds: 100));
      _preloadAllBookingCounts();
      return;
    }

    final services = provider.cards;
    if (services.isEmpty) return;

    print("🕵️‍♂️ Preloading availability data for ${services.length} services...");

    // Loop through each service card to fetch its specific availability data
    for (final service in services) {
      final sid = service['service_id'] as String;
      final dateCount = <DateTime, int>{};

      // 1. Fetch the main document to get max_pets_allowed
      final parentSnap = await FirebaseFirestore.instance
          .collection('users-sp-boarding')
          .doc(sid)
          .get();

      if (parentSnap.exists && parentSnap.data() != null) {
        final rawMax = parentSnap.data()!['max_pets_allowed'];
        _serviceMaxAllowed[sid] = int.tryParse(rawMax?.toString() ?? '0') ?? 0;
      } else {
        _serviceMaxAllowed[sid] = 0;
      }

      // 2. Fetch the daily_summary to get booked counts and holidays
      final summarySnap = await FirebaseFirestore.instance
          .collection('users-sp-boarding')
          .doc(sid)
          .collection('daily_summary')
          .get();

      for (final doc in summarySnap.docs) {
        try {
          final date = DateFormat('yyyy-MM-dd').parse(doc.id);
          final dayOnly = DateTime(date.year, date.month, date.day);
          final docData = doc.data();

          final bool isHoliday = docData['isHoliday'] as bool? ?? false;

          if (isHoliday) {
            // If it's a holiday, use our 999 signal
            dateCount[dayOnly] = 999;
          } else {
            // Otherwise, use the actual booked count
            dateCount[dayOnly] = docData['bookedPets'] as int? ?? 0;
          }
        } catch (e) {
          // Ignore malformed doc IDs
        }
      }
      _allBookingCounts[sid] = dateCount;
    }

    // Once all data is fetched, trigger a UI update.
    setState(() {
      print("✅ Preloading complete. Data is ready for filtering.");
    });
  }

  // [REPLACE] your existing _showAvailabilityFilterDialog method with this one.

  Future<void> _showAvailabilityFilterDialog() async {
    final petCountCtl = TextEditingController(
      text: _filterPetCount > 0 ? '$_filterPetCount' : '',
    );
    List<DateTime> tempDates = List.from(_filterDates);

    // NEW: Create a FocusNode to control the keyboard
    final petCountFocusNode = FocusNode();

    await showDialog(
      context: context,
      // Ensure the dialog itself doesn't dismiss when tapping outside the textfield
      barrierDismissible: false,
      builder: (ctx) {
        // Use a StatefulBuilder to manage the internal state of the calendar
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Dialog(
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(dialogContext).viewInsets.bottom),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Availability Filter',
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF25ADAD),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close, color: Colors.grey[600]),
                              // MODIFIED: Close button now unfocuses before popping
                              onPressed: () {
                                petCountFocusNode.unfocus();
                                Navigator.pop(dialogContext);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // "Number of Pets" Field
                        Text(
                          'Number of pets',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),

                        // --- MODIFIED TEXTFIELD ---
                        TextField(
                          controller: petCountCtl,
                          focusNode: petCountFocusNode, // MODIFIED: Assign the FocusNode
                          keyboardType: TextInputType.number,
                          // MODIFIED: Change keyboard action to "Done"
                          textInputAction: TextInputAction.done,
                          // MODIFIED: Hide keyboard when "Done" is pressed
                          onEditingComplete: () => petCountFocusNode.unfocus(),
                          decoration: InputDecoration(
                            hintText: 'Enter the number',
                            border: const OutlineInputBorder(
                              borderRadius: BorderRadius.zero,
                              borderSide: BorderSide(color: Color(0xFF25ADAD)),
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            // NEW: The "tick button" (checkmark icon)
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.check, color: Color(0xFF25ADAD)),
                              onPressed: () {
                                // This is the key part: it dismisses the keyboard
                                petCountFocusNode.unfocus();
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // "Select Dates" Label
                        Text(
                          'Select dates',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Calendar
                        TableCalendar(
                          firstDay: DateTime.now(),
                          lastDay: DateTime.now().add(const Duration(days: 365)),
                          focusedDay: DateTime.now(),
                          selectedDayPredicate: (day) => tempDates.any((d) => isSameDay(d, day)),
                          onDaySelected: (sel, focus) {
                            // This now uses the StatefulBuilder's setState equivalent
                            setDialogState(() {
                              if (tempDates.any((d) => isSameDay(d, sel))) {
                                tempDates.removeWhere((d) => isSameDay(d, sel));
                              } else {
                                tempDates.add(sel);
                              }
                            });
                          },
                          calendarStyle: CalendarStyle(
                            selectedDecoration: const BoxDecoration(
                              color: Color(0xFF25ADAD),
                              shape: BoxShape.rectangle,
                            ),
                            todayDecoration: BoxDecoration(
                              border: Border.all(color: Color(0xFF25ADAD)),
                              shape: BoxShape.rectangle,
                            ),
                            todayTextStyle: const TextStyle(color: Colors.black),
                          ),
                          headerStyle: const HeaderStyle(
                            formatButtonVisible: false,
                            titleCentered: true,
                          ),
                        ),

                        const SizedBox(height: 16),
                        // Clear / Apply Buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: const Color(0xFF25ADAD).withOpacity(0.5)),
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _filterPetCount = 0;
                                    _filterDates.clear();
                                  });
                                  setDialogState(() {
                                    petCountCtl.text = '';
                                    tempDates.clear();
                                  });
                                },
                                child: Text('Clear', style: GoogleFonts.poppins(color: const Color(0xFF25ADAD))),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF25ADAD),
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: () {
                                  final enteredCount = int.tryParse(petCountCtl.text) ?? 0;
                                  if (enteredCount <= 0) {
                                    _showWarningDialog(message: 'Please enter a valid pet count.');
                                    return;
                                  }
                                  if (tempDates.isEmpty) {
                                    _showWarningDialog(message: 'Please select at least one date.');
                                    return;
                                  }
                                  setState(() {
                                    _filterPetCount = enteredCount;
                                    _filterDates = List.from(tempDates);
                                  });
                                  Navigator.pop(dialogContext);
                                },
                                child: Text('Apply', style: GoogleFonts.poppins(color: Colors.white)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    // After dialog closes and setState runs:
    if (_filterPetCount > 0 || _filterDates.isNotEmpty) {
      // We only need to check if the filter was used at all
      _startFiltering(); // 🚨 Re-filter after applying availability dates
    }

    // NEW: Important cleanup to prevent memory leaks
    petCountFocusNode.dispose();
  }
}

// boarding_homepage.dart (add this to the bottom of the file)

// A separate class to hold the data needed by the isolate
class IsolateData {
  final List<Map<String, dynamic>> services;
  IsolateData(this.services);
}

// The top-level function to run in the isolate. It MUST be static or top-level.
// lib/screens/Boarding/boarding_homepage.dart

// The top-level function to run in the isolate.
// lib/screens/Boarding/boarding_homepage.dart

// Replace your _computeBookingCounts function with this one

Future<Map<String, Map<DateTime, int>>> _computeBookingCounts(IsolateData data) async {
  final allBookingCounts = <String, Map<DateTime, int>>{};

  for (final service in data.services) {
    final sid = service['service_id'] as String;
    final dateCount = <DateTime, int>{};

    final summarySnap = await FirebaseFirestore.instance
        .collection('users-sp-boarding')
        .doc(sid)
        .collection('daily_summary')
        .get();

    // === START DEBUG PRINT #1 ===
    print("--- [ISOLATE TRACE for ${service['shopName']}] Found ${summarySnap.docs.length} summary docs.");
    // === END DEBUG PRINT #1 ===

    for (final doc in summarySnap.docs) {
      try {
        final date = DateFormat('yyyy-MM-dd').parse(doc.id);
        final dayOnly = DateTime(date.year, date.month, date.day);
        final docData = doc.data();

        final bool isHoliday = docData['isHoliday'] as bool? ?? false;

        if (isHoliday) {
          // === START DEBUG PRINT #1 ===
          print("--- [ISOLATE TRACE for ${service['shopName']}] 👉 HOLIDAY FOUND for ${doc.id}. Setting slots to 999.");
          // === END DEBUG PRINT #1 ===
          dateCount[dayOnly] = 999;
        } else {
          final bookedPets = docData['bookedPets'] as int? ?? 0;
          dateCount[dayOnly] = bookedPets;
        }

      } catch (e) {
        print('Could not parse date from summary document ID: ${doc.id}');
      }
    }

    allBookingCounts[sid] = dateCount;
  }
  return allBookingCounts;
}



class RunTypeFilterDialog extends StatefulWidget {
  final Set<String> selected;
  const RunTypeFilterDialog({ Key? key, required this.selected }) : super(key: key);

  @override
  _RunTypeFilterDialogState createState() => _RunTypeFilterDialogState();
}

class _RunTypeFilterDialogState extends State<RunTypeFilterDialog> {
  late Set<String> _tempSelected;
  static const _allTypes = [
    'Home Run',
    'Business Run',
    'NGO Run',
    'Govt Run',
    'Vet Run',
  ];


  @override
  void initState() {
    super.initState();
    _tempSelected = Set.from(widget.selected);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text(
        'Filter by Run Type',
        style: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      content: SingleChildScrollView(
        child: ListBody(
          children: _allTypes.map((type) {
            final isSelected = _tempSelected.contains(type);
            return CheckboxListTile(
              activeColor: AppColors.primaryColor,
              checkColor: Colors.white,
              value: isSelected,
              title: Text(
                type,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? AppColors.primaryColor : Colors.black87,
                ),
              ),
              onChanged: (checked) {
                setState(() {
                  if (checked == true) _tempSelected.add(type);
                  else                 _tempSelected.remove(type);
                });
              },
            );
          }).toList(),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          onPressed: () => Navigator.pop(context, widget.selected),
          child: Text(
            'CANCEL',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryColor,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () => Navigator.pop(context, _tempSelected),
          child: Text(
            'APPLY',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

}

class PulsingCard extends StatefulWidget {
  final bool isPulsing;
  final Widget child;

  const PulsingCard({
    Key? key,
    required this.isPulsing,
    required this.child,
  }) : super(key: key);

  @override
  _PulsingCardState createState() => _PulsingCardState();
}

class _PulsingCardState extends State<PulsingCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _animation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.isPulsing) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(PulsingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPulsing != oldWidget.isPulsing) {
      if (widget.isPulsing) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.animateTo(0.0); // Reset to the beginning (scale 1.0)
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: widget.child,
    );
  }
}

class BoardingServiceCard extends StatefulWidget {
  final Map<String, dynamic> service;
  final int mode;

  const BoardingServiceCard({
    Key? key,
    required this.service,
    this.mode = 1,
  }) : super(key: key);

  @override
  State<BoardingServiceCard> createState() => _BoardingServiceCardState();
}

class _BoardingServiceCardState extends State<BoardingServiceCard> {
  String? _selectedPet;
  List<Map<String, String>> _branchOptions = [];
  bool _isLoadingBranches = true;
  bool _isSwitchingBranch = false;

  @override
  void initState() {
    super.initState();
    _initializeCardState(widget.service);
  }

  @override
  void didUpdateWidget(covariant BoardingServiceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.service['id'] != oldWidget.service['id']) {
      _initializeCardState(widget.service);
    }
  }

  void _initializeCardState(Map<String, dynamic> serviceData) {
    setState(() {
      _isLoadingBranches = true;
      _initializePetSelection(serviceData);
    });
    _fetchBranchDetails(serviceData);
  }
  bool _needsWarning(BuildContext context) {
    // 1. Check if the user's pets are loaded.
    final userPets = context.read<PetProvider>().pets;
    print('DEBUG T1: Total User Pets Loaded: ${userPets.length}');

    // 2. Check what the service provider accepts.
    final acceptedTypes = (widget.service['pets'] as List<dynamic>? ?? [])
        .map((p) => p.toString().toLowerCase()).toSet();
    print('DEBUG T1: Service ID: ${widget.service['service_id']} accepts: ${acceptedTypes.join(', ')}');

    if (userPets.isEmpty) return false;

    // 3. Check for each user pet if it is rejected.
    final unacceptedCount = userPets.where((pet) {
      final petType = pet['pet_type']?.toString().toLowerCase() ?? 'type_missing';
      final isRejected = !acceptedTypes.contains(petType);

      if (isRejected) {
        print('DEBUG T1: ❌ REJECTED PET FOUND: ${pet['name']} (Type: $petType)');
      }
      return isRejected;
    }).length;

    // 4. Final outcome.
    print('DEBUG T1: Final Warning Status: ${unacceptedCount > 0}');
    return unacceptedCount > 0;
  }

  void _initializePetSelection(Map<String, dynamic> serviceData) {
    final standardPrices =
    Map<String, dynamic>.from(serviceData['pre_calculated_standard_prices'] ?? {});
    if (standardPrices.isEmpty) {
      _selectedPet = null;
      return;
    }
    final userMajorityPet = context.read<BoardingCardsProvider>().majorityPetType;    _selectedPet = (userMajorityPet != null &&
        standardPrices.containsKey(userMajorityPet))
        ? userMajorityPet
        : standardPrices.keys.first;
  }

  Future<void> _fetchBranchDetails(Map<String, dynamic> serviceData) async {
    final otherBranchIds =
    List<String>.from(serviceData['other_branches'] ?? []);
    final currentBranchId = serviceData['id'].toString();
    final currentBranchName = serviceData['areaName'].toString();
    _branchOptions = [{'id': currentBranchId, 'areaName': currentBranchName}];

    if (otherBranchIds.isNotEmpty) {
      final futures = otherBranchIds
          .map((id) => FirebaseFirestore.instance
          .collection('users-sp-boarding')
          .doc(id)
          .get())
          .toList();
      final results = await Future.wait(futures);
      for (var doc in results) {
        if (doc.exists) {
          _branchOptions.add(
              {'id': doc.id, 'areaName': doc.data()?['area_name'] ?? 'Unknown'});
        }
      }
    }
    if (mounted) setState(() => _isLoadingBranches = false);
  }

  Future<void> _switchBranch(String? newBranchId) async {
    if (newBranchId == null || newBranchId == widget.service['id']) return;
    setState(() => _isSwitchingBranch = true);

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users-sp-boarding')
          .doc(newBranchId)
          .get();
      if (doc.exists && mounted) {
        // ... (all the logic to build fullNewData is correct) ...
        final newData = doc.data()!;
        final distances = context.read<DistanceProvider>().distances;
        final standardPrices = Map<String, dynamic>.from(newData['pre_calculated_standard_prices'] ?? {});
        final offerPrices = Map<String, dynamic>.from(newData['pre_calculated_offer_prices'] ?? {});
        final List<num> allPrices = [];
        standardPrices.values.forEach((petPrices) {
          allPrices.addAll((petPrices as Map).values.map((price) => _safeParseDouble(price)));
        });
        offerPrices.values.forEach((petPrices) {
          allPrices.addAll((petPrices as Map).values.map((price) => _safeParseDouble(price)));
        });
        final minPrice = allPrices.isNotEmpty ? allPrices.reduce(min).toDouble() : 0.0;
        final maxPrice = allPrices.isNotEmpty ? allPrices.reduce(max).toDouble() : 0.0;

        final fullNewData = {
          ...newData,
          'id': doc.id,
          'service_id': newData['service_id'] ?? doc.id,
          'shopName': newData['shop_name'] ?? '',
          'shop_image': newData['shop_logo'] ?? '',
          'areaName': newData['area_name'] ?? '',
          'distance': distances[newBranchId] ?? double.infinity,
          'min_price': minPrice,
          'max_price': maxPrice,
          'other_branches': [
            widget.service['id'],
            ...List<String>.from(widget.service['other_branches'] ?? []).where((id) => id != newBranchId),
          ],
        };

        // ✅ FIX: The `preservePosition` flag is no longer needed here.
        context.read<BoardingCardsProvider>().replaceService(
          widget.service['id'],
          fullNewData,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isSwitchingBranch = false);
      print("Error switching branch: $e");
    }
  }


  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final documentId = service['id']?.toString() ?? '';
    final serviceId = service['service_id']?.toString() ?? '';
    final shopName = service['shopName']?.toString() ?? 'Unknown Shop';
    final shopImage = service['shop_image']?.toString() ?? '';
    final standardPricesMap = Map<String, dynamic>.from(service['pre_calculated_standard_prices'] ?? {});
    final offerPricesMap = Map<String, dynamic>.from(service['pre_calculated_offer_prices'] ?? {});

    final runType = service['type'] as String? ?? '';
    final isOfferActive = service['isOfferActive'] as bool? ?? false;
    final petList = List<String>.from(service['pets'] ?? []);
    final dKm = service['distance'] as double? ?? 0.0;
    final isCertified = service['mfp_certified'] as bool? ?? false;
    final otherBranches = List<String>.from(service['other_branches'] ?? []);

    final isProfileVerified = !isCertified && (service['profile_verified'] as bool? ?? false);


    return Stack(
      children: [
        Card(
          color: Colors.white,

          margin: const EdgeInsets.fromLTRB(2, 0, 2, 12),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
            side: isOfferActive
                ? const BorderSide(color: Colors.black87, width: 1.0)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BoardingServiceDetailPage(
                    mode: widget.mode.toString(),
                    pets: petList,
                    documentId: documentId,
                    shopName: shopName,
                    shopImage: shopImage,
                    areaName: service['areaName']?.toString() ?? '',
                    distanceKm: dKm,
                    rates: const {},
                    otherBranches: List<String>.from(service['other_branches'] ?? []),
                    isOfferActive: isOfferActive,
                    isCertified: isCertified,
                    initialSelectedPet: _selectedPet,
                    preCalculatedStandardPrices: standardPricesMap,
                    preCalculatedOfferPrices: offerPricesMap,
                  ),
                ),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                Container(
                  padding: isOfferActive ? const EdgeInsets.all(8.0) : EdgeInsets.zero,
                  color: Colors.white,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          Material(
                            elevation: 3,
                            borderRadius: BorderRadius.circular(12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 110,
                                height: 140,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.grey.shade200),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Image.network(
                                  shopImage,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(Icons.image_not_supported,
                                        color: Colors.grey),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // bottom gradient (runType)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 22,
                              decoration: BoxDecoration(
                                gradient: _runTypeGradient(runType),
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(12),
                                  bottomRight: Radius.circular(12),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  _runTypeLabel(runType),
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // favorite button (stays on image)
                          Positioned(
                            top: 2,
                            right: 0,
                            child: Consumer<FavoritesProvider>(
                              builder: (_, favProv, __) {
                                final isLiked = favProv.liked.contains(serviceId);
                                return Container(
                                  height: 28,
                                  width: 28,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                  ),
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    onPressed: () => favProv.toggle(serviceId),
                                    icon: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 300),
                                      transitionBuilder: (c, a) =>
                                          ScaleTransition(scale: a, child: c),
                                      child: Icon(
                                        isLiked
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        key: ValueKey(isLiked),
                                        size: 16,
                                        color: isLiked
                                            ? const Color(0xFFFF5B20)
                                            : Colors.grey,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                        ],
                      ),
                      // ===== RIGHT SIDE DETAILS =====
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 0, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [

                              Text(
                                // Truncate the shopName to 12 characters if it's longer, then add '...'
                                shopName.length > 12
                                    ? '${shopName.substring(0, 12)}...'
                                    : shopName,
                                // --- END TWEAK ---
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87, // optional for consistency
                                ),
                                overflow: TextOverflow.ellipsis, // Use ellipsis for safety, though the truncation handles it
                                maxLines: 1, // Ensure it stays on one line
                              ),


                              FutureBuilder<Map<String, dynamic>>(
                                future: fetchRatingStats(serviceId),
                                builder: (ctx, snap) {
                                  if (!snap.hasData) {
                                    return const SizedBox(height: 20);
                                  }

                                  final avg = (snap.data!['avg'] as double?) ?? 0.0;
                                  final count = (snap.data!['count'] as int?) ?? 0;

                                  if (count == 0) return const SizedBox.shrink();

                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.center, // ✅ keeps everything visually centered
                                    children: [
                                      // ⭐ Stars Row
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: List.generate(
                                          5,
                                              (i) => Padding(
                                            padding: const EdgeInsets.only(right: 2.0),
                                            child: Icon(
                                              i < avg.round() ? Icons.star_rounded : Icons.star_border_rounded,
                                              size: 16,
                                              color: Colors.amber,
                                            ),
                                          ),
                                        ),
                                      ),

                                      const SizedBox(width: 6),

                                      // 🔢 Rating text
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                            avg.toStringAsFixed(1),
                                            style: GoogleFonts.poppins(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black87,
                                              height: 1.0,
                                            ),
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            '($count)',
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.black54,
                                              height: 1.0,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),

                              SizedBox(height: 2),
                              PriceAndPetSelector(
                                standardPrices: standardPricesMap,
                                offerPrices: offerPricesMap,
                                isOfferActive: isOfferActive,
                                initialSelectedPet: _selectedPet,
                                onPetSelected: (pet) {
                                  setState(() {
                                    _selectedPet = pet;
                                  });
                                },
                              ),
                              BranchSelector(
                                currentServiceId: serviceId,
                                currentAreaName: service['areaName']?.toString() ?? '',
                                otherBranches: List<String>.from(service['other_branches'] ?? []),
                                onBranchSelected: _switchBranch,
                              ),                                  SizedBox(height: 2),
                              // if (!_isLoadingBranches) _buildBranchSelector(),
                              SizedBox(height: 2),
                              SizedBox(
                                height: 25,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: petList
                                      .map((pet) => Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: _buildPetChip(pet),
                                  ))
                                      .toList(),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                // dKm is 0.0 if not fetched, and double.infinity if error/no location
                                dKm.isInfinite || dKm == 0.0 // Check for both
                                    ? 'Location services disabled. Enable to view'
                                    : '${dKm.toStringAsFixed(1)} km away',
                                style: const TextStyle(fontSize: 9),
                              ),
                            ],
                          ),
                        ),
                      ),



                      // --- 🛠️ MODIFICATION 3: MORE_VERT MENU (FIXED) ---

                    ],
                  ),
                ),




                if (_needsWarning(context))
                  _buildPetWarningBanner(context),

                if (isOfferActive)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.accentColor, const Color(0xFFD96D0B)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.local_offer,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'SPECIAL OFFER',
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
        ),
        // --- 🛠️ MODIFICATION 2: Verified/Profile Verified Badges ---
        Positioned(
          top: 0,
          right: 2,
          child: isCertified
              ? const VerifiedBadgeInner(isCertified: true)
              : const ProfileVerifiedInner()
        ),
        Positioned(
          bottom: 14,
          right: 0,
          child: _FloatingMenuContainer(serviceId: serviceId),

        ),
        // --- REMOVED: The outer Positioned element is gone ---
        // We rely on the inner Stack for the badge and the main Row for the menu button.
      ],
    );
  }

  // 🛠️ NEW WIDGET: Replaces the outer Positioned more_vert menu
  Widget _FloatingMenuContainer({required String serviceId}) {
    return Container(
      margin: const EdgeInsets.only(top: 2, right: 2),
      height: 32,
      width: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Consumer<HiddenServicesProvider>(
        builder: (context, hideProv, _) {
          final isHidden = hideProv.hidden.contains(serviceId);
          return IconButton(
            padding: EdgeInsets.zero,
            iconSize: 18,
            icon: const Icon(
              Icons.more_vert,
              color: Colors.black87,
            ),
            onPressed: () {
              _showHideConfirmationDialog(context, serviceId, isHidden, hideProv);
            },
          );
        },
      ),
    );
  }


  // lib/screens/Boarding/boarding_homepage.dart

  Widget _buildPetWarningBanner(BuildContext context) {
    // Use amber text/icon on a very light, subtle background
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // Increased padding for a cleaner look
      decoration: BoxDecoration(
        // 🚨 TWEAK 1: Lighter background and no border
        color: Colors.orange.withOpacity(0.08),
        // 🚨 TWEAK 2: Only round the bottom corners to match the card shape
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      // 🚨 TWEAK 3: Increased font size and improved color contrast
      child: Row(
        children: [
          Icon(Icons.pets, size: 18, color: Colors.orange.shade700), // More relevant icon
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Pet Compatibility Check. Tap for details.', // Shorter, clearer message
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade900,
              ),
            ),
          ),
          const Icon(Icons.info_outline, size: 16, color: Colors.orange),
        ],
      ),
    );
  }
// Place this method inside your State class (e.g., _BoardingHomepageState)

// In _BoardingServiceCardState class
}

double _safeParseDouble(dynamic value) {
  return double.tryParse(value?.toString() ?? '0') ?? 0.0;
}

// -------------------------------------------------------------------------
// --- INNER BADGE WIDGETS (POSITIONED INSIDE IMAGE STACK) ---
// -------------------------------------------------------------------------

class VerifiedBadgeInner extends StatelessWidget {
  final bool isCertified;
  const VerifiedBadgeInner({Key? key, required this.isCertified}) : super(key: key);

  Future<void> _showDialog(BuildContext context, String field) async {
    final doc = await FirebaseFirestore.instance
        .collection('settings')
        .doc('testaments')
        .get();

    final message = doc.data()?[field] ?? 'No info available';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("MFP Certified", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.accentColor)),
        content: Text(message, style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade800)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Close", style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: AppColors.accentColor))),
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
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.accentColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(5),
              topRight: Radius.circular(5),
              bottomLeft: Radius.circular(5),
            ),
          ),

          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Text("Certified", style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 0.3)),
            ],
          ),
        ),
    );
  }
}

class ProfileVerifiedInner extends StatelessWidget {
  const ProfileVerifiedInner({Key? key}) : super(key: key);

  Future<void> _showDialog(BuildContext context, String field) async {
    final doc = await FirebaseFirestore.instance
        .collection('settings')
        .doc('testaments')
        .get();

    final message = doc.data()?[field] ?? 'No info available';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("Profile Verified", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.primaryColor)),
        content: Text(message, style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade800)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Close", style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: AppColors.primaryColor))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: () => _showDialog(context, 'profile_verified_user_app'),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
          decoration: BoxDecoration(
            color: AppColors.primaryColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(5),
              topRight: Radius.circular(5),
              bottomLeft: Radius.circular(5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Text("Verified", style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 0.3)),
            ],
          ),
        ),
    );
  }
}
// -------------------------------------------------------------------------
// --- REST OF HELPERS (UNCHANGED) ---
// -------------------------------------------------------------------------

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  // ... (Class code remains the same)
  _SliverTabBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white, // Or your desired background color for the tab bar
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return false;
  }
}

class ComingSoonPage extends StatefulWidget {
  // ... (Class code remains the same)
  const ComingSoonPage({super.key});

  @override
  State<ComingSoonPage> createState() => _ComingSoonPageState();
}

class _ComingSoonPageState extends State<ComingSoonPage> with SingleTickerProviderStateMixin {
  // ... (Class code remains the same)
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // Subtle gradient background for a modern feel
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              const Color(0xFF25ADAD).withOpacity(0.08),
            ],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title with Poppins font
                  Text(
                    "Daycare Centers Coming Soon",
                    style: GoogleFonts.poppins(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800,
                      height: 1.3,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 16),

                  // Extra description
                  Text(
                    "We're busy setting up a network of safe and fun daycare centers for your beloved pets. Stay tuned!",
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 40),

                  // A "Notify Me" button instead of a progress indicator
                  ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.grey.shade800,
                          content: Text(
                            "Great! We'll notify you as soon as it's available.",
                            style: GoogleFonts.poppins(color: Colors.white),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.notifications_active_outlined, size: 20,color: Colors.white,),
                    label: Text(
                      "Notify Me",
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFF25ADAD),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum FilterTab { price, species }


class PriceAndPetSelector extends StatefulWidget {
  final Map<String, dynamic> standardPrices;
  final Map<String, dynamic> offerPrices;
  final bool isOfferActive;
  final String? initialSelectedPet;
  final Function(String) onPetSelected; // Callback

  const PriceAndPetSelector({
    Key? key,
    required this.standardPrices,
    required this.offerPrices,
    required this.isOfferActive,
    this.initialSelectedPet,
    required this.onPetSelected,
  }) : super(key: key);

  @override
  _PriceAndPetSelectorState createState() => _PriceAndPetSelectorState();
}

class _PriceAndPetSelectorState extends State<PriceAndPetSelector> {
  String? _selectedPet;

  @override
  void initState() {
    super.initState();
    _selectedPet = widget.initialSelectedPet;
  }

  @override
  void didUpdateWidget(covariant PriceAndPetSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSelectedPet != oldWidget.initialSelectedPet) {
      setState(() {
        _selectedPet = widget.initialSelectedPet;
      });
    }
  }

  Widget _buildPetSelector() {
    final standardPrices = Map<String, dynamic>.from(widget.standardPrices);
    final availablePets = standardPrices.keys.toList();
    if (availablePets.isEmpty) return const SizedBox.shrink();

    String capitalize(String s) =>
        s.isNotEmpty ? '${s[0].toUpperCase()}${s.substring(1)}' : s;

    return PopupMenuButton<String>(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (pet) {
        setState(() => _selectedPet = pet);
        widget.onPetSelected(pet);
      },
      itemBuilder: (context) => availablePets
          .map((pet) => PopupMenuItem<String>(
        value: pet,
        child: Text(
          capitalize(pet),
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
          color: Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _selectedPet != null ? capitalize(_selectedPet!) : 'Pet',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 16, color: Colors.teal),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceDisplay(bool isOfferActive) {
    if (_selectedPet == null) {
      return const Text(
        'Pricing not available',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );
    }

    final standardPrices = Map<String, dynamic>.from(widget.standardPrices);
    final offerPrices = Map<String, dynamic>.from(widget.offerPrices);

    final ratesSource = (isOfferActive && offerPrices.containsKey(_selectedPet))
        ? Map<String, num>.from(offerPrices[_selectedPet])
        : Map<String, num>.from(standardPrices[_selectedPet] ?? {});

    if (ratesSource.isEmpty) {
      return const Text(
        'No price set',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );
    }
    // --- MODIFICATION START: Logic to find the effective minimum price ---
    final allPrices = ratesSource.values.toList();

    // Sort prices to find the smallest non-zero one
    allPrices.sort((a, b) => a.compareTo(b));

    // Find the smallest non-zero price
    num minPrice = allPrices.firstWhere(
          (price) => price > 0,
      // If no price is > 0 (i.e., all are 0 or less), default to the actual minimum.
      orElse: () => allPrices.reduce(min),
    );
    // --- MODIFICATION END ---

    int? minOldPrice;
    if (isOfferActive && standardPrices.containsKey(_selectedPet)) {
      final oldPricesForPet =
      Map<String, num>.from(standardPrices[_selectedPet]);
      if (oldPricesForPet.isNotEmpty) {
        minOldPrice = oldPricesForPet.values.reduce(min).toInt();
      }
    }

    return PopupMenuButton<String>(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      itemBuilder: (_) => ratesSource.entries
          .map(
            (entry) => PopupMenuItem<String>(
          enabled: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                entry.key,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              Text(
                '₹${entry.value}',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOfferActive && minOldPrice != null) ...[
              Text(
                '₹$minOldPrice',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: const Color(0xFFFF9A9A),
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '₹$minPrice',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.green,
                ),
              ),
            ] else
              Text(
                'Starts from ₹$minPrice',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
                overflow: TextOverflow.ellipsis, // ✅ avoids overflow warning
                maxLines: 1,
              ),

            const SizedBox(width: 3),
            const Icon(Icons.arrow_drop_down, size: 16, color: Colors.teal),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPriceDisplay(widget.isOfferActive),
        const SizedBox(width: 6),
        _buildPetSelector(),
      ],
    );
  }
}

class BranchSelector extends StatefulWidget {
  final String currentServiceId;
  final String currentAreaName;
  final List<String> otherBranches;
  final Function(String?) onBranchSelected;

  const BranchSelector({
    Key? key,
    required this.currentServiceId,
    required this.currentAreaName,
    required this.otherBranches,
    required this.onBranchSelected,
  }) : super(key: key);

  @override
  _BranchSelectorState createState() => _BranchSelectorState();
}

class _BranchSelectorState extends State<BranchSelector> {
  List<Map<String, String>> _branchOptions = [];
  bool _isLoadingBranches = true;

  @override
  void initState() {
    super.initState();
    _fetchBranchDetails();
  }

  @override
  void didUpdateWidget(covariant BranchSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentServiceId != oldWidget.currentServiceId) {
      _fetchBranchDetails();
    }
  }

  Future<void> _fetchBranchDetails() async {
    setState(() {
      _isLoadingBranches = true;
      _branchOptions = [];
    });

    List<Map<String, String>> branches = [{
      'id': widget.currentServiceId,
      'areaName': widget.currentAreaName
    }];

    if (widget.otherBranches.isNotEmpty) {
      final futures = widget.otherBranches
          .map((id) => FirebaseFirestore.instance
          .collection('users-sp-boarding')
          .doc(id)
          .get())
          .toList();
      final results = await Future.wait(futures);
      for (var doc in results) {
        if (doc.exists) {
          branches.add({
            'id': doc.id,
            'areaName': doc.data()?['area_name'] ?? 'Unknown'
          });
        }
      }
    }
    if (mounted) {
      setState(() {
        _branchOptions = branches;
        _isLoadingBranches = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingBranches) {
      return const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2,color: AppColors.primary),
      );
    }

    if (_branchOptions.length <= 1) {
      return _buildInfoRow(
          widget.currentAreaName, Icons.location_on, Colors.black54);
    }

    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      onSelected: widget.onBranchSelected,
      itemBuilder: (_) => _branchOptions
          .map((branch) => PopupMenuItem<String>(
        value: branch['id'],
        child: Text(
          branch['areaName']!,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade800,
          ),
        ),
      ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
          color: Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on, size: 12, color: Colors.black54),
            const SizedBox(width: 4),
            Text(
              widget.currentAreaName,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const Icon(Icons.arrow_drop_down,
                color: Color(0xFFF67B0D), size: 20),
          ],
        ),
      ),
    );
  }
}