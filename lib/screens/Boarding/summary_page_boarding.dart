import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_colors.dart';
import '../../main.dart';
import '../Tickets/chat_support.dart';
import 'BoardingChatScreen.dart';
import 'OpenCloseBetween.dart';
import 'boarding_confirmation_page.dart';

class CancellationReason {
  final String code;
  final String reason;
  final int order;
  CancellationReason(this.code, this.reason, this.order);
}

class SummaryPage extends StatefulWidget {
  final double spServiceFeeExcGst;
  final double spServiceFeeIncGst;
  final double gstOnSpService;

  final double platformFeeExcGst;
  final double platformFeeIncGst;
  final double gstOnPlatformFee;

  final double totalAmountPaid;
  final double remainingRefundableAmount;
  final double totalRefundedAmount;

  final double adminFeeTotal;
  final double adminFeeGstTotal;
  static const routeName = '/summary';
  final String serviceId, shopImage, shopName, walkingFee, sp_id, bookingId;
  final DateTime? startDate, endDate;
  final List<Map<String, dynamic>> petCostBreakdown;
  final double totalCost;
  final double? transportCost, pickupDistance, dropoffDistance, foodCost, walkingCost;
  final bool? dailyWalkingRequired, pickupRequired, dropoffRequired;
  final String transportVehicle, openTime, closeTime, areaName, foodOption;
  final List<String> petIds, petNames, petImages;
  final int numberOfPets, availableDaysCount;
  final List<DateTime> selectedDates;
  final GeoPoint sp_location;
  final Map<String, dynamic>? foodInfo;
  final String mode;
  final Map<String, int> mealRates, dailyRates;
  final Map<String, int> refundPolicy;
  final String fullAddress;
  final String areaNameOnly;
  final double boarding_rate;
  final Map<String, int> walkingRates;
  final Map<String, Map<String, dynamic>> perDayServices;
  final List<Map<String, dynamic>> petSizesList;

  const SummaryPage({
    super.key,
    required this.totalCost,
    required this.transportCost,
    required this.foodCost,
    required this.walkingCost,
    required this.perDayServices,
    required this.serviceId,
    required this.shopImage,
    required this.shopName,
    required this.sp_id,
    this.startDate,
    this.endDate,
    this.dailyWalkingRequired,
    this.pickupDistance,
    this.dropoffDistance,
    required this.petIds,
    required this.petNames,
    required this.numberOfPets,
    this.pickupRequired,
    this.dropoffRequired,
    this.transportVehicle = 'Default Vehicle',
    required this.availableDaysCount,
    required this.selectedDates,
    required this.openTime,
    required this.closeTime,
    required this.sp_location,
    required this.areaName,
    required this.foodOption,
    required this.foodInfo,
    required this.petImages,
    required this.bookingId,
    required this.mode,
    required this.mealRates,
    required this.refundPolicy,
    required this.fullAddress,
    required this.walkingRates,
    required this.walkingFee,
    required this.petSizesList,
    required this.boarding_rate,
    required this.dailyRates,
    required this.petCostBreakdown, required this.spServiceFeeExcGst, required this.spServiceFeeIncGst, required this.gstOnSpService, required this.platformFeeExcGst, required this.platformFeeIncGst, required this.gstOnPlatformFee, required this.totalAmountPaid, required this.remainingRefundableAmount, required this.totalRefundedAmount, required this.adminFeeTotal, required this.adminFeeGstTotal, required this.areaNameOnly,
  });

  @override
  _SummaryPageState createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
// --- State & Theme Variables ---
  static const Color primaryColor = Color(0xFF00C2CB);
  static const Color secondaryColor = Color(0xFF0097A7);
  static const Color darkColor = Color(0xFF263238);
  static const Color lightTextColor = Color(0xFF757575);
  static const Color backgroundColor = Color(0xFFF5F7FA);

  String? lastPaymentMethod;

  // 💡 MODIFIED: Use the structured list instead of the simple map
  late List<CancellationReason> _orderedCancellationReasons = [];
// Slightly grey bg for cards

  bool _isProcessingPayment = false;
  late Razorpay _razorpay;
  late FirebaseMessaging _messaging;
  late final Future<_FeesData> _feesFuture;
  late final List<DateTime> _sortedDates;
  late Map<String, String> cancellationReasonsMap = {};
  late bool gstRegistered = true;
  late bool checkoutEnabled = true;
  bool _showPetBreakdown = false; // State for invoice expansion

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
  Future<void> _fetchGlobalLastPaymentMethod() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (snap.exists) {
      lastPaymentMethod = snap.data()?['lastPaymentMethod'];
    }
  }


  @override
  void initState() {
    super.initState();
    _fetchGstFlag();
    _fetchCheckOutEnabledFlag();
    _fetchGlobalLastPaymentMethod();


    _sortedDates = List<DateTime>.from(widget.selectedDates)..sort();
    _feesFuture = _fetchFees();
    _messaging = FirebaseMessaging.instance;
    _messaging.subscribeToTopic('chat_${widget.sp_id}');
    _messaging.requestPermission(alert: true, badge: true, sound: true);
    _saveFcmToken();
    _fetchCancellationReasons();
    _razorpay = Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError)
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  // In _SummaryPageState

  Future<void> _fetchCancellationReasons() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('tnc_cancellation_reasons')
          .get();

      if (!doc.exists || doc.data() == null) {
        _setHardcodedReasons();
        return;
      }

      final data = doc.data()!;
      List<CancellationReason>? fetchedReasons;

      // 1. Try to fetch the NEW, ORDERED ARRAY ('boardingReasons')
      final boardingList = data['boardingReasons'] as List<dynamic>?;

      if (boardingList != null) {
        // SUCCESS: Data is in the new, ordered array format.
        fetchedReasons = boardingList.map((item) {
          final map = item as Map<String, dynamic>;
          final dynamic rawOrder = map['order']; // Read as dynamic (could be String or int)

          int parsedOrder = 999; // Default high order for safety

          if (rawOrder is int) {
            parsedOrder = rawOrder;
          } else if (rawOrder is String) {
            // Safely parse the string to an int
            parsedOrder = int.tryParse(rawOrder) ?? 999;
          }

          return CancellationReason(
            map['code'] as String? ?? '',
            map['reason'] as String? ?? '',
            parsedOrder, // Use the parsed integer
          );
        }).toList();

      } else {
        // 2. FALLBACK: Try to fetch the OLD, UNORDERED MAP ('boarding')
        final oldBoardingMap = data['boarding'] as Map<String, dynamic>?;

        if (oldBoardingMap != null) {
          // SUCCESS: Found the old map. Convert it into the new List<CancellationReason> model.
          int order = 1; // Assign default order based on map iteration

          fetchedReasons = oldBoardingMap.entries.map((entry) {
            // Use the key as the code and the value as the reason.
            return CancellationReason(
              entry.key,
              entry.value as String,
              order++,
            );
          }).toList();
        }
      }

      // 3. APPLY TO STATE IF DATA WAS FOUND
      if (fetchedReasons != null && fetchedReasons.isNotEmpty) {
        // Sort: Essential for the new list, and also helps stabilize the fallback list.
        fetchedReasons.sort((a, b) => a.order.compareTo(b.order));

        if (mounted) {
          setState(() {
            _orderedCancellationReasons = fetchedReasons!;

            // Rebuild the cancellationReasonsMap for existing logic dependencies
            cancellationReasonsMap = Map.fromIterable(
              fetchedReasons!,
              key: (r) => (r as CancellationReason).code,
              value: (r) => (r as CancellationReason).reason,
            );
          });
        }
      } else {
        // 4. FINAL FALLBACK: Hardcoded default
        _setHardcodedReasons();
      }
    } catch (e) {
      // Catch any remaining parsing/network errors and use hardcoded values
      debugPrint('Error fetching cancellation reasons: $e');
      _setHardcodedReasons();
    }
  }

  // 💡 You must also update _setHardcodedReasons to return/set the CancellationReason list
  void _setHardcodedReasons() {
    final hardcodedMap = {
      'change_plans': 'Change of plans',
      'cost_high': 'Cost was too high',
      'sp_timeout': 'Service provider took too long to respond',
      'admin_timeout': 'Admin took too long to respond',
      'other': 'Other',
    };
    if (mounted) {
      setState(() {
        // Create an ordered list from the map using keys for default order
        _orderedCancellationReasons = hardcodedMap.entries.toList()
            .asMap().entries.map((entry) {
          final index = entry.key;
          final code = entry.value.key;
          final reason = entry.value.value;
          return CancellationReason(code, reason, index + 1);
        }).toList();

        cancellationReasonsMap = hardcodedMap; // Keep this for compatibility
      });
    }
  }

