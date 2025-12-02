import 'dart:convert';
import 'dart:async'; // Added for Future
import 'package:flutter/foundation.dart'; // Added for compute
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lottie/lottie.dart';

import '../../app_colors.dart';
import '../Boarding/OpenCloseBetween.dart';
import '../Boarding/boarding_confirmation_page.dart';
import '../refund/cancellation_invoice_page.dart';

// ── ISOLATE DATA MODELS ────────────────────────────────────────────────────────

class OrderComputeData {
  final List<QueryDocumentSnapshot> docs;
  final DateTime todayStart;

  OrderComputeData({required this.docs, required this.todayStart});
}

class FilteredOrders {
  final List<OrderSummary> ongoing;
  final List<OrderSummary> upcoming;
  final List<OrderSummary> past;

  FilteredOrders({
    required this.ongoing,
    required this.upcoming,
    required this.past,
  });
}

// ── ISOLATE COMPUTATION FUNCTION ────────────────────────────────────────────────
// ── ISOLATE COMPUTATION FUNCTION ────────────────────────────────────────────────
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
                fontSize: 13,
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
                  backgroundColor: const Color(0xFF2D3436),
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
/// Must be a top-level function to run in an isolate
FilteredOrders computeOrderLists(OrderComputeData data) {
  // 1. Map raw documents to OrderSummary objects
  final orders = data.docs.map((d) => OrderSummary(d)).toList();
  final todayStart = data.todayStart;

  // 2. Define the filtering logic

  // Past: All dates are before today's date at midnight AND isEndPinUsed is true.
  final actualPast = orders.where((o) {
    // Check 1: All dates are before today's date at midnight.
    final isDatePast = o.dates.isNotEmpty && o.dates.every((d) => d.isBefore(todayStart));

    // Check 2: The document must have isEndPinUsed set to true.
    final isCompleted = (o.doc.data() as Map<String, dynamic>)['isEndPinUsed'] == true;

    // Only include in Past if both conditions are met.
    return isDatePast && isCompleted;
  }).toList();

  // Upcoming: All dates are after today's date at midnight.
  // Note: We need to adjust Upcoming and Ongoing to exclude orders marked as "Past"
  // This is a common pattern when using `where` conditions that are mutually exclusive
  // with the definitions below.

  // Upcoming (must not be considered past): All dates are after today's date at midnight.
  final actualUpcoming = orders.where((o) =>
  o.dates.isNotEmpty &&
      o.dates.every((d) => d.isAfter(todayStart)) &&
      !actualPast.contains(o) // Ensure it wasn't already moved to Past
  ).toList();


  // Ongoing: Not strictly Upcoming AND not strictly Past (includes today).
  // Orders whose dates are past but haven't been completed (`isEndPinUsed` is false)
  // will now fall into this `ongoing` list until they are completed.
  final actualOngoing = orders.where((o) => !actualUpcoming.contains(o) && !actualPast.contains(o)).toList();

  return FilteredOrders(
    ongoing: actualOngoing,
    upcoming: actualUpcoming,
    past: actualPast,
  );
}
// ────────────────────────────────────────────────────────────────────────────────


/// Calculate refund % based on time-to-start vs policy brackets
int calculateRefundPercent({
  required double timeToStartInHours,
  required List<Map<String, dynamic>> brackets,
  required Map<String, int> providerPolicy,
}) {
  brackets.sort((a, b) =>
      (b['min_hours'] as num).compareTo(a['min_hours'] as num));
  for (final bracket in brackets) {
    final min = (bracket['min_hours'] as num).toDouble();
    final max = bracket['max_hours'] != null
        ? (bracket['max_hours'] as num).toDouble()
        : double.infinity;
    final label = bracket['label'] as String;
    if (timeToStartInHours >= min && timeToStartInHours < max) {
      return providerPolicy[label] ?? 0;
    }
  }
  return 0;
}

/// Sum refund across days
double calculateTotalRefund({
  required DateTime now,
  required List<DateTime> bookedDays,
  required double dailyTotalCost,
  required List<Map<String, dynamic>> brackets,
  required Map<String, int> providerPolicy,
}) {
  var total = 0.0;
  for (final day in bookedDays) {
    if (!now.isBefore(day)) continue;
    final hoursUntil = day.difference(now).inHours.toDouble();
    final pct = calculateRefundPercent(
      timeToStartInHours: hoursUntil,
      brackets: brackets,
      providerPolicy: providerPolicy,
    );
    total += dailyTotalCost * (pct / 100);
  }
  return total;
}

/// Selection per date → pet IDs
class _CancelSelectionPerDate {
  final Map<DateTime, List<String>> cancellations;
  _CancelSelectionPerDate({required this.cancellations});
}

