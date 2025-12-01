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
import 'package:lottie/lottie.dart';
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
// 🎯 TOP-LEVEL ISOLATE FUNCTION
// Runs all filter checks in the background to prevent UI blocking.
// 🎯 TOP-LEVEL ISOLATE FUNCTION
// Runs all filter checks in the background to prevent UI blocking.
List<Map<String, dynamic>> _filterCardsInBackground(Map<String, dynamic> payload) {
  // ---------------------------------------------------------------------------
  // 1. DESERIALIZE PAYLOAD (Extract data sent from main thread)
  // ---------------------------------------------------------------------------

  // Basic Lists and Sets
  final rawCards = payload['cards'] as List<dynamic>;
  final List<Map<String, dynamic>> cards = rawCards.map((e) => Map<String, dynamic>.from(e as Map)).toList();  final Set<String> hidden =
  (payload['hidden'] as List<dynamic>).cast<String>().toSet();
  final Set<String> liked =
  (payload['liked'] as List<dynamic>).cast<String>().toSet();
  final List<String> selectedPetTypes =
  (payload['selectedPetTypes'] as List<dynamic>)
      .cast<String>()
      .map((s) => s.toLowerCase())
      .toSet()
      .toList();
  final Set<String> selectedRunTypes =
  (payload['selectedRunTypes'] as List<dynamic>).cast<String>().toSet();

  // Maps
  final Map<String, double> distances =
  payload['distances'].cast<String, double>();
  final Map<String, int> serviceMaxAllowed =
  payload['serviceMaxAllowed'].cast<String, int>();

  // Simple Variables
  final double filterMinPrice = payload['selectedPriceRange'][0];
  final double filterMaxPrice = payload['selectedPriceRange'][1];
  final double stateMinPrice = payload['minPrice'];
  final double stateMaxPrice = payload['maxPrice'];
  final String selectedDistanceOption = payload['selectedDistanceOption'];
  final bool showOffersOnly = payload['showOffersOnly'];
  final bool showFavoritesOnly = payload['showFavoritesOnly'];
  final bool showCertifiedOnly = payload['showCertifiedOnly'];
  final String searchQuery = payload['searchQuery'].toLowerCase();

  // 🔥 AVAILABILITY DATA (Now using Strings)
  final int filterPetCount = payload['filterPetCount'];
  // We receive a list of "yyyy-MM-dd" strings directly
  final List<String> filterDateStrings =
  (payload['filterDateStrings'] as List<dynamic>).cast<String>();

  // We reconstruct the map. It is now Map<String, Map<String, int>>
  // Key 1: Service ID, Key 2: Date String ("2025-12-04"), Value: Count
  final Map<String, Map<String, int>> allBookingCounts =
  (payload['allBookingCounts'] as Map<String, dynamic>).map((sid, dateMap) {
    return MapEntry(sid, (dateMap as Map<String, dynamic>).cast<String, int>());
  });

  // ---------------------------------------------------------------------------
  // 2. FILTERING LOGIC
  // ---------------------------------------------------------------------------

  final filteredList = cards.where((service) {
    // Extract service details safely
    final id = service['service_id']?.toString() ?? '';
    final shopName = service['shopName']?.toString().toLowerCase() ?? '';
    final areaName = service['areaName']?.toString().toLowerCase() ?? '';
    final isOfferActive = service['isOfferActive'] as bool? ?? false;
    final certified = service['mfp_certified'] as bool? ?? false;
    final runType = service['type'] as String? ?? '';
    final serviceMinPrice = (service['min_price'] as num?)?.toDouble() ?? 0.0;
    // Unused but extracted for completeness:
    // final serviceMaxPrice = (service['max_price'] as num?)?.toDouble() ?? 0.0;
    final dKm = distances[id] ?? double.infinity;

    // --- A. Basic Text Search ---
    if (searchQuery.isNotEmpty) {
      if (!shopName.contains(searchQuery) && !areaName.contains(searchQuery)) {
        return false;
      }
    }

    // --- B. Hidden Services ---
    if (hidden.contains(id)) {
      return false;
    }

    // --- C. Favorites Only ---
    if (showFavoritesOnly && !liked.contains(id)) {
      return false;
    }

    // --- D. Offers Only ---
    if (showOffersOnly && !isOfferActive) {
      return false;
    }

    // --- E. Certified Only (MFP Premium) ---
    if (showCertifiedOnly && !certified) {
      return false;
    }

    // --- F. Run Type Filter ---
    if (selectedRunTypes.isNotEmpty && !selectedRunTypes.contains(runType)) {
      return false;
    }

    // --- G. Pet Species Compatibility ---
    if (selectedPetTypes.isNotEmpty) {
      final acceptedPetsLower = (service['pets'] as List<dynamic>? ?? [])
          .map((p) => p.toString().toLowerCase())
          .toList();
      // If service doesn't accept ANY of the selected types, filter it out
      if (!selectedPetTypes.any((selectedPet) => acceptedPetsLower.contains(selectedPet))) {
        return false;
      }
    }

    // --- H. Price Range Filter ---
    // Only check if the user has actually moved the sliders away from global min/max
    if (filterMaxPrice < stateMaxPrice || filterMinPrice > stateMinPrice) {
      // Check for overlap between user range and service range
      // Logic: (UserMax >= ServiceMin) AND (UserMin <= ServiceMax)
      // Note: We use the service's Max Price here
      final sMax = (service['max_price'] as num?)?.toDouble() ?? 0.0;

      final bool overlaps = (filterMaxPrice >= serviceMinPrice) &&
          (filterMinPrice <= sMax);
      if (!overlaps) {
        return false;
      }
    }

    // --- I. Distance Filter ---
    if (selectedDistanceOption.isNotEmpty) {
      final maxKm = double.tryParse(
          selectedDistanceOption.replaceAll(RegExp(r'[^0-9.]'), '')
      ) ?? double.infinity;

      if (dKm > maxKm) {
        return false;
      }
    }

    // --- J. AVAILABILITY CHECK (Capacity & Holidays) ---
    // This is the updated logic using String keys to prevent timezone bugs
    if (filterDateStrings.isNotEmpty && filterPetCount > 0) {
      final bookingCounts = allBookingCounts[id] ?? {};
      final maxAllowed = serviceMaxAllowed[id] ?? 0;

      for (final dateKey in filterDateStrings) {
        // Look up using "yyyy-MM-dd" string key directly.
        final usedSlots = bookingCounts[dateKey] ?? 0;

        if (usedSlots >= 999) {
          return false;
        }

        if ((usedSlots + filterPetCount) > maxAllowed) {
          return false;
        }



        // 2. Capacity Check
        if ((usedSlots + filterPetCount) > maxAllowed) {
          return false; // Not enough space, reject service
        }

      }
    }

    return true;
  }).toList();

  return filteredList;
}

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
  StreamSubscription<Position>? _positionSubscription;
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

  void _startFiltering() async {
    // 1. Prevent overlapping runs
    if (_isFiltering) return;

    final cardsProv = context.read<BoardingCardsProvider>();
    if (!cardsProv.ready) return;

    // 2. Turn ON the spinner
    setState(() => _isFiltering = true);

    try {
      final favProv = context.read<FavoritesProvider>();
      final hideProv = context.read<HiddenServicesProvider>();
      final distProv = context.read<DistanceProvider>();

      // 3. Date Formatting (String Comparison Fix)
      final List<String> filterDateStrings = _filterDates
          .map((d) => DateFormat('yyyy-MM-dd').format(d))
          .toList();

      // 4. 🔥 CRITICAL FIX: SANITIZE CARDS DATA
      // We explicitly create a new list containing ONLY simple types.
      // This removes GeoPoints/Timestamps that crash the Isolate.
      final List<Map<String, dynamic>> safeCards = cardsProv.cards.map((c) {
        return {
          'service_id': c['service_id']?.toString() ?? '',
          'shopName': c['shopName']?.toString() ?? '',
          'areaName': c['areaName']?.toString() ?? '',
          'isOfferActive': c['isOfferActive'] ?? false,
          'mfp_certified': c['mfp_certified'] ?? false,
          'type': c['type']?.toString() ?? '',
          'min_price': c['min_price'] ?? 0.0,
          'max_price': c['max_price'] ?? 0.0,
          'pets': c['pets'] ?? [], // Lists of strings are safe
          // Note: We do NOT pass 'location' or 'timestamp' here
        };
      }).toList();

      // 5. Construct Payload
      final payload = {
        'cards': safeCards, // Passing the safe list
        'distances': distProv.distances,
        'liked': favProv.liked.toList(),
        'hidden': hideProv.hidden.toList(),
        'selectedPetTypes': _selectedPetTypes.toList(),
        'selectedPriceRange': [_selectedPriceRange.start, _selectedPriceRange.end],
        'selectedDistanceOption': _selectedDistanceOption,
        'showOffersOnly': _showOffersOnly,
        'showFavoritesOnly': _showFavoritesOnly,
        'showCertifiedOnly': _showCertifiedOnly,
        'selectedRunTypes': _selectedRunTypes.toList(),
        'searchQuery': _searchQuery,
        'minPrice': _minPrice,
        'maxPrice': _maxPrice,
        'filterPetCount': _filterPetCount,
        'filterDateStrings': filterDateStrings,
        'allBookingCounts': _allBookingCounts,
        'serviceMaxAllowed': _serviceMaxAllowed,
      };

      // 6. Run Isolate
      final List<Map<String, dynamic>> result = await compute(
        _filterCardsInBackground,
        payload,
      );

      // 7. Update UI (Turn OFF spinner)
      if (mounted) {
        setState(() {
          // We need to map the result back to the original full objects
          // so the UI has all data (like images) to display.
          // We filter the *original* list based on the IDs returned by the isolate.
          final Set<String> validIds = result.map((r) => r['service_id'] as String).toSet();

          _filteredServices = cardsProv.cards
              .where((c) => validIds.contains(c['service_id']))
              .toList();

          _isFiltering = false;
        });
      }
    } catch (e) {
      // CRITICAL: Turn off spinner if error occurs
      if (mounted) {
        setState(() => _isFiltering = false);
      }
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
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final header = Provider.of<HeaderData>(context);
    _greeting = header.greeting;
    _mediaUrl = header.mediaUrl;
// 👇 ADD THESE LINES to watch for changes in hidden/favorites
    // By accessing them with Provider.of(context), this method will re-run
    // whenever they change.
    Provider.of<HiddenServicesProvider>(context);
    Provider.of<FavoritesProvider>(context);

    // Then call filter
    _startFiltering();

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
    _startLocationListening();
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

  /*Future<void> _fetchCurrentLocation() async {
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
    }
  }*/
  // lib/screens/Boarding/boarding_homepage.dart

  Future<void> _startLocationListening() async {
    // 1. Cancel previous subscription to prevent duplicates
    await _positionSubscription?.cancel();

    // 2. Check Permissions and Services
    LocationPermission permission = await Geolocator.checkPermission();
    bool isServiceEnabled = await Geolocator.isLocationServiceEnabled();

    // Handle Denied/Disabled states
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        !isServiceEnabled) {
      if (mounted) {
        setState(() => _locationPermissionDenied = true);
      }
      // Still call filter even if denied, to show un-filtered data
      _startFiltering();
      return;
    }

    if (mounted) {
      setState(() => _locationPermissionDenied = false); // Location is working
    }

    // 3. Start Stream Listener
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50, // Only update if moved > 50 meters
      ),
    ).listen(
          (Position position) {
        // Stream Listener fires whenever a new position is available.
        if (mounted) {
          setState(() {
            _currentPosition = position;
          });

          // 4. CRITICAL: Recalculate Distances and Re-filter
          context.read<BoardingCardsProvider>().recalculateCardDistances(position);
          _startFiltering();
        }
      },
      onError: (e) {
        // Handle any stream errors (e.g., location timeout)
        if (mounted) {
          setState(() => _locationPermissionDenied = true);
        }
        _startFiltering();
      },
    );
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
      });
    } else {
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
      _startLocationListening();
    }
  }


  @override
  void dispose() {
    _positionSubscription?.cancel();
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
        // ─── IMPROVED FILTER DRAWER ─────────────────────────
        endDrawer: Drawer(
          backgroundColor: Colors.white,
          elevation: 0,
          width: MediaQuery.of(context).size.width * 0.85, // Responsive width (85% of screen)
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.horizontal(left: Radius.circular(0)),
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ─── 1. HEADER ───────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Filters',
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade900,
                        ),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey.shade50,
                          ),
                          child: Icon(Icons.close, size: 20, color: Colors.grey.shade700),
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // ─── 2. SCROLLABLE CONTENT ───────────────────────────
                Expanded(
                  child: Scrollbar(
                    controller: _filterScrollController,
                    thumbVisibility: true,
                    child: ListView(
                      controller: _filterScrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                      children: [

                        // ─── A. TOGGLES SECTION (Premium, Offers, Hidden) ───
                        Text(
                          'Preferences',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // MFP Premium
                        _buildSwitchTile(
                          title: 'MFP Premium Only',
                          icon: Icons.verified_user_outlined,
                          isActive: _showCertifiedOnly,
                          onChanged: (val) => setState(() => _showCertifiedOnly = val),
                        ),
                        const SizedBox(height: 12),

                        // At Offer Price
                        // At Offer Price
                        _buildSwitchTile(
                          title: 'Special Offers',
                          icon: null, // <-- This is correctly set to null
                          isActive: _showOffersOnly,
                          onChanged: (val) {
                            setState(() {
                              _showOffersOnly = val;
                              _startFiltering();
                            });
                          },
                        ),
                        const SizedBox(height: 12),

                        // Hidden Services Link
                        InkWell(
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => HiddenServicesPage()));
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.visibility_off_outlined, size: 20, color: Colors.grey.shade600),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Manage Hidden Services',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                ),
                                Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade400),
                              ],
                            ),
                          ),
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Divider(height: 1),
                        ),

                        // ─── B. RUN TYPE (CHIPS) ──────────────────────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Run Type',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade900,
                              ),
                            ),
                            if (_selectedRunTypes.isNotEmpty)
                              GestureDetector(
                                onTap: () => setState(() => _selectedRunTypes.clear()),
                                child: Text(
                                  'Clear',
                                  style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF25ADAD), fontWeight: FontWeight.w600),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: ['Home Run', 'Business Run', 'NGO Run', 'Govt Run', 'Vet Run'].map((type) {
                            final isSelected = _selectedRunTypes.contains(type);
                            return FilterChip(
                              label: Text(type),
                              labelStyle: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                color: isSelected ? Colors.white : Colors.grey.shade700,
                              ),
                              selected: isSelected,
                              showCheckmark: false,
                              backgroundColor: Colors.white,
                              selectedColor: const Color(0xFF25ADAD),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                  color: isSelected ? const Color(0xFF25ADAD) : Colors.grey.shade300,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              onSelected: (bool selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedRunTypes.add(type);
                                  } else {
                                    _selectedRunTypes.remove(type);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Divider(height: 1),
                        ),

                        // ─── C. PRICE RANGE ──────────────────────────────
                        // Only show if loaded
                        if (!_priceFilterLoaded)
                          const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF25ADAD)))
                        else ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Price Range',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade900,
                                ),
                              ),
                              // Live Update of Values here
                              Text(
                                '₹${_selectedPriceRange.start.toInt()} - ₹${_selectedPriceRange.end.toInt()}',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF25ADAD),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: const Color(0xFF25ADAD),
                              inactiveTrackColor: Colors.grey.shade200,
                              thumbColor: Colors.white,
                              overlayColor: const Color(0xFF25ADAD).withOpacity(0.1),
                              valueIndicatorColor: const Color(0xFF25ADAD),
                              trackHeight: 4,
                              rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 10, elevation: 2),
                            ),
                            child: RangeSlider(
                              values: _selectedPriceRange,
                              min: _minPrice.toDouble(),
                              max: _maxPrice.toDouble(),
                              divisions: ((_maxPrice - _minPrice) ~/ 100).toInt(),
                              labels: RangeLabels(
                                '₹${_selectedPriceRange.start.toInt()}',
                                '₹${_selectedPriceRange.end.toInt()}',
                              ),
                              onChanged: (newRange) {
                                setState(() {
                                  // Clamp to ensure we don't go out of bounds
                                  _selectedPriceRange = RangeValues(
                                    newRange.start.clamp(_minPrice.toDouble(), _maxPrice.toDouble()),
                                    newRange.end.clamp(_minPrice.toDouble(), _maxPrice.toDouble()),
                                  );
                                });
                              },
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('₹${_minPrice.toInt()}', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                              Text('₹${_maxPrice.toInt()}+', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                            ],
                          ),
                        ],

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Divider(height: 1),
                        ),

                        // ─── D. SPECIES SELECTOR ──────────────────────────
                        Text(
                          'Species',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade900,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Search Box
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: TextField(
                            onChanged: (v) => setState(() => _speciesSearchQuery = v),
                            decoration: InputDecoration(
                              hintText: 'Search species (e.g. Dog, Cat)',
                              hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13),
                              prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 14),
                              isDense: true,
                            ),
                            style: GoogleFonts.poppins(fontSize: 14),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Species List (Limited Height)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 250),
                          child: ListView(
                            shrinkWrap: true,
                            physics: const ClampingScrollPhysics(),
                            children: filteredPetTypes.map((pt) {
                              final name = _capitalize(pt.id);
                              final available = pt.display;
                              final sel = _selectedPetTypes.contains(name);

                              // Disabled State
                              if (!available) {
                                return Opacity(
                                  opacity: 0.5,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                                    child: Row(
                                      children: [
                                        Icon(Icons.check_box_outline_blank, color: Colors.grey.shade300),
                                        const SizedBox(width: 12),
                                        Text(name, style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade800)),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                              color: Colors.grey.shade200,
                                              borderRadius: BorderRadius.circular(4)
                                          ),
                                          child: Text('Coming Soon', style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w600)),
                                        )
                                      ],
                                    ),
                                  ),
                                );
                              }

                              // Active State
                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    if (sel) _selectedPetTypes.remove(name);
                                    else _selectedPetTypes.add(name);
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                                  child: Row(
                                    children: [
                                      Icon(
                                        sel ? Icons.check_box : Icons.check_box_outline_blank,
                                        color: sel ? const Color(0xFF25ADAD) : Colors.grey.shade400,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        name,
                                        style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                                            color: sel ? const Color(0xFF25ADAD) : Colors.grey.shade800
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ─── 3. FOOTER BUTTONS ──────────────────────────────
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            _resetFilters();
                            Navigator.pop(context);
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          child: Text(
                            'Clear All',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            _startFiltering();
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: const Color(0xFF25ADAD),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Apply Filters',
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
                Padding(
                  padding: const EdgeInsets.only(
                    left: 20.0,
                    right: 20.0,
                    bottom: 16,
                    top: 0,
                  ),
                  child: Center(
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                        children: [
                          const TextSpan(text: "Tap "),
                          TextSpan(
                            text: "Apply",
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700, // bold
                              color: Colors.grey.shade800, // slightly stronger
                            ),
                          ),
                          const TextSpan(text: " to confirm your filter changes."),
                        ],
                      ),
                    ),
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
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),

                            Text(
                              "No Services Found",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),

                            Text(
                              "No services match your current filters.\nTry adjusting or clearing some filters.",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                height: 1.6,
                                color: Colors.grey.shade600,
                              ),
                            ),

                            const SizedBox(height: 20),

                            ElevatedButton(
                              onPressed: () {
                                _resetFilters();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryColor,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                "Clear Filters",
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }


                  // 4. --- SHOW FILTERED RESULTS ---
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
  Widget _buildSwitchTile({
    required String title,
    required IconData? icon, // 🚨 Ensure icon is nullable
    required bool isActive,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!isActive),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF25ADAD).withOpacity(0.05) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? const Color(0xFF25ADAD).withOpacity(0.3) : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            // 🚨 MODIFIED: Conditionally render the Icon and SizedBox
            if (icon != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: isActive ? const Color(0xFF25ADAD) : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w500,
                  color: isActive ? const Color(0xFF25ADAD) : Colors.grey.shade800,
                ),
              ),
            ),
            Transform.scale(
              scale: 0.8,
              child: Switch(
                value: isActive,
                onChanged: onChanged,
                activeColor: const Color(0xFF25ADAD),
              ),
            ),
          ],
        ),
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

  Map<String, Map<String, int>> _allBookingCounts = {};

  Future<void> _preloadAllBookingCounts() async {
    final provider = context.read<BoardingCardsProvider>();

    // 1. Wait for provider to be ready
    if (!provider.ready) {
      await Future.delayed(const Duration(milliseconds: 100));
      _preloadAllBookingCounts();
      return;
    }

    final services = provider.cards;
    if (services.isEmpty) return;

    int chunkSize = 20;

    // 3. Loop through the services in "chunks"
    for (var i = 0; i < services.length; i += chunkSize) {

      // Calculate the slice (e.g., 0 to 20, then 20 to 40)
      int end = (i + chunkSize < services.length) ? i + chunkSize : services.length;
      List<Map<String, dynamic>> currentBatch = services.sublist(i, end);

      // 4. Fire requests for this batch in PARALLEL
      // Future.wait makes the app wait for all 20 to finish before moving to the next 20.
      await Future.wait(currentBatch.map((service) async {
        final sid = service['service_id'] as String;
        final dateCount = <String, int>{};

        try {
          // 🔥 SUPER OPTIMIZATION:
          // Fetch the Parent Doc (Max Pets) AND the Summary Collection (Dates) at the same time
          final results = await Future.wait([
            FirebaseFirestore.instance.collection('users-sp-boarding').doc(sid).get(),
            FirebaseFirestore.instance.collection('users-sp-boarding').doc(sid).collection('daily_summary').get(),
          ]);

          final parentSnap = results[0] as DocumentSnapshot;
          final summarySnap = results[1] as QuerySnapshot;

          // A. Parse Max Allowed
          if (parentSnap.exists && parentSnap.data() != null) {
            final rawMax = (parentSnap.data() as Map<String, dynamic>)['max_pets_allowed'];
            _serviceMaxAllowed[sid] = int.tryParse(rawMax?.toString() ?? '0') ?? 0;
          } else {
            _serviceMaxAllowed[sid] = 0;
          }

          // B. Parse Daily Summary (With Date & Holiday Fixes)
          for (final doc in summarySnap.docs) {
            final docData = doc.data() as Map<String, dynamic>;

            // Fix 1: Normalize Date Key ("2025-1-1" -> "2025-01-01")
            String dateKey = doc.id;
            try {
              final parsedDate = DateFormat('yyyy-MM-dd').parse(doc.id);
              dateKey = DateFormat('yyyy-MM-dd').format(parsedDate);
            } catch (e) {
              continue; // Skip invalid dates
            }

            // Fix 2: Robust Holiday Check
            bool isHoliday = false;
            final rawHoliday = docData['isHoliday'];
            if (rawHoliday is bool) isHoliday = rawHoliday;
            else if (rawHoliday is String) isHoliday = rawHoliday.toLowerCase() == 'true';

            if (isHoliday) {
              dateCount[dateKey] = 999; // Holiday blocked
            } else {
              dateCount[dateKey] = int.tryParse(docData['bookedPets']?.toString() ?? '0') ?? 0;
            }
          }

          // Save result to the main map
          _allBookingCounts[sid] = dateCount;

        } catch (e) {
        }
      }));
    }

    // 5. Update UI once ALL batches are done
    if (mounted) {
      setState(() {}); // Refresh UI
      // If the user already had filters set, re-run the filter logic now that data is loaded
      if (_filterPetCount > 0 && _filterDates.isNotEmpty) {
        _startFiltering();
      }
    }
  }

  Future<void> _showAvailabilityFilterDialog() async {
    final petCountCtl = TextEditingController(
      text: _filterPetCount > 0 ? '$_filterPetCount' : '',
    );

    List<DateTime> tempDates = List.from(_filterDates);
    int tempPetCount = _filterPetCount;
    DateTime tempFocusedDay = DateTime.now();

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14), // smaller radius
              ),
              insetPadding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12), // smaller padding
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // --- HEADER ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Check Availability',
                                style: GoogleFonts.poppins(
                                  fontSize: 17, // reduced
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                'Filter services by capacity',
                                style: GoogleFonts.poppins(
                                  fontSize: 11, // reduced
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.grey.shade100,
                              ),
                              child: const Icon(Icons.close, size: 18), // smaller
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16), // reduced spacing

                      // --- SECTION 1: PET COUNT ---
                      Text(
                        'How many pets?',
                        style: GoogleFonts.poppins(
                          fontSize: 12.5, // reduced
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 8),

                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14), // slightly smaller
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: TextField(
                          controller: petCountCtl,
                          keyboardType: TextInputType.number,
                          style: GoogleFonts.poppins(
                            fontSize: 14.5, // smaller
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'e.g., 1',
                            hintStyle: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.grey.shade400,
                            ),
                            icon: const Icon(Icons.pets,
                                color: Color(0xFF25ADAD), size: 18),
                          ),
                          onChanged: (val) {
                            tempPetCount = int.tryParse(val) ?? 0;
                          },
                        ),
                      ),

                      const SizedBox(height: 16),

                      // --- SECTION 2: CALENDAR ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Select Dates',
                            style: GoogleFonts.poppins(
                              fontSize: 12.5, // reduced
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          if (tempDates.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF25ADAD).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${tempDates.length} Selected',
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF25ADAD),
                                ),
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(14), // smaller
                        ),
                        child: TableCalendar(
                          firstDay: DateTime.now(),
                          lastDay: DateTime.now().add(const Duration(days: 90)),
                          focusedDay: tempFocusedDay,
                          headerStyle: const HeaderStyle(
                            formatButtonVisible: false,
                            titleCentered: true,
                            leftChevronIcon: Icon(Icons.chevron_left, size: 18),
                            rightChevronIcon: Icon(Icons.chevron_right, size: 18),
                          ),
                          calendarStyle: const CalendarStyle(
                            todayDecoration: BoxDecoration(
                              color: Color(0xFFB2DFDB),
                              shape: BoxShape.circle,
                            ),
                            selectedDecoration: BoxDecoration(
                              color: Color(0xFF25ADAD),
                              shape: BoxShape.circle,
                            ),
                          ),
                          selectedDayPredicate: (day) {
                            return tempDates.any((d) => isSameDay(d, day));
                          },
                          onDaySelected: (selectedDay, focusedDay) {
                            setDialogState(() {
                              tempFocusedDay = focusedDay;   // <-- KEEP MONTH

                              if (tempDates.any((d) => isSameDay(d, selectedDay))) {
                                tempDates.removeWhere((d) => isSameDay(d, selectedDay));
                              } else {
                                tempDates.add(selectedDay);
                              }
                            });
                          },
                          onPageChanged: (newFocusedDay) {
                            setDialogState(() {
                              tempFocusedDay = newFocusedDay;
                            });
                          },


                        ),
                      ),

                      const SizedBox(height: 16),

                      // --- SECTION 3: BUTTONS ---
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () {
                                setState(() {
                                  _filterPetCount = 0;
                                  _filterDates.clear();
                                });
                                _startFiltering();
                                Navigator.pop(context);
                              },
                              style: TextButton.styleFrom(
                                padding:
                                const EdgeInsets.symmetric(vertical: 12), // smaller
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: Text(
                                'Reset',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: () {
                                if (tempPetCount <= 0) {
                                  _showWarningDialog(
                                      message: "Please enter at least 1 pet.");
                                  return;
                                }
                                if (tempDates.isEmpty) {
                                  _showWarningDialog(
                                      message:
                                      "Please select at least one date.");
                                  return;
                                }

                                setState(() {
                                  _filterPetCount = tempPetCount;
                                  _filterDates = List.from(tempDates);
                                });

                                _startFiltering();
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25ADAD),
                                padding:
                                const EdgeInsets.symmetric(vertical: 12), // smaller
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: Text(
                                'Apply Filter',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
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
      },
    );
  }

}

// boarding_homepage.dart (add this to the bottom of the file)

// A separate class to hold the data needed by the isolate
class IsolateData {
  final List<Map<String, dynamic>> services;
  IsolateData(this.services);
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

    // 2. Check what the service provider accepts.
    final acceptedTypes = (widget.service['pets'] as List<dynamic>? ?? [])
        .map((p) => p.toString().toLowerCase()).toSet();

    if (userPets.isEmpty) return false;

    // 3. Check for each user pet if it is rejected.
    final unacceptedCount = userPets.where((pet) {
      final petType = pet['pet_type']?.toString().toLowerCase() ?? 'type_missing';
      final isRejected = !acceptedTypes.contains(petType);

      if (isRejected) {
      }
      return isRejected;
    }).length;

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

  void showFullWhiteLoader(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Loading',
      barrierColor: Colors.white,
      useRootNavigator: true,
      pageBuilder: (_, __, ___) {
        return Container(
          color: Colors.white,
          child: Center(
            child: SizedBox(
              width: 180,
              height: 180,
              child: Lottie.asset('assets/Loaders/App_Loader.json'),
            ),
          ),
        );
      },
    );
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
          elevation: 0,
          shadowColor: Colors.transparent,
          margin: const EdgeInsets.fromLTRB(2, 0, 2, 12),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
            side: isOfferActive
                ? const BorderSide(color: Colors.black87, width: 1.0)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: () async {
              // 1️⃣ Show loader ON ROOT NAVIGATOR
              showFullWhiteLoader(context);

              // Give time for loader UI to mount
              await Future.delayed(const Duration(milliseconds: 50));

              // 2️⃣ Navigate using NORMAL navigator
              await Navigator.push(
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

              // 3️⃣ REMOVE LOADER ON ROOT NAVIGATOR
              Navigator.of(context, rootNavigator: true).pop();
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
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Material(
                                elevation: 3,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                  topRight: Radius.circular(12),
                                  bottomLeft: Radius.circular(0),
                                  bottomRight: Radius.circular(0),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: SizedBox(
                                    width: 110,
                                    height: 120,
                                    child: Image.network(
                                      shopImage,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Center(
                                        child: Icon(Icons.image_not_supported, color: Colors.grey),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // BELOW IMAGE
                              Container(
                                width: 110, // match width of the image card
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
                            ],
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
                                  // Defaults when no reviews OR no data
                                  double avg = 0.0;
                                  int count = 0;

                                  if (snap.hasData) {
                                    avg = (snap.data!['avg'] as double?) ?? 0.0;
                                    count = (snap.data!['count'] as int?) ?? 0;
                                  }

                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      // ⭐ Stars (filled only if count > 0)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: List.generate(
                                          5,
                                              (i) => Padding(
                                            padding: const EdgeInsets.only(right: 2.0),
                                            child: Icon(
                                              count > 0 && i < avg.round()
                                                  ? Icons.star_rounded
                                                  : Icons.star_border_rounded,
                                              size: 16,
                                              color: Colors.amber,
                                            ),
                                          ),
                                        ),
                                      ),

                                      const SizedBox(width: 3),

                                      // ⭐ avg rating (always show)
                                      Text(
                                        avg.toStringAsFixed(1),
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: Colors.black87,
                                          height: 1.0,
                                        ),
                                      ),

                                      const SizedBox(width: 3),

                                      // ⭐ review count (always show)
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

                              // Replace the existing single Text widget that displays dKm with this Row:
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center, // Crucial for vertical alignment
                                children: [
                                  Text(
                                    // dKm is 0.0 if not fetched, and double.infinity if error/no location
                                    dKm.isInfinite || dKm == 0.0 // Check for both
                                        ? 'Location services disabled. Enable to view'
                                        : '${dKm.toStringAsFixed(1)} km away',
                                    style: const TextStyle(fontSize: 9),
                                  ),

                                  // 🚨 STABILITY FIX: Reserve space for the button regardless of its visibility
                                  SizedBox(
                                    width: 24, // Fixed width
                                    height: 16, // Fixed height (to match text height)
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.only(left: 4.0),
                                        child: (dKm.isInfinite || dKm == 0.0)
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
                                          icon: Icon(Icons.refresh, size: 14, color: Colors.red.shade700),
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

  // lib/screens/Boarding/boarding_homepage.dart (Add this new dialog function)

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
  // lib/screens/Boarding/boarding_homepage.dart (Add this new dialog function near line 160, before class definitions)

  void _showManualPermissionDialog(BuildContext context) {
    // Define colors and responsiveness based on your AppColors/GoogleFonts usage
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

                  const Divider(height: 25),

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

                  // lib/screens/Boarding/boarding_homepage.dart (Inside _showManualPermissionDialog)

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

                      ElevatedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
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
        title: Text("MFP Premium", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.accentColor)),
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
              Text("Premium", style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 0.3)),
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