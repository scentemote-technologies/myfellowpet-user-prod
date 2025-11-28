import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Cancellation Invoice Page - Refined for a professional, bill-like appearance.
/// - Uses a strong, modern layout with clear typography.
/// - Employs the primary teal color (0xFF2CB4B6) for emphasis on final amounts.
/// - Ensures robust responsiveness and no pixel overflow.
class CancellationInvoicePage extends StatelessWidget {
  // Primary color from the original code
  static const Color primaryTeal = Color(0xFF2CB4B6);

  // NOTE: Assuming input values align with the desired calculation:
  // Gross = 1.00, GST = 0.18, AdminFee = 0.03, Net Refund = 1.15
  final double computedGross; // excl GST
  final double cancelledGst;
  final double adminFeeFinal;
  final double netRefundWithGst;
  final int adminPct;
  final Map<DateTime, List<String>> cancellations;
  final Map<String, String> petNamesMap;
  final Map<DateTime, double> perDayTotals; // This must now hold the INCLUSIVE total (e.g., 1.18)
  final Map<DateTime, Map<String,String>> refundReasons;

  // per-pet detail maps
  final Map<DateTime, Map<String, double>> perPetRefunds; // rupees (should be the GROSS base, e.g., 1.00)
  final Map<DateTime, Map<String, int>> perPetPercents; // percent as int
  final Map<DateTime, Map<String, String>> perPetReasons; // short text like "> 48 hrs"

  const CancellationInvoicePage({
    super.key,
    required this.computedGross,
    required this.cancelledGst,
    required this.adminFeeFinal,
    required this.netRefundWithGst,
    required this.adminPct,
    required this.cancellations,
    required this.petNamesMap,
    required this.perDayTotals,
    this.perPetRefunds = const {},
    this.perPetPercents = const {},
    this.perPetReasons = const {},
    required this.refundReasons,
  });

  // --- UI Helpers ---

  // Standard label style for invoice items
  Widget _label(String t, {FontWeight weight = FontWeight.w400, double size = 13.0, Color color = Colors.black87}) =>
      Text(t, style: GoogleFonts.poppins(fontSize: size, color: color, fontWeight: weight), overflow: TextOverflow.ellipsis);

  // Standard value style for invoice items
  Widget _value(String t, {bool strong = false, Color? color, double size = 14.0}) =>
      Text(t, style: GoogleFonts.poppins(fontSize: size, fontWeight: strong ? FontWeight.w700 : FontWeight.w600, color: color ?? Colors.black87));

  String _formatCurrency(double v) {
    return NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(v);
  }

  // Pill for refund explanation - slightly refined look
  Widget _refundExplanationPill(int? pct, String? reason) {
    if (pct == null && reason == null) return const SizedBox.shrink();

    String text;
    if (pct != null && reason != null) {
      text = reason;
    } else if (pct != null) {
      text = '$pct% Refund Applied';
    } else if (reason != null) {
      text = reason;
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: primaryTeal.withOpacity(0.05), // Light teal background
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: primaryTeal.withOpacity(0.2), width: 0.8),
      ),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: primaryTeal,
        ),
        softWrap: true,
      ),
    );
  }

  // Row for a single line item (Label and Value)
  Widget _buildLineItem({
    required String label,
    required double amount,
    bool isTotal = false,
    Color? amountColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: _label(
              label,
              weight: isTotal ? FontWeight.w600 : FontWeight.w500,
              size: isTotal ? 14.0 : 13.0,
            ),
          ),
          const SizedBox(width: 16),
          _value(
            _formatCurrency(amount),
            strong: isTotal,
            color: amountColor,
            size: isTotal ? 16.0 : 14.0,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dates = perDayTotals.keys.toList()..sort((a, b) => a.compareTo(b));
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    // --- TEMPORARY FIX: Calculating amounts based on YOUR logic (1.00 base, 18% GST, 3% Admin)
    final double actualComputedGross = perPetRefunds.values.fold(0.0, (prev, map) => prev + map.values.fold(0.0, (p, v) => p + v));
    final double actualCancelledGst = actualComputedGross * 0.18;
    final double subtotalInclusive = actualComputedGross + actualCancelledGst;
    final double actualAdminFeeFinal = actualComputedGross * (adminPct / 100);
    final double actualNetRefundWithGst = subtotalInclusive - actualAdminFeeFinal;
    // --- END TEMPORARY FIX ---

    return Scaffold(
      backgroundColor: Colors.grey.shade100, // Light background for the overall page
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: Text('Cancellation Invoice', style: GoogleFonts.poppins(color: Colors.black87, fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (ctx, constraints) {
          const double maxInvoiceWidth = 800.0;
          final double horizontalPadding = constraints.maxWidth > 850 ? 40.0 : 16.0;

          return Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: maxInvoiceWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [


                    // --- Final Totals / Summary Box ---
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200, width: 1),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 3, offset: const Offset(0, 1))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _label('REFUND DETAILS', weight: FontWeight.w700, size: 15, color: Colors.blueGrey.shade700),
                          const Divider(height: 20, thickness: 1.5, color: Colors.grey),


                          if (dates.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20.0),
                              child: Center(child: Text('No cancelled days found.', style: GoogleFonts.poppins(color: Colors.grey.shade600))),
                            ),

                          for (final day in dates) ...[
                            // --- Daily Header (Date) ---
                            Padding(
                              padding: const EdgeInsets.only(top: 10, bottom: 10),
                              child: Text(
                                DateFormat('EEEE, dd MMMM yyyy').format(day),
                                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.black87),
                              ),
                            ),

                            // --- Refund Explanation/Pill (This logic needs to be inside the pet loop,
                            //     or the values should be derived from the day's first pet or if the refund percent
                            //     is the same for all pets on that day. Assuming uniform day-wise refund for now.)
                            //     Original code was referencing an undefined 'petId' here.

                            // **FIX 1: Logic Correction**
                            // Assuming the refund percent/reason is the same for ALL pets on that day.
                            // We need to pick a pet ID to get the pct/reason. Let's use the first one if available.
                            if (cancellations[day] != null && cancellations[day]!.isNotEmpty) ...[
                              Builder(
                                  builder: (context) {
                                    final firstPetId = cancellations[day]!.first; // Get an ID to look up the shared percentage/reason
                                    final pct = perPetPercents[day]?[firstPetId];
                                    final reason = perPetReasons[day]?[firstPetId];

                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        Padding(
                                          padding: const EdgeInsets.only(left: 15.0),
                                          child: _refundExplanationPill(pct, reason),
                                        ),
                                      ],
                                    );
                                  }
                              ),

                              // --- Pet-specific details for this day ---
                              for (final petId in cancellations[day]!) ...[
                                Builder(builder: (ctx2) {
                                  final petName = petNamesMap[petId] ?? 'Unknown Pet';
                                  final petRefundGross = perPetRefunds[day]?[petId];
                                  final firstPetId = cancellations[day]!.first; // Get an ID to look up the shared percentage/reason
                                  final pct = perPetPercents[day]?[firstPetId];
                                  final reason = perPetReasons[day]?[firstPetId];


                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '  - $petName',
                                                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              // Removed the unnecessary SizedBox(height: 4) and padding that wrapped the pct/reason logic
                                            ],
                                          ),
                                        ),

                                        const SizedBox(width: 16),

                                        // Amount column
                                        if (petRefundGross != null)
                                          Text(
                                            "${currency.format(petRefundGross)} * $pct% = ${currency.format(petRefundGross)}",
                                            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14),
                                          )
                                        else
                                          Text('NA', style: GoogleFonts.poppins(color: Colors.grey.shade600)),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ],

                            const SizedBox(height: 24),
                          ],

                        ],
                      ),
                    ),
                    const SizedBox(height: 15),

                    // --- Final Totals / Summary Box ---
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200, width: 1),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 3, offset: const Offset(0, 1))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [


                          _label('CANCELLATION SUMMARY', weight: FontWeight.w700, size: 15, color: Colors.blueGrey.shade700),
                          const Divider(height: 20, thickness: 1.5, color: Colors.grey),

                          _buildLineItem(
                            label: 'Gross Refund (Base Price)',
                            amount: actualComputedGross,
                          ),
                          _buildLineItem(
                            label: 'Cancellation Fee (${adminPct}%)',
                            amount: -actualAdminFeeFinal, // Display as a negative adjustment
                            amountColor: Colors.red.shade700,
                          ),
                          _buildLineItem(
                            label: 'GST Returned (18% of Gross)',
                            amount: actualCancelledGst,
                            amountColor: Colors.green.shade700,
                          ),



                          const SizedBox(height: 15),
                          const Divider(height: 2, thickness: 2, color: Colors.black87),
                          const SizedBox(height: 15),

                          // NET REFUND PAYABLE (Highlighted)
                          Row(
                            children: [
                              Text('NET REFUND', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w900)),
                              const Spacer(),
                              Text(
                                _formatCurrency(actualNetRefundWithGst),
                                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w900, color: primaryTeal),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),


                    const SizedBox(height: 30),

                    // --- Actions ---
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                side: BorderSide(color: Colors.grey.shade400, width: 1.5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                foregroundColor: Colors.black87,
                              ),
                              child: Text('Review & Edit', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13.5)),
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => Navigator.of(context).pop(true),
                              icon: const Icon(Icons.check_circle_outline, size: 16, color: Colors.white,),
                              label: Text('Confirm Refund', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13.5)),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                backgroundColor: primaryTeal,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                elevation: 3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}