Future<void> triggerAdminCancellationPayout({
  required String orderId,
  required double adminFee,
}) async {
  try {
    final settingsDoc = await FirebaseFirestore.instance
        .collection('settings')
        .doc('cancellation_time_brackets')
        .get();

    final adminFundAccountId = settingsDoc.data()?['admin_razorpay_fund_acc_id'];
    if (adminFundAccountId == null || adminFundAccountId.isEmpty) {
      print('❌ Admin fund account not found.');
      return;
    }

    print('💸 Triggering admin payout: ₹$adminFee to fund $adminFundAccountId');

    final url = "https://us-central1-petproject-test-g.cloudfunctions.net/v2initiatePayout";

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "serviceProviderId": "ADMIN", // label only
        "orderId": orderId,
        "fundAccountId": adminFundAccountId,
        "amount": (adminFee * 100).toInt(), // Razorpay expects paise
      }),
    );

    print("📤 Admin payout response: ${response.body}");
  } catch (e) {
    print("🚨 Admin payout error: $e");
  }
}
/// Main cancel handler
Future<void> handleCancel(
    DocumentSnapshot bookingDoc,
    BuildContext context,
    ) async {

  final data = bookingDoc.data() as Map<String, dynamic>;
  final String? paymentId = data['payment_id'];

  // If there is no payment ID, it was a direct booking.
  // Stop the process and show the dialog.
  if (paymentId == null || paymentId.isEmpty) {
    _showDirectPaymentCancellationDialog(context);
    return;
  }
  final now = DateTime.now();

  final petNames = (data['pet_name'] as List<dynamic>? ?? [])
      .map((e) => e.toString())
      .toList();

  final petIds = (data['pet_id'] as List<dynamic>? ?? [])
      .map((e) => e.toString())
      .toList();

  final Map<String, List<String>> overrides =
      (data['attendance_override'] as Map<String, dynamic>?)
          ?.map((k, v) =>
          MapEntry(k, (v as List<dynamic>).cast<String>()))
          ?? {};


  // 1) build list of open-points
  final rawDates = (data['selectedDates'] as List<dynamic>? ?? [])
      .map<DateTime?>((d) => d is Timestamp ? d.toDate() : d as DateTime?)
      .whereType<DateTime>()
      .toList()
    ..sort();

  final openTimeStr = data['openTime'] as String? ?? '12:00 AM';
  final parsedOpen = DateFormat('h:mm a').parse(openTimeStr);

  final openPoints = rawDates
  // skip dates where all pets are cancelled
      .where((d) {
    final key = DateFormat('yyyy-MM-dd').format(d);
    final cancelled = overrides[key] ?? <String>[];
    return !petIds.every((id) => cancelled.contains(id));
  })
  // convert to full DateTime with open hour
      .map((d) => DateTime(d.year, d.month, d.day, parsedOpen.hour, parsedOpen.minute))
  // keep only today/future
      .where((dt) {
    final today = DateTime(now.year, now.month, now.day);
    return dt.isAtSameMomentAs(today) || dt.isAfter(now);
  })
      .toSet()
      .toList()
    ..sort();

  // 2) build UI for selecting pets-per-date
  final selection = await showModalBottomSheet<_CancelSelectionPerDate>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) {
      final selectedPerDate = <DateTime, Set<int>>{
        for (var d in openPoints) d: <int>{}
      };

      return GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          color: Colors.black45,
          child: GestureDetector(
            onTap: () {},
            child: DraggableScrollableSheet(
              maxChildSize: 0.85,
              initialChildSize: 0.6,
              minChildSize: 0.3,
              builder: (ctx, ctrl) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: ListView(
                    controller: ctrl,
                    children: [

                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      SizedBox(height: 12),

                      Text(
                        "Cancel Booking",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary),
                      ),
                      SizedBox(height: 24),

                      for (final date in openPoints) ...[
                        Text(
                          DateFormat('MMM dd, yyyy').format(date),
                          style: GoogleFonts.poppins(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 8),

                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(petNames.length, (i) {
                            final name = petNames[i];
                            final isSel = selectedPerDate[date]!.contains(i);

                            final key = DateFormat('yyyy-MM-dd').format(date);
                            final cancelledOnDate = overrides[key] ?? <String>[];

                            return Tooltip(
                              message: cancelledOnDate.contains(petIds[i])
                                  ? 'Already cancelled for this date'
                                  : '',
                              triggerMode: TooltipTriggerMode.tap,
                              child: FilterChip(
                                label: Text(
                                  name,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight:
                                    isSel ? FontWeight.w600 : FontWeight.w400,
                                    color: cancelledOnDate.contains(petIds[i])
                                        ? Colors.grey
                                        : isSel
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                selected: isSel,
                                onSelected: cancelledOnDate.contains(petIds[i])
                                    ? null
                                    : (on) {
                                  if (on) {
                                    selectedPerDate[date]!.add(i);
                                  } else {
                                    selectedPerDate[date]!.remove(i);
                                  }
                                  (ctx as Element).markNeedsBuild();
                                },
                                backgroundColor: cancelledOnDate.contains(petIds[i])
                                    ? Colors.grey.shade300
                                    : AppColors.secondary.withOpacity(0.1),
                                selectedColor:
                                cancelledOnDate.contains(petIds[i])
                                    ? Colors.grey.shade400
                                    : const Color(0xFF2CB4B6),
                                disabledColor: Colors.grey.shade300,
                                checkmarkColor: cancelledOnDate.contains(petIds[i])
                                    ? Colors.grey
                                    : Colors.white,
                              ),
                            );
                          }),
                        ),

                        SizedBox(height: 24),
                      ],

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              elevation: 2),
                          onPressed: () {
                            final cancellations = <DateTime, List<String>>{};
                            selectedPerDate.forEach((date, idxs) {
                              if (idxs.isNotEmpty) {
                                cancellations[date] =
                                    idxs.map((i) => petIds[i]).toList();
                              }
                            });

                            if (cancellations.isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text("Select at least one pet."),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                              return;
                            }

                            Navigator.of(ctx).pop(
                              _CancelSelectionPerDate(cancellations: cancellations),
                            );
                          },
                          child: Text(
                            "Continue",
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: 16),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
    },
  );

  if (selection == null) return;

  // 4) pull cost data
  final petSizes = (data['pet_sizes'] as List).cast<Map<String, dynamic>>();
  final cb = data['cost_breakdown'] as Map<String, dynamic>? ?? {};

  final walkCostPerDay =
      double.tryParse(cb['daily_walking_per_day']?.toString() ?? '') ?? 0.0;

  final mealCostPerDay =
      double.tryParse(cb['meal_per_day']?.toString() ?? '') ?? 0.0;

  final settingsDoc = await FirebaseFirestore.instance
      .collection('settings')
      .doc('cancellation_time_brackets')
      .get();

  final brackets =
  (settingsDoc.data()?['brackets'] as List<dynamic>? ?? [])
      .cast<Map<String, dynamic>>();

  final adminPct = int.tryParse(
      settingsDoc.data()?['admin_cancel_fee_percentage']?.toString() ?? '0') ??
      0;

  final providerPolicyMap =
  (data['refund_policy'] as Map<dynamic, dynamic>? ?? {})
      .map((k, v) => MapEntry(k.toString(), int.tryParse(v.toString()) ?? 0));

  final Map<String, double> boardingPriceByPet = {
    for (var i = 0; i < petIds.length; i++)
      petIds[i]: (petSizes[i]['price'] as num).toDouble(),
  };

  // 5) compute refund totals
  double grossTotal = 0.0;
  final attendanceUpdates = <String, List<String>>{};
  final dayTotals = <DateTime, double>{};

  for (final entry in selection.cancellations.entries) {
    final date = entry.key;
    final petsOnThatDate = entry.value;

    double dailyRefund = 0.0;

    for (final petId in petsOnThatDate) {
      final base =
          (boardingPriceByPet[petId] ?? 0) + walkCostPerDay + mealCostPerDay;

      final r = calculateTotalRefund(
        now: now,
        bookedDays: [date],
        dailyTotalCost: base,
        brackets: brackets,
        providerPolicy: providerPolicyMap,
      );

      dailyRefund += r;
    }

    grossTotal += dailyRefund;
    dayTotals[date] = dailyRefund;
    attendanceUpdates[DateFormat('yyyy-MM-dd').format(date)] = petsOnThatDate;
  }

  final petNamesMap = Map<String, String>.fromIterables(petIds, petNames);

  // -----------------------------------------------------------
  // 🟦 ADD THIS BLOCK EXACTLY HERE — refund % explanation map
  // -----------------------------------------------------------
  final refundReasons = <DateTime, Map<String, String>>{};
  final now2 = DateTime.now();

  for (final entry in selection.cancellations.entries) {
    final date = entry.key;
    refundReasons[date] = {};

    for (final petId in entry.value) {
      final base =
          (boardingPriceByPet[petId] ?? 0) + walkCostPerDay + mealCostPerDay;

      final hoursUntil = date.difference(now2).inHours.toDouble();
      final pct = calculateRefundPercent(
        timeToStartInHours: hoursUntil,
        brackets: brackets,
        providerPolicy: providerPolicyMap,
      );

      refundReasons[date]![petId] =
      "$pct% refund because cancelled ${hoursUntil.toStringAsFixed(0)}h before service start";
    }
  }
  // -----------------------------------------------------------

  // GST rate
  final feesSnap = await FirebaseFirestore.instance
      .collection('company_documents')
      .doc('fees')
      .get();

  double gstRate = 0.18;
  if (feesSnap.exists) {
    final val = feesSnap.data()?['gst_rate_percent'];
    if (val != null) {
      final parsed = double.tryParse(val.toString()) ?? 18;
      gstRate = parsed > 1 ? parsed / 100 : parsed;
    }
  }

  // TAX SPLIT
  final computedGross = grossTotal / (1 + gstRate);
  final cancelledGst = computedGross * gstRate;

  final adminFeeFinal = computedGross * adminPct / 100;
  final adminGstFinal = adminFeeFinal * gstRate;

  final netRefundWithGst =
      (computedGross + cancelledGst) - adminFeeFinal - adminGstFinal;
  final perPetPercents = <DateTime, Map<String, int>>{};
  final perPetReasons = <DateTime, Map<String, String>>{};
  final perPetRefunds = <DateTime, Map<String, double>>{};

  for (final entry in selection.cancellations.entries) {
    final date = entry.key;
    perPetPercents[date] = {};
    perPetReasons[date] = {};
    perPetRefunds[date] = {};

    for (final petId in entry.value) {
      final boarding = boardingPriceByPet[petId]!;
      final subtotal = boarding + walkCostPerDay + mealCostPerDay;

      final hoursUntil = date.difference(now).inHours.toDouble();

      final pct = calculateRefundPercent(
        timeToStartInHours: hoursUntil,
        brackets: brackets,
        providerPolicy: providerPolicyMap,
      );

      perPetPercents[date]![petId] = pct;
      perPetReasons[date]![petId] =
      "You cancelled ${hoursUntil.toStringAsFixed(0)} hours early, so the boarder's policy allows $pct% refund.";

      final r = calculateTotalRefund(
        now: now,
        bookedDays: [date],
        dailyTotalCost: subtotal,
        brackets: brackets,
        providerPolicy: providerPolicyMap,
      );

      perPetRefunds[date]![petId] = r;
    }
  }


  // OPEN FULL PAGE INVOICE
  final approve = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => CancellationInvoicePage(
        computedGross: computedGross,
        cancelledGst: cancelledGst,
        adminFeeFinal: adminFeeFinal,
        netRefundWithGst: netRefundWithGst,
        adminPct: adminPct,
        cancellations: selection.cancellations,
        petNamesMap: petNamesMap,
        perDayTotals: dayTotals,
        refundReasons: refundReasons, // 🔥 NEW
        // ADD THESE
        perPetRefunds: perPetRefunds,
        perPetPercents: perPetPercents,
        perPetReasons: perPetReasons,
      ),
    ),
  );

  if (approve != true) return;

  // After confirm → run actual cancellation logic (update DB + refund)
  await finalizeCancellationAndRefund(
    bookingDoc: bookingDoc,
    cancellations: attendanceUpdates,
    grossTotal: grossTotal,
    computedGross: computedGross,
    cancelledGst: cancelledGst,
    adminFee: adminFeeFinal,
    adminGst: adminGstFinal,
    netRefund: netRefundWithGst,
    requestRefund: requestRefund,
  );
}

