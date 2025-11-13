import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../app_colors.dart';
import '../Boarding/OpenCloseBetween.dart';
import '../Boarding/boarding_confirmation_page.dart';
// Note: You will need to import the navigation function or the helper class from HomeScreen
// Since the helper is in ActiveOrderBannerState, we'll recreate the logic here
// for independence, or pass a navigation callback. For simplicity, we'll
// use the exact complex navigation logic from the previous file.

class AllActiveOrdersPage extends StatelessWidget {
  final List<DocumentSnapshot> docs;

  const AllActiveOrdersPage({super.key, required this.docs});

  // ✨ Helper function for navigation (copied from ActiveOrderBannerState)
  Future<void> _navigateToConfirmationPage(BuildContext context, DocumentSnapshot doc) async {
    if (!context.mounted) return;
    try {
      final data = doc.data() as Map<String, dynamic>? ?? {};

      final shopName = data['shopName'] ?? '';
      final shopImage = data['shop_image'] ?? '';
      final openTime = data['openTime'] ?? '';
      final closeTime = data['closeTime'] ?? '';
      final bookingId = doc.id;
      final serviceId = data['service_id'] ?? '';

      final costBreakdown = data['cost_breakdown'] as Map<String, dynamic>? ?? {};
      final totalCost = double.tryParse(costBreakdown['total_amount']?.toString() ?? '0') ?? 0.0;
      final foodCost = double.tryParse(costBreakdown['meals_cost']?.toString() ?? '0') ?? 0.0;
      final walkingCost = double.tryParse(costBreakdown['daily_walking_cost']?.toString() ?? '0') ?? 0.0;
      final boardingCost = double.tryParse(costBreakdown['boarding_cost']?.toString() ?? '0') ?? 0.0;
      final transportCost = double.tryParse(costBreakdown['transport_cost']?.toString() ?? '0') ?? 0.0;

      final petIds = List<String>.from(data['pet_id'] ?? []);
      final petNames = List<String>.from(data['pet_name'] ?? []);
      final petImages = List<String>.from(data['pet_images'] ?? []);
      final fullAddress = data['full_address'] ?? 'Address not found';
      final spLocation = data['sp_location'] as GeoPoint? ?? const GeoPoint(0, 0);

      final mealRates = Map<String, int>.from(data['mealRates'] ?? {});
      final walkingRates =
      Map<String, int>.from(data['walkingRates'] ?? {});
      final dailyRates =
      Map<String, int>.from(data['rates_daily'] ?? {});

      // ✨ CRITICAL: Retrieve the pre-calculated breakdown from the document
      final petCostBreakdown = List<Map<String, dynamic>>.from(data['petCostBreakdown'] ?? []);

      // Fetch perDayServices subcollection
      final Map<String, dynamic> perDayServices = {};
      final petServicesSnapshot = await doc.reference.collection('pet_services').get();

      for (var petDoc in petServicesSnapshot.docs) {
        final petDocData = petDoc.data() as Map<String, dynamic>? ?? {};
        perDayServices[petDoc.id] = {
          'name': petDocData['name'] ?? 'No Name',
          'size': petDocData['size'] ?? 'Unknown Size',
          'image': petDocData['image'] ?? '',
          'dailyDetails': petDocData['dailyDetails'] ?? {},
        };
      }

      final dates = (data['selectedDates'] as List?)?.map((d) => (d as Timestamp).toDate()).toList() ?? [];
      final sortedDates = List<DateTime>.from(dates)..sort();

      if (!context.mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ConfirmationPage(
            perDayServices: perDayServices,
            petIds: petIds,
            foodCost: foodCost,
            walkingCost: walkingCost,
            transportCost: transportCost,
            boarding_rate: boardingCost,
            mealRates: mealRates,
            walkingRates: walkingRates,
            fullAddress: fullAddress,
            sp_location: spLocation,
            shopName: shopName,
            fromSummary: false,
            shopImage: shopImage,
            selectedDates: dates,
            totalCost: totalCost,
            petNames: petNames,
            openTime: openTime,
            closeTime: closeTime,
            bookingId: bookingId,
            buildOpenHoursWidget: buildOpenHoursWidget(openTime, closeTime, dates),
            sortedDates: sortedDates,
            petImages: petImages,
            serviceId: serviceId, dailyRates: dailyRates,
            // ✨ PASS THE NEW BREAKDOWN HERE
            petCostBreakdown: petCostBreakdown,
          ),
        ),
      );
    } catch (e, s) {
      print('❌❌❌ AN ERROR OCCURRED ❌❌❌');
      print('Error navigating to confirmation page: $e');
      print('Stack trace: $s');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load order details. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('All Active Orders', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      backgroundColor: Colors.white,
      body: docs.isEmpty
          ? Center(
        child: Text(
          'No active orders found.',
          style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600]),
        ),
      )
          : ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        itemCount: docs.length,
        separatorBuilder: (_, __) => const Divider(
          color: Colors.transparent, // Use transparent for cleaner spacing
          thickness: 0,
          height: 16,
        ),
        itemBuilder: (context, index) => _buildOrderTile(context, docs[index]),
      ),
    );
  }

  Widget _buildOrderTile(BuildContext context, DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final shopName = data['shopName'] ?? '';
    final shopImageUrl = data['shop_image'] ?? '';
    final totalCostValue = data.containsKey('cost_breakdown.total_amount')
        ? data['cost_breakdown']['total_amount']
        : '0';

    final totalCost = totalCostValue is num
        ? totalCostValue.toDouble()
        : (totalCostValue is String ? double.tryParse(totalCostValue) ?? 0.0 : 0.0);
    final petNames = List<String>.from(data['pet_name'] ?? []);

    // Display Date Range Logic (Corrected to use sorted dates)
    final dates = (data['selectedDates'] as List?)?.map((d) => (d as Timestamp).toDate()).toList() ?? [];
    final sortedDates = List<DateTime>.from(dates)..sort();
    String displayDateStr;
    String dateLabel = 'Date:';

    if (sortedDates.isEmpty) {
      displayDateStr = 'No dates selected';
    } else if (sortedDates.length == 1) {
      dateLabel = 'Date:';
      displayDateStr = DateFormat('dd MMM, yyyy').format(sortedDates.first);
    } else {
      dateLabel = 'Dates:';
      final firstDate = DateFormat('dd MMM').format(sortedDates.first);
      final lastDate = DateFormat('dd MMM, yyyy').format(sortedDates.last);
      displayDateStr = '$firstDate - $lastDate';
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _navigateToConfirmationPage(context, doc),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // --- Row 1: Shop Info & Pet Names ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: shopImageUrl.isNotEmpty
                        ? CachedNetworkImage(
                      imageUrl: shopImageUrl,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => const SizedBox(
                        width: 50,
                        height: 50,
                        child: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
                      ),
                      errorWidget: (_, __, ___) => const Icon(Icons.storefront, size: 30, color: Colors.grey),
                    )
                        : Container(
                      width: 50,
                      height: 50,
                      color: Colors.grey[300],
                      child: const Icon(Icons.storefront, size: 30, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shopName,
                          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.black),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          petNames.join(', '),
                          style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: AppColors.primary, size: 24),
                ],
              ),

              const Divider(height: 20),

              // --- Row 2: Dates and Cost ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dateLabel,
                        style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        displayDateStr,
                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.black),
                      ),
                    ],
                  ),

                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}