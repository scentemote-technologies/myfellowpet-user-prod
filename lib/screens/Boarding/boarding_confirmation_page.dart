import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

import '../../app_colors.dart';
import '../../main.dart';
import '../HomeScreen/HomeScreen.dart';
import '../Orders/BoardingOrders.dart';
import '../Tickets/chat_support.dart';
import '../refund/refund_input_page.dart';
import 'OpenCloseBetween.dart';

// --- Main Confirmation Page Widget ---


// 🔽🔽🔽 REPLACE the existing _FeesData class 🔽🔽🔽
class _FeesData {
  final double platformFeePreGst;
  final double platformFeeGst;
  final double gstPercentage;

  // Provide the old names as getters for backward compatibility within this widget if needed
  double get platform => platformFeePreGst;
  double get gst => platformFeeGst;


  _FeesData(this.platformFeePreGst, this.platformFeeGst, this.gstPercentage);
}

class ConfirmationPage extends StatefulWidget  {
  final bool gstRegistered;
  final bool checkoutEnabled;
  final String shopName;
  final String gstNumber;
  final String bookingId;
  final String serviceId;
  final bool fromSummary;
  final String shopImage;
  final double boarding_rate;
  final List<DateTime> selectedDates;
  final double totalCost;
  final List<String> petNames;
  final String openTime;
  final String closeTime;
  final Widget buildOpenHoursWidget;
  final List<DateTime> sortedDates;
  final List<String> petImages;

  // Add these inside your ConfirmationPage class
  final Map<String, dynamic> perDayServices;
  final List<String> petIds;
  final double? foodCost;
  final double? walkingCost;
  final double? transportCost;
  final Map<String, int> mealRates;
  final Map<String, int> dailyRates;
  final Map<String, int> walkingRates;
  final String fullAddress;
  final GeoPoint sp_location;

  // NEW PARAMETER: Pet Cost Breakdown
  final List<Map<String, dynamic>> petCostBreakdown;

  const ConfirmationPage({
    Key? key,
    required this.shopName,
    required this.shopImage,
    required this.gstRegistered,
    required this.checkoutEnabled,
    required this.selectedDates,
    required this.totalCost,
    required this.petNames,
    required this.openTime,
    required this.closeTime,
    required this.bookingId,
    required this.buildOpenHoursWidget,
    required this.sortedDates,
    required this.petImages,
    required this.serviceId,
    required this.fromSummary,

    required this.perDayServices,
    required this.petIds,
    required this.foodCost,
    required this.walkingCost,
    required this.transportCost,
    required this.mealRates,
    required this.walkingRates,
    required this.fullAddress,
    required this.sp_location, required this.boarding_rate, required this.dailyRates,
    required this.petCostBreakdown, required this.gstNumber, // <<< NEW PARAMETER
  }) : super(key: key);

  // --- Constants for Styling ---
  static const Color accentColor = Color(0xFF00C2CB);
  static const Color primaryTextColor = Color(0xFF1A2528);
  static const Color secondaryTextColor = Color(0xFF657D83);
  static const Color backgroundColor = Color(0xFFF8F9FA);
  static const Color cardColor = Colors.white;

  @override
  _ConfirmationPageState createState() => _ConfirmationPageState();
}

class _ConfirmationPageState extends State<ConfirmationPage> {



  static const Color primaryColor = Color(0xFF00C2CB);

  static const Color secondaryColor = Color(0xFF0097A7);

  static const Color accentColor = Color(0xFFFF9800);

  static const Color darkColor = Color(0xFF263238);

  static const Color lightTextColor = Color(0xFF757575);

  static const Color backgroundColor = Color(0xFFFFFFFF);

  late final Future<_CombinedData> _combinedDataFuture;


  // Inside _ConfirmationPageState
  late final Future<_FeesData> _feesFuture;

  @override
  void initState() {
    super.initState();
    _combinedDataFuture = _fetchAllData();
  }



// --- NEW COMBINED FETCH FUNCTION ---
  Future<_CombinedData> _fetchAllData() async {
    // 1. Fetch SP Document (users-sp-boarding/widget.serviceId)
    final spDocFuture = FirebaseFirestore.instance
        .collection('users-sp-boarding')
        .doc(widget.serviceId) // FIX: widget. added
        .get();

    // 2. Fetch Fees Document (company_documents/fees)
    final feesDocFuture = FirebaseFirestore.instance
        .collection('company_documents')
        .doc('fees')
        .get();

    // Wait for both documents simultaneously
    final results = await Future.wait([spDocFuture, feesDocFuture]);

    final spDoc = results[0] as DocumentSnapshot;
    final feesDoc = results[1] as DocumentSnapshot;

    final spData = spDoc.data() as Map<String, dynamic>? ?? {};
    final feesData = feesDoc.data() as Map<String, dynamic>? ?? {}; // 🚀 FIX: Ensure feesData is explicitly cast to Map<String, dynamic>

// Now the access below should work:
    final double platformFeePreGst =
        double.tryParse(feesData['platform_fee_user_app']?.toString() ?? '7.0') ?? 7.0;

    final double gstPercentageForDisplay =
        double.tryParse(feesData['gst_rate_percent']?.toString() ?? '') ?? 0.0;
// ...
    final double gstRateDecimal = gstPercentageForDisplay / 100.0;
    final double platformFeeGst = platformFeePreGst * gstRateDecimal;
    final fees = _FeesData(platformFeePreGst, platformFeeGst, gstPercentageForDisplay);

    // 4. Extract SP Data
    return _CombinedData(
      areaName: spData['area_name']?.toString() ?? 'Unknown area',
      shopLocation: spData['shop_location'] as GeoPoint? ?? const GeoPoint(0, 0),
      phoneNumber: spData['dashboard_whatsapp']?.toString() ?? 'N/A',
      whatsappNumber: spData['dashboard_whatsapp']?.toString() ?? 'N/A', // Assuming same number for both
      fees: fees,
    );
  }

  Future<void> processRefund(double refundRequest) async {
    final docRef = FirebaseFirestore.instance
        .collection('users-sp-boarding')
        .doc(widget.serviceId)
        .collection('service_request_boarding')
        .doc(widget.bookingId);

    final snap = await docRef.get();
    final data = snap.data()!;

    double remaining = (data['remaining_refundable_amount'] ?? 0).toDouble();
    double refunded = (data['total_refunded_amount'] ?? 0).toDouble();
    double adminFeeTotal = (data['admin_fee_collected_total'] ?? 0).toDouble();
    double adminGstTotal = (data['admin_fee_gst_collected_total'] ?? 0).toDouble();

    double allowed = refundRequest;
    if (allowed > remaining) allowed = remaining;

    double adminFee = allowed * 0.10;
    double adminGst = adminFee * 0.18;

    double netRefund = allowed - adminFee - adminGst;

    await docRef.update({
      'remaining_refundable_amount': remaining - allowed,
      'total_refunded_amount': refunded + allowed,
      'admin_fee_collected_total': adminFeeTotal + adminFee,
      'admin_fee_gst_collected_total': adminGstTotal + adminGst,
    });

    await requestRefund(
      paymentId: data['payment_id'],
      amountInPaise: (netRefund * 100).toInt(),
    );
  }

  Future<void> requestRefund({
    required String paymentId,
    required int amountInPaise,
  }) async {
    await http.post(
      Uri.parse("https://razorpayrefundtest-urjpiqxoca-uc.a.run.app/razorpayRefundTest"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "paymentId": paymentId,
        "amount": amountInPaise,
      }),
    );
  }



  Future<Map<String, String>> _fetchBookingDates() async {
    final doc = await FirebaseFirestore.instance
        .collection('users-sp-boarding')
        .doc(widget.serviceId)
        .collection('service_request_boarding')
        .doc(widget.bookingId)
        .get();

    const String unknown = 'Unknown date';
    final Map<String, String> results = {
      'creationDate': unknown,
      'confirmationDate': unknown,
    };

    if (!doc.exists) return results;
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return results;

    final formatter = DateFormat('dd MMM yyyy, hh:mm a');

    // 1. Retrieve Booking Creation Time ('timestamp')
    final rawCreation = data['timestamp'];
    if (rawCreation is Timestamp) {
      results['creationDate'] = formatter.format(rawCreation.toDate());
    }

    // 2. Retrieve Booking Confirmation Time ('confirmed_at')
    final rawConfirmation = data['confirmed_at'];
    if (rawConfirmation is Timestamp) {
      results['confirmationDate'] = formatter.format(rawConfirmation.toDate());
    }

    return results;
  }
  Future<DocumentSnapshot> _bookingDoc() {
    return FirebaseFirestore.instance
        .collection('users-sp-boarding')
        .doc(widget.serviceId)
        .collection('service_request_boarding')
        .doc(widget.bookingId)
        .get();
  }

  Future<void> _openPhone(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (!await launchUrl(uri)) throw 'Could not call $number';
  }

  Future<void> _openWhatsApp(String number) async {
    final uri = Uri.parse('https://wa.me/$number');
    if (!await launchUrl(uri)) throw 'Could not open WhatsApp';
  }

  Future<void> _openMap(double lat, double lng) async {
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw 'Could not launch $url';
    }
  }

  Widget _buildMainActionsRow() {
    return Row(
      children: [
// Shop Details Button

        Expanded(
          child: _actionDialogButton(
            "Shop Details",
            _showShopDetailsDialog,
          ),
        ),

        const SizedBox(width: 4), // minimal spacing

// Booking Details Button

        Expanded(
          child: _actionDialogButton(
            "Booking Details",
            _showBookingDetailsDialog,
          ),
        ),

        const SizedBox(width: 4),

// Invoice Button

        Expanded(
          child: _actionDialogButton(
            "Invoice",
            _showInvoiceDialog,
          ),
        ),
      ],
    );
  }
  Widget _actionDialogButton(String label, VoidCallback onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: darkColor,
        side: BorderSide(color: Colors.grey.shade300, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        textStyle: GoogleFonts.poppins(
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        alignment: Alignment.center, // Ensures center alignment
      ),
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: darkColor,
          ),
        ),
      ),
    );
  }

  void _showShopDetailsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
// Consistent rounded corners

          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),

// Responsive padding for different screen sizes

          insetPadding:
          const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),

          backgroundColor: backgroundColor,

          titlePadding: EdgeInsets.zero,

          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),

          title: _buildDialogHeader("Shop Details", context),

          content: SizedBox(
// Ensures the dialog width is responsive

            width: MediaQuery.of(context).size.width * 0.9,

// We now use a new, more detailed content widget

            child: SingleChildScrollView(
              child: _buildShopDetailsContent(),
            ),
          ),

          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'CLOSE',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold, color: primaryColor),
              ),
            ),
          ],

          actionsPadding: const EdgeInsets.only(right: 16, bottom: 8),
        );
      },
    );
  }

// Add this new widget to your _SummaryPageState

  Widget _buildShopDetailsContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _shopHeader(),
        const Divider(height: 24, thickness: 1),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.location_pin,
                size: 18, color: darkColor.withOpacity(0.7)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.fullAddress,
                style: GoogleFonts.poppins(
                    fontSize: 14, color: lightTextColor, height: 1.5),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // 🚀 MODIFIED: Use _combinedDataFuture to get location
        FutureBuilder<_CombinedData>(
          future: _combinedDataFuture,
          builder: (context, snapshot) {
            final bool isReady = snapshot.hasData;
            final GeoPoint? location = snapshot.data?.shopLocation;

            return SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.location_on, size: 20, color: Colors.white,),
                label: const Text("View on Map"),
                onPressed: (isReady && location != null)
                    ? () => _openMap(location.latitude, location.longitude)
                    : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: secondaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  disabledBackgroundColor: Colors.grey.shade300,
                ),
              ),
            );
          },
        )
      ],
    );
  }

  Widget _shopHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              widget.shopImage,
              width: 60,
              height: 60,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 60,
                height: 60,
                color: backgroundColor,
                child: const Icon(Icons.store, size: 30, color: lightTextColor),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.shopName,
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: darkColor),
                ),
                const SizedBox(height: 4),

                // --- ADD THIS ROW ---
                Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 14,
                      color: lightTextColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "${widget.openTime} - ${widget.closeTime}",
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: lightTextColor,
                      ),
                    ),
                  ],
                ),
                // --- END OF ADDITION ---

              ],
            ),
          ),
        ],
      ),
    );
  }


// Inside _ConfirmationPageState
  void _showInvoiceDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        bool showPetDetails = false;

        // 1. --- FUTURE BUILDER WRAPS EVERYTHING ---
        return FutureBuilder<_CombinedData>(
          future: _combinedDataFuture,
          builder: (context, snap) {
            if (!snap.hasData) {
              return Center(
                child: Container(
                  height: 150,
                  width: 150,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                      child: CircularProgressIndicator(
                          color: ConfirmationPage.accentColor)),
                ),
              );
            }

            final _CombinedData combinedData = snap.data!;
            final _FeesData fees = combinedData.fees;
            final String gstNumber = widget.gstNumber ?? ''; // Assuming gstNumber field exists

            // Pre-calculate costs (this logic remains outside the inner StateBuilder)
            final double newBoardingCost = widget.petCostBreakdown
                .map<double>((m) => m['totalBoardingCost'] as double? ?? 0.0)
                .fold(0.0, (prev, current) => prev + current);

            final double newMealsCost = widget.petCostBreakdown
                .map<double>((m) => m['totalMealCost'] as double? ?? 0.0)
                .fold(0.0, (prev, current) => prev + current);

            final double newWalkingCost = widget.petCostBreakdown
                .map<double>((m) => m['totalWalkingCost'] as double? ?? 0.0)
                .fold(0.0, (prev, current) => prev + current);

            final double serviceSubTotal =
                newBoardingCost + newMealsCost + newWalkingCost;

            // 2. --- STATEFUL BUILDER (To handle showPetDetails toggle) ---
            return StatefulBuilder(
              builder: (context, setState) {
                final bool gstRegistered = widget.gstRegistered;
                final bool checkoutEnabled = widget.checkoutEnabled;

                double serviceGst = gstRegistered
                    ? serviceSubTotal * (fees.gstPercentage / 100)
                    : 0.0;

                double platformFeeTotal = checkoutEnabled
                    ? (fees.platformFeePreGst + fees.platformFeeGst)
                    : 0.0;

                double grandTotal =
                    serviceSubTotal + serviceGst + platformFeeTotal;

                return DraggableScrollableSheet(
                  expand: false,
                  initialChildSize: 0.8,
                  minChildSize: 0.5,
                  maxChildSize: 0.95,
                  builder: (context, scrollController) {
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(26)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 20,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // 3. --- SHOP NAME & GSTIN CONTAINER (OUTSIDE LISTVIEW) ---
                          // Replaces the two separate, empty Containers you had
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
                            decoration: const BoxDecoration(
                              color: Colors.transparent,
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.shopName,
                                    style: GoogleFonts.poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  // 🚀 Display GSTIN below shop name
                                  if (gstRegistered)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'GSTIN: $gstNumber',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          // --- END SHOP NAME / GSTIN ---

                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                            child: Divider(
                                color: darkColor,
                                thickness: 2.5,
                                height: 25), // Strong divider
                          ),

                          Padding(
                            padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                            child: _buildEmbeddedBookingDetailsInInvoice(),
                          ),
                          Divider(color: Colors.grey.shade300),

                          // 4. --- CONTENT LISTVIEW ---
                          Expanded(
                            child: ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 3, 16, 20),
                              children: [
                                _buildItemRow('Boarding Fee', newBoardingCost),
                                if (newMealsCost > 0)
                                  _buildItemRow('Meal Fee', newMealsCost),
                                if (newWalkingCost > 0)
                                  _buildItemRow('Walking Fee', newWalkingCost),

                                const SizedBox(height: 4),

                                // --- TOGGLE ---
                                Center(
                                  child: InkWell(
                                    onTap: () => setState(
                                            () => showPetDetails = !showPetDetails),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          showPetDetails
                                              ? "Hide Price Breakdown"
                                              : "Show Price Breakdown",
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade900,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          showPetDetails
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                          color: AppColors.primaryColor,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),

                                AnimatedCrossFade(
                                  firstChild: const SizedBox.shrink(),
                                  secondChild: _buildPerPetDailyBreakdown(),
                                  crossFadeState: showPetDetails
                                      ? CrossFadeState.showSecond
                                      : CrossFadeState.showFirst,
                                  duration: const Duration(milliseconds: 300),
                                ),

                                if (gstRegistered || checkoutEnabled) ...[
                                  const SizedBox(height: 10),
                                  Divider(color: Colors.grey.shade300, thickness: 1),
                                  const SizedBox(height: 10),
                                ],
                                if (gstRegistered)
                                  _buildItemRow(
                                      'GST (${fees.gstPercentage.toStringAsFixed(0)}%) on Service',
                                      serviceGst),

                                if (checkoutEnabled)
                                  _buildItemRow('Platform Fee (Pre-GST)',
                                      fees.platformFeePreGst),

                                if (checkoutEnabled)
                                  _buildItemRow(
                                      'GST on Platform Fee', fees.platformFeeGst),

                                const SizedBox(height: 14),
                                Divider(
                                    color: Colors.grey.shade400, thickness: 1.2),
                                const SizedBox(height: 14),

                                _buildItemRow('Overall Total', grandTotal,
                                    isTotal: true),

                                if (!checkoutEnabled)
                                  Container(
                                    width: double.infinity,
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                                    child: Text(
                                      "This payment must be made directly to the boarder.",
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        color: Colors.grey.shade900,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  bool _showAllPets = false;

  Widget _buildEmbeddedBookingDetailsInInvoice() {
    final totalPets = widget.petIds.length;
    final hasMorePets = totalPets > 1;

    return Card(
      color: Colors.white,
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 0, bottom: 0),
            child: Column(
              children: [
                /// -------------------------------------
                /// 1️⃣ SHOW PETS
                /// -------------------------------------

                /// Show only 1 if collapsed
                _buildPetTile(0),

                /// Show rest only when expanded
                if (_showAllPets)
                  ...List.generate(
                    totalPets - 1,
                        (i) => _buildPetTile(i + 1),
                  ),

                /// -------------------------------------
                /// 2️⃣ SHOW MORE / SHOW LESS (AT BOTTOM)
                /// -------------------------------------
                if (hasMorePets)
                  GestureDetector(
                    onTap: () {
                      setState(() => _showAllPets = !_showAllPets);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _showAllPets ? "Show less" : "Show more",
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _showAllPets
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 15,
                            color: AppColors.primaryColor,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildPetTile(int index) {
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
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      minTileHeight: 0,
      shape: const Border(),

      children: [
        ...sortedDatesForPet.map((dateString) {
          final date = DateFormat('yyyy-MM-dd').parse(dateString);
          final details = dailyDetails[dateString] as Map<String, dynamic>;

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
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.restaurant_menu, size: 14),
                  ),
                if (hasWalk)
                  const Icon(Icons.directions_walk, size: 14),
              ],
            ),
          );
        }),
      ],
    );
  }

  // --- ConfirmationPage.dart / SummaryPage.dart ---

  Widget _buildPerPetDailyBreakdown() {
    return Column(
      children: List.generate(widget.petIds.length, (index) {
        final petId = widget.petIds[index];
        final petName = widget.petNames[index];
        final serviceDetails = widget.perDayServices[petId];

        if (serviceDetails == null) {
          return const SizedBox.shrink();
        }

        final dailyDetails = serviceDetails['dailyDetails'] as Map<String, dynamic>;
        final petSize = serviceDetails['size'] as String;
        final List<Widget> dailyRows = [];
        final sortedDates = dailyDetails.keys.toList()
          ..sort((a, b) => a.compareTo(b));

        final days = sortedDates.length.toDouble().clamp(1, double.infinity);

        // 1. Find the pet's entry in the reliable petCostBreakdown list.
        final breakdownEntry = widget.petCostBreakdown
            .map((e) => Map<String, dynamic>.from(e)) // Robust Map cast
            .where((b) => b['id'] == petId)
            .singleOrNull; // Use singleOrNull for safe retrieval (or firstWhere/orElse if unavailable)

        // Ensure the entry is valid before accessing totals
        final bool entryIsValid = breakdownEntry != null && breakdownEntry.isNotEmpty;

        // 2. Derive Per-Day Rates from the breakdown TOTALS.

        // Calculate Per-Day Rate (Total Cost / Total Days).
        // We assume if a service was booked for a pet, the cost is spread evenly across all days.
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
              padding: const EdgeInsets.only(top: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ${DateFormat('EEEE, MMM d').format(date)}',
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: darkColor)),
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0),
                    child: Column(
                      children: [
                        // ... inside the loop (dateString in sortedDates)

                        // Boarding is always charged per day
                        // --- FIX: Use the Per-Day Rate ---
                        _buildItemRow('Boarding', boardingRatePerDay),
                        // Walk/Meals are only charged if the per-day flag is set
                        if (hasWalk)
                          _buildItemRow('Daily Walking', walkingRatePerDay),
                        if (hasMeals)
                          _buildItemRow('Meals', mealRatePerDay),
                        // --------------------------------
                        // Boarding is always charged per day
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
              Text(
                'Pet: $petName ($petSize)',
                style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: secondaryColor),
              ),
              ...dailyRows,
            ],
          ),
        );
      }),
    );
  }

  Widget _buildItemRow(String label, double amount, {bool isTotal = false}) {
    final textStyle = GoogleFonts.poppins(
        fontSize: isTotal ? 18 : 14,
        fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
        color: isTotal ? darkColor : lightTextColor);

    final amountStyle = GoogleFonts.poppins(
        fontSize: isTotal ? 18 : 14,
        fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
        color: darkColor);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label, style: textStyle),
          const Spacer(),
          Text('₹${amount.toStringAsFixed(2)}', style: amountStyle),
        ],
      ),
    );
  }


  void _showBookingDetailsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
// Set padding around the dialog to control its distance from screen edges.

          insetPadding:
          const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),

// A rounded shape looks more modern than the previous circular(0).

          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),

          backgroundColor: backgroundColor,

// Remove default padding for title and content to use our own.

          titlePadding: EdgeInsets.zero,

          contentPadding: const EdgeInsets.only(top: 12),

// Your existing header widget goes here.

          title: _buildDialogHeader("Booking Details", context),

          content: SizedBox(
// Make the dialog's width a percentage of the screen width.

            width: MediaQuery.of(context).size.width * 0.9,

// Your existing scrollable content.

            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                child: _bookingDetailsContent(),
              ),
            ),
          ),

          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'CLOSE',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold, color: primaryColor),
              ),
            ),
          ],

          actionsPadding: const EdgeInsets.only(right: 16, bottom: 8),
        );
      },
    );
  }

// Placeholder for your header widget.

  Widget _buildDialogHeader(String title, BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.bold, color: darkColor),
          ),
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            customBorder: const CircleBorder(),
            child: const Padding(
              padding: EdgeInsets.all(4.0),
              child: Icon(Icons.close, color: darkColor, size: 24),
            ),
          ),
        ],
      ),
    );
  }

// Your _bookingDetailsContent widget remains unchanged. It is already well-built.

  Widget _bookingDetailsContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(widget.petIds.length, (index) {
          final petId = widget.petIds[index];

          final petName = widget.petNames[index];

          final petImage = widget.petImages[index];

          final petServiceDetails = widget.perDayServices[petId];

          if (petServiceDetails == null) return const SizedBox.shrink();

          final dailyDetails =
          petServiceDetails['dailyDetails'] as Map<String, dynamic>;

          final sortedDatesForPet = dailyDetails.keys.toList()..sort();

          return Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ExpansionTile(
              leading: CircleAvatar(
                radius: 20,
                backgroundImage: NetworkImage(petImage),
                backgroundColor: Colors.grey.shade200,
              ),
              title: Text(petName,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold, color: darkColor)),
              subtitle: Text(
                  "${dailyDetails.length} day${dailyDetails.length > 1 ? 's' : ''} booked",
                  style:
                  GoogleFonts.poppins(fontSize: 12, color: lightTextColor)),
              childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              expandedAlignment: Alignment.topLeft,
              children: [
                const Divider(height: 1),
                const SizedBox(height: 8),
                ...sortedDatesForPet.map((dateString) {
                  final date = DateFormat('yyyy-MM-dd').parse(dateString);

                  final details =
                  dailyDetails[dateString] as Map<String, dynamic>;

                  final hasMeal = details['meals'] == true;

                  final hasWalk = details['walk'] == true;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_rounded,
                            size: 16, color: darkColor.withOpacity(0.7)),
                        const SizedBox(width: 12),
                        Text(DateFormat('EEE, dd MMM yyyy').format(date),
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: darkColor,
                                fontWeight: FontWeight.w500)),
                        const Spacer(),
                        if (hasMeal)
                          Tooltip(
                              message: "Meal Included",
                              child: Icon(Icons.restaurant_menu_rounded,
                                  size: 18, color: secondaryColor)),
                        if (hasMeal && hasWalk) const SizedBox(width: 12),
                        if (hasWalk)
                          Tooltip(
                              message: "Walk Included",
                              child: Icon(Icons.directions_walk_rounded,
                                  size: 18, color: ConfirmationPage.secondaryTextColor)),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        }),
      ),
    );
  }


  // --- UI Builder Methods ---

  @override
  Widget build(BuildContext context) {
    final earliestDate = widget.selectedDates.isNotEmpty
        ? widget.selectedDates.reduce((a, b) => a.isBefore(b) ? a : b)
        : DateTime.now();
    final canCancel =
    DateTime.now().isBefore(earliestDate.subtract(const Duration(hours: 24)));

    return PopScope(
      canPop: false, // Prevents the default back action
      onPopInvoked: (didPop) {
        if (didPop) return; // If it already popped, do nothing

        // Only run this logic if `fromSummary` is true
        if (widget.fromSummary) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (_) => HomeWithTabs()));
          Future.microtask(() => _showTicketInfoDialog(context));
        } else {
          // Otherwise, just do a normal pop
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: ConfirmationPage.backgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: ConfirmationPage.primaryTextColor,
          elevation: 1,
          shadowColor: Colors.black.withOpacity(0.1),
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
                    size: 16,
                    color: Colors.black87,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "Help",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
        body: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              buildConfirmationHeader(context,widget.bookingId),
              const SizedBox(height: 8),
              _buildDashboardCard(),
              SizedBox(height: 10),


            ],
          ),
        ),
        bottomNavigationBar: _buildBottomActions(context, canCancel),
      ),);
  }
  Widget buildConfirmationHeader(BuildContext context, String bookingId) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.center, // ✅ center text horizontally
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Booking Confirmed!",
                  textAlign: TextAlign.center, // ✅ ensures multiline centering
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF333333),
                  ),
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: bookingId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Order ID copied to clipboard!'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center, // ✅ centers within Row
                    children: [
                      Text(
                        "Order #$bookingId",
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.copy, size: 13, color: Colors.grey),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildDashboardCard() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: ConfirmationPage.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Column(
        children: [
          _buildProviderHeader(),
          const SizedBox(height: 16),

          // --- ADD THE NEW WIDGET HERE ---
          _buildMainActionsRow(),
          const Divider(height: 24), // Optional: add a divider
          // --------------------------------
          _buildContactActions(),
          const SizedBox(height: 16),
          _buildPinsSection(),

          const Divider(height: 32),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildLeftColumn()),
              ],
            ),
          )
        ],
      ),
    );
  }

  // lib/screens/Boarding/boarding_confirmation_page.dart

  Widget _buildProviderHeader() {
    // Check if the image URL is valid or available
    final bool isImageValid = widget.shopImage.isNotEmpty && widget.shopImage.startsWith('http');

    Widget imageWidget;
    if (isImageValid) {
      // Attempt to load the network image
      imageWidget = Image.network(
        widget.shopImage,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        // Provide a fallback icon if the network image fails to load (errorBuilder)
        errorBuilder: (_, __, ___) => Container(
          width: 60,
          height: 60,
          color: backgroundColor,
          child: const Icon(Icons.store, size: 30, color: lightTextColor),
        ),
      );
    } else {
      // Show the fallback icon immediately if the URL is empty or invalid
      imageWidget = Container(
        width: 60,
        height: 60,
        color: backgroundColor,
        child: const Icon(Icons.store, size: 30, color: lightTextColor),
      );
    }

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: imageWidget, // Use the determined image/icon widget
        ),
        const SizedBox(width: 16),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.shopName,
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: darkColor),
              ),
              const SizedBox(height: 4),

              // --- Time Row ---
              Row(
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    size: 14,
                    color: lightTextColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "${widget.openTime} - ${widget.closeTime}",
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: lightTextColor,
                    ),
                  ),
                ],
              ),
              // --- Area Name FutureBuilder ---
              // 🚀 MODIFIED: Use _combinedDataFuture
              FutureBuilder<_CombinedData>(
                future: _combinedDataFuture,
                builder: (ctx, snap) {
                  final areaName = snap.data?.areaName ?? 'Loading area...';

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const FaIcon(
                        Icons.location_pin,
                        size: 16,
                        color: Colors.black87,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        areaName,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: ConfirmationPage.secondaryTextColor,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
  Widget _buildContactActions() {
    // 🚀 NEW: Use a single FutureBuilder to fetch all data once
    return FutureBuilder<_CombinedData>(
      future: _combinedDataFuture,
      builder: (context, snapshot) {
        final isReady = snapshot.hasData;
        final data = snapshot.data;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Location button
            _ContactIconButton(
              label: 'Location',
              assetImagePath: 'assets/google_maps_logo.png',
              // 🚀 MODIFIED: Pass the GeoPoint directly
              future: Future.value(data?.shopLocation ?? const GeoPoint(0, 0)),
              onPressed: (location) => _openMap(location.latitude, location.longitude),
            ),

            // Call button
            _ContactIconButton(
              label: 'Call',
              icon: FontAwesomeIcons.phone,
              iconColor: const Color(0xFF34A853),
              // 🚀 MODIFIED: Pass the phone number directly
              future: Future.value(data?.phoneNumber ?? 'N/A'),
              onPressed: (phone) => _openPhone(phone),
            ),

            // WhatsApp button
            _ContactIconButton(
              label: 'WhatsApp',
              icon: FontAwesomeIcons.whatsapp,
              iconColor: const Color(0xFF25D366),
              // 🚀 MODIFIED: Pass the whatsapp number directly
              future: Future.value(data?.whatsappNumber ?? 'N/A'),
              onPressed: (whatsapp) => _openWhatsApp(whatsapp),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLeftColumn() {
    final datesFuture = _fetchBookingDates();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<Map<String, String>>(
          future: datesFuture,
          builder: (ctx, snap) {
            final data = snap.data;

            final creationTime = data?['creationDate'] ?? '...';
            final confirmationTime = data?['confirmationDate'] ?? '...';

            if (snap.connectionState == ConnectionState.waiting) {
              return _buildDetailRow(label: "Requested On:", value: '...');
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Booking Creation Time (Request Time)
                _buildDetailRow(
                  label: "Requested On:",
                  value: creationTime,
                  // REMOVED: labelStyle: GoogleFonts.poppins(...)
                  // REMOVED: valueStyle: GoogleFonts.poppins(...)
                ),

                const SizedBox(height: 6),

                // 2. Booking Confirmation Time
                _buildDetailRow(
                  label: "Confirmed On:",
                  value: confirmationTime,
                  // REMOVED: labelStyle: GoogleFonts.poppins(...)
                  // REMOVED: valueStyle: GoogleFonts.poppins(...)
                ),
              ],
            );
          },
        ),
      ],
    );
  }
  Widget _buildDetailRow({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Label Text Size Reduced to 12
          Text(label, style: GoogleFonts.poppins(fontSize: 12, color: ConfirmationPage.secondaryTextColor)),
          const SizedBox(width: 4),
          // 2. Value Text Size Reduced to 12
          Expanded(child: Text(value, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: ConfirmationPage.primaryTextColor))),
        ],
      ),
    );
  }

  Widget _buildPinsSection() {
    return FutureBuilder<DocumentSnapshot>(
      future: _bookingDoc(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: ConfirmationPage.accentColor, strokeWidth: 2)));
        }
        if (!snapshot.hasData || snapshot.hasError || !snapshot.data!.exists) {
          return const Center(child: Text('No PINs.', style: TextStyle(fontSize: 12)));
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final double fontSize = 10.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PinDisplayWidget(title: 'Start PIN', pin: data['startPinRaw'] ?? '----', isUsed: data['isStartPinUsed'] ?? false),
            const SizedBox(height: 8),
            PinDisplayWidget(title: 'End PIN', pin: data['endPinRaw'] ?? '----', isUsed: data['isEndPinUsed'] ?? false),
            const SizedBox(height: 16),
            _buildProfessionalNote(context),
          ],
        );
      },
    );
  }
  Widget _buildProfessionalNote(BuildContext context) {
    // Use a slightly larger font for better readability with icon bullets
    const double contentFontSize = 10.0;

    // Use a color with transparency for the background
    final Color noteBackgroundColor = AppColors.primaryColor.withOpacity(0.08);

    // Define a reusable style for the heading
    final TextStyle headingStyle = GoogleFonts.poppins(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryColor,
    );

    // Define a reusable style for the bullet icons
    const Color bulletColor = AppColors.primaryColor;
    const double iconSize = 10.0;

    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: noteBackgroundColor, // Background color with opacity
        border: Border.all(
          color: AppColors.primaryColor, // Primary color border
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(8.0), // Rounded corners
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. HEADING
          Row(
            children: [
              const Icon(
                FontAwesomeIcons.circleExclamation, // Info/Alert Icon
                color: bulletColor,
                size: 12,
              ),
              const SizedBox(width: 8),
              Text("Note", style: headingStyle),
            ],
          ),

          const Divider(height: 18, thickness: 0.5, color: bulletColor),

          // 2. PIN ENTRY NOTE (with Font Awesome Bullet)
          _buildIconBulletRow(
            icon: FontAwesomeIcons.angleRight, // Solid, clean bullet point
            text: 'Please ensure the **service provider** enters the **PIN for check-in**.',
            fontSize: contentFontSize,
            iconColor: bulletColor,
          ),

          const SizedBox(height: 8),

          // 3. CONFIRMATION TIME NOTE (with Font Awesome Bullet)
          // Inside _buildProfessionalNote...

          _buildIconBulletRow(
            icon: FontAwesomeIcons.angleRight,
            text: 'If you do not receive a **confirmation from MyFellowPet regarding this booking** within 10 minutes, please contact support.',
            fontSize: contentFontSize,
            iconColor: bulletColor,
          )

// ...
        ],
      ),
    );
  }

// ⚠️ NEW HELPER FUNCTION REQUIRED: _buildIconBulletRow
// You must add this function to your class (e.g., SummaryPage or _SummaryPageState)
  Widget _buildIconBulletRow({
    required IconData icon,
    required String text,
    required double fontSize,
    required Color iconColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2.0),
          child: Icon(
            icon,
            size: 10.0,
            color: iconColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildText(
            text,
            fontSize,
          ),
        ),
      ],
    );
  }

// NOTE: The _buildText function (which takes text and fontSize) is still required
// to render the actual note content, as it was in your previous structure.

  // Update this helper to use Text.rich for bolding
  Widget _buildText(String text, double fontSize) {
    // Define base style
    final TextStyle baseStyle = GoogleFonts.poppins(
      fontSize: fontSize,
      color: ConfirmationPage.primaryTextColor, // Or suitable dark color
    );

    // Define bold style
    final TextStyle boldStyle = baseStyle.copyWith(fontWeight: FontWeight.w700);

    // Split the string based on the bold marker '**'
    final parts = text.split('**');
    final List<TextSpan> spans = [];

    for (int i = 0; i < parts.length; i++) {
      // Content outside of '**' is normal (0, 2, 4...)
      if (i % 2 == 0) {
        spans.add(TextSpan(text: parts[i], style: baseStyle));
      }
      // Content inside of '**' is bold (1, 3, 5...)
      else {
        spans.add(TextSpan(text: parts[i], style: boldStyle));
      }
    }

    // Return the Text.rich widget
    return Text.rich(
      TextSpan(children: spans),
    );
  }
  Widget _buildBulletText(String text, double fontSize) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: fontSize,
              height: 0,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActions(BuildContext context, bool canCancel) {
    const Color primaryColor = Color(0xFF2CB4B6);

    // Check if it's a direct payment booking
    final bool isDirectBooking = !widget.checkoutEnabled;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, -5))
        ],
        border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // --- CANCEL BUTTON ---
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  // 🔥 TWEAK: Grey style if direct payment, Red if app payment
                  foregroundColor: isDirectBooking ? Colors.grey.shade600 : Colors.red.shade700,
                  side: BorderSide(
                    color: isDirectBooking ? Colors.grey.shade300 : Colors.red.shade700,
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  backgroundColor: isDirectBooking ? Colors.grey.shade50 : Colors.transparent,
                ),
                onPressed: () async {
                  // --- NEW CHECK: Is checkout enabled? ---
                  if (isDirectBooking) {
                    _showDirectPaymentCancellationDialog(context);
                    return; // Stop here
                  }

                  // --- EXISTING CANCELLATION LOGIC ---
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) =>
                    const Center(child: CircularProgressIndicator()),
                  );
                  try {
                    final DocumentSnapshot bookingDoc = await _bookingDoc();
                    if (context.mounted) Navigator.pop(context);
                    if (bookingDoc.exists) {
                      handleCancel(bookingDoc, context);
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Error: Booking not found.')),
                        );
                      }
                    }
                  } catch (e) {
                    if (context.mounted) Navigator.pop(context);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to get booking details: $e')),
                      );
                    }
                  }
                },
                child: Text(
                  "Cancel Booking",
                  style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // --- DONE BUTTON ---
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline,
                    size: 20, color: Colors.white),
                label: Text("Done",
                    style: GoogleFonts.poppins(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                onPressed: () {
                  if (widget.fromSummary) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                    Navigator.pushReplacement(context,
                        MaterialPageRoute(builder: (_) => HomeWithTabs()));
                    Future.microtask(() => _showTicketInfoDialog(context));
                  } else {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDirectPaymentCancellationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon Header
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.info_outline_rounded,
                    color: Colors.orange.shade800,
                    size: 28
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                "Direct Booking",
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2D3436),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // Body
              Text(
                "Since payment was handled directly at the center, please contact the boarder to process cancellations or refunds.",
                style: GoogleFonts.poppins(
                  fontSize: 13, // Professional small font
                  color: const Color(0xFF636E72),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),

              // Action Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D3436), // Dark professional button
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Understood',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
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

  void _showTicketInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: _TicketWidget(),
      ),
    );
  }

  // --- Cancellation Logic (Unchanged) ---

  Future<void> _cancelBooking(BuildContext context) async {
    print("Starting booking cancellation for bookingId: ${widget.bookingId}");
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text("Processing...", style: GoogleFonts.poppins(fontSize: 16, color: Colors.white, decoration: TextDecoration.none)),
            ],
          ),
        ),
      );

      final querySnapshot = await FirebaseFirestore.instance
          .collectionGroup('service_request_boarding')
          .where('bookingId', isEqualTo: widget.bookingId)
          .get();
      print("Query completed. Number of documents found: ${querySnapshot.docs.length}");

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final data = doc.data();
        print("Document found: ${doc.id} with data: $data");

        final paymentId = data['payment_id'];
        final Timestamp firestoreTimestamp = data['timestamp'];
        final DateTime refundTimestamp = firestoreTimestamp.toDate();
        final int refundAmountPaise = await _calculateRefundAmount(refundTimestamp);
        final double refundAmountRupees = refundAmountPaise / 100.0;

        Navigator.pop(context);

        final bool? confirm = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Confirm Cancellation', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: ConfirmationPage.primaryTextColor)),
            content: Text(
              "This will result in a refund of ₹${refundAmountRupees.toStringAsFixed(2)}. Do you want to proceed?",
              style: GoogleFonts.poppins(fontSize: 15, color: ConfirmationPage.secondaryTextColor),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('No', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: ConfirmationPage.secondaryTextColor)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Yes, Cancel', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.red)),
              ),
            ],
          ),
        );

        if (confirm != true) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Cancellation aborted.", style: GoogleFonts.poppins())));
          return;
        }

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text("Cancelling...", style: GoogleFonts.poppins(fontSize: 16, color: Colors.white, decoration: TextDecoration.none)),
              ],
            ),
          ),
        );

        final refundId = await _refundPayment(paymentId, refundTimestamp);

        if (refundId == null) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Refund failed. Booking cancellation aborted.", style: GoogleFonts.poppins())));
          return;
        }

        final firestore = FirebaseFirestore.instance;
        final batch = firestore.batch();
        final serviceRef = firestore.collection('users-sp-boarding').doc(widget.serviceId);

        final dates = (data['selectedDates'] as List<dynamic>).map((d) => (d as Timestamp).toDate()).toList();
        final numPets = data['numberOfPets'] as int? ?? 0;

        if (numPets > 0) {
          for (final date in dates) {
            final dateString = DateFormat('yyyy-MM-dd').format(date);
            final summaryRef = serviceRef.collection('daily_summary').doc(dateString);
            batch.update(summaryRef, {'bookedPets': FieldValue.increment(-numPets)});
          }
        }

        data['status'] = 'user_cancellation';
        data['refund_id'] = refundId;

        final rejectedRef = firestore.collection('rejected-boarding-bookings').doc(doc.id);
        batch.set(rejectedRef, data);
        batch.delete(doc.reference);

        await batch.commit();
        print("Atomically updated daily_summary, moved booking to rejected, and deleted original.");

        Navigator.pop(context);

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text("Booking Cancelled", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            content: Text("Your refund has been initiated and will be processed shortly.", style: GoogleFonts.poppins(color: ConfirmationPage.secondaryTextColor)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('OK', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: ConfirmationPage.accentColor)),
              ),
            ],
          ),
        );

        await Future.delayed(const Duration(seconds: 3));
        if(context.mounted) Navigator.pop(context);

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Booking cancelled and refund initiated.", style: GoogleFonts.poppins())));

        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => HomeScreen()), (route) => false);
      } else {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Booking not found.", style: GoogleFonts.poppins())));
      }
    } catch (e) {
      if(context.mounted) Navigator.pop(context);
      print("Error cancelling booking: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error cancelling booking.", style: GoogleFonts.poppins())));
    }

    print("Booking cancellation process completed for widget.bookingId: ${widget.bookingId}");
  }

  Future<String?> _refundPayment(String paymentId, DateTime refundTimestamp) async {
    const url = 'https://razorpayrefundtest-urjpiqxoca-uc.a.run.app/razorpayRefundTest';

    final feesDoc = await FirebaseFirestore.instance.collection('company_documents').doc('fees').get();
    final platformFeeStr = feesDoc.data()?['user_app_platform_fee'] ?? '0';
    final gstPercentageStr = feesDoc.data()?['gst_percentage'] ?? '0';

    final double platformFee = double.parse(platformFeeStr);
    final double gstPercentage = double.parse(gstPercentageStr);

    final int totalCostPaise = (widget.totalCost * 100).toInt();
    final int platformFeePaise = (platformFee * 100).toInt();
    final int gstAmountPaise = ((platformFee * gstPercentage) / 100.0 * 100).toInt();

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'paymentId': paymentId,
          'timestamp': refundTimestamp.toString(),
          'totalCost': totalCostPaise,
          'platformFee': platformFeePaise,
          'gstAmount': gstAmountPaise,
        }),
      );

      if (response.statusCode == 200) {
        final refundResponse = jsonDecode(response.body);
        final refundId = refundResponse['refund']['id'];
        return refundId;
      } else {
        print("Refund failed: ${response.statusCode} ${response.body}");
        return null;
      }
    } catch (error) {
      print("Error calling cloud function: $error");
      return null;
    }
  }

  Future<int> _calculateRefundAmount(DateTime refundTimestamp) async {
    final feesDoc = await FirebaseFirestore.instance.collection('company_documents').doc('fees').get();
    final platformFeeStr = feesDoc.data()?['user_app_platform_fee'] ?? '0';
    final gstPercentageStr = feesDoc.data()?['gst_percentage'] ?? '0';

    final double platformFee = double.parse(platformFeeStr);
    final double gstPercentage = double.parse(gstPercentageStr);

    final int totalCostPaise = (widget.totalCost * 100).toInt();
    final int platformFeePaise = (platformFee * 100).toInt();
    final int gstAmountPaise = ((platformFee * gstPercentage) / 100.0 * 100).toInt();

    final int refundableBasePaise = totalCostPaise - (platformFeePaise + gstAmountPaise);

    final double diffHours = DateTime.now().difference(refundTimestamp).inHours.toDouble();

    double refundPercentage = 0;
    if (diffHours < 12) refundPercentage = 1;
    else if (diffHours < 24) refundPercentage = 0.5;
    else if (diffHours < 36) refundPercentage = 0.25;

    return (refundableBasePaise * refundPercentage).floor();
  }
}

// --- Helper Widgets (Restyled) ---

class PinDisplayWidget extends StatelessWidget {
  final String title;
  final String pin;
  final bool isUsed;

  const PinDisplayWidget({
    Key? key,
    required this.title,
    required this.pin,
    required this.isUsed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: GoogleFonts.poppins(fontSize: 14, color: ConfirmationPage.secondaryTextColor)),
        const Spacer(),
        ...pin.split('').map((digit) {
          return Container(
            margin: const EdgeInsets.only(left: 4),
            width: 30,
            height: 40,
            decoration: BoxDecoration(
              color: isUsed ? Colors.green.shade50 : const Color(0xFFF0F4F8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isUsed ? Colors.green.shade200 : Colors.grey.shade300),
            ),
            child: Center(
              child: Text(
                digit,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isUsed ? Colors.green.shade700 : ConfirmationPage.primaryTextColor,
                ),
              ),
            ),
          );
        }).toList(),
      ],
    );
  }
}


/// A flexible contact button that can display either an icon or an asset image.
class _ContactIconButton<T> extends StatelessWidget {
  final String label;
  final IconData? icon;
  final String? assetImagePath;
  final Color? iconColor;
  final Future<T> future;
  final Function(T) onPressed;

  const _ContactIconButton({
    required this.label,
    required this.future,
    required this.onPressed,
    this.icon,
    this.assetImagePath,
    this.iconColor,
  }) : assert(icon != null || assetImagePath != null, 'Either icon or assetImagePath must be provided.');

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (ctx, snap) {
        final isReady = snap.connectionState == ConnectionState.done && snap.hasData;

        // Conditionally build the icon widget
        Widget iconWidget;
        if (assetImagePath != null) {
          iconWidget = Image.asset(
            assetImagePath!,
            width: 22,
            height: 22,
          );
        } else {
          iconWidget = FaIcon(
            icon!,
            size: 20,
            color: isReady ? iconColor ?? ConfirmationPage.accentColor : Colors.grey,
          );
        }

        return Column(
          children: [
            IconButton(
              icon: iconWidget,
              onPressed: isReady ? () => onPressed(snap.data as T) : null,
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                // Add the border here
                side: BorderSide(
                  color: Colors.grey.shade300,
                  width: 1.5,
                ),
                padding: const EdgeInsets.all(12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: ConfirmationPage.secondaryTextColor)),
          ],
        );
      },
    );
  }
}

class _TicketWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none, alignment: Alignment.topCenter,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 40),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 50),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Text("Booking Saved!", style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: ConfirmationPage.primaryTextColor)),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Text("You can find your ticket anytime in your account.", textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 15, color: ConfirmationPage.secondaryTextColor)),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  children: [
                    _buildStepRow(icon: Icons.account_circle_outlined, text: "Go to your Account"),
                    _buildStepRow(icon: Icons.list_alt_rounded, text: "Select 'My Orders'"),
                    _buildStepRow(icon: Icons.article_outlined, text: "Find your ticket in 'Boarding'"),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ConfirmationPage.accentColor, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 5, shadowColor: ConfirmationPage.accentColor.withOpacity(0.4),
                    ),
                    child: Text('Got it!', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 0,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(shape: BoxShape.circle, color: ConfirmationPage.accentColor),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepRow({required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: ConfirmationPage.accentColor, size: 24),
          const SizedBox(width: 16),
          Expanded(child: Text(text, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500, color: ConfirmationPage.primaryTextColor))),
        ],
      ),
    );
  }
}


// --- NEW DATA MODEL ---
class _CombinedData {
  // Data from users-sp-boarding (Service Provider document)
  final String areaName;
  final GeoPoint shopLocation;
  final String phoneNumber;
  final String whatsappNumber;

  // Data from company_documents/fees
  final _FeesData fees;

  _CombinedData({
    required this.areaName,
    required this.shopLocation,
    required this.phoneNumber,
    required this.whatsappNumber,
    required this.fees,
  });
}