// --- Data Handling Methods ---
  Future<String> _generateSingleUniquePin(String boarderId,
      {String? excludePin}) async {
    final random = Random();
    final firestore = FirebaseFirestore.instance;
    String pin = '';
    bool isUnique = false;

    while (!isUnique) {
      pin = (1000 + random.nextInt(9000)).toString();
      if (pin == excludePin) continue;

      final startPinQuery = firestore
          .collectionGroup('service_request_boarding')
          .where('sp_id', isEqualTo: boarderId)
          .where('isStartPinUsed', isEqualTo: false)
          .where('startPinRaw', isEqualTo: pin)
          .limit(1)
          .get();

      final endPinQuery = firestore
          .collectionGroup('service_request_boarding')
          .where('sp_id', isEqualTo: boarderId)
          .where('isEndPinUsed', isEqualTo: false)
          .where('endPinRaw', isEqualTo: pin)
          .limit(1)
          .get();

      final results = await Future.wait([startPinQuery, endPinQuery]);
      isUnique = results[0].docs.isEmpty && results[1].docs.isEmpty;
    }
    return pin;
  }

  Future<Map<String, dynamic>> _generateUniquePins(String boarderId) async {
    final startPin = await _generateSingleUniquePin(boarderId);
    final endPin =
    await _generateSingleUniquePin(boarderId, excludePin: startPin);
    final startPinHash = sha256.convert(utf8.encode(startPin)).toString();
    final endPinHash = sha256.convert(utf8.encode(endPin)).toString();

    return {
      'startPinRaw': startPin,
      'startPinHash': startPinHash,
      'isStartPinUsed': false,
      'endPinRaw': endPin,
      'endPinHash': endPinHash,
      'isEndPinUsed': false,
      'pinsCreatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<_FeesData> _fetchFees() async {
    final snap = await FirebaseFirestore.instance
        .collection('company_documents')
        .doc('fees')
        .get();
    final data = snap.data() ?? {};
    final double platformFeePreGst =
        double.tryParse(data['platform_fee_user_app']?.toString() ?? '7.0') ??
            7.0;
    final double gstPercentageForDisplay =
        double.tryParse(data['gst_rate_percent']?.toString() ?? '') ?? 0.0;
    final double gstRateDecimal = gstPercentageForDisplay / 100.0;
    final double platformFeeGst = platformFeePreGst * gstRateDecimal;

    return _FeesData(
        platformFeePreGst, platformFeeGst, gstPercentageForDisplay);
  }

  Future<void> _saveFcmToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await _messaging.getToken();
    if (token != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({'fcmToken': token}, SetOptions(merge: true));
    }
  }

// --- Dialog & Cancellation Logic ---
  Future<void> _confirmAndCancelBooking() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 5,
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red.shade600, size: 50),
              const SizedBox(height: 16),
              Text('Cancel Request?', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: darkColor), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('Are you sure you want to cancel this request?', style: GoogleFonts.poppins(fontSize: 14, color: lightTextColor), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: primaryColor, width: 2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text('NO', style: GoogleFonts.poppins(color: primaryColor, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.red.shade600,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.red.shade600, width: 1.4)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text('Yes, Cancel', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm != true) return;

    List<String> selectedReasons = [];
    TextEditingController otherController = TextEditingController();

    // (Existing simplified cancellation dialog logic omitted for brevity, keeping original flow)
    await _showCancellationReasonDialog(selectedReasons, otherController);
  }

  Future<void> _showCancellationReasonDialog(
      List<String> selectedReasons,
      TextEditingController otherController,
      ) async {
    bool showOtherText = false;
    String? validationMessage;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12), // less round
              ),
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.symmetric(horizontal: 26),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // Title
                    Text(
                      "Why are you cancelling?",
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 14),
                    Divider(height: 1, color: Colors.grey.shade300),
                    const SizedBox(height: 10),

                    // REASONS LIST
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: _orderedCancellationReasons.map((reasonObj) {
                            final code = reasonObj.code;
                            final reasonText = reasonObj.reason;

                            return CheckboxListTile(
                              dense: true,
                              activeColor: AppColors.accentColor,
                              title: Text(
                                reasonText, // Use the human-readable reason
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                              value: selectedReasons.contains(code),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    selectedReasons.add(code);
                                  } else {
                                    selectedReasons.remove(code);
                                  }
                                  showOtherText = selectedReasons.contains('other');
                                });
                              },
                              controlAffinity: ListTileControlAffinity.leading,
                            );
                          }).toList(),
                        ),
                      ),
                    ),

                    // OTHER TEXT FIELD
                    if (showOtherText) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: otherController,
                        maxLines: 2,
                        style: GoogleFonts.poppins(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: "Tell us more...",
                          hintStyle: GoogleFonts.poppins(
                            color: Colors.grey,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                            BorderSide(color: Colors.grey.shade300, width: 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                            BorderSide(color: AppColors.accentColor, width: 1.2),
                          ),
                        ),
                      ),
                    ],

                    if (validationMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        validationMessage!,
                        style: GoogleFonts.poppins(
                          color: Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // BUTTONS
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(color: Colors.grey.shade400),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              "Close",
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 10),

                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              if (selectedReasons.isEmpty) {
                                setState(() => validationMessage = "Select a reason");
                                return;
                              }

                              final Map<String, String> reasonMap = {};
                              for (final code in selectedReasons) {
                                if (code == "other") {
                                  reasonMap[code] = otherController.text.trim();
                                } else {
                                  reasonMap[code] = cancellationReasonsMap[code]!;
                                }
                              }

                              Navigator.pop(ctx);
                              await _finalizeCancellation(reasonMap);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade600,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              "Submit",
                              style: GoogleFonts.poppins(
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
            );
          },
        );
      },
    );
  }

  Future<void> _finalizeCancellation(Map<String, String> reasonMap) async {
    final fs = FirebaseFirestore.instance;
    final bookingRef = fs.collection('users-sp-boarding').doc(widget.serviceId).collection('service_request_boarding').doc(widget.bookingId);
    final cancelledRef = fs.collection('users-sp-boarding').doc(widget.serviceId).collection('cancelled_requests').doc(widget.bookingId);

    try {
      final snap = await bookingRef.get();
      if (!snap.exists) return;
      final data = snap.data()!;
      final petServicesSnap = await bookingRef.collection('pet_services').get();

      List<WriteBatch> batches = [fs.batch()];
      int opCount = 0;
      void _ensureBatchCapacity() {
        if (opCount >= 450) { batches.add(fs.batch()); opCount = 0; }
      }

      final bookedDates = (data['selectedDates'] as List<dynamic>? ?? []).cast<Timestamp>();
      final numberOfPets = data['numberOfPets'] as int? ?? 0;
      if (numberOfPets > 0 && bookedDates.isNotEmpty) {
        for (final ts in bookedDates) {
          final date = ts.toDate();
          final dateId = DateFormat('yyyy-MM-dd').format(date);
          final summaryRef = fs.collection('users-sp-boarding').doc(widget.serviceId).collection('daily_summary').doc(dateId);
          _ensureBatchCapacity();
          batches.last.update(summaryRef, {'bookedPets': FieldValue.increment(-numberOfPets)});
          opCount++;
        }
      }

      _ensureBatchCapacity();
      batches.last.set(cancelledRef, {...data, 'cancelled_at': FieldValue.serverTimestamp(), 'cancellation_reason': reasonMap}, SetOptions(merge: true));
      opCount++;

      for (final d in petServicesSnap.docs) {
        final srcData = d.data();
        final destRef = cancelledRef.collection('pet_services').doc(d.id);
        _ensureBatchCapacity();
        batches.last.set(destRef, srcData, SetOptions(merge: false));
        opCount++;
      }

      for (final d in petServicesSnap.docs) {
        _ensureBatchCapacity();
        batches.last.delete(d.reference);
        opCount++;
      }

      _ensureBatchCapacity();
      batches.last.delete(bookingRef);
      opCount++;

      for (final b in batches) { await b.commit(); }

      if (mounted) {
        // 🚨 CORRECTED NAVIGATION: Use pushAndRemoveUntil to replace ALL routes
        // with HomeWithTabs, ensuring a clean navigation stack.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => HomeWithTabs()),
              (Route<dynamic> route) => false, // This predicate returns false for all routes, removing all history
        );
      }
    } catch (e) {
      debugPrint("Error during cancellation: $e");
    }
  }

// --- Payment & Booking Logic ---
  Future<void> _book() async {
    if (_isProcessingPayment) return;

    // (Confirmation Dialog logic same as before)
    // [Your confirmation dialog is unchanged]

    final ok = await showDialog<bool>(

      context: context,

      barrierDismissible: false,

      barrierColor: Colors.black.withOpacity(0.3), // subtle dim

      builder: (ctx) {

        final theme = Theme.of(ctx);

        return Theme(

          data: theme.copyWith(

            dialogTheme: DialogTheme(

              backgroundColor: Colors.white,

              shape: RoundedRectangleBorder(

                borderRadius: BorderRadius.circular(8), // ↓ less curved

                side: BorderSide(
                  color: AppColors.accentColor.withValues(alpha: 31),
                ),

              ),

              elevation: 6,

            ),

            textButtonTheme: TextButtonThemeData(

              style: TextButton.styleFrom(

                foregroundColor: AppColors.accentColor,

                shape: RoundedRectangleBorder(

                  borderRadius: BorderRadius.circular(8),

                ),

              ),

            ),

          ),

          child: AlertDialog(

            titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),

            contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),

            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),

            title: Row(

              children: [

                Icon(Icons.payments_rounded, color: AppColors.accentColor, size: 20),

                const SizedBox(width: 8),

                const Text(

                  'Confirm Booking',

                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),

                ),

              ],

            ),

            content: const Text(

              'Confirm and proceed to payment?',

              style: TextStyle(fontSize: 14.5, height: 1.25, color: Colors.black87),

            ),

            actionsAlignment: MainAxisAlignment.end,

            actions: [

              OutlinedButton(

                style: OutlinedButton.styleFrom(

                  side: BorderSide(color: AppColors.accentColor.withValues(alpha: (0.35 * 255))),

                  shape: RoundedRectangleBorder(

                    borderRadius: BorderRadius.circular(8),

                  ),

                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),

                ),

                onPressed: () => Navigator.pop(ctx, false),

                child: const Text('Cancel', style: TextStyle(color: Colors.black87),),

              ),

              FilledButton(

                style: FilledButton.styleFrom(

                  backgroundColor: AppColors.accentColor,

                  foregroundColor: Colors.white,

                  shape: RoundedRectangleBorder(

                    borderRadius: BorderRadius.circular(8),

                  ),

                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),

                ),

                onPressed: () => Navigator.pop(ctx, true),

                child: const Text('Confirm'),

              ),

            ],

          ),

        );

      },

    ) ?? false;

    if (!ok) return;

    setState(() => _isProcessingPayment = true);

    try {
      final settingsDoc = await FirebaseFirestore.instance.collection('settings').doc('payment').get();
      final settingsData = settingsDoc.data() ?? {};
      final userAppPayment = settingsData['user_app_payment'] as Map<String, dynamic>? ?? {};
      final bool isLiveMode = userAppPayment['home_boarding'] as bool? ?? false;

      final String razorpayKey = isLiveMode ? const String.fromEnvironment('LIVE_RAZORPAY_KEY') : const String.fromEnvironment('TEST_RAZORPAY_KEY');
      final String createOrderUrl = isLiveMode ? const String.fromEnvironment('LIVE_ORDER_URL') : const String.fromEnvironment('TEST_ORDER_URL');

      if (razorpayKey.isEmpty || createOrderUrl.isEmpty) {
        setState(() => _isProcessingPayment = false);
        return;
      }

      double newBoardingCost = 0.0;
      final datesCount = widget.selectedDates.length;
      for (final pet in widget.petSizesList) {
        final boardingRatePerDay = (pet['price'] as double?) ?? 0.0;
        newBoardingCost += boardingRatePerDay * datesCount;
      }

      final double grandTotal = (checkoutEnabled)
          ? widget.totalAmountPaid - (gstRegistered ? 0.0 : widget.gstOnSpService)
          : widget.totalAmountPaid
          - widget.platformFeeIncGst
          - (gstRegistered ? 0.0 : widget.gstOnSpService);


      final int amountPaise = (grandTotal * 100).toInt();
      final pinData = await _generateUniquePins(widget.sp_id);
      final ord = await _createOrder(amountPaise, createOrderUrl);
      final orderId = (ord['id'] ?? (ord['order'] is Map ? ord['order']['id'] : null))?.toString();

      if (orderId == null || orderId.isEmpty) throw Exception('Order-id missing');

      final ref = FirebaseFirestore.instance.collection('users-sp-boarding').doc(widget.serviceId).collection('service_request_boarding').doc(widget.bookingId);
      await ref.set({
        'order_status': 'pending_payment',
        'payment_skipped': false,
        'original_total_amount': grandTotal.toString(),
        'razorpay_order_id': orderId,
        ...pinData,
        'pending_payment_created_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _openCheckout(orderId, razorpayKey);

    } catch (e) {
      setState(() => _isProcessingPayment = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _bookSlot() async {
    setState(() => _isProcessingPayment = true);
    try {
      final pinData = await _generateUniquePins(widget.sp_id);
      final ref = FirebaseFirestore.instance.collection('users-sp-boarding').doc(widget.serviceId).collection('service_request_boarding').doc(widget.bookingId);
      await ref.set({
        'order_status': 'confirmed',
        'status': 'Confirmed',
        'payment_skipped': true,
        'sp_confirmation': true,
        'user_confirmation': true,
        'user_t&c_acceptance': true,
        'confirmed_at': FieldValue.serverTimestamp(),
        'gstRegistered': gstRegistered,
        'checkoutEnabled': checkoutEnabled,
        ...pinData,
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ConfirmationPage(
        gstRegistered: gstRegistered,
        checkoutEnabled: checkoutEnabled,
        dailyRates: widget.dailyRates,
        perDayServices: widget.perDayServices,
        sortedDates: _sortedDates,
        buildOpenHoursWidget: buildOpenHoursWidget(widget.openTime, widget.closeTime, _sortedDates),
        shopName: widget.shopName,
        shopImage: widget.shopImage,
        selectedDates: widget.selectedDates,
        totalCost: widget.totalCost,
        petNames: widget.petNames,
        petImages: widget.petImages,
        openTime: widget.openTime,
        closeTime: widget.closeTime,
        bookingId: widget.bookingId,
        serviceId: widget.serviceId,
        fromSummary: true,
        petIds: widget.petIds,
        foodCost: widget.foodCost,
        walkingCost: widget.walkingCost,
        transportCost: widget.transportCost,
        boarding_rate: widget.boarding_rate,
        mealRates: widget.mealRates,
        walkingRates: widget.walkingRates,
        fullAddress: widget.fullAddress,
        sp_location: widget.sp_location,
        petCostBreakdown: widget.petCostBreakdown,
      )));
    } catch (e) {
      setState(() => _isProcessingPayment = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<Map<String, dynamic>> _createOrder(int amountPaise, String createOrderUrl) async {
    final res = await http.post(Uri.parse(createOrderUrl), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'amount': amountPaise, 'currency': 'INR', 'receipt': 'rcpt_${DateTime.now().millisecondsSinceEpoch}'}));
    if (res.statusCode != 200) throw Exception('API failed');
    return jsonDecode(res.body);
  }

  Future<void> _openCheckout(String orderId, String razorpayKey) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    double newBoardingCost = 0.0;
    final datesCount = widget.selectedDates.length;
    for (final pet in widget.petSizesList) { newBoardingCost += (pet['price'] as double? ?? 0.0) * datesCount; }
    final double grandTotal = (checkoutEnabled) ? widget.totalAmountPaid - (gstRegistered ? 0.0 : widget.gstOnSpService) : widget.totalAmountPaid - widget.platformFeeIncGst - (gstRegistered ? 0.0 : widget.gstOnSpService);
    final int amountInPaise = (grandTotal * 100).toInt();
    final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final d = snap.data() ?? {};

    final opts = {
      'key': razorpayKey,
      'amount': amountInPaise,
      'order_id': orderId,
      'name': widget.shopName,
      'description': 'Booking',
      'prefill': {'contact': d['phone_number'] ?? '', 'email': d['email'] ?? ''},
      'external': {'wallets': ['googlepay']},
    };
    _razorpay.open(opts);
  }

  void _handlePaymentSuccess(PaymentSuccessResponse r) async {
    try {
      final ref = FirebaseFirestore.instance.collection('users-sp-boarding').doc(widget.serviceId).collection('service_request_boarding').doc(widget.bookingId);
      await ref.update({
        'payment_id': r.paymentId,
        'order_id': r.orderId,
        'razorpay_signature': r.signature,
        'order_status': 'confirmed',
        'sp_confirmation': true,
        'user_confirmation': true,
        'user_t&c_acceptance': true,
        'confirmed_at': FieldValue.serverTimestamp(),
        'gstRegistered': gstRegistered,
        'checkoutEnabled': checkoutEnabled,
      });
      // 🌍 Save globally for user
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({
          'lastPaymentMethod': 'UPI',
        }, SetOptions(merge: true));
      }


      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ConfirmationPage(
        gstRegistered: gstRegistered,
        checkoutEnabled: checkoutEnabled,
        perDayServices: widget.perDayServices,
        boarding_rate: widget.boarding_rate,
        petIds: widget.petIds,
        sortedDates: _sortedDates,
        buildOpenHoursWidget: buildOpenHoursWidget(widget.openTime, widget.closeTime, _sortedDates),
        shopName: widget.shopName,
        shopImage: widget.shopImage,
        selectedDates: widget.selectedDates,
        totalCost: widget.totalCost,
        petNames: widget.petNames,
        petImages: widget.petImages,
        openTime: widget.openTime,
        closeTime: widget.closeTime,
        bookingId: widget.bookingId,
        serviceId: widget.serviceId,
        foodCost: widget.foodCost,
        walkingCost: widget.walkingCost,
        transportCost: widget.transportCost,
        mealRates: widget.mealRates,
        walkingRates: widget.walkingRates,
        fullAddress: widget.fullAddress,
        sp_location: widget.sp_location,
        fromSummary: true, dailyRates: widget.dailyRates,
        petCostBreakdown: widget.petCostBreakdown,
      )));
    } catch (e) {
      print("Error: $e");
    }
  }

  void _handlePaymentError(PaymentFailureResponse r) {
    setState(() => _isProcessingPayment = false);
    _alert('Payment Failed', r.message ?? '');
  }

  void _handleExternalWallet(ExternalWalletResponse r) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'lastPaymentMethod': r.walletName ?? 'Wallet',
      }, SetOptions(merge: true));
    }

    _alert('External Wallet', r.walletName ?? '');
  }

  void _alert(String t, String m) => showDialog(context: context, builder: (_) => AlertDialog(title: Text(t), content: Text(m)));

  Future<void> _launchURL(String urlString) async {
    final String encodedUrl = Uri.encodeComponent(urlString);
    final String googleDocsUrl = 'https://docs.google.com/gview?url=$encodedUrl&embedded=true';
    if (!await launchUrl(Uri.parse(googleDocsUrl), mode: LaunchMode.platformDefault)) {
      // handle error
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isProcessingPayment) {
      return const Scaffold(
        backgroundColor: backgroundColor,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users-sp-boarding')
          .doc(widget.serviceId)
          .collection('service_request_boarding')
          .doc(widget.bookingId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2,color: AppColors.primary)));
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final spConfirmationValue = data['sp_confirmation'];
        final isRejected = spConfirmationValue is bool && spConfirmationValue == false;

        return PopScope(
          canPop: false, // block default back
          onPopInvokedWithResult: (didPop, result) async {
            if (!didPop) {
              await _confirmAndCancelBooking();
            }
          },
          child: Scaffold(
            appBar: buildHeaderAppBar(
              context,
              widget.shopName,
              widget.areaNameOnly,
              widget.serviceId,
            ),

            backgroundColor: const Color(0xfff1f1f1),

            body: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 100.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOrderIdBox(widget.bookingId),

                  if (isRejected)
                    _buildRejectionNotice()
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          _buildEmbeddedBookingDetails(),
                          const SizedBox(height: 9),
                          _buildEmbeddedInvoice(),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            bottomNavigationBar: !isRejected
                ? SafeArea(
              top: false,
              child: _bottomBar(context),
            )
                : null,
          ),
        );
      },
    );
  }
  Widget _buildOrderIdBox(String orderId) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),

      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.black.withValues(alpha: (0.30 * 255)),
          width: 0.9,
        ),
      ),

      child: Row(
        children: [
          Icon(
            Icons.confirmation_number_rounded,
            size: 16,
            color: AppColors.success,
          ),

          const SizedBox(width: 8),

          // Dynamic, no substring — ellipsis handles everything
          Expanded(
            child: Text(
              "Order ID: $orderId",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.black,
              ),
            ),
          ),

          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: orderId));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Order ID copied!"),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: Icon(
              Icons.copy,
              size: 14,
              color: AppColors.black,
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildEmbeddedBookingDetails() {
    return Card(
      elevation: 0.8,
      shadowColor: AppColors.primaryColor.withValues(alpha: (0.20 * 255)),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔵 TOP TITLE STRIP
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.primaryColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Text(
              "Booking Details",
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),

          // 🔽 MAIN CONTENT
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 12),
            child: Column(
              children: List.generate(widget.petIds.length, (index) {
                final petId = widget.petIds[index];
                final petName = widget.petNames[index];
                final petImage = widget.petImages[index];
                final petServiceDetails = widget.perDayServices[petId];

                if (petServiceDetails == null) return const SizedBox.shrink();

                final dailyDetails =
                petServiceDetails['dailyDetails'] as Map<String, dynamic>;
                final sortedDatesForPet = dailyDetails.keys.toList()..sort();

                return ExpansionTile(
                  iconColor: Colors.black87,
                  collapsedIconColor: Colors.black87,

                  leading: CircleAvatar(
                    backgroundImage: NetworkImage(petImage),
                    radius: 18,
                  ),
                  title: Text(
                    petName,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    "${dailyDetails.length} days",
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  childrenPadding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 16),

                  shape: const Border(), // removes default outline
                  children: [
                    ...sortedDatesForPet.map((dateString) {
                      final date =
                      DateFormat('yyyy-MM-dd').parse(dateString);
                      final details =
                      dailyDetails[dateString] as Map<String, dynamic>;

                      final hasMeal = details['meals'] == true;
                      final hasWalk = details['walk'] == true;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            Text(
                              DateFormat('EEE, dd MMM').format(date),
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                            const Spacer(),

                            if (hasMeal)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Icon(
                                  Icons.restaurant_menu,
                                  size: 14,
                                  color: AppColors.primaryColor,
                                ),
                              ),

                            if (hasWalk)
                              Icon(
                                Icons.directions_walk,
                                size: 14,
                                color: AppColors.primaryColor,
                              ),
                          ],
                        ),
                      );
                    }),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
  PreferredSizeWidget buildHeaderAppBar(
      BuildContext context,
      String shopName,
      String areaName,
      String orderId,
      ) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      automaticallyImplyLeading: false,
      toolbarHeight: 68,

      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new,
            color: Colors.black, size: 18),
        onPressed: () async {
          // Show the cancellation dialog instead of popping directly
          await _confirmAndCancelBooking();
        },
      ),


      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            shopName,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🎯 MODIFIED: GestureDetector added to the text to open the dialog
              GestureDetector(
                onTap: () => _showOrderDetailsDialog(
                    context,
                    areaName,
                    orderId // Pass the full order ID
                ),
                child: Text(
                  "${areaName.substring(0, 9)}..  |  ${orderId.substring(0, 11)}..",
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    color: Colors.grey.shade600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              const SizedBox(width: 4),

              // Copy button remains dedicated to copying the ID
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: orderId)); // copy full order id
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Order ID copied!"),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: const Icon(
                  Icons.copy,
                  size: 14,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ],
      ),

      actions: [
        TextButton(
          onPressed: () async {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserOrderSupportPage(
                  initialOrderId: widget.bookingId,
                  serviceId: widget.serviceId,
                  shop_name: widget.shopName,
                  user_phone_number: FirebaseAuth.instance.currentUser?.phoneNumber,
                  user_uid: FirebaseAuth.instance.currentUser?.uid, // if you don’t store email, keep blank
                ),
              ),
            );
          },


          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                FontAwesomeIcons.headset,
                size: 20,
                color: Colors.black87,
              ),
            ],
          ),
        )
      ],
    );
  }
  // lib/screens/Boarding/SummaryPage.dart (Add this helper function)

  void _showOrderDetailsDialog(BuildContext context, String fullAreaName, String fullOrderId) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;
    const Color primaryColor = AppColors.primaryColor;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              width: isSmallScreen ? screenWidth * 0.9 : 450,

              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // 1. Title
                  Text(
                    "Booking Identification Details",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: isSmallScreen ? 18 : 20,
                      color: Colors.black87,
                    ),
                  ),
                  const Divider(height: 20, color: Colors.grey),

                  // 2. Order ID
                  _buildDetailRow(
                    icon: Icons.confirmation_number_rounded,
                    title: "Full Order ID",
                    value: fullOrderId,
                    isSmallScreen: isSmallScreen,
                    context: context,
                  ),

                  const SizedBox(height: 12),

                  // 3. Area Name
                  _buildDetailRow(
                    icon: Icons.location_on_rounded,
                    title: "Service Area Name",
                    value: fullAreaName,
                    isSmallScreen: isSmallScreen,
                    context: context,
                  ),

                  const SizedBox(height: 20),

                  // 4. Close Button
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(
                        "Close",
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: isSmallScreen ? 14 : 15,
                          color: primaryColor,
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
    );
  }