/// ------------------------------------------------------------
/// FINAL: Cancels booking in Firestore + triggers refund API
/// ------------------------------------------------------------
Future<void> finalizeCancellationAndRefund({
  required DocumentSnapshot bookingDoc,
  required Map<String, List<String>> cancellations,
  required double grossTotal,
  required double computedGross,
  required double cancelledGst,
  required double adminFee,
  required double adminGst,
  required double netRefund,
  required Future<String?> Function({
  required String paymentId,
  required double refundAmount,
  }) requestRefund,
}) async {

  final firestore = FirebaseFirestore.instance;
  final data = bookingDoc.data() as Map<String, dynamic>;
  final now = DateTime.now();
  final bookingRef = bookingDoc.reference;

  final serviceId = data['service_id'] ?? data['sp_id'];
  final paymentId = data['payment_id'];
  final petIds = (data['pet_id'] as List).cast<String>();
  final selectedDates = (data['selectedDates'] as List<dynamic>)
      .map((d) => (d as Timestamp).toDate())
      .toList();
  final existingOverrides = (data['attendance_override'] as Map<String, dynamic>? ?? {})
      .map((k, v) => MapEntry(k, (v as List).cast<String>()));

  if (paymentId == null) {
    debugPrint("❌ No paymentId found — cannot refund");
    return;
  }

  // ---------------------------
  // 1️⃣ CREATE BATCH
  // ---------------------------
  final batch = firestore.batch();

  // ---------------------------
  // 2️⃣ DECREMENT DAILY SUMMARY
  // ---------------------------
  cancellations.forEach((dateStr, pets) {
    final summaryRef = firestore
        .collection('users-sp-boarding')
        .doc(serviceId)
        .collection('daily_summary')
        .doc(dateStr);

    batch.update(summaryRef, {
      'bookedPets': FieldValue.increment(-pets.length)
    });
  });

  // ---------------------------
  // 3️⃣ CALCULATE ADJUSTED SP FEE
  // ---------------------------
  final cb = data['cost_breakdown'] as Map<String, dynamic>? ?? {};
  final originalSpFee =
      double.tryParse(cb['sp_service_fee']?.toString() ?? '0') ?? 0.0;
  final originalSpGst =
      double.tryParse(cb['sp_service_gst']?.toString() ?? '0') ?? 0.0;

  final adjustedSpFee = originalSpFee - computedGross;
  final adjustedSpGst = (originalSpGst - cancelledGst).clamp(0, double.infinity);

  // ---------------------------
  // 4️⃣ UPDATE ATTENDANCE OVERRIDE
  // ---------------------------
  cancellations.forEach((dateStr, pets) {
    existingOverrides[dateStr] = [
      ...{...existingOverrides[dateStr] ?? [], ...pets}
    ];
  });

  // ---------------------------
  // 5️⃣ PERFORM RAZORPAY REFUND
  // ---------------------------
  final originalTotal = double.tryParse(cb['total_amount']?.toString() ?? '0') ?? 0;
  final historySnap =
  await bookingRef.collection('user_cancellation_history').get();

  final alreadyRefunded = historySnap.docs.fold<double>(0, (sum, doc) {
    final raw = doc['net_refund_including_gst']?.toString() ?? '0';
    return sum + (double.tryParse(raw) ?? 0);
  });

  final remainingRefundable = (originalTotal - alreadyRefunded).clamp(0, double.infinity);
  double refundToSend = double.parse(netRefund.toStringAsFixed(2));

  if (refundToSend > remainingRefundable) {
    refundToSend = remainingRefundable is double
        ? remainingRefundable
        : remainingRefundable.toDouble();
  }

  final refundId = await requestRefund(
    paymentId: paymentId,
    refundAmount: refundToSend,
  );

  // ---------------------------
  // 6️⃣ UPDATE BOOKING DOCUMENT
  // ---------------------------
  batch.update(bookingRef, {
    "refund_id": refundId,
    "refunded_amount": refundToSend,
    "refunded_before_gst": computedGross,
    "refunded_gst": cancelledGst,
    "admin_fee": adminFee,
    "admin_gst": adminGst,
    "attendance_override": existingOverrides,
    "updatedAt": FieldValue.serverTimestamp(),
    "status": "partially_cancelled",
    "cost_breakdown.sp_service_fee": adjustedSpFee,
    "cost_breakdown.sp_service_gst": adjustedSpGst,
    "cost_breakdown.sp_total_with_gst": adjustedSpFee + adjustedSpGst,
  });

  // ---------------------------
  // 7️⃣ WRITE CANCELLATION HISTORY
  // ---------------------------
  final historyEntry = {
    "refund_requested_at": DateTime.now(),
    "cancellation_details": {
      for (final e in cancellations.entries)
        e.key: e.value.map((id) => {"id": id}).toList()
    },
    "computed_gross": computedGross,
    "admin_fee": adminFee,
    "admin_gst": adminGst,
    "net_refund_including_gst": refundToSend,
    "refund_id": refundId,
    "payment_id": paymentId,
    "created_at": DateTime.now(),
  };

  batch.set(
    bookingRef.collection("user_cancellation_history").doc(),
    historyEntry,
  );

  // ---------------------------
  // 8️⃣ COMMIT BATCH
  // ---------------------------
  await batch.commit();

  // ---------------------------
  // 9️⃣ ADMIN PAYOUT
  // ---------------------------
  if (adminFee > 0) {
    await triggerAdminCancellationPayout(
      orderId: bookingDoc.id,
      adminFee: adminFee,
    );
  }

  // ---------------------------
  // 🔟 CHECK FULL CANCEL — MOVE BOOKING
  // ---------------------------
  final updatedDoc = await bookingRef.get();
  final updatedOverrides = (updatedDoc['attendance_override'] as Map<String, dynamic>)
      .map((k, v) => MapEntry(k, (v as List).cast<String>()));

  final isFullCancel = selectedDates.every((day) {
    final key = DateFormat('yyyy-MM-dd').format(day);
    return petIds.every((p) => updatedOverrides[key]?.contains(p) ?? false);
  });

  if (!isFullCancel) return;

  // MOVE BOOKING + SUBCOLLECTIONS
  final sourceRef = firestore
      .collection('users-sp-boarding')
      .doc(serviceId)
      .collection('service_request_boarding')
      .doc(bookingDoc.id);

  final destRef = firestore
      .collection('users-sp-boarding')
      .doc(serviceId)
      .collection('cancellations')
      .doc(bookingDoc.id);

  final sourceData = (await sourceRef.get()).data();
  if (sourceData != null) await destRef.set(sourceData);

  final subNames = [
    'pet_services',
    'user_cancellation_history',
    'sp_cancellation_history',
  ];

  for (final sub in subNames) {
    final col = await sourceRef.collection(sub).get();
    for (final doc in col.docs) {
      await destRef.collection(sub).doc(doc.id).set(doc.data());
      await doc.reference.delete();
    }
  }

  await sourceRef.delete();

  print("🎉 Booking fully cancelled and moved.");
}


/// ------------------------------------------------------------
/// Razorpay refund API caller (basic version)
/// ------------------------------------------------------------
Future<String?> requestRefund({
  required String paymentId,
  required double refundAmount,
}) async {
  const refundUrl =
      "https://razorpayrefundtest-urjpiqxoca-uc.a.run.app/razorpayRefundTest";

  try {
    final response = await http.post(
      Uri.parse(refundUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "paymentId": paymentId,
        "refundAmount": (refundAmount * 100).round(), // paise
      }),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return json['refund']['id'];
    } else {
      debugPrint("Refund Error: ${response.body}");
      return null;
    }
  } catch (e) {
    debugPrint("Refund Exception: $e");
    return null;
  }
}


Future<void> _triggerSpFullCancelPayout({
  required String serviceId,
  required String bookingId,
}) async {
  final firestore = FirebaseFirestore.instance;
  final spDoc = await FirebaseFirestore.instance
      .collection('users-sp-boarding')
      .doc(serviceId)
      .get();

  final spData = spDoc.data();
  if (spData == null) {
    print('❌ SP data missing for $serviceId');
    return;
  }

  final fundAccountId = spData['payout_fund_account_id'];
  if (fundAccountId == null) {
    print('❌ SP payout fund account NOT linked for $serviceId');
    return;
  }


  // get booking data
  final doc = await firestore
      .collection('users-sp-boarding')
      .doc(serviceId)
      .collection('service_request_boarding')
      .doc(bookingId)
      .get();

  if (!doc.exists) return;
  final data = doc.data() as Map<String, dynamic>;

  // 1️⃣ Base SP fee EXCLUDING GST
  final baseStr = data['sp_service_fee_exc_gst']?.toString() ?? '0';
  final baseFee = double.tryParse(baseStr) ?? 0.0;

  // 2️⃣ Sum refunds (EX GST)
  Future<double> sumRefunds(String col) async {
    final qs = await doc.reference.collection(col).get();
    double total = 0.0;
    for (final d in qs.docs) {
      final raw = d['net_refund_excluding_gst']?.toString() ?? '0';
      total += double.tryParse(raw) ?? 0.0;
    }
    return total;
  }

  final userRefund = await sumRefunds('user_cancellation_history');
  final spRefund   = await sumRefunds('sp_cancellation_history');

  final totalRefund = userRefund + spRefund;

  // 3️⃣ Payout before commission
  double payout = baseFee - totalRefund;
  if (payout < 0) payout = 0;

  // 4️⃣ Apply admin commission
  const commissionRate = 10;  // (your value)
  final commissionAmount = payout * commissionRate / 100;
  final finalPayout = payout - commissionAmount;

  // 5️⃣ Trigger Razorpay Payout (Cloud Function)
  final url = "https://us-central1-petproject-test-g.cloudfunctions.net/v2initiatePayout";

  await http.post(
    Uri.parse(url),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      "serviceProviderId": serviceId,
      "fundAccountId": fundAccountId,
      "orderId": bookingId,
      "amount": (finalPayout * 100).toInt(), // paise
    }),
  );

  print("💸 SP payout triggered after full cancel: ₹$finalPayout");
}

void showCancellationInvoiceDialog({
  required BuildContext context,
  required Map<DateTime,List<String>> cancellations,
  required Map<String, String> petNamesMap,
  required List<Map<String, dynamic>> petSizes,
  required double walkCostPerDay,
  required Map<String, double> boardingPriceByPet,
  required double mealCostPerDay,
  required int adminPct,
  required Map<String, int> providerPolicyMap,       // <-- int values
  required List<Map<String, dynamic>> brackets,
  required Future<Map<String, dynamic>> Function({
  required String paymentId,
  required int amountInPaise,
  }) requestRefund,
  required DocumentSnapshot bookingDoc,
  required double gstRate, // 👈 add this line

}) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    pageBuilder: (ctx, animation, secondaryAnimation) {
      final now = DateTime.now();
      final dates = cancellations.keys.toList()..sort();
      // -----------------------------------------------------------
// BUILD refundReasons (same as handleCancel)
// -----------------------------------------------------------
      final refundReasons = <DateTime, Map<String, String>>{};
      final now2 = DateTime.now();

      for (final entry in cancellations.entries) {
        final date = entry.key;
        refundReasons[date] = {};

        for (final petId in entry.value) {
          final boarding = boardingPriceByPet[petId]!;
          final subtotal = boarding + walkCostPerDay + mealCostPerDay;

          final hoursUntil = date.difference(now2).inHours.toDouble();
          final pct = calculateRefundPercent(
            timeToStartInHours: hoursUntil,
            brackets: brackets,
            providerPolicy: providerPolicyMap,
          );

          refundReasons[date]![petId] =
          "$pct% refund because cancelled ${hoursUntil.toStringAsFixed(0)}h before start";
        }
      }

      // ── Compute gross via your helper, not by hand ─────────────────
      // ── Build per-pet daily cost ─────────────────────────────
      final perPetDaily = petSizes
          .map((ps) => (ps['price'] as num).toDouble())
          .fold<double>(walkCostPerDay + mealCostPerDay, (sum, price) => sum + price);

// ── Compute a per-day total (all pets) ────────────────────
      // ── Compute a per-day total by summing each pet’s refund ───
      final Map<DateTime, double> dayTotals = {
        for (final day in dates)
          day: cancellations[day]!.fold<double>(0, (sum, petId) {
            // 1) boarding price for this pet
            final boarding = boardingPriceByPet[petId]!;

            // 2) full subtotal (boarding + walk + meal)
            final subtotal = boarding + walkCostPerDay + mealCostPerDay;

            // 3) find refund % for this date
            final hoursUntil = day.difference(now).inHours.toDouble();
            final pct = calculateRefundPercent(
              timeToStartInHours: hoursUntil,
              brackets: brackets,
              providerPolicy: providerPolicyMap,
            );

            // 4) that pet’s refund amount
            final petRefund = subtotal * (pct / 100);

            return sum + petRefund;
          }),
      };



// ── Compute gross (all days × all pets) ───────────────────
      final computedGross = dayTotals.values.fold(0.0, (sum, v) => sum + v);
      final adminFeeFinal =(computedGross*(adminPct/100));
      final netRefund = computedGross - adminFeeFinal;
      // 🔹 Calculate GST refund portion
// GST is already part of total_amount in booking, so extract the GST portion correctly
      final cancelledGst = (computedGross / (1 + gstRate)) * gstRate;  // isolates GST from the gross refund
      final netRefundWithGst = computedGross + cancelledGst - adminFeeFinal;          // refund includes GST implicitly

      // 🔽🔽🔽 ONLY ADDITIONS BELOW: state to lock the button + show spinner
      bool isCancelling = false;
      return StatefulBuilder(
        builder: (ctx, setState) {
          return SafeArea(
            child: Center(
              child: Material(
                color: Colors.white,
                elevation: 24,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Container(
                  width: MediaQuery.of(ctx).size.width * 0.9,
                  padding: const EdgeInsets.all(24),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Title ───────────────────────────
                        Text(
                          'Cancellation Invoice',
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            showGeneralDialog(
                              context: ctx,
                              barrierDismissible: true,
                              barrierLabel: 'Dismiss',
                              pageBuilder: (ctx3, anim, secAnim) {
                                return Stack(
                                  children: [
                                    // Semi-transparent scrim to dismiss when tapping outside
                                    Positioned.fill(
                                      child: GestureDetector(
                                        onTap: () => Navigator.of(ctx3).pop(),
                                        child: Container(color: Colors.black38),
                                      ),
                                    ),

                                    // Centered popup
                                    Center(
                                      child: Material(
                                        color: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Container(
                                          width: MediaQuery.of(ctx3).size.width * 0.9,
                                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // ── Title ───────────────────────────
                                              Text(
                                                'Service Provider Refund Policy',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: const Color(0xFF2CB4B6),
                                                ),
                                              ),
                                              const SizedBox(height: 12),

                                              // ── Policy lines ────────────────────
                                              // 1) “greater than Xh” cases, skipping any 0-hour bracket
                                              for (final bracket in brackets.where((b) => (b['min_hours'] as num) > 0)) ...[
                                                Builder(builder: (_) {
                                                  final minH = (bracket['min_hours'] as num).toInt();
                                                  final pct  = providerPolicyMap[bracket['label']] ?? 0;
                                                  return Text.rich(
                                                    TextSpan(children: [
                                                      TextSpan(
                                                        text: 'If the time difference between now and the start of service is ',
                                                        style: GoogleFonts.poppins(fontSize: 13),
                                                      ),
                                                      TextSpan(
                                                        text: 'more than ${minH} hours',
                                                        style: GoogleFonts.poppins(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                      TextSpan(
                                                        text: ': ',
                                                        style: GoogleFonts.poppins(fontSize: 13),
                                                      ),
                                                      TextSpan(
                                                        text: '${pct}%',
                                                        style: GoogleFonts.poppins(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                      TextSpan(
                                                        text: ' refund',
                                                        style: GoogleFonts.poppins(fontSize: 13),
                                                      ),
                                                    ]),
                                                  );
                                                }),
                                                const SizedBox(height: 8),
                                              ],

                                              // 2) “less than smallest non-zero bracket” case
                                              if (brackets.any((b) => (b['min_hours'] as num) > 0)) ...[
                                                Builder(builder: (_) {
                                                  final nonZero = brackets.where((b) => (b['min_hours'] as num) > 0).toList();
                                                  final cutoff  = (nonZero.last['min_hours'] as num).toInt();
                                                  return Text.rich(
                                                    TextSpan(children: [
                                                      TextSpan(
                                                        text: 'If the time difference between now and the start of service is ',
                                                        style: GoogleFonts.poppins(fontSize: 13),
                                                      ),
                                                      TextSpan(
                                                        text: 'less than ${cutoff} hours',
                                                        style: GoogleFonts.poppins(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                      TextSpan(
                                                        text: ': ',
                                                        style: GoogleFonts.poppins(fontSize: 13),
                                                      ),
                                                      TextSpan(
                                                        text: '0%',
                                                        style: GoogleFonts.poppins(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                      TextSpan(
                                                        text: ' refund',
                                                        style: GoogleFonts.poppins(fontSize: 13),
                                                      ),
                                                    ]),
                                                  );
                                                }),
                                                const SizedBox(height: 8),
                                              ],

                                              // ── Footnote ────────────────────────
                                              const SizedBox(height: 4),
                                              Text(
                                                'Note: “start of service” refers to the provider’s operating hours on that day.',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 10,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                              const SizedBox(height: 12),

                                              // ── Close button ────────────────────
                                              Align(
                                                alignment: Alignment.centerRight,
                                                child: TextButton(
                                                  onPressed: () => Navigator.of(ctx3).pop(),
                                                  child: Text(
                                                    'Close',
                                                    style: GoogleFonts.poppins(
                                                      color: const Color(0xFF2CB4B6),
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),


                                  ],
                                );
                              },
                              transitionBuilder: (_, anim, __, child) =>
                                  FadeTransition(opacity: anim, child: child),
                              transitionDuration: const Duration(milliseconds: 200),
                            );
                          },
                          child: Text(
                            '(Service Provider Refund Policy)',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              decoration: TextDecoration.underline,
                              color: const Color(0xFF2CB4B6),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Per-date breakdown ───────────────────────────
                        for (final day in dates) ...[
                          Text(
                            DateFormat('MMM dd, yyyy').format(day),
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),

                          for (final petId in cancellations[day]!) ...[
                            Builder(builder: (ctx2) {
                              final petName = petNamesMap[petId] ?? petId;
// look up the index of this petId in the original petIds list
                              final boarding = boardingPriceByPet[petId]!;
                              final subtotal =
                                  boarding + walkCostPerDay + mealCostPerDay;
                              final hoursUntil =
                              day.difference(now).inHours.toDouble();
                              final pct = calculateRefundPercent(
                                timeToStartInHours: hoursUntil,
                                brackets: brackets,
                                providerPolicy: providerPolicyMap,
                              );
                              final refundAmt = subtotal * pct / 100;

                              return Padding(
                                padding: const EdgeInsets.only(left: 8, bottom: 6),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '• $petName: ₹${subtotal.toStringAsFixed(2)}',
                                        style: GoogleFonts.poppins(),
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        // 1) the percent line
                                        Text(
                                          '× $pct% refund',
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        Text(
                                          refundReasons[day]?[petId] ?? '',
                                          style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),

                                      ],
                                    ),
                                    const SizedBox(width: 16),
                                    Text(
                                      '= ₹${refundAmt.toStringAsFixed(2)}',
                                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],

                          // Date total
                          Builder(builder: (ctx2) {
                            final dayTotal = cancellations[day]!.fold<double>(0, (sum, petId) {
                              // directly pull boarding price from your map
                              final boarding = boardingPriceByPet[petId]!;
                              final subtotal = boarding + walkCostPerDay + mealCostPerDay;
                              final hoursUntil = day.difference(now).inHours.toDouble();
                              final pct = calculateRefundPercent(
                                timeToStartInHours: hoursUntil,
                                brackets: brackets,
                                providerPolicy: providerPolicyMap,
                              );
                              return sum + (subtotal * pct / 100);
                            });


                            return Padding(
                              padding: const EdgeInsets.only(left: 8, bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Total refund for this date: ₹${dayTotal.toStringAsFixed(2)}',
                                    style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            );
                          }),

                          const Divider(),
                        ],

                        // ── Summary ─────────────────────────────
                        const SizedBox(height: 8),

                        Text(
                          'Gross refund (excl. GST): ₹${computedGross.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Refunded GST (${(gstRate * 100).toStringAsFixed(0)}%): +₹${cancelledGst.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Subtotal (incl. GST): ₹${(computedGross + cancelledGst).toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Admin fee ($adminPct%): –₹${adminFeeFinal.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Net you’ll receive: ₹${netRefundWithGst.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),

                        Text(
                          'Amount credited to your account',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Actions ─────────────────────────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.white,                             // fill black
                                side: BorderSide(color: AppColors.primary, width: 1.5),         // white outline
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: Text(
                                'No',
                                style: GoogleFonts.poppins(
                                  color: AppColors.primary,                                   // black text
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),

                            const SizedBox(width: 12),
                            TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.white,                             // fill black
                                side: BorderSide(color: AppColors.primary, width: 1.5),         // white outline
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                              // Inside showCancellationInvoiceDialog, find the "Yes, Cancel" TextButton
// and replace its onPressed callback with this entire block.

                              onPressed: isCancelling ? null : () async {
                                setState(() => isCancelling = true);
                                try {
                                  // --- Start of Cancellation Logic ---
                                  final raw = bookingDoc.data()! as Map<String, dynamic>;
                                  final nowTs = DateTime.now();
                                  final firestore = FirebaseFirestore.instance;
                                  final ref = bookingDoc.reference;

                                  // 1️⃣ Create a WriteBatch to handle all DB changes atomically.
                                  final batch = firestore.batch();

                                  // 2️⃣ NEW: Loop through the cancellations to decrement daily_summary counts.
                                  cancellations.forEach((date, petsToCancel) {
                                    final dateString = DateFormat('yyyy-MM-dd').format(date);
                                    final summaryRef = firestore
                                        .collection('users-sp-boarding')
                                        .doc(raw['service_id'] as String)
                                        .collection('daily_summary')
                                        .doc(dateString);

                                    // Decrement by the number of pets cancelled on this specific day.
                                    batch.update(summaryRef, {
                                      'bookedPets': FieldValue.increment(-petsToCancel.length)
                                    });
                                  });

                                  // 3️⃣ Compute adjusted total for the booking document.
                                  final cb = raw['cost_breakdown'] as Map<String, dynamic>? ?? {};
                                  final originalSpFee = double.tryParse(cb['sp_service_fee']?.toString() ?? '0') ?? 0.0;
                                  final rawAdjustedSpFee = originalSpFee - computedGross;
                                  final adjustedSpFee = rawAdjustedSpFee;

                                  final settingsSnap = await FirebaseFirestore.instance
                                      .collection('company_documents')
                                      .doc('fees')
                                      .get();

                                  final gstRate = double.tryParse(
                                    settingsSnap.data()?['gst_rate_percent']?.toString() ?? '0.18',
                                  ) ??
                                      0.18; // fallback just in case the doc is missing
                                  final originalSpGst =
                                      double.tryParse(cb['sp_service_gst']?.toString() ?? '0') ?? 0.0;

// AFTER: Apply rounding to 2 decimal places
                                  final cancelledGst = (computedGross / (1 + gstRate)) * gstRate;
                                  final rawAdjustedSpGst = (originalSpGst - cancelledGst).clamp(0, double.infinity);
                                  final adjustedSpGst = rawAdjustedSpGst;

                                  final updates = <String, dynamic>{
                                    'refund_amount': netRefundWithGst.toStringAsFixed(2),
                                    'cost_breakdown.sp_service_fee': adjustedSpFee,
                                    'cost_breakdown.sp_service_gst': adjustedSpGst,
                                    'cost_breakdown.sp_total_with_gst': adjustedSpFee + adjustedSpGst,
                                    'cancellation_requested_at': nowTs,

                                  };
                                  for (final d in dates) {
                                    final key = DateFormat('yyyy-MM-dd').format(d);
                                    updates['attendance_override.$key'] =
                                        FieldValue.arrayUnion(cancellations[d]!);
                                  }

                                  // Add this update to the batch.
                                  batch.update(ref, updates);

                                  // 5️⃣ Handle Razorpay refund if enabled.
                                  final payDoc = await firestore.collection('company_documents').doc('payment').get();
                                  final bool refundEnabled = (payDoc.data()?['checkoutEnabled'] as bool?) ?? false;
                                  String? refundId;

                                  if (refundEnabled) {
                                    final String? paymentId = raw['payment_id'] as String?;
                                    if (paymentId == null) {
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        const SnackBar(content: Text('Refund failed: no payment ID found')),
                                      );
                                      setState(() => isCancelling = false);
                                      return;
                                    }

                                    // 🧾 1️⃣ Calculate original total & previous refunds before refund call
                                    final originalTotal = double.tryParse(
                                      (raw['cost_breakdown']?['total_amount'] ?? '0').toString(),
                                    ) ?? 0.0;

                                    final historySnap = await bookingDoc.reference
                                        .collection('user_cancellation_history')
                                        .get();

                                    final totalAlreadyRefunded = historySnap.docs.fold<double>(0.0, (sum, doc) {
                                      final data = doc.data();

                                      // 💥 FIX APPLIED HERE: Safely read it as a String and parse it.
                                      final prevRefundString = data['net_refund_including_gst']?.toString();

                                      final prevRefund = double.tryParse(prevRefundString ?? '0.0') ?? 0.0;

                                      return sum + prevRefund;
                                    });
                                    double refundToSend = double.parse(netRefundWithGst.toStringAsFixed(2));
                                    final remaining = (originalTotal - totalAlreadyRefunded).clamp(0, double.infinity);

                                    // 🧠 2️⃣ Debug print everything before refunding
                                    print("===== 🔍 REFUND DEBUG START =====");
                                    print("🧾 Original total: ₹${originalTotal.toStringAsFixed(2)}");
                                    print("💰 Already refunded: ₹${totalAlreadyRefunded.toStringAsFixed(2)}");
                                    print("📦 Remaining refundable: ₹${remaining.toStringAsFixed(2)}");
                                    print("🧮 Requested refund (netRefundWithGst): ₹${netRefundWithGst.toStringAsFixed(2)}");

                                    if (refundToSend > remaining) {
                                      print("⚠️ Requested refund ₹${refundToSend.toStringAsFixed(2)} > remaining ₹${remaining.toStringAsFixed(2)}");
                                      refundToSend = remaining.toDouble();
                                    }

                                    print("✅ Final refundToSend: ₹${refundToSend.toStringAsFixed(2)}");
                                    print("💸 Sending ${refundToSend * 100} paise to Razorpay for paymentId: $paymentId");
                                    print("===== 🔍 REFUND DEBUG END =====");

                                    // 🪙 3️⃣ Send refund
                                    try {
                                      final resp = await requestRefund(
                                        paymentId: paymentId,
                                        amountInPaise: (refundToSend * 100).toInt(),
                                      );
                                      refundId = resp['id'] as String?;
                                    } catch (e) {
                                      setState(() => isCancelling = false);
                                      return;
                                    }
                                  }


                                  // 6️⃣ Add the cancellation history entry to the batch.
                                  final historyEntry = {
                                    'refund_requested_at': nowTs,
                                    'cancellation_details': {
                                      for (final date in cancellations.keys)
                                        DateFormat('yyyy-MM-dd').format(date): cancellations[date]!
                                            .map((petId) => {'id': petId, 'name': petNamesMap[petId] ?? 'Unknown'})
                                            .toList(),
                                    },
                                    'cancelled_gst': cancelledGst,
                                    'gst_rate_percent': gstRate * 100,
                                    'net_refund_including_gst': netRefundWithGst.toStringAsFixed(2),
                                    'net_refund_excluding_gst': netRefund,
                                    'computed_gross': computedGross,
                                    'admin_fee': adminFeeFinal,
                                    'admin_fee_pct': adminPct,
                                    'sp_service_fee_after_cancellation': adjustedSpFee,
                                    'net_refund': netRefund,
                                    'payment_id': raw['payment_id'] as String?,
                                    'refund_id': refundId,
                                    'created_at': nowTs,
                                  };

                                  // Use .doc() to create a new entry with an auto-ID.
                                  final historyRef = ref.collection('user_cancellation_history').doc();
                                  batch.set(historyRef, historyEntry);

                                  // 7️⃣ Commit all batched writes to Firestore.
                                  await batch.commit();
                                  // 🟢 Trigger Admin Payout after refund
                                  if (adminFeeFinal > 0) {
                                    await triggerAdminCancellationPayout(
                                      orderId: bookingDoc.id,
                                      adminFee: adminFeeFinal,
                                    );

                                    // Optional: mark payout status in user cancellation history
                                    await bookingDoc.reference
                                        .collection('user_cancellation_history')
                                        .doc(historyRef.id)
                                        .update({
                                      'admin_fee_payout_done': true,
                                      'admin_fee_payout_time': FieldValue.serverTimestamp(),
                                    });
                                  }

                                  // Show success message.
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        refundId != null
                                            ? 'Refund of ₹${netRefundWithGst.toStringAsFixed(2)} initiated (ID: $refundId)'
                                            : 'Booking successfully updated.',
                                      ),
                                    ),
                                  );

                                  final updatedDoc = await ref.get(); // Re-fetch the doc to get the latest override data
                                  final latestData = updatedDoc.data() as Map<String, dynamic>;
                                  final fullDates = (latestData['selectedDates'] as List<dynamic>)
                                      .map((d) => (d as Timestamp).toDate())
                                      .toList();
                                  final fullPets = (latestData['pet_id'] as List<dynamic>).cast<String>();
                                  final effectiveOverrides = (latestData['attendance_override'] as Map<String, dynamic>?)
                                      ?.map((k, v) => MapEntry(k, (v as List).cast<String>())) ?? {};

                                  final isFullCancel = fullDates.every((d) {
                                    final key = DateFormat('yyyy-MM-dd').format(d);
                                    return fullPets.every((petId) => effectiveOverrides[key]?.contains(petId) ?? false);
                                  });

                                  if (isFullCancel) {
                                    final serviceId = raw['service_id'] as String? ?? bookingDoc.id;
                                    final firestore = FirebaseFirestore.instance;

                                    final sourceRef = firestore
                                        .collection('users-sp-boarding')
                                        .doc(serviceId)
                                        .collection('service_request_boarding')
                                        .doc(bookingDoc.id);
                                    // ⚡ Trigger SP payout BEFORE moving booking
                                    await _triggerSpFullCancelPayout(
                                      serviceId: serviceId,
                                      bookingId: bookingDoc.id,
                                    );


                                    final destRef = firestore
                                        .collection('users-sp-boarding')
                                        .doc(serviceId)
                                        .collection('cancellations')
                                        .doc(bookingDoc.id);

                                    print('♻️ Moving booking ${bookingDoc.id} and its subcollections to cancellations...');

                                    // 1️⃣ Copy main document
                                    final latestData = (await sourceRef.get()).data();
                                    if (latestData != null) {
                                      await destRef.set(latestData);
                                    }

                                    // 2️⃣ Manually copy subcollections (since .listCollections() isn’t available)
                                    final possibleSubcollections = [
                                      'pet_services',
                                      'user_cancellation_history',
                                      'sp_cancellation_history',
                                    ];

                                    for (final subName in possibleSubcollections) {
                                      final subCol = sourceRef.collection(subName);
                                      final subDocs = await subCol.get();

                                      if (subDocs.docs.isEmpty) continue;

                                      final subDest = destRef.collection(subName);
                                      for (final doc in subDocs.docs) {
                                        await subDest.doc(doc.id).set(doc.data());
                                      }
                                      print('✅ Copied subcollection: $subName');
                                    }

                                    // 3️⃣ Delete original docs and their subcollections
                                    for (final subName in possibleSubcollections) {
                                      final subCol = sourceRef.collection(subName);
                                      final subDocs = await subCol.get();
                                      for (final doc in subDocs.docs) {
                                        await subCol.doc(doc.id).delete();
                                      }
                                    }

                                    await sourceRef.delete();
                                    print('🗑️ Deleted original booking and its subcollections.');
                                    print('✅ Booking ${bookingDoc.id} fully cancelled and moved successfully.');
                                  }

                                  // 9️⃣ Close the dialog.
                                  Navigator.of(ctx).pop();
                                } catch (e) {
                                  setState(() => isCancelling = false);
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text('Cancellation failed: $e')),
                                  );
                                }
                              },

                              child: isCancelling
                                  ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                              )
                                  : Text(
                                'Yes, Cancel',
                                style: GoogleFonts.poppins(
                                  color: AppColors.primary,                                   // black text
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),


                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
    transitionBuilder: (ctx, anim, secAnim, child) =>
        FadeTransition(opacity: anim, child: child),
    transitionDuration: const Duration(milliseconds: 200),
  );
}




/// Helper to return the user’s choices.
/// Helper to return the user’s choices.
class _CancelSelection {
  final List<DateTime> dates;
  final List<String> petIds;
  final int   numPets;
  _CancelSelection({
    required this.dates,
    required this.petIds,
    required this.numPets,
  });
}



class BoardingOrders extends StatelessWidget {
  final String userId;
  const BoardingOrders({Key? key, required this.userId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFffffff),
        title: Text(
          'My Bookings',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        // The `bottom` property is removed completely.
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.grey.shade100,
              Colors.white,
            ],
          ),
        ),
        // The body now directly holds `ConfirmedBookingsNav`
        child: ConfirmedBookingsNav(userId: userId),
      ),
    );
  }
}


class ConfirmedBookingsNav extends StatefulWidget {
  final String userId;
  const ConfirmedBookingsNav({Key? key, required this.userId}) : super(key: key);

  @override
  _ConfirmedBookingsNavState createState() => _ConfirmedBookingsNavState();
}

class _ConfirmedBookingsNavState extends State<ConfirmedBookingsNav> {
  // 0 = Ongoing, 1 = Upcoming, 2 = Past
  int _selectedIndex = 0;
  String _searchTerm = '';

  void _showCannotCancelDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("Cancellation Not Allowed", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text("Bookings can only be cancelled up to 24 hours before the service start time.", style: GoogleFonts.poppins()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('OK', style: GoogleFonts.poppins(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  final TextEditingController _searchController = TextEditingController();

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  dynamic openTime;
  dynamic closeTime;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 1) Search bar at top, full width:
        _buildSearchBar(),

        // 2) Main content below:
        Expanded(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
                labelType: NavigationRailLabelType.all,
                backgroundColor: Colors.white, // Match the card background
                selectedLabelTextStyle: GoogleFonts.poppins(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelTextStyle: GoogleFonts.poppins(
                  color: Colors.black54,
                ),
                selectedIconTheme: IconThemeData(
                  color: AppColors.primary,
                  size: 24,
                ),
                unselectedIconTheme: IconThemeData(
                  color: Colors.black54,
                  size: 24,
                ),
                destinations: [
                  NavigationRailDestination(
                    icon: Icon(Icons.play_arrow_outlined),
                    selectedIcon: Icon(Icons.play_arrow),
                    label: Text('Ongoing'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.schedule_outlined),
                    selectedIcon: Icon(Icons.schedule),
                    label: Text('Upcoming'),
                  ),
                  // 🆕 ADDED DESTINATION FOR PAST ORDERS
                  NavigationRailDestination(
                    icon: Icon(Icons.history_outlined),
                    selectedIcon: Icon(Icons.history),
                    label: Text('Past'),
                  ),
                ],
              ),

              // ---- content area ----
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collectionGroup('service_request_boarding')
                      .where('user_id', isEqualTo: widget.userId)
                      .where('order_status', isEqualTo: 'confirmed')
                      .snapshots(),
                  builder: (_, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator(color: AppColors.primary));
                    }
                    if (snap.hasError) {
                      return Center(child: Text('Something went wrong. Please try again.', style: GoogleFonts.poppins()));
                    }
                    if (!snap.hasData || snap.data!.docs.isEmpty) {
                      return Center(child: Text('No confirmed bookings found.', style: GoogleFonts.poppins()));
                    }

                    // --- ISOLATE LOGIC START ---
                    final docs = snap.data!.docs;
                    final today = DateTime.now();
                    final todayStart = DateTime(today.year, today.month, today.day);

                    // Use FutureBuilder to run heavy filtering on a separate isolate
                    return FutureBuilder<FilteredOrders>(
                      future: compute(
                        computeOrderLists,
                        OrderComputeData(docs: docs, todayStart: todayStart),
                      ),
                      builder: (context, computeSnap) {
                        if (computeSnap.connectionState == ConnectionState.waiting) {
                          return Center(child: CircularProgressIndicator(color: AppColors.primary));
                        }
                        if (computeSnap.hasError) {
                          return Center(child: Text('Error filtering orders: ${computeSnap.error}', style: GoogleFonts.poppins()));
                        }

                        final filtered = computeSnap.data!;
                        var listToShow = <OrderSummary>[];

                        // 2. Select the list based on the current tab
                        switch (_selectedIndex) {
                          case 0: // Ongoing
                            listToShow = filtered.ongoing;
                            break;
                          case 1: // Upcoming
                            listToShow = filtered.upcoming;
                            break;
                          case 2: // Past
                            listToShow = filtered.past;
                            break;
                        }

                        // 3. Apply search filter
                        if (_searchTerm.isNotEmpty) {
                          final term = _searchTerm.toLowerCase();
                          listToShow = listToShow.where((o) {
                            return o.shopName.toLowerCase().contains(term)
                                || o.doc.id.toLowerCase().contains(term);
                          }).toList();
                        }
                        // --- ISOLATE LOGIC END ---

                        if (listToShow.isEmpty) {
                          final tabName = _selectedIndex == 0 ? 'Ongoing' : (_selectedIndex == 1 ? 'Upcoming' : 'Past');
                          return Center(child: Text('No $tabName bookings match your criteria.', style: GoogleFonts.poppins()));
                        }

                        return ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: listToShow.length,
                          itemBuilder: (_, i) => _buildOrderCard(listToShow[i]),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.poppins(
          fontSize: 14,
          color: Colors.black,
        ),
        decoration: InputDecoration(
          hintText: 'Search by shop name or order ID',
          hintStyle: GoogleFonts.poppins(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
          prefixIcon: Icon(Icons.search, color: AppColors.primary),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
            icon: Icon(Icons.clear, color: AppColors.primary),
            onPressed: () {
              setState(() {
                _searchController.clear();
                _searchTerm = '';
              });
            },
          )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade400, width: 1.0),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade400, width: 1.0),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade600, width: 1.5),
          ),
        ),
        onChanged: (val) {
          setState(() => _searchTerm = val.trim());
        },
      ),
    );
  }

  // REPLACE your entire _buildOrderCard method with this one

  // lib/screens/Orders/BoardingOrders.dart (inside _buildOrderCard)

  Widget _buildOrderCard(OrderSummary order) {
    // --- MODIFICATION START ---
    // 1. Find the earliest date that is today or in the future
    final now = DateTime.now();
    final upcomingDates = order.dates
        .where((d) => !d.isBefore(now.subtract(const Duration(days: 1))))
        .toList();
    upcomingDates.sort();

    bool canCancel = false;
    bool checkoutEnabled = false;

    // --- MODIFICATION END ---

    // Extract raw data
    final data = order.doc.data() as Map<String, dynamic>;
    final rawList = data['selectedDates'] as List<dynamic>? ?? [];

    // convert each entry (Timestamp or ISO‐string) into a DateTime
    final selectedDates = rawList
        .map<DateTime>((e) {
      if (e is Timestamp) return e.toDate();
      if (e is String) return DateTime.parse(e);
      throw StateError('Unknown date type: $e');
    })
    // (optional) strip off any time component so you only have YYYY‑MM‑DD
        .map((dt) => DateTime(dt.year, dt.month, dt.day))
        .toList();
    final dates = order.dates;
    final sortedDates = List<DateTime>.from(dates)..sort();
    final openTime = data['openTime'] as String? ?? '12:00 AM';
    final closeTime = data['closeTime'] as String? ?? '11:59 PM';
    final petNamesList = order.petNames;

    final startedAtTs = (data['startedAt'] as Timestamp?)?.toDate();
    final startedAtStr = startedAtTs != null
        ? DateFormat('dd-MM-yyyy hh:mm a').format(startedAtTs)
        : 'Not started';

    final furthestDate = selectedDates.isNotEmpty
        ? selectedDates.reduce((a, b) => b.isAfter(a) ? b : a)
        : null;
    final completesOnStr = furthestDate != null
        ? DateFormat('dd-MM-yyyy').format(furthestDate)
        : '–––';

    final petImages = (data['pet_images'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList() ??
        <String>[];
    // ✨ CRITICAL: Retrieve the pre-calculated breakdown from the document
    final petCostBreakdown = List<Map<String, dynamic>>.from(data['petCostBreakdown'] ?? []);
    final totalCost = double.tryParse(
      (data['cost_breakdown'] as Map<String, dynamic>?)?['total_amount']
          ?.toString() ??
          '0',
    ) ?? 0.0;
    final serviceId = data['service_id'] as String? ?? order.doc.id;
    final String? pid = data['payment_id'];
    final bool isDirectBooking = pid == null || pid.isEmpty;


    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('company_documents')
          .doc('payment')
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final checkoutEnabled = data?['checkoutEnabled'] == true;


        // This logic remains the same for the "CANCEL" button appearance
        final canCancel = checkoutEnabled;

        return Padding(
          padding: const EdgeInsets.all(0),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            // [Inside _buildOrderCard]
            // [Inside _buildOrderCard]
            onTap: () async {
              // ---------------------------------------------------------
              // 1. SHOW LOADER DIALOG
              // ---------------------------------------------------------
              showGeneralDialog(
                context: context,
                barrierDismissible: false,
                barrierLabel: 'Loading',
                barrierColor: Colors.white,  // FULL WHITE BACKGROUND
                pageBuilder: (context, _, __) {
                  return Container(
                    color: Colors.white, // Ensure full white
                    child: Center(
                      child: SizedBox(
                        width: 200,
                        height: 200,
                        child: Lottie.asset('assets/Loaders/App_Loader.json'),
                      ),
                    ),
                  );
                },
              );

              try {
                // ---------------------------------------------------------
                // 2. FETCH DATA (Existing Logic)
                // ---------------------------------------------------------

                // 1. Get the BOOKING document
                final bookingDoc = await order.doc.reference.get();

                // Safety check: if doc is gone, close loader and return
                if (!bookingDoc.exists) {
                  if (context.mounted) Navigator.of(context).pop();
                  return;
                }

                final data = bookingDoc.data() as Map<String, dynamic>;

                // 2. Extract Data
                final fullAddress = data['full_address'] as String? ?? 'Address not found';
                final serviceId = data['service_id'] as String?;
                final costBreakdown = data['cost_breakdown'] as Map<String, dynamic>? ?? {};

                final foodCost = double.tryParse(costBreakdown['meals_cost']?.toString() ?? '0') ?? 0.0;
                final walkingCost = double.tryParse(costBreakdown['daily_walking_cost']?.toString() ?? '0') ?? 0.0;
                final boardingCost = double.tryParse(costBreakdown['boarding_cost']?.toString() ?? '0') ?? 0.0;
                final transportCost = double.tryParse(data['transport_cost']?.toString() ?? '0') ?? 0.0;

                final petIds = List<String>.from(data['pet_id'] ?? []);
                final mealRates = Map<String, int>.from(data['mealRates'] ?? {});
                final walkingRates = Map<String, int>.from(data['walkingRates'] ?? {});
                final dailyRates = Map<String, int>.from(data['rates_daily'] ?? {});

                final spLocation = data['sp_location'] as GeoPoint? ?? const GeoPoint(0, 0);

                // 4. Fetch perDayServices (Async operation)
                final Map<String, Map<String, dynamic>> perDayServices = {};
                final petServicesSnapshot = await bookingDoc.reference.collection('pet_services').get();
                for (var petDoc in petServicesSnapshot.docs) {
                  perDayServices[petDoc.id] = petDoc.data();
                }

                // ---------------------------------------------------------
                // 3. CLOSE LOADER & NAVIGATE
                // ---------------------------------------------------------

                if (context.mounted) {
                  // Close the Loader Dialog
                  Navigator.of(context).pop();

                  // Navigate to Confirmation Page
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ConfirmationPage(
                        gstNumber:data['gst_number'] ?? "NA",

                        gstRegistered: data['gstRegistered'] ?? false,
                        checkoutEnabled: data['checkoutEnabled'] ?? false,
                        boarding_rate: boardingCost,
                        perDayServices: perDayServices,
                        petIds: petIds,
                        foodCost: foodCost,
                        walkingCost: walkingCost,
                        transportCost: transportCost,
                        mealRates: mealRates,
                        dailyRates: dailyRates,
                        walkingRates: walkingRates,
                        fullAddress: fullAddress,
                        sp_location: spLocation,
                        buildOpenHoursWidget: buildOpenHoursWidget(openTime, closeTime, dates),
                        shopName: order.shopName,
                        shopImage: order.shopImage,
                        selectedDates: dates,
                        totalCost: totalCost,
                        petNames: petNamesList,
                        openTime: openTime,
                        closeTime: closeTime,
                        bookingId: order.doc.id,
                        sortedDates: sortedDates,
                        petImages: petImages,
                        serviceId: serviceId ?? '',
                        fromSummary: false,
                        petCostBreakdown: petCostBreakdown,
                      ),
                    ),
                  );
                }
              } catch (e) {
                // If something fails, make sure to close the loader
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error loading booking details: $e")),
                  );
                }
              }
            },
            child: Card(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Color(0xFF2CB4B6), width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Header with Image ──────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RichText(
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                text: TextSpan(
                                  style: GoogleFonts.poppins(fontSize: 13),
                                  children: [
                                    const TextSpan(
                                      text: 'Name - ',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextSpan(
                                      text: order.shopName,
                                      style: const TextStyle(
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              RichText(
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                text: TextSpan(
                                  style: GoogleFonts.poppins(fontSize: 11),
                                  children: [
                                    const TextSpan(
                                      text: 'Order ID - ',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextSpan(
                                      text: order.doc.id,
                                      style: const TextStyle(
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            order.shopImage,
                            width: 45,
                            height: 45,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                            const Icon(Icons.store, size: 50, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),
                    RichText(
                      text: TextSpan(
                        style: GoogleFonts.poppins(fontSize: 11),
                        children: [
                          const TextSpan(
                            text: 'Booked on - ',
                            style: TextStyle(
                                color: Colors.black, fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                            text: order.timestampStr,
                            style: const TextStyle(color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    RichText(
                      text: TextSpan(
                        style: GoogleFonts.poppins(fontSize: 11),
                        children: [
                          const TextSpan(
                            text: 'Amount - ',
                            style: TextStyle(
                                color: Colors.black, fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                            text: "₹ ${order.Amount}",
                            style: const TextStyle(color: Colors.black87),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    for (final d in order.dates) ...[
                      Builder(builder: (_) {
                        final key = DateFormat('yyyy-MM-dd').format(d);
                        final cancelled = order.attendanceOverride[key] ?? <String>[];
                        final attendingPets = <String>[];
                        for (int i = 0; i < order.petIds.length; i++) {
                          if (!cancelled.contains(order.petIds[i])) {
                            attendingPets.add(order.petNames[i]);
                          }
                        }
                        if (attendingPets.isEmpty) return const SizedBox.shrink();

                        final isToday = DateTime(d.year, d.month, d.day) ==
                            DateTime.now().toLocal().copyWith(hour: 0, minute: 0);
                        final dateBg = isToday
                            ? AppColors.primary.withOpacity(0.15)
                            : Colors.grey.shade200;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: dateBg,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  DateFormat('dd MMM').format(d),
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: isToday
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  attendingPets.join(', '),
                                  style: GoogleFonts.poppins(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],

                    _infoRow('Started At', startedAtStr),
                    _infoRow('Completes On', completesOnStr),

                    // ── CANCEL & HISTORY BUTTONS ───────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton(
                          onPressed: canCancel
                              ? () => handleCancel(order.doc, context) // Calls your function (which now handles the dialog)
                              : null, // Disabled if date is too close
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              // COLOR LOGIC:
                              // If Cancellable:
                              //    - Direct Booking? -> Dark Grey (Professional)
                              //    - Online Payment? -> Red (Alert)
                              // If Not Cancellable: -> Light Grey (Disabled)
                              color: canCancel
                                  ? (isDirectBooking ? Colors.grey.shade700 : Colors.red)
                                  : Colors.grey.shade300,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                            elevation: 0,
                          ),
                          child: Text(
                            'CANCEL',
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              // TEXT COLOR LOGIC (Matches Border)
                              color: canCancel
                                  ? (isDirectBooking ? Colors.grey.shade700 : Colors.red)
                                  : Colors.grey,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    CancellationHistoryPage(bookingDoc: order.doc),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            side: const BorderSide(
                                color: Color(0xFF2CB4B6), width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 7),
                            elevation: 0,
                          ),
                          child: Text(
                            'CANCELLATION HISTORY',
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF2CB4B6),
                            ),
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
  }

  Widget _infoRow(String label, String value) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.poppins(
          fontSize: 13,
          color: Colors.black,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

class SubBooking {
  final QueryDocumentSnapshot doc;
  final DateTime date;
  SubBooking({required this.doc, required this.date});
}

class OrderSummary {
  final QueryDocumentSnapshot doc;
  final String shopName;
  final String Amount;
  final String fullAddress; // <-- ADD THIS
  final String shopImage;
  final List<DateTime> dates;
  final List<String> petIds;
  final List<String> petNames;
  final Map<String, List<String>> attendanceOverride;
  final String timestampStr; // 👈 your new field

  OrderSummary(this.doc)
      : shopName = (doc.data() as Map<String, dynamic>)['shopName'] as String? ?? 'Unknown Shop',
        fullAddress = (doc.data() as Map<String, dynamic>)['full_address'] as String? ?? 'Address not found',
        shopImage = (doc.data() as Map<String, dynamic>)['shop_image'] as String? ?? 'Unknown Shop',
        Amount       = (() {
          final data = doc.data() as Map<String, dynamic>;
          final cost = data?['cost_breakdown'] as Map<String, dynamic>?;
          final rawAmt = cost?['total_amount'];
          if (rawAmt is num) {
            // Format to two decimals (or use intl for currency formatting)
            return rawAmt.toDouble().toStringAsFixed(2);
          }
          return rawAmt?.toString() ?? '0.00';
        })(),

        timestampStr = (() {
          final ts = (doc.data() as Map<String, dynamic>)['timestamp'];
          if (ts is Timestamp) {
            final dt = ts.toDate();
            final date = DateFormat('dd MMM yyyy').format(dt);
            final time = DateFormat('h:mm a').format(dt); // 12-hour format with AM/PM
            return '$date ($time)';
          }
          return 'No Timestamp';
        })(),

        dates = _extractDates(doc),

        petIds = ((doc.data() as Map<String, dynamic>)['pet_id'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ?? <String>[],

        petNames = ((doc.data() as Map<String, dynamic>)['pet_name'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ?? <String>[],

        attendanceOverride = (() {
          final raw = (doc.data() as Map<String, dynamic>)['attendance_override'];
          if (raw is Map<String, dynamic>) {
            return raw.map((key, val) {
              final list = (val as List<dynamic>).map((e) => e.toString()).toList();
              return MapEntry(key, list);
            });
          }
          return <String, List<String>>{};
        })();
}

List<DateTime> _extractDates(QueryDocumentSnapshot doc) {
  final raw = (doc.data() as Map<String, dynamic>)['selectedDates'] as List<dynamic>? ?? [];
  return raw
      .map((d) {
    if (d is Timestamp) return d.toDate();
    if (d is DateTime) return d;
    return null;
  })
      .whereType<DateTime>()
      .map((dt) => DateTime(dt.year, dt.month, dt.day))
      .toList()
    ..sort();
}


class CancellationHistoryPage extends StatelessWidget {
  final DocumentSnapshot bookingDoc;

  const CancellationHistoryPage({Key? key, required this.bookingDoc}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final serviceId = bookingDoc['service_id'] as String;
    final bookingId = bookingDoc.id;
    final basePath = FirebaseFirestore.instance
        .collection('users-sp-boarding')
        .doc(serviceId)
        .collection('service_request_boarding')
        .doc(bookingId);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          title: Text('Cancellation History', style: GoogleFonts.poppins()),
          bottom: TabBar(
            indicatorColor: AppColors.primary,
            tabs: [
              Tab(
                child: Text(
                  'User History',
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
              Tab(
                child: Text(
                  'Provider History',
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildHistoryStream(basePath.collection('user_cancellation_history')),
            _buildHistoryStream(basePath.collection('sp_cancellation_history')),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryStream(CollectionReference col) {
    return StreamBuilder<QuerySnapshot>(
      stream: col.orderBy('created_at', descending: true).snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(child: Text('No history entries.', style: GoogleFonts.poppins()));
        }
        return ListView.builder(
          padding: EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final when = (data['refund_requested_at'] as Timestamp).toDate();
            final details = data['cancellation_details'] as Map<String, dynamic>;

            return Card(
              color: Colors.white,
              margin: EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: AppColors.primary),
              ),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    //_infoRow('Gross Refund', data['computed_gross']),
                    //  _infoRow('Admin Fee (${data['admin_fee_pct']}%)', data['admin_fee']),

                    // …then your loop:
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ✨ Nice title
                        Text(
                          'Cancelled Pets by Date',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),

                      ],
                    ),
                    const SizedBox(height: 5),
                    for (final entry in details.entries) ...[
                      Text(
                        DateFormat('dd MMM yyyy').format(DateTime.parse(entry.key)),
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                      Wrap(
                        spacing: 3,
                        children: (entry.value as List<dynamic>).map<Widget>((pet) {
                          return Chip(
                            label: Text(
                              pet['name'],
                              style: GoogleFonts.poppins(fontSize: 12),
                            ),
                            backgroundColor: Colors.white,
                            shape: StadiumBorder(
                              side: BorderSide(
                                color: AppColors.primary,  // your border color
                                width: 1.5,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _infoRow('Net Refund', data['net_refund']),
                    _infoRow('Refund ID', data['refund_id'] ?? 'N/A'),
                    Text('Cancelled at ${DateFormat('dd MMM yyyy, h:mm a').format(when)}',
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 5),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _infoRow(String label, dynamic value) {
    final display = (value is num) ? '₹${value.toStringAsFixed(2)}' : value.toString();
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.black),
          children: [
            TextSpan(text: '$label: ', style: TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: display),
          ],
        ),
      ),
    );
  }
}