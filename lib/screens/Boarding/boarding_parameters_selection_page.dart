// lib/screens/Boarding/boarding_parameters_selection_page.dart
// ✨ FULLY OPTIMIZED CODE ✨

import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart'; // ✨ Used this
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:myfellowpet_user/screens/Boarding/summary_page_boarding.dart';
import 'package:provider/provider.dart';
import 'package:step_progress_indicator/step_progress_indicator.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:http/http.dart' as http;
import '../../app_colors.dart';
import '../../preloaders/PetsInfoProvider.dart';
import '../../preloaders/petpreloaders.dart';
import '../Pets/AddPetPage.dart';
import 'boarding_servicedetailspage.dart';
import 'new_location.dart';


List<String> _convertFirestoreDataToList(dynamic data) {
  if (data == null) return [];
  if (data is List) return data.map((e) => e.toString()).toList();
  if (data is String) return data.isNotEmpty ? [data] : []; // This line fixes the crash
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

      // ✨ THE FIX IS HERE: Use the helper function just like in the other file
      acceptedSizes: _convertFirestoreDataToList(data['accepted_sizes']),
      acceptedBreeds: _convertFirestoreDataToList(data['accepted_breeds']),
    );
  }).toList();
}
// Brand Colors
const Color primaryColor = Color(0xFF2CB4B6);
const Color accentColor = Color(0xFFF67B0D);

// Reusable Components
class CustomCard extends StatelessWidget {
  final Widget child;
  final Color color;

  const CustomCard({required this.child, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(0),
        boxShadow: [AppShadows.cardShadow],
      ),
      child: child,
    );
  }
}

class ServiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isActive;
  final ValueChanged<bool> onChanged;

  const ServiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingLg,
        vertical: AppDimensions.spacingMd,
      ),
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title, style: AppTextStyles.bodyLarge),
      subtitle: Text(subtitle, style: AppTextStyles.bodySmall),
      trailing: Switch.adaptive(
        value: isActive,
        activeColor: AppColors.primary,
        onChanged: onChanged,
      ),
    );
  }
}

class FoodOptionTile extends StatelessWidget {
  final String title;
  final Widget subtitle;
  final double? cost;
  final bool isSelected;
  final VoidCallback onTap;

  const FoodOptionTile({
    required this.title,
    required this.subtitle,
    required this.cost,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppDimensions.spacingLg),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryLight : null,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Icon(
                Icons.check,
                size: 16,
                color: isSelected ? Colors.white : Colors.transparent,
              ),
            ),
            const SizedBox(width: AppDimensions.spacingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.bodyLarge),
                  subtitle,
                ],
              ),
            ),
            if (cost != null)
              Text(
                '₹${cost!.toStringAsFixed(2)}/day',
                style: AppTextStyles.bodyLarge.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Style Constants
class AppDimensions {
  static const double radiusLg = 20;
  static const double radiusMd = 15;
  static const double spacingLg = 16;
  static const double spacingMd = 12;
}

class AppTextStyles {
  static const TextStyle headingMedium = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
    letterSpacing: 0.5,
  );

  static const TextStyle subheading = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.primary,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );
}

class AppShadows {
  static BoxShadow get cardShadow => BoxShadow(
    color: Colors.blue.shade100.withOpacity(0.2),
    blurRadius: 20,
    offset: const Offset(0, 10),
  );
}

class StageProgressBar extends StatelessWidget {
  final int currentStage;
  final int totalStages;
  final List<String> labels;
  final void Function(int)? onStepTap;
  final EdgeInsetsGeometry padding;

  const StageProgressBar({
    Key? key,
    required this.currentStage,
    required this.totalStages,
    required this.labels,
    this.onStepTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
  })  : assert(labels.length == totalStages,
  'The number of labels must match the total number of stages.'),
        super(key: key);

  @override
  Widget build(BuildContext context) {
    final List<Widget> stepWidgets = [];

    for (int i = 0; i < totalStages; i++) {
      final stepNumber = i + 1;
      stepWidgets.add(
        Flexible(
          child: _buildStep(context, stepNumber),
        ),
      );

      if (i < totalStages - 1) {
        stepWidgets.add(
          Expanded(child: _buildConnector(stepNumber)),
        );
      }
    }

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: stepWidgets,
      ),
    );
  }

  Widget _buildStep(BuildContext context, int stepNumber) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCircle(stepNumber),
        const SizedBox(height: 12),
        _buildLabel(stepNumber),
      ],
    );
  }

  Widget _buildConnector(int stepNumber) {
    final bool isCompleted = stepNumber < currentStage;
    final Color activeColor = AppColors.primary;
    final Color inactiveColor = Colors.grey.shade300;

    return Container(
      margin: const EdgeInsets.only(top: 18.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        height: 2.0,
        color: isCompleted ? activeColor : inactiveColor,
      ),
    );
  }

  Widget _buildCircle(int stepNumber) {
    final isCompleted = stepNumber < currentStage;
    final isCurrent = stepNumber == currentStage;

    final double circleSize = 36.0;
    final Color activeColor = AppColors.primary;
    final Color completedColor = AppColors.primary;
    final Color inactiveColor = Colors.grey.shade400;

    Widget child;
    BoxDecoration decoration;

    if (isCompleted) {
      decoration = BoxDecoration(
        color: completedColor,
        shape: BoxShape.circle,
      );
      child = const Icon(Icons.check, color: Colors.white, size: 20);
    } else if (isCurrent) {
      decoration = BoxDecoration(
        color: activeColor,
        shape: BoxShape.circle,
      );
      child = Text(
        '$stepNumber',
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      );
    } else {
      decoration = BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: inactiveColor, width: 2.0),
      );
      child = Text(
        '$stepNumber',
        style: GoogleFonts.poppins(
          color: inactiveColor,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return GestureDetector(
      onTap: onStepTap != null && !isCurrent ? () => onStepTap!(stepNumber) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: circleSize,
        height: circleSize,
        decoration: decoration,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(int stepNumber) {
    final isCompleted = stepNumber < currentStage;
    final isCurrent = stepNumber == currentStage;
    final bool isActive = isCompleted || isCurrent;

    final labelStyle = GoogleFonts.poppins(
      fontSize: 13,
      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
      color: isActive ? Colors.black87 : Colors.grey.shade600,
    );

    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 300),
      style: labelStyle,
      textAlign: TextAlign.center,
      child: Text(
        labels[stepNumber - 1],
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class BoardingParametersSelectionPage extends StatefulWidget {
  final String walkingFee;
  final int max_pets_allowed;
  final String current_count_of_pet;
  final GeoPoint sp_location;
  final String companyName;
  final String sp_id;
  final String close_time;
  final String shopName;
  final String shopImage;
  final String open_time;
  final String mode;
  final Map<String, int> rates;
  final String serviceId;
  final Map<String, int> mealRates;
  final Map<String, int> refundPolicy;
  final String fullAddress;
  final String areaName;
  final Map<String, int> walkingRates;
  final Map<String, dynamic> feedingDetails;
  final String? initialSelectedPet;

  BoardingParametersSelectionPage({
    required this.sp_location,
    required this.companyName,
    required this.sp_id,
    required this.shopName,
    required this.shopImage,
    required this.max_pets_allowed,
    required this.current_count_of_pet,
    required this.walkingFee,
    required this.close_time,
    required this.serviceId,
    required this.open_time,
    required this.mode,
    required this.rates,
    required this.mealRates,
    required this.refundPolicy,
    required this.fullAddress,
    required this.walkingRates,
    required this.feedingDetails,
    this.initialSelectedPet, required this.areaName,
  });

  @override
  _BoardingParametersSelectionPageState createState() =>
      _BoardingParametersSelectionPageState();
}

class _BoardingParametersSelectionPageState
    extends State<BoardingParametersSelectionPage> {
  int currentStep = 0;
  late Future<List<PetPricing>> _petPricingFuture;
  bool _isInitialPetLoadDone = false; // ✨ ADD THIS NEW VARIABLE
  bool _isLoading = false;

  bool _isSaving = false;
  Map<String, int> _mealRates = {};
  Map<String, int> _refundPolicy = {};
  String _fullAddress = '';
  Map<String, int> _walkingRates = {};

  late final Stream<List<Map<String, dynamic>>> _petListStream;

  bool get hasAdditionalServices =>
      widget.walkingFee != '0' || _foodInfo != null;
  late TextEditingController _searchController;
  String _searchTerm = '';
  String? _selectedPet;
  List<String> _acceptedSizes = [];
  List<String> _acceptedBreeds = [];
  List<String> _petDocIds = [];

  int get totalSteps {
    final hasWalkingServices =
    widget.walkingRates.values.any((rate) => rate > 0);
    final hasMealServices = widget.mealRates.values.any((rate) => rate > 0);
    return (hasWalkingServices || hasMealServices) ? 3 : 2;
  }

  Map<String, String> _petSizesMap = {};
  List<Map<String, dynamic>> _petSizesList = [];
  late final Map<String, int> _lcRates;
  late final Map<String, int> _lcMealRates;
  late final Map<String, int> _lcWalkingRates;

  DateTime? _startDate;
  List<Map<String, dynamic>> _filteredPets = [];

  int totalDays = 0;
  DateTime? _endDate;
  bool _pickupRequired = false;
  bool _dropoffRequired = false;
  bool _transportOptionSelected = false;
  bool _isFoodDescriptionExpanded = false;

  late double _pricePerDay;
  double _transportCost = 0.0;
  Set<DateTime> _holidayDates = {};
  double _totalCost = 0.0;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  final RangeSelectionMode _rangeSelectionMode = RangeSelectionMode.toggledOn;
  final double _costPerKm = 60.0;
  double _pickupDistance = 0.0;
  double? foodCost = 0.0;
  double? foodcostPerDay = 0.0;
  double _dropoffDistance = 0.0;
  Map<DateTime, int> _bookingCountMap = {};
  Set<DateTime> _maskedDates = {};
  List<String> _selectedPetIds = [];
  List<String> _selectedPetNames = [];
  List<Map<String, dynamic>> _pets = [];
  List<String> _selectedPetImages = [];
  List<DateTime> _unavailableDates = [];
  DateTime _selectedDay = DateTime.now();
  String? _selectedTransportVehicle;
  final List<String> _stepTitles = [
    'Select Pets',
    'Choose Dates',
    'Add-ons',
  ];
  Map<String, Map<String, dynamic>> _locations = {};

  Map<String, Map<DateTime, bool>> _petWalkingOptions = {};
  Map<String, Map<DateTime, String>> _petFoodOptions = {};
  Map<String, dynamic>? _foodInfo;
  late Future<List<Map<String, dynamic>>> _petListFuture;
  List<Map<String, dynamic>> _allPets = [];
  late bool gstRegistered = true; // default true
  late bool checkoutEnabled = true; // default true

  Future<void> _fetchGstFlag() async {
    final doc = await FirebaseFirestore.instance
        .collection('users-sp-boarding')
        .doc(widget.serviceId)
        .get();

    gstRegistered = doc.data()?['gst_registered'] == true;
  }
  Future<void> _fetchCheckOutEnabledFlag() async {
    final doc = await FirebaseFirestore.instance
        .collection('company_documents')
        .doc("payment")
        .get();

    checkoutEnabled = doc.data()?['checkoutEnabled'] == true;
  }

  // ✨ --- OPTIMIZATION 1 ---
  // Fetches all selected pet documents in a single query instead of N+1 loops.
  Future<void> _loadPetSizes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _selectedPetIds.isEmpty) return; // Added safety check

    // 1️⃣ Fetch all pet docs in one go
    final petSnaps = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('users-pets')
        .where(FieldPath.documentId, whereIn: _selectedPetIds)
        .get();

    final sizeMap = <String, String>{};
    // 2️⃣ Create a map of petId -> size from the results
    for (final snap in petSnaps.docs) {
      if (snap.exists) {
        final size = (snap.data()['size'] as String? ?? 'small').toLowerCase();
        sizeMap[snap.id] = size;
      }
    }

    // 3️⃣ Build list with correct size-based rates (no change here)
    final list = _selectedPetIds.map((petId) {
      final size = sizeMap[petId] ?? 'small'; // Fallback just in case
      final boardingRate = (_lcRates[size] ?? 0).toDouble();
      final walkingRate = (_lcWalkingRates[size] ?? 0).toDouble();
      final mealRate = (_lcMealRates[size] ?? 0).toDouble();

      return {
        'id': petId,
        'size': size,
        'price': boardingRate,
        'walkFee': walkingRate,
        'mealFee': mealRate,
      };
    }).toList();

    // 4️⃣ Update state once
    setState(() {
      _petSizesMap = sizeMap;
      _petSizesList = list;
    });
  }

  List<DateTime> _getDatesInRange() {
    if (_rangeStart == null) {
      return [];
    }
    if (_rangeEnd == null) {
      return [_rangeStart!];
    }
    final dates = <DateTime>[];
    final dayCount = _rangeEnd!.difference(_rangeStart!).inDays + 1;
    for (int i = 0; i < dayCount; i++) {
      dates.add(_rangeStart!.add(Duration(days: i)));
    }
    return dates;
  }

  @override
  void initState() {
    super.initState();
    _fetchGstFlag();
    _fetchCheckOutEnabledFlag();
    _petPricingFuture = _fetchPetPricing(widget.serviceId);
    _fetchPetDocIds().then((_) {
      if (_selectedPet != null) {
        _fetchPetDetails(_selectedPet!);
      }
    });

    _lcRates = {
      for (var e in widget.rates.entries) e.key.toLowerCase(): e.value ?? 0
    };
    _lcMealRates = {
      for (var e in widget.mealRates.entries) e.key.toLowerCase(): e.value ?? 0
    };
    _lcWalkingRates = {
      for (var e in widget.walkingRates.entries)
        e.key.toLowerCase(): e.value ?? 0
    };
    _mealRates = widget.mealRates;
    _refundPolicy = widget.refundPolicy;
    _fullAddress = widget.fullAddress;
    _walkingRates = widget.walkingRates;
    _searchController = TextEditingController();
    PetService.instance.watchMyPetsAsMap(context).listen((pets) {
      if (mounted) {
        setState(() {
          _allPets = pets;
          // ✨ SET THE FLAG TO TRUE AFTER THE FIRST DATA LOAD
          _isInitialPetLoadDone = true;
        });
      }
    });
  }

  Future<void> _fetchPetDocIds() async {
    final serviceDocRef =
    FirebaseFirestore.instance.collection('users-sp-boarding').doc(widget.serviceId);
    final petCollectionSnap =
    await serviceDocRef.collection('pet_information').get();

    final docIds = petCollectionSnap.docs.map((doc) => doc.id).toList();
    _petDocIds = docIds;
    _selectedPet =
        widget.initialSelectedPet ?? (docIds.isNotEmpty ? docIds.first : null);
  }

  Future<void> _fetchPetDetails(String petId) async {
    if (petId.isEmpty) return;
    try {
      final petSnap = await FirebaseFirestore.instance
          .collection('users-sp-boarding')
          .doc(widget.serviceId)
          .collection('pet_information')
          .doc(petId)
          .get();

      if (petSnap.exists) {
        final data = petSnap.data() as Map<String, dynamic>;
        setState(() {
          _acceptedSizes = List<String>.from(data['accepted_sizes'] ?? []);
          _acceptedBreeds = List<String>.from(data['accepted_breeds'] ?? []);
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refreshAllPets() {
    _searchController.clear();
    setState(() {
      _searchTerm = '';
    });
  }

  BoxDecoration _getCalendarCardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24.0),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF2CB4B6).withOpacity(0.08),
          blurRadius: 40,
          spreadRadius: 0,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String text, {BoxBorder? border}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: border,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarSection() {
    final stageNumber = currentStep + 1;
    const Color primaryBrandColor = Color(0xFF2CB4B6);
    final Color lightPrimaryColor = primaryBrandColor.withOpacity(0.15);
    final Color accentColor = Colors.orange.shade700;

    final combinedUnavailable = [
      ..._bookingCountMap.entries
          .where(
              (e) => e.value + _selectedPetIds.length > widget.max_pets_allowed)
          .map((e) => e.key),
      ..._unavailableDates.where(
              (d) => !_bookingCountMap.keys.any((u) => isSameDay(u, d))),
      // Holidays (now correctly tracked in state)
      ..._holidayDates, // <--- Now uses the defined state variable
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_rangeStart != null && _rangeEnd != null) {
        final dayCount = _rangeEnd!.difference(_rangeStart!).inDays + 1;
        final daysInRange = List.generate(
            dayCount, (i) => _rangeStart!.add(Duration(days: i)));
        final bool isRangeInvalid = daysInRange.any((day) =>
            combinedUnavailable.any((unavailable) => isSameDay(day, unavailable)));
        if (isRangeInvalid) {
          setState(() {
            _rangeStart = null;
            _rangeEnd = null;
            _calculateTotalCost();
          });
        }
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: StageProgressBar(
            currentStage: stageNumber,
            totalStages: totalSteps,
            onStepTap: _handleStepTap,
            labels: _stepTitles.take(totalSteps).toList(),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16.0),
          padding: const EdgeInsets.all(8),
          decoration: _getCalendarCardDecoration(),
          child: Column(
            children: [
              TableCalendar(
                availableGestures: AvailableGestures.horizontalSwipe,
                focusedDay: _selectedDay,
                firstDay: DateTime.now(),
                lastDay: DateTime.now().add(const Duration(days: 365)),
                startingDayOfWeek: StartingDayOfWeek.monday,
                enabledDayPredicate: (day) {
                  final now = DateTime.now();
                  final today = DateTime(now.year, now.month, now.day);

                  if (day.isBefore(today)) {
                    return false;
                  }

                  if (isSameDay(day, now)) {
                    try {
                      final closeParts = widget.close_time.split(RegExp('[: ]'));
                      int hour = int.parse(closeParts[0]);
                      int minute = int.parse(closeParts[1]);
                      bool isPM = widget.close_time.toLowerCase().contains('pm');
                      if (isPM && hour != 12) hour += 12;
                      if (!isPM && hour == 12) hour = 0;

                      final closeTime =
                      DateTime(now.year, now.month, now.day, hour, minute);

                      if (now.isAfter(closeTime)) {
                        return false;
                      }
                    } catch (e) {
                      print(
                          "⚠️ Error parsing close_time (${widget.close_time}): $e");
                    }
                  }

                  final isUnavailable =
                  combinedUnavailable.any((d) => isSameDay(d, day));
                  return !isUnavailable;
                },
                rangeSelectionMode: _rangeSelectionMode,
                rangeStartDay: _rangeStart,
                rangeEndDay: _rangeEnd,
                onRangeSelected: (start, end, focusedDay) {
                  setState(() {
                    _selectedDay = focusedDay;
                    _rangeStart = start;
                    _rangeEnd = end;
                    _calculateTotalCost();
                  });
                },
                calendarStyle: CalendarStyle(
                  rangeStartDecoration: BoxDecoration(
                    color: primaryBrandColor,
                    shape: BoxShape.circle,
                  ),
                  rangeEndDecoration: BoxDecoration(
                    color: primaryBrandColor,
                    shape: BoxShape.circle,
                  ),
                  rangeHighlightColor: lightPrimaryColor,
                  todayDecoration: BoxDecoration(
                    color: lightPrimaryColor,
                    shape: BoxShape.circle,
                  ),
                  selectedDecoration: BoxDecoration(
                    color: primaryBrandColor,
                    shape: BoxShape.circle,
                  ),
                  defaultTextStyle: const TextStyle(fontWeight: FontWeight.w500),
                  weekendTextStyle:
                  TextStyle(color: accentColor, fontWeight: FontWeight.w500),
                  outsideTextStyle: TextStyle(color: Colors.grey.shade400),
                  disabledTextStyle: TextStyle(
                    color: Colors.grey.shade400,
                    decoration: TextDecoration.lineThrough,
                  ),
                  withinRangeTextStyle: const TextStyle(color: Colors.black),
                  withinRangeDecoration: const BoxDecoration(
                    shape: BoxShape.circle,
                  ),
                  todayTextStyle: const TextStyle(
                      color: Colors.black87, fontWeight: FontWeight.w600),
                ),
                headerStyle: HeaderStyle(
                  titleCentered: true,
                  formatButtonVisible: false,
                  titleTextStyle: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  leftChevronIcon: const Icon(Icons.chevron_left_rounded,
                      color: Colors.grey, size: 28),
                  rightChevronIcon: const Icon(Icons.chevron_right_rounded,
                      color: Colors.grey, size: 28),
                  headerPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle: GoogleFonts.poppins(
                      color: Colors.grey.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                  weekendStyle: GoogleFonts.poppins(
                      color: accentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
                calendarBuilders: CalendarBuilders(
                  disabledBuilder: (context, date, focusedDate) {
                    return Center(
                      child: Text(
                        '${date.day}',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    );
                  },
                  defaultBuilder: (context, day, focusedDay) {
                    final bookedCount = _bookingCountMap[day] ?? 0;
                    if (bookedCount > 0) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Text('${day.day}',
                              style: const TextStyle(fontWeight: FontWeight.w500)),
                          Positioned(
                            bottom: 4,
                            child: Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: accentColor.withOpacity(0.8),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return null;
                  },
                ),
              ),
              const Divider(height: 32, indent: 16, endIndent: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildLegendItem(primaryBrandColor, 'Selected'),
                    _buildLegendItem(Colors.grey.shade300, 'Unavailable'),
                    _buildLegendItem(
                      lightPrimaryColor,
                      'Today',
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

  Future<void> _fetchUnavailableDates() async {
    try {
      final summarySnap = await FirebaseFirestore.instance
          .collection('users-sp-boarding')
          .doc(widget.serviceId)
          .collection('daily_summary')
          .get();

      final Map<DateTime, int> dateCountMap = {};
      final List<DateTime> unavailableDates = [];
      final Set<DateTime> holidays = {}; // Added local set for clarity
      final int petsInCurrentSelection = _selectedPetIds.length;
      final int maxPetsAllowed = widget.max_pets_allowed;

      for (final doc in summarySnap.docs) {
        final date = DateFormat('yyyy-MM-dd').parse(doc.id);
        final normalizedDate = DateTime(date.year, date.month, date.day);
        final data = doc.data();

        final bool isHoliday = data['isHoliday'] as bool? ?? false;

        if (isHoliday) {
          print(
              '🗓️ Holiday Found (Date Blocked): ${DateFormat('yyyy-MM-dd').format(normalizedDate)}');
          unavailableDates.add(normalizedDate); // Keep in original list for disabling
          holidays.add(normalizedDate); // Add to local holiday set
          dateCountMap[normalizedDate] =
          0;
        } else {
          final int currentBookedCount = data['bookedPets'] as int? ?? 0;
          dateCountMap[normalizedDate] = currentBookedCount;

          if (currentBookedCount + petsInCurrentSelection > maxPetsAllowed) {
            unavailableDates.add(normalizedDate);
          }
        }
      }

      if (mounted) {
        setState(() {
          _bookingCountMap = dateCountMap;
          _unavailableDates = unavailableDates.toSet().toList();
          _holidayDates = holidays; // 🎯 TWEAK 2: Update the global state
        });
      }
    } catch (e) {
      print("Error fetching optimized unavailable dates: $e");
    }
  }

  void _calculateTotalCost() {
    if (_rangeStart == null) return; // Allow cost calculation for single day

    double totalBoardingCost = 0.0;
    double totalWalkingCost = 0.0;
    double totalMealsCost = 0.0;
    final dates = _getDatesInRange(); // This now correctly returns 1 day

    for (final pet in _petSizesList) {
      final petId = pet['id'] as String;
      final petSize = (pet['size'] as String).toLowerCase();

      final boardingRate =
          double.tryParse((_lcRates[petSize]?.toString() ?? '0')) ?? 0.0;
      final walkingRate =
          double.tryParse((_lcWalkingRates[petSize]?.toString() ?? '0')) ?? 0.0;
      final mealRate =
          double.tryParse((_lcMealRates[petSize]?.toString() ?? '0')) ?? 0.0;

      totalBoardingCost += boardingRate * dates.length;

      for (final date in dates) {
        if (_petWalkingOptions[petId]?[date] == true) {
          totalWalkingCost += walkingRate;
        }
        if (_petFoodOptions[petId]?[date] == 'provider') {
          totalMealsCost += mealRate;
        }
      }
    }

    final total =
        totalBoardingCost + totalWalkingCost + totalMealsCost + _transportCost;

    setState(() {
      _totalCost = total;
    });
  }

  Future<_FeesData> _fetchFees() async {
    final snap = await FirebaseFirestore.instance
        .collection('company_documents')
        .doc('fees')
        .get();
    final data = snap.data() ?? {};
    final platformFee =
        double.tryParse(data['platform_fee_user_app'] ?? '0') ?? 0;
    final gstPct = double.tryParse(data['gst_rate_percent'] ?? '0') ?? 0;
    return _FeesData(platformFee, platformFee * gstPct / 100);
  }

  // ✨ OPTIMIZED: This function now fetches booking prerequisites in parallel
  Future<Map<String, dynamic>> _fetchBookingPrerequisites(String userId) async {
    final feesFuture = _fetchFees();
    final gstRateFuture = _fetchServiceGstRate();
    final userFuture =
    FirebaseFirestore.instance.collection('users').doc(userId).get();

    // Run all 3 network requests at the same time
    final results = await Future.wait([
      feesFuture,
      gstRateFuture,
      userFuture,
    ]);

    // Return a structured map of the results
    return {
      'fees': results[0] as _FeesData,
      'gstRate': results[1] as double,
      'userSnap': results[2] as DocumentSnapshot,
    };
  }

  Future<void> _onNextPressed() async {
    if (_isSaving || _isLoading) return;

    // --- Step 0: Pet Selection ---
    if (currentStep == 0) {
      if (_selectedPetIds.isEmpty) {
        _showWarningDialog(
            message: 'Please select at least one pet to proceed.');
        return;
      }
      setState(() => _isLoading = true);
      try {
        // This parallel fetch is already optimal
        await Future.wait([
          _fetchUnavailableDates(),
          _loadPetSizes(),
        ]);
      } catch (e) {
        setState(() => _isLoading = false);
        _showWarningDialog(
            message: 'Failed to load calendar data. Please try again.');
        return;
      }
      setState(() {
        currentStep++;
        _isLoading = false;
      });
      return;
    }

    // --- Step 1: Date Selection ---
    if (currentStep == 1) {
      if (_rangeStart == null) {
        _showWarningDialog(
            message: 'Please select at least one date to proceed.');
        return;
      }
      // Check if we need to show the add-ons step
      if (totalSteps == 3) {
        setState(() => currentStep++); // Move to add-ons
      } else {
        // Skip add-ons and go directly to summary
        _executeBooking();
      }
      return;
    }

    // --- Step 2: Add-ons (Final Step) ---
    if (currentStep == totalSteps - 1) {
      _executeBooking();
    }
  }

  // ✨ NEW: Extracted the final booking logic into its own function
  Future<void> _executeBooking() async {
    final int numberOfPets = _selectedPetIds.length;
    final List<DateTime> selectedDates = _getDatesInRange();
    if (selectedDates.isEmpty) {
      _showWarningDialog(message: 'Please select your dates to proceed.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;

      // --- Fetch all prerequisites in parallel ---
      final prerequisites = await _fetchBookingPrerequisites(user.uid);
      final _FeesData f = prerequisites['fees'];
      final double gstRatePercent = prerequisites['gstRate'];
      final DocumentSnapshot uSnap = prerequisites['userSnap'];
      final uData = uSnap.data() as Map<String, dynamic>? ?? {};
      // --- End of parallel fetch ---

      double totalBoardingCost = 0.0;
      double totalWalkingCost = 0.0;
      double totalMealsCost = 0.0;

      // ✨ 1. New breakdown array for summary page
      final List<Map<String, dynamic>> petCostBreakdown = [];

      for (final pet in _petSizesList) {
        final petId = pet['id'] as String;
        final petIndex = _selectedPetIds.indexOf(petId);
        final petName = _selectedPetNames[petIndex];
        final petImage = _selectedPetImages[petIndex];
        final petSize = pet['size'] as String;

        // --- CRITICAL FIX: Declare rate variables here (scope fix) ---
        final double petBoardingRatePerDay = (_lcRates[petSize] ?? 0).toDouble();
        final double petWalkingRatePerDay = (_lcWalkingRates[petSize] ?? 0).toDouble();
        final double petMealRatePerDay = (_lcMealRates[petSize] ?? 0).toDouble();
        // -------------------------------------------------------------

        double petTotalBoarding = 0.0;
        double petTotalWalking = 0.0;
        double petTotalMeals = 0.0;

        // Calculate costs for this specific pet
        petTotalBoarding = petBoardingRatePerDay * selectedDates.length;

        for (final date in selectedDates) {
          if (_petWalkingOptions[petId]?[date] == true) {
            petTotalWalking += petWalkingRatePerDay;
          }
          if (_petFoodOptions[petId]?[date] == 'provider') {
            petTotalMeals += petMealRatePerDay;
          }
        }

        // Accumulate total costs
        totalBoardingCost += petTotalBoarding;
        totalWalkingCost += petTotalWalking;
        totalMealsCost += petTotalMeals;

        // ✨ 2. Add pet's cost contribution to the new array
        // Note: We use the *PerDayRate* variables declared above.
        petCostBreakdown.add({
          'id': petId,
          'name': petName,
          'size': petSize,
          // --- FIX: Store Per-Day Rates and Total Costs for clarity ---
          'boardingRatePerDay': petBoardingRatePerDay,
          'walkingRatePerDay': petWalkingRatePerDay,
          'mealRatePerDay': petMealRatePerDay,
          'totalBoardingCost': petTotalBoarding, // This is for the invoice/backend
          'totalWalkingCost': petTotalWalking,   // This is for the invoice/backend
          'totalMealCost': petTotalMeals,       // This is for the invoice/backend
          // -------------------------------------------------------------
          'totalPetCost': petTotalBoarding + petTotalWalking + petTotalMeals,
        });
      }

      // Use the accumulated totals for GST calculation
      final double spServiceFee = totalBoardingCost + totalWalkingCost + totalMealsCost;

      // ... (Rest of cost calculation is unchanged, using accumulated totals)
      double transportCost = _transportCost;
      final double spServiceGst = spServiceFee * (gstRatePercent / 100);
      final double grandTotal =
          spServiceFee + spServiceGst + transportCost + f.platform + f.gst;
      setState(() => _totalCost = grandTotal);

      // ... (Unchanged perPetServices creation logic)
      final Map<String, Map<String, dynamic>> perPetServices = {};
      for (final petId in _selectedPetIds) {
        final petIndex = _selectedPetIds.indexOf(petId);
        final petName = _selectedPetNames[petIndex];
        final petImage = _selectedPetImages[petIndex];
        final petSizeRaw = _petSizesMap[petId] ?? 'small';
        final petSize = petSizeRaw.isNotEmpty
            ? petSizeRaw[0].toUpperCase() + petSizeRaw.substring(1)
            : 'Small';

        final Map<String, Map<String, dynamic>> dailyDetailsMap = {};
        for (final date in selectedDates) {
          final dateString = DateFormat('yyyy-MM-dd').format(date);
          dailyDetailsMap[dateString] = {
            'meals': _petFoodOptions[petId]?[date] == 'provider',
            'walk': _petWalkingOptions[petId]?[date] ?? false,
          };
        }

        perPetServices[petId] = {
          'name': petName,
          'size': petSize,
          'image': petImage,
          'dailyDetails': dailyDetailsMap,
        };
      }

      final db = FirebaseFirestore.instance;
      final bookingRef = db
          .collection('users-sp-boarding')
          .doc(widget.serviceId)
          .collection('service_request_boarding')
          .doc();

      final mainBookingData = {
        // ⭐ ADD THESE TWO
        'gstRegistered': gstRegistered,
        'checkoutEnabled': checkoutEnabled,

        // ... (mainBookingData remains the same, using totalBoardingCost, totalWalkingCost, totalMealsCost)
        'order_status': 'pending_payment',
        'admin_account_number': '2323230014933488',
        'user_id': user.uid,
        'start_reminder_stage': 0,
        'bookingId': bookingRef.id,
        'mode': "Online",
        "source": "sp",
        "pet_name": _selectedPetNames,
        "full_address": widget.fullAddress,
        'pet_images': _selectedPetImages,
        'pet_id': _selectedPetIds,
        'pet_sizes': _petSizesList,
        'user_reviewed': "false",
        'sp_reviewed': "false",
        'service_id': widget.serviceId,
        'numberOfPets': numberOfPets,
        'user_name': uData['name'] ?? '',
        'phone_number': uData['phone_number'] ?? '',
        'email': uData['email'] ?? '',
        'user_location': uData['user_location'],
        'timestamp': FieldValue.serverTimestamp(),
        // --- SIMPLE PAYMENT MODEL ---

// SP Earnings
        'sp_service_fee_exc_gst': spServiceFee,
        'sp_service_fee_inc_gst': spServiceFee + spServiceGst,
        'gst_on_sp_service': spServiceGst,

// Admin Earnings
        'platform_fee_exc_gst': f.platform,
        'platform_fee_inc_gst': f.platform + f.gst,
        'gst_on_platform_fee': f.gst,

// User Paid = SP inc GST + Platform inc GST  (NO grandTotal)
        'total_amount_paid': (spServiceFee + spServiceGst) + (f.platform + f.gst),

// Refund System
        'remaining_refundable_amount': spServiceFee + spServiceGst, // only SP part refundable
        'total_refunded_amount': 0,

// Admin keeps this
        'admin_fee_collected_total': f.platform,
        'admin_fee_gst_collected_total': f.gst,


        // ✨ 3. Save the new pet cost breakdown array in the main booking data
        'petCostBreakdown': petCostBreakdown,


        'shopName': widget.shopName,
        'areaName': widget.areaName,
        'shop_image': widget.shopImage,
        'selectedDates': selectedDates,
        'openTime': widget.open_time,
        'closeTime': widget.close_time,
        'user_confirmation': false,
        'user_t&c_acceptance': false,
        'admin_called': false,
        'refund_policy': widget.refundPolicy,
        'referral_code_used': false,
      };

      // ... (Transaction logic remains the same)
      await db.runTransaction((transaction) async {
        final List<String> dateStrings = selectedDates
            .map((date) => DateFormat('yyyy-MM-dd').format(date))
            .toList();

        if (dateStrings.isEmpty) return; // Safety check

        final summaryCollection = db
            .collection('users-sp-boarding')
            .doc(widget.serviceId)
            .collection('daily_summary');

        // 1️⃣ Read all required documents in one batch
        final summaryQuery = await summaryCollection
            .where(FieldPath.documentId, whereIn: dateStrings)
            .get();
        // 2️⃣ Process reads and check capacity in memory
        final Map<String, int> currentBookedMap = {};
        for (final doc in summaryQuery.docs) {
          currentBookedMap[doc.id] = (doc.data()?['bookedPets'] as int? ?? 0);
        }

        for (final dateString in dateStrings) {
          final currentBooked = currentBookedMap[dateString] ?? 0;
          final newTotal = currentBooked + numberOfPets;

          if (newTotal > widget.max_pets_allowed) {
            // This specific date is full
            throw Exception('spot_full on $dateString');
          }
        }

        // 3️⃣ Perform all writes
        for (final dateString in dateStrings) {
          final summaryRef = summaryCollection.doc(dateString);
          transaction.set(
            summaryRef,
            {
              'bookedPets': FieldValue.increment(numberOfPets),
              'lastUpdated': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        // 4️⃣ Write the main booking and sub-collections
        transaction.set(bookingRef, mainBookingData); // mainBookingData now includes petCostBreakdown

        for (final petEntry in perPetServices.entries) {
          final petId = petEntry.key;
          final petData = petEntry.value;
          final petServiceRef = bookingRef.collection('pet_services').doc(petId);
          transaction.set(petServiceRef, petData);
        }
      });
      // --- End of Transaction ---

      print('✅ Booking confirmed safely with transaction.');
      if (!mounted) return; // Check if widget is still alive

      // ✨ 4. Pass the new petCostBreakdown list to SummaryPage
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SummaryPage(
            spServiceFeeExcGst: spServiceFee,
            spServiceFeeIncGst: spServiceFee + spServiceGst,
            gstOnSpService: spServiceGst,

            platformFeeExcGst: f.platform,
            platformFeeIncGst: f.platform + f.gst,
            gstOnPlatformFee: f.gst,

            totalAmountPaid: (spServiceFee + spServiceGst) + (f.platform + f.gst),
            remainingRefundableAmount: spServiceFee + spServiceGst,
            totalRefundedAmount: 0,

            adminFeeTotal: f.platform,
            adminFeeGstTotal: f.gst,
            mode: widget.mode,
            boarding_rate: totalBoardingCost, // Pass total boarding cost for legacy field
            bookingId: bookingRef.id,
            openTime: widget.open_time,
            closeTime: widget.close_time,
            foodCost: totalMealsCost,
            shopImage: widget.shopImage,
            shopName: widget.shopName,
            sp_id: widget.sp_id,
            startDate: _rangeStart,
            endDate: _rangeEnd,
            transportCost: _transportCost,
            dailyWalkingRequired: totalWalkingCost > 0,
            walkingFee: widget.walkingFee,
            totalCost: _totalCost,
            pickupDistance: _pickupDistance,
            dropoffDistance: _dropoffDistance,
            petIds: _selectedPetIds,
            petNames: _selectedPetNames,
            petImages: _selectedPetImages,
            numberOfPets: numberOfPets,
            pickupRequired: _pickupRequired,
            dropoffRequired: _dropoffRequired,
            transportVehicle: _selectedTransportVehicle ?? 'Not Selected',
            availableDaysCount: selectedDates.length,
            selectedDates: selectedDates,
            serviceId: widget.serviceId,
            sp_location: widget.sp_location,
            areaNameOnly: widget.areaName,
            areaName: widget.fullAddress,
            foodOption: totalMealsCost > 0 ? 'provider' : 'self',
            foodInfo: null,
            mealRates: widget.mealRates,
            dailyRates: widget.rates,
            refundPolicy: widget.refundPolicy,
            fullAddress: widget.fullAddress,
            walkingRates: widget.walkingRates,
            perDayServices: perPetServices,
            walkingCost: totalWalkingCost,
            petSizesList: _petSizesList,
            petCostBreakdown: petCostBreakdown, // <<< NEW PARAMETER
          ),
        ),
      );
    } catch (e) {
      if (e.toString().contains('spot_full')) {
        _showWarningDialog(
            message: 'Uh Oh! Someone booked one of those spots just now!');
      } else {
        print('⛔️ Booking failed with error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Booking failed: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }


  Future<double> _fetchServiceGstRate() async {
    final snap = await FirebaseFirestore.instance
        .collection('company_documents')
        .doc('fees')
        .get();

    final data = snap.data() ?? {};
    return double.tryParse(data['gst_rate_percent']?.toString() ?? '0') ?? 0.0;
  }

  int _getExistingCountForDate(DateTime date) {
    int count = 0;
    for (DateTime unavailableDate in _unavailableDates) {
      if (isSameDay(unavailableDate, date)) {
        count += int.parse(widget.current_count_of_pet);
      }
    }
    return count;
  }

  void _showWarningDialog({required String message}) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withOpacity(0.4),
      transitionDuration: const Duration(milliseconds: 300), // Increased slightly for smooth effect
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            // BackdropFilter and Material/Container remain the same for the blur/container structure
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Material(
                color: Colors.white,
                elevation: 8,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.8,
                  padding: const EdgeInsets.all(28), // Increased padding
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15), // Darker shadow
                        blurRadius: 18, // Larger blur
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // --- Animated Icon (using AppColor.primaryColor) ---
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.8, end: 1.0),
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.elasticOut,
                        builder: (context, scale, child) =>
                            Transform.scale(
                              scale: scale,
                              child: Icon(
                                Icons.error_outline_rounded,
                                color: AppColors.primaryColor, // ✨ Used primaryColor
                                size: 64, // Slightly larger icon
                              ),
                            ),
                      ),
                      const SizedBox(height: 20),

                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins( // ✨ Used Poppins
                          fontSize: 15,
                          color: Colors.black87,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 28),
                      // --- Action Button (using primaryColor) ---
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryColor, // ✨ Used primaryColor
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 4, // Higher elevation for pop
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            "Dismiss",
                            style: GoogleFonts.poppins( // ✨ Used Poppins
                              fontSize: 16,
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
            ),
          ),
        );
      },
      // The transition is already clean and professional, using Curves.easeOutBack is great.
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved =
        CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: curved,
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
    );
  }

  void _showProviderFoodDialog({required String message}) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fastfood, size: 48, color: Color(0xFF00C2CB)),
              SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.justify,
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Color(0xFF00C2CB)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child:
                Text('OK', style: TextStyle(color: Color(0xFF00C2CB))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    // ✨ Show a loader overlay during navigation steps
    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 0),
                child: AnimatedSwitcher( // Add smooth transition
                  duration: const Duration(milliseconds: 300),
                  child: _buildStepContent(), // Use a helper
                ),
              ),
            ),
          ],
        ),
        // ✨ Loader overlay
        if (_isLoading || _isSaving)
          Positioned.fill(
            child: Container(
              color: Colors.white.withOpacity(0.7),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary,
                  valueColor:
                  AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ✨ Helper to make AnimatedSwitcher cleaner
  Widget _buildStepContent() {
    switch (currentStep) {
      case 0:
        return _buildPetSelector();
      case 1:
        return _buildCalendarSection();
      case 2:
        return _buildAdditionalServicesSection();
      default:
        return _buildPetSelector();
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✨ Use a simple loader while the *initial* pet list is loading
    if (!_isInitialPetLoadDone) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      );
    }
    return _buildMainScaffold();
  }

  Widget _buildMainScaffold() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon:
          const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _stepTitles[currentStep],
          style: GoogleFonts.poppins(
              fontSize: 20, fontWeight: FontWeight.w700, color: Colors.black),
        ),
        backgroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: _buildCurrentStep(), // This now includes the loading overlay
      ),
      bottomNavigationBar: SafeArea(
    top: false,
    child: _buildFloatingActionBar(),
    ),);
  }

  Widget _buildPetSelector() {
    final displayList = _searchTerm.isEmpty
        ? _allPets
        : _allPets.where((p) {
      return (p['name'] as String)
          .toLowerCase()
          .contains(_searchTerm.toLowerCase());
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: StageProgressBar(
            currentStage: currentStep + 1,
            totalStages: totalSteps,
            onStepTap: _handleStepTap,
            labels: _stepTitles.take(totalSteps).toList(),
          ),
        ),
        _buildSearchBarAndRefresh(),
        const SizedBox(height: AppDimensions.spacingLg),
        displayList.isEmpty
            ? _buildEmptyState()
            : _buildPetGrid(displayList),
        const SizedBox(height: AppDimensions.spacingLg),
        _buildAddPetButton(),
        const SizedBox(height: AppDimensions.spacingMd),
      ],
    );
  }

  Widget _buildSearchBarAndRefresh() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search your pets…',
                hintStyle: GoogleFonts.poppins(color: Colors.grey.shade500),
                prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                  borderSide:
                  const BorderSide(color: AppColors.primary, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                  borderSide:
                  const BorderSide(color: AppColors.primary, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                  borderSide:
                  const BorderSide(color: AppColors.primary, width: 2),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              ),
              onChanged: (term) {
                setState(() => _searchTerm = term);
              },
            ),
          ),
          const SizedBox(width: 8),
          Container(
            height: 50, // ✨ Adjusted height to match common TextField height
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.primary, width: 1),
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.black),
              onPressed: _refreshAllPets,
              tooltip: 'Refresh',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPetGrid(List<Map<String, dynamic>> displayList) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount =
          (constraints.maxWidth / 150).floor().clamp(2, 4);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displayList.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: AppDimensions.spacingMd,
              mainAxisSpacing: AppDimensions.spacingMd,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, i) {
              final pet = displayList[i];
              final isSel = _selectedPetIds.contains(pet['pet_id']);
              return _buildPetCard(pet, isSel);
            },
          );
        },
      ),
    );
  }

  Widget _buildPetCard(Map<String, dynamic> pet, bool isSelected) {
    // 1. --- Get Pet's Data ---
    // Get the pet's data from its own document
    final petType = pet['pet_type']?.toString().toLowerCase() ?? 'unknown';
    final petBreed = pet['pet_breed']?.toString().toLowerCase() ?? 'unknown';
    final petSize = pet['size']?.toString().toLowerCase() ?? 'unknown';

    // 2. --- Get Service's Acceptance Criteria ---
    // The *only* pet type this page is for (e.g., "dog")
    final serviceAcceptsPetType = widget.initialSelectedPet?.toLowerCase();

    // The list of sizes for this pet type (e.g., {"small", "medium"})
    final acceptedSizes = _acceptedSizes.map((s) => s.toLowerCase()).toSet();

    // The list of breeds for this pet type (e.g., {"labrador", "beagle"})
    final acceptedBreeds = _acceptedBreeds.map((b) => b.toLowerCase()).toSet();

    // 3. --- Logically Check for Rejection ---
    String rejectionReason = '';

    if (serviceAcceptsPetType == null) {
      // Safety check, this should never happen
      rejectionReason = 'The service pet type was not specified.';
    } else if (petType == 'unknown') {
      // This is your "Unknown" error! It means the pet's profile is incomplete.
      rejectionReason =
      'This pet (named ${pet['name']}) has an **Unknown** pet type in its profile. Please update your pet\'s profile.';
    } else if (petType != serviceAcceptsPetType) {
      // Simple and clear pet type mismatch reason
      rejectionReason =
      'This pet is a ${petType.capitalize()}, but the type you selected for this service on the previous page was ${serviceAcceptsPetType.capitalize()}.';
    } else if (petSize == 'unknown') {
      rejectionReason =
      'This pet (named ${pet['name']}) has an **Unknown** size listed in its profile. Please update your pet\'s profile.';
    } else if (petBreed == 'unknown') {
      rejectionReason =
      'This pet (named ${pet['name']}) has an **Unknown** breed listed in its profile. Please update your pet\'s profile.';
    } else if (!acceptedSizes.any((s) => s.startsWith(petSize))) {
      rejectionReason = 'This service does not accept ${petSize.capitalize()} size ${petType.capitalize()}s.';
    } else if (!acceptedBreeds.contains(petBreed)) {
      // This is the real breed check
      rejectionReason =
      'This service does not accept the breed ${petBreed.capitalize()} for ${petType.capitalize()}s.';
    }
    // 4. --- Build the Card ---
    final bool isAccepted = rejectionReason.isEmpty;
    final bool isMasked = !isAccepted;

    final onTapAction = isMasked
        ? () => _showWarningDialog(message: rejectionReason)
        : () => _handlePetSelection(pet);

    return GestureDetector(
      onTap: onTapAction,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          side: BorderSide(
            color: isSelected ? AppColors.primary : Colors.grey.shade200,
            width: isSelected ? 2.5 : 1,
          ),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color:
            isSelected ? AppColors.primary.withOpacity(0.05) : Colors.white,
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd - 1),
          ),
          child: Opacity(
            opacity: isMasked ? 0.4 : 1.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppDimensions.radiusMd - 2),
                    ),
                    child: (pet['pet_image'] != null && pet['pet_image'].isNotEmpty)
                        ? CachedNetworkImage(
                      imageUrl: pet['pet_image'],
                      fit: BoxFit.contain,
                      placeholder: (context, url) =>
                          _buildImagePlaceholder(),
                      errorWidget: (context, url, error) =>
                          _buildImagePlaceholder(),
                    )
                        : _buildImagePlaceholder(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppDimensions.spacingMd),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          pet['name'],
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected
                                ? AppColors.primary
                                : Colors.black87,
                          ),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child:
                            ScaleTransition(scale: animation, child: child),
                          );
                        },
                        child: isSelected
                            ? const Icon(
                          Icons.check_circle,
                          color: AppColors.primary,
                          key: ValueKey('selected_icon'),
                        )
                            : const SizedBox.shrink(
                          key: ValueKey('empty_icon'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddPetButton() {
    return Center(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.primary, width: 1.5),
          borderRadius: BorderRadius.circular(30),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AddPetPage()),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Add Pet',
                  style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.primary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingLg * 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off_rounded, size: 64, color: Colors.grey),
          const SizedBox(height: AppDimensions.spacingMd),
          Text(
            'No Pets Found',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try searching for another name, or add a new pet!',
            textAlign: TextAlign.center,
            style:
            GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  void _showMaxPetsDialog() {
    final max = widget.max_pets_allowed;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.pets, size: 48, color: Color(0xFF00C2CB)),
              SizedBox(height: 16),
              Text(
                'Too Many Pets',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'This shop can take in only $max pet${max > 1 ? 's' : ''} per day.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black),
              ),
              SizedBox(height: 24),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Color(0xFF00C2CB)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'OK',
                  style: TextStyle(color: Color(0xFF00C2CB)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handlePetSelection(Map<String, dynamic> pet) {
    final max = widget.max_pets_allowed;
    final already = _selectedPetIds.contains(pet['pet_id']);

    if (!already && _selectedPetIds.length >= max) {
      _showMaxPetsDialog();
      return;
    }

    setState(() {
      if (already) {
        _selectedPetIds.remove(pet['pet_id']);
        _selectedPetNames.remove(pet['name']);
        _selectedPetImages.remove(pet['pet_image']);
      } else {
        _selectedPetIds.add(pet['pet_id']);
        _selectedPetNames.add(pet['name']);
        _selectedPetImages.add(pet['pet_image']);
      }
      _rangeStart = null;
      _rangeEnd = null;
      _calculateTotalCost();
    });
  }

  Widget _buildImagePlaceholder() {
    return Container(
      color: Colors.grey.shade100,
      child: Center(
        child: Icon(Icons.pets_rounded, size: 32, color: Colors.grey.shade400),
      ),
    );
  }

  void _handleStepTap(int step) async {
    final targetIndex = step - 1;

    if (targetIndex == currentStep) return;

    if (targetIndex > currentStep) {
      if (currentStep == 0 && _selectedPetIds.isEmpty) {
        _showWarningDialog(
            message: 'Please select at least one pet to proceed.');
        return;
      }
      if (currentStep == 1 && _getDatesInRange().isEmpty) {
        _showWarningDialog(message: 'Please select your dates to proceed.');
        return;
      }
    }

    if (targetIndex == 1) {
      // Show loader *before* fetching
      setState(() => _isLoading = true);
      await _fetchUnavailableDates();
      await _loadPetSizes();
      setState(() => _isLoading = false);
    }

    setState(() => currentStep = targetIndex);
  }

  Widget _buildUnavailableDay(String label) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.black12,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: Colors.black87,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildServiceToggle({
    required IconData icon,
    required String label,
    required double cost,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final Color activeColor = AppColors.primary;
    final Color inactiveColor = Colors.grey.shade400;
    final Color bgColor =
    isSelected ? activeColor.withOpacity(0.1) : Colors.grey.shade100;
    final Color borderColor =
    isSelected ? activeColor.withOpacity(0.5) : Colors.grey.shade300;
    final Color textColor = isSelected ? activeColor : Colors.grey.shade600;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? activeColor : inactiveColor, size: 20),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: textColor,
                  ),
                ),
                if (cost > 0)
                  Text(
                    '₹${cost.toStringAsFixed(0)}',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      color: textColor.withOpacity(0.8),
                    ),
                  ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildServiceOptionBox({
    required IconData icon,
    required String label,
    required double cost,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    const Color primaryBrandColor = Color(0xFF2CB4B6);
    final Color textColor = isSelected ? Colors.white : Colors.grey.shade800;
    final Color iconColor = isSelected ? Colors.white : primaryBrandColor;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            color: isSelected ? primaryBrandColor : Colors.white,
            border: Border.all(
              color: isSelected ? primaryBrandColor : Colors.grey.shade300,
              width: 1.2,
            ),
            borderRadius: BorderRadius.circular(12.0),
            boxShadow: isSelected
                ? [
              BoxShadow(
                color: primaryBrandColor.withOpacity(0.25),
                blurRadius: 6,
                offset: const Offset(0, 3),
              )
            ]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, size: 18, color: iconColor),
                  AnimatedOpacity(
                    opacity: isSelected ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.check_circle,
                        color: Colors.white, size: 16),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '+₹${cost.toStringAsFixed(0)}',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                  color: isSelected
                      ? Colors.white.withOpacity(0.9)
                      : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdditionalServicesSection() {
    final sortedDates = _getDatesInRange().toList()..sort();
    final hasWalking = widget.walkingRates.values.any((rate) => rate > 0);
    final hasMeals = _mealRates.values.any((rate) => rate > 0);


    if (!hasWalking && !hasMeals) {
      return _buildNoServicesAvailable();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: StageProgressBar(
            currentStage: currentStep + 1,
            totalStages: totalSteps,
            onStepTap: _handleStepTap,
            labels: _stepTitles.take(totalSteps).toList(),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Text(
            'Customise Add-ons',
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _selectedPetIds.length,
          itemBuilder: (context, petIndex) {
            final petId = _selectedPetIds[petIndex];
            final petName = _selectedPetNames[petIndex];
            final petImage = _selectedPetImages[petIndex];
            final petSize = _petSizesMap[petId] ?? 'small';

            // ✨ Use lowercase key for lookup
            final walkingCost = (_lcWalkingRates[petSize] ?? 0).toDouble();
            final mealCost = (_lcMealRates[petSize] ?? 0).toDouble();

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24.0),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundImage:
                        petImage.isNotEmpty ? CachedNetworkImageProvider(petImage) : null,
                        backgroundColor:
                        const Color(0xFF2CB4B6).withOpacity(0.1),
                        child: petImage.isEmpty
                            ? Icon(Icons.pets, color: const Color(0xFF2CB4B6))
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Services for $petName',
                          style: GoogleFonts.poppins(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            for (final date in sortedDates) {
                              if (hasMeals)
                                _petFoodOptions.putIfAbsent(
                                    petId, () => {})[date] = 'self';
                              if (hasWalking)
                                _petWalkingOptions.putIfAbsent(
                                    petId, () => {})[date] = false;
                            }
                            _calculateTotalCost();
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: Colors.grey.shade400, width: 1.2),
                            borderRadius: BorderRadius.circular(14),
                            color: Colors.white,
                          ),
                          child: Text(
                            'Clear',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: sortedDates.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, dateIndex) {
                      final date = sortedDates[dateIndex];
                      final formattedDate =
                      DateFormat('EEE, MMM d').format(date);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding:
                            const EdgeInsets.only(bottom: 8.0, left: 4.0),
                            child: Text(
                              formattedDate,
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                  fontSize: 13),
                            ),
                          ),
                          Row(
                            children: [
                                _buildServiceOptionBox(
                                  icon: Icons.restaurant_menu_rounded,
                                  label: 'Meal',
                                  cost: mealCost,
                                  isSelected:
                                  _petFoodOptions[petId]?[date] == 'provider',
                                  onTap: () {
                                    setState(() {
                                      _petFoodOptions.putIfAbsent(
                                          petId, () => {});
                                      bool isProvider =
                                          _petFoodOptions[petId]![date] == 'provider';
                                      _petFoodOptions[petId]![date] =
                                      isProvider ? 'self' : 'provider';
                                      _calculateTotalCost();
                                    });
                                  },
                                ),
                                const SizedBox(width: 10),
                                _buildServiceOptionBox(
                                  icon: Icons.directions_walk_rounded,
                                  label: 'Walk',
                                  cost: walkingCost,
                                  isSelected:
                                  _petWalkingOptions[petId]?[date] ?? false,
                                  onTap: () {
                                    setState(() {
                                      _petWalkingOptions.putIfAbsent(
                                          petId, () => {});
                                      _petWalkingOptions[petId]![date] =
                                      !(_petWalkingOptions[petId]![date] ??
                                          false);
                                      _calculateTotalCost();
                                    });
                                  },
                                ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: FutureBuilder<List<PetPricing>>(
            future: _petPricingFuture,
            builder: (context, petPricingSnapshot) {
              if (petPricingSnapshot.connectionState != ConnectionState.done ||
                  !petPricingSnapshot.hasData ||
                  petPricingSnapshot.data!.isEmpty) {
                return const SizedBox.shrink();
              }
              final allPetData = petPricingSnapshot.data!;
              final allFeedingDetails = {
                for (var pet in allPetData) pet.petName: pet.feedingDetails
              };
              return FeedingInfoButton(
                  allFeedingDetails: allFeedingDetails,
                  initialSelectedPet: _selectedPet);
            },
          ),
        ),
        const SizedBox(height: 24), // Add space at the bottom
      ],
    );
  }

  Widget _buildNoServicesAvailable() {
    return Container(
      margin: const EdgeInsets.all(24.0),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.hotel_class_outlined,
              size: 50, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No Additional Services',
            style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800),
          ),
          const SizedBox(height: 8),
          Text(
            'This provider only offers the standard boarding service.',
            textAlign: TextAlign.center,
            style:
            GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24), // Respect safe area
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(
              color: Color(0xFF2BCECE),
              width: 3.0,
            ),
          ),
          elevation: 0,
        ),
        // Disable button while loading or saving
        onPressed: (_isLoading || _isSaving) ? null : _onNextPressed,
        child: (_isLoading || _isSaving)
            ? SizedBox( // Show a small loader inside the button
          height: 20,
          width: 20,
          child: CircularProgressIndicator(
            strokeWidth: 3,color: AppColors.primary,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              currentStep == totalSteps - 1 ? 'Continue' : 'Next',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
            ),
            const SizedBox(width: 10),
            Icon(
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

class _FeesData {
  final double platform, gst;
  _FeesData(this.platform, this.gst);
}