// Helper widget for a single row in the dialog
  Widget _buildDetailRow({
    required IconData icon,
    required String title,
    required String value,
    required bool isSmallScreen,
    required BuildContext context,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primaryColor),
            const SizedBox(width: 8),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: isSmallScreen ? 13 : 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 26),
          child: SelectableText( // Use SelectableText to allow copying the full value
            value,
            style: GoogleFonts.poppins(
              fontSize: isSmallScreen ? 14 : 15,
              fontWeight: FontWeight.w500,
              color: Colors.black,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
 /* Widget _supportIcon(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('settings')
              .doc('contact_details')
              .get();

          final whatsappNumber =
          doc.data()?['whatsapp_user_support_number'];

          if (whatsappNumber == null || whatsappNumber.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Support number not found')),
            );
            return;
          }

          final cleanNumber = whatsappNumber.replaceAll('+', '').trim();
          final message = Uri.encodeComponent("Hey, I need help with my booking 🐾");
          final whatsappUrl =
          Uri.parse("https://wa.me/$cleanNumber?text=$message");

          if (await canLaunchUrl(whatsappUrl)) {
            await launchUrl(
              whatsappUrl,
              mode: LaunchMode.externalApplication,
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open WhatsApp')),
            );
          }
        } catch (e) {
          debugPrint("❌ $e");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Something went wrong. Please try again.')),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(right: 14),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 4,
            )
          ],
        ),
        padding: const EdgeInsets.all(6),
        child: const Icon(
          Icons.headset_mic_rounded,
          color: Colors.black,
          size: 20,
        ),
      ),
    );
  }*/


  Widget _buildEmbeddedInvoice() {
    return FutureBuilder<_FeesData>(
      future: _feesFuture,
      builder: (_, snap) {
        if (!snap.hasData) {
          return const SizedBox(
            height: 60,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final fees = snap.data!;

        final double newBoardingCost = widget.petCostBreakdown
            .fold(0.0, (p, m) => p + (m['totalBoardingCost'] as double? ?? 0.0));

        final double newMealsCost = widget.petCostBreakdown
            .fold(0.0, (p, m) => p + (m['totalMealCost'] as double? ?? 0.0));

        final double newWalkingCost = widget.petCostBreakdown
            .fold(0.0, (p, m) => p + (m['totalWalkingCost'] as double? ?? 0.0));

        final double serviceGst =
        gstRegistered ? widget.gstOnSpService : 0.0;
        // 1. Core Service Cost (Boarding + Meal + Walk)
        double serviceSubtotal = newBoardingCost + newMealsCost + newWalkingCost;

        // 2. Add Service Provider's GST (only if registered)
        double serviceGstComponent = gstRegistered ? widget.gstOnSpService : 0.0;

        // 3. Add Platform Fee components (only if checkout is ENABLED)
        double platformFeeComponent = checkoutEnabled ? (widget.platformFeeExcGst + widget.gstOnPlatformFee) : 0.0;

        // 4. Final calculation based on components
        double overallTotal = serviceSubtotal + serviceGstComponent + platformFeeComponent;

        return Card(
          elevation: 0.8,
          shadowColor: AppColors.primaryColor.withOpacity(0.25),
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // 🔵 TOP TITLE STRIP
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.primaryColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Text(
                  "Invoice Summary",
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),

              // 🔽 MAIN CONTENT
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: Column(
                  children: [
                    _buildItemRow("Boarding Fee", newBoardingCost),
                    if (newMealsCost > 0)
                      _buildItemRow("Meal Fee", newMealsCost),
                    if (newWalkingCost > 0)
                      _buildItemRow("Walking Fee", newWalkingCost),

                    if (gstRegistered || checkoutEnabled) ...[
                      const SizedBox(height: 10),
                      Divider(color: Colors.grey.shade300),
                      const SizedBox(height: 10),
                    ],

                    if (gstRegistered)
                      _buildItemRow(
                        "GST (${fees.gstPercentage.toStringAsFixed(0)}%) on Service",
                        serviceGst,
                      ),

                    if (checkoutEnabled) ...[
                      _buildItemRow("Platform Fee", widget.platformFeeExcGst),
                      _buildItemRow("GST on Platform Fee", widget.gstOnPlatformFee),
                    ],

                    const SizedBox(height: 12),
        Divider(color: darkColor, thickness: 1.5, height: 25), // Strong divider
                    // Calculate the final Grand Total
                    // This uses the widget's pre-calculated total cost, which should include all component fees, transport, and initial GST.
                    _buildItemRow(
                      "Overall Total",
                      overallTotal, // 🚨 Use the manually calculated total
                      isTotal: true,
                    ),

                    const SizedBox(height: 12),// Spacer before the toggle

                    // 🔽 Toggle Per Pet Breakdown
                    InkWell(
                      onTap: () => setState(
                              () => _showPetBreakdown = !_showPetBreakdown),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _showPetBreakdown
                                ? "Hide Details"
                                : "View Details",
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryColor,
                            ),
                          ),
                          Icon(
                            _showPetBreakdown
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 18,
                            color: AppColors.primaryColor,
                          ),
                        ],
                      ),
                    ),

                    AnimatedCrossFade(
                      firstChild: const SizedBox.shrink(),
                      secondChild: Column(
                        children: [_buildPerPetDailyBreakdown()],
                      ),
                      crossFadeState: _showPetBreakdown
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 300),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bottomBar(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users-sp-boarding').doc(widget.serviceId).collection('service_request_boarding').doc(widget.bookingId).snapshots(),
      builder: (ctxBook, bookSnap) {
        if (!bookSnap.hasData) return const SizedBox.shrink();

        final d = bookSnap.data!.data() as Map<String, dynamic>;
        final paymentLabel = lastPaymentMethod ?? "UPI";
        final spConfirmed = d['sp_confirmation'] == true;
        final tncAccepted = d['user_t&c_acceptance'] == true;

        // Calculate Logic
        final readyForConfirmation = spConfirmed && tncAccepted;
        final useCheckout = readyForConfirmation && checkoutEnabled;
        final PayDorPay2B = checkoutEnabled;
        final currentUser = FirebaseAuth.instance.currentUser!;

        double grandTotal;
        if (checkoutEnabled) {
          grandTotal = widget.totalAmountPaid - (gstRegistered ? 0.0 : widget.gstOnSpService);
        } else {
          grandTotal = widget.totalAmountPaid - widget.platformFeeIncGst - (gstRegistered ? 0.0 : widget.gstOnSpService);
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, -4))],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min, // Important for compact height
              children: [
                if (!spConfirmed)
                  Column(children: [
                    _buildCompactStatusRow(currentUser.uid),
                    _buildBannerButtons(context),
                  ])
                else if (spConfirmed && !tncAccepted)
                  Column(children: [
                    _buildActionRequiredBanner(),
                    _buildBannerButtons(context),
                  ]),

                // --- PAYMENT ROW (CLEAN MODERN VERSION) ---
                // --- PAYMENT ROW (MODERN + PAYMENT METHOD SHOWN) ---
                if (spConfirmed && tncAccepted)
                  Column(children: [
                    _buildPaymentBanner(),
                    _buildBannerButtons(context),
                  ]),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Row(
                    children: [

// tight spacing with button

                      // --- BUTTON ---
                      Expanded(
                        child: ElevatedButton(
                          onPressed: !spConfirmed
                              ? null
                              : (spConfirmed && !tncAccepted)
                              ? () => FirebaseFirestore.instance
                              .collection('users-sp-boarding')
                              .doc(widget.serviceId)
                              .collection('service_request_boarding')
                              .doc(widget.bookingId)
                              .update({'user_t&c_acceptance': true})
                              : (_isProcessingPayment
                              ? null
                              : (useCheckout ? _book : _bookSlot)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: !spConfirmed
                                ? Colors.grey.shade300
                                : (spConfirmed && !tncAccepted ? primaryColor : secondaryColor),
                            // 👇 TWEAK 1: Reduced padding so 2 lines fit comfortably
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          // 👇 TWEAK 2: Logic to show Payment text
                          // 👇 TWEAK 2: Logic to show Payment text
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // --- TOP LINE: Main Action ---
                              Text(
                                !spConfirmed
                                    ? "Book"
                                    : (!tncAccepted // If confirmed but T&C not accepted
                                    ? "Accept & Continue"
                                    : (PayDorPay2B ? "Pay Now" : "Confirm Slot")),
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  height: 1.1,
                                  color: !spConfirmed ? Colors.grey.shade600 : Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),

                              // --- BOTTOM LINE: Price/Location ---
                              // Only show this if we are fully confirmed AND accepted T&C
                              if (spConfirmed && tncAccepted) ...[
                                const SizedBox(height: 2),
                                Text(
                                  PayDorPay2B
                                      ? "(Pay ₹${grandTotal.toStringAsFixed(0)})"
                                      : "(Pay at the Boarding Center)",
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                ),
                              ]
                            ],
                          ),                        ),
                      ),
                    ],
                  ),
                )


              ],
            ),
          ),
        );
      },
    );
  }
  Widget _buildCompactStatusRow(String userId) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [

          // 🟠 Orange Circle with loading spinner
          Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              color: Colors.orange,
              shape: BoxShape.circle,
            ),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: CircularProgressIndicator(
                strokeWidth: 7,
                color: Colors.white,
              ),
            ),
          ),

          const SizedBox(width: 14),

          // Text Column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Awaiting Confirmation",
                  style: GoogleFonts.poppins(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: darkColor,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  "Hang tight, your request is being reviewed by the boarder.",
                  // ↑ 3–4 more natural words: “Hang tight,” “being reviewed”
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    color: Colors.black87,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),

        ],
      ),
    );
  }
  Widget _buildActionRequiredBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [

          // 🟢 Green Circle Tick
          Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 24),
          ),

          const SizedBox(width: 14),

          // Text Column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Boarder Approved!",
                  style: GoogleFonts.poppins(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: darkColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Please review & accept to proceed. By accepting, you agree to the partner’s policies.",
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    color: Colors.black87,
                    height: 1.3,
                  ),
                ),

              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [


          // 🟢 Green Circle Tick
          Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 24),
          ),

          const SizedBox(width: 14),

          // Text Column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Text(
                  "Complete the payment to confirm your booking.",
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    color: Colors.black87,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBannerButtons(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    // Responsive scaling
    final double vPad = width * 0.025; // vertical padding dynamic
    final double fontSize = width * 0.032; // 11–14 depending on screen
    final double radius = width * 0.03; // responsive radius

    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 10, right: 10),
      child: Row(
        children: [
          // CHAT BUTTON
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                side: BorderSide(color: primaryColor, width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radius),
                ),
                padding: EdgeInsets.symmetric(vertical: vPad),
              ),
              onPressed: () {
                final chatId = '${widget.serviceId}_${widget.bookingId}';
                FirebaseFirestore.instance
                    .collection('chats')
                    .doc(chatId)
                    .update({
                  'lastReadBy_${FirebaseAuth.instance.currentUser!.uid}':
                  FieldValue.serverTimestamp()
                });
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => BoardingChatScreen(chatId: chatId, bookingId: widget.bookingId, serviceId : widget.serviceId, shopName: widget.shopName)),
                );
              },
              child: Text(
                "Chat with Boarder",
                style: GoogleFonts.poppins(
                  color: primaryColor,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // POLICY BUTTON
          Expanded(child: _partnerPolicyButton(context)),
        ],
      ),
    );
  }

  Widget _partnerPolicyButton(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    // Responsive size scaling
    final double vPad = width * 0.025; // vertical padding
    final double fontSize = width * 0.032; // responsive font
    final double radius = width * 0.03;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users-sp-boarding')
          .doc(widget.serviceId)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final spData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final policyUrl = spData['partner_policy_url'] as String?;

        if (policyUrl == null || policyUrl.isEmpty) {
          return const SizedBox.shrink();
        }

        return OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            side: const BorderSide(color: Colors.black87),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
            ),
            padding: EdgeInsets.symmetric(vertical: vPad),
          ),
          onPressed: () => _launchURL(policyUrl),

          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.picture_as_pdf_rounded,
                color: Colors.red,
                size: fontSize + 2,
              ),
              const SizedBox(width: 6),

              Text(
                "Partner Policy",
                style: GoogleFonts.poppins(
                  color: Colors.black87,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }




  // (Keeping _buildItemRow, _buildPerPetDailyBreakdown, _buildRejectionNotice exactly as they were in your previous code or slightly cleaned up for embedding)
  Widget _buildItemRow(String label, double amount, {bool isTotal = false}) {
    final textStyle = GoogleFonts.poppins(fontSize: 14, fontWeight: isTotal ? FontWeight.bold : FontWeight.w500, color: isTotal ? darkColor : lightTextColor);
    final amountStyle = GoogleFonts.poppins(fontSize: 14, fontWeight: isTotal ? FontWeight.bold : FontWeight.w600, color: darkColor);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [Text(label, style: textStyle), const Spacer(), Text('₹${amount.toStringAsFixed(2)}', style: amountStyle)]),
    );
  }

  Widget _buildPerPetDailyBreakdown() {
    // (Pasted your exact logic for breakdown here)
    return Column(
      children: List.generate(widget.petIds.length, (index) {
        final petId = widget.petIds[index];
        final petName = widget.petNames[index];
        final serviceDetails = widget.perDayServices[petId];
        if (serviceDetails == null) return const SizedBox.shrink();

        final dailyDetails = serviceDetails['dailyDetails'] as Map<String, dynamic>;
        final petSize = serviceDetails['size'] as String;
        final List<Widget> dailyRows = [];
        final sortedDates = dailyDetails.keys.toList()..sort((a, b) => a.compareTo(b));

        final breakdownEntry = widget.petCostBreakdown.map((e) => Map<String, dynamic>.from(e)).where((b) => b['id'] == petId).singleOrNull;
        final bool entryIsValid = breakdownEntry != null && breakdownEntry.isNotEmpty;
        final double boardingRatePerDay = entryIsValid ? (breakdownEntry['boardingRatePerDay'] as double? ?? 0.0) : 0.0;
        final double walkingRatePerDay = entryIsValid ? (breakdownEntry['walkingRatePerDay'] as double? ?? 0.0) : 0.0;
        final double mealRatePerDay = entryIsValid ? (breakdownEntry['mealRatePerDay'] as double? ?? 0.0) : 0.0;

        for (final dateString in sortedDates) {
          final date = DateFormat('yyyy-MM-dd').parse(dateString);
          final daily = dailyDetails[dateString] as Map<String, dynamic>;
          final bool hasWalk = daily['walk'] ?? false;
          final bool hasMeals = daily['meals'] ?? false;

          dailyRows.add(
            Padding(
              padding: const EdgeInsets.only(top: 8.0, left: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ${DateFormat('MMM d').format(date)}', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: darkColor)),
                  Padding(
                    padding: const EdgeInsets.only(left: 12.0),
                    child: Column(
                      children: [
                        _buildItemRow('Boarding', boardingRatePerDay),
                        if (hasWalk) _buildItemRow('Walking', walkingRatePerDay),
                        if (hasMeals) _buildItemRow('Meals', mealRatePerDay),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$petName (Size: $petSize)', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: secondaryColor)),
              ...dailyRows,
            ],
          ),
        );
      }),
    );
  }
  Widget _buildRejectionNotice() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: primaryColor.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: primaryColor.withOpacity(0.3))),
        child: Column(
          children: [
            Text("Booking Request Denied", style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.red.shade600)),
            const SizedBox(height: 12),
            Text("The boarder couldn't fit your request. We're sorry!", style: GoogleFonts.poppins(color: lightTextColor)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeWithTabs(initialTabIndex: 1)));
              },
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white),
              child: Text("Find Other Shops"),
            ),
          ],
        ),
      ),
    );
  }
}
class _FeesData {
  final double platformFeePreGst;
  final double platformFeeGst;
  final double gstPercentage;
  _FeesData(this.platformFeePreGst, this.platformFeeGst, this.gstPercentage);
}