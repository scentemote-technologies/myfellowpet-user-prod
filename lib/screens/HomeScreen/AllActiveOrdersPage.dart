import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../app_colors.dart';
import '../Boarding/OpenCloseBetween.dart';
import '../Boarding/boarding_confirmation_page.dart';

class AllActiveOrdersPage extends StatelessWidget {
  final List<DocumentSnapshot> docs;

  const AllActiveOrdersPage({super.key, required this.docs});

  // 🔁 Navigation (same logic as before)
  Future<void> _navigateToConfirmationPage(
      BuildContext context, DocumentSnapshot doc) async {
    if (!context.mounted) return;
    try {
      final data = doc.data() as Map<String, dynamic>? ?? {};

      final shopName = data['shopName'] ?? '';
      final shopImage = data['shop_image'] ?? '';
      final openTime = data['openTime'] ?? '';
      final closeTime = data['closeTime'] ?? '';
      final bookingId = doc.id;
      final serviceId = data['service_id'] ?? '';

      final costBreakdown =
          data['cost_breakdown'] as Map<String, dynamic>? ?? {};
      final totalCost = double.tryParse(
          costBreakdown['total_amount']?.toString() ?? '0') ??
          0.0;
      final foodCost = double.tryParse(
          costBreakdown['meals_cost']?.toString() ?? '0') ??
          0.0;
      final walkingCost = double.tryParse(
          costBreakdown['daily_walking_cost']?.toString() ?? '0') ??
          0.0;
      final boardingCost = double.tryParse(
          costBreakdown['boarding_cost']?.toString() ?? '0') ??
          0.0;
      final transportCost = double.tryParse(
          costBreakdown['transport_cost']?.toString() ?? '0') ??
          0.0;

      final petIds = List<String>.from(data['pet_id'] ?? []);
      final petNames = List<String>.from(data['pet_name'] ?? []);
      final petImages = List<String>.from(data['pet_images'] ?? []);
      final fullAddress = data['full_address'] ?? 'Address not found';
      final spLocation =
          data['sp_location'] as GeoPoint? ?? const GeoPoint(0, 0);

      final mealRates = Map<String, int>.from(data['mealRates'] ?? {});
      final walkingRates =
      Map<String, int>.from(data['walkingRates'] ?? {});
      final dailyRates =
      Map<String, int>.from(data['rates_daily'] ?? {});

      // pre-calculated breakdown
      final petCostBreakdown =
      List<Map<String, dynamic>>.from(data['petCostBreakdown'] ?? []);

      final Map<String, dynamic> perDayServices = {};
      final petServicesSnapshot =
      await doc.reference.collection('pet_services').get();

      for (var petDoc in petServicesSnapshot.docs) {
        final petDocData =
            petDoc.data() as Map<String, dynamic>? ?? {};
        perDayServices[petDoc.id] = {
          'name': petDocData['name'] ?? 'No Name',
          'size': petDocData['size'] ?? 'Unknown Size',
          'image': petDocData['image'] ?? '',
          'dailyDetails': petDocData['dailyDetails'] ?? {},
        };
      }

      final dates = (data['selectedDates'] as List?)
          ?.map((d) => (d as Timestamp).toDate())
          .toList() ??
          [];
      final sortedDates = List<DateTime>.from(dates)..sort();

      if (!context.mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ConfirmationPage(
            gstRegistered: data['gstRegistered'] ?? false,
            checkoutEnabled: data['checkoutEnabled'] ?? false,
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
            buildOpenHoursWidget:
            buildOpenHoursWidget(openTime, closeTime, dates),
            sortedDates: sortedDates,
            petImages: petImages,
            serviceId: serviceId,
            dailyRates: dailyRates,
            petCostBreakdown: petCostBreakdown,
          ),
        ),
      );
    } catch (e, s) {
      // ignore: avoid_print
      print('❌ Error navigating to confirmation page: $e');
      // ignore: avoid_print
      print(s);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
            Text('Could not load order details. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = const Color(0xFFF5F7FB);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Active bookings',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ),
      body: docs.isEmpty
          ? _buildEmptyState(context)
          : ListView.separated(
        padding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        itemCount: docs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, index) =>
            _buildOrderTile(context, docs[index]),
      ),
    );
  }

  // 🌤 Empty state
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.pets_rounded,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              "No active bookings yet",
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Once you book a stay for your pet, you'll see all your active bookings here.",
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13.5,
                height: 1.4,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🧾 Each order card
  Widget _buildOrderTile(BuildContext context, DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final shopName = data['shopName'] ?? '';
    final shopImageUrl = data['shop_image'] ?? '';
    final petNames = List<String>.from(data['pet_name'] ?? []);

    // Safely get total cost from nested cost_breakdown
    final costBreakdown =
        data['cost_breakdown'] as Map<String, dynamic>? ?? {};
    final totalCostRaw = costBreakdown['total_amount'];
    final totalCost = totalCostRaw is num
        ? totalCostRaw.toDouble()
        : (totalCostRaw is String
        ? double.tryParse(totalCostRaw) ?? 0.0
        : 0.0);

    // Date range
    final dates = (data['selectedDates'] as List?)
        ?.map((d) => (d as Timestamp).toDate())
        .toList() ??
        [];
    final sortedDates = List<DateTime>.from(dates)..sort();

    String displayDateStr;
    String dateLabel = 'Dates';

    if (sortedDates.isEmpty) {
      displayDateStr = 'No dates selected';
    } else if (sortedDates.length == 1) {
      dateLabel = 'Date';
      displayDateStr = DateFormat('dd MMM, yyyy').format(sortedDates.first);
    } else {
      final firstDate = DateFormat('dd MMM').format(sortedDates.first);
      final lastDate =
      DateFormat('dd MMM, yyyy').format(sortedDates.last);
      displayDateStr = '$firstDate • $lastDate';
    }

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _navigateToConfirmationPage(context, doc),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(
          children: [
            // 🔹 Row 1: Image + names + arrow
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildShopImage(shopImageUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTitleAndSubtitle(shopName, petNames),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.primary, size: 24),
              ],
            ),

            const SizedBox(height: 10),
            Divider(
              height: 18,
              thickness: 0.7,
              color: Colors.grey.shade200,
            ),

            // 🔹 Row 2: Date & Amount
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Dates
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateLabel,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      displayDateStr,
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShopImage(String shopImageUrl) {
    const double size = 52;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: shopImageUrl.isNotEmpty
          ? CachedNetworkImage(
        imageUrl: shopImageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => const SizedBox(
          width: size,
          height: size,
          child: Center(
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2,
            ),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          width: size,
          height: size,
          color: Colors.grey.shade200,
          child: const Icon(
            Icons.storefront_rounded,
            size: 28,
            color: Colors.grey,
          ),
        ),
      )
          : Container(
        width: size,
        height: size,
        color: Colors.grey.shade200,
        child: const Icon(
          Icons.storefront_rounded,
          size: 28,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildTitleAndSubtitle(
      String shopName, List<String> petNames) {
    final subtitle =
    petNames.isEmpty ? 'Pet details not found' : petNames.join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          shopName,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.black,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
