// --- 📱 lib/screens/pet_store_detail_page.dart (FINAL CORRECTED & OPTIMIZED CODE) ---

import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:myfellowpet_user/screens/pet_store/pet_store_card_data.dart';
import 'package:myfellowpet_user/screens/pet_store/pet_store_detail_data.dart';
// Note: Ensure these model imports are correct in your project structure
import 'package:shimmer/shimmer.dart';
import 'package:toastification/toastification.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

// --- Global Constants ---
const Color primaryColor = Color(0xFF25ADAD);
const Color imageBorderColor = Colors.black; // Specific border for the image
const Color accentColor = Color(0xFFF67B0D);
const Color subtleTextColor = Color(0xFF6B7280);
const Color textColor = Colors.black;
const Color cardBorderColor = Color(0xFFE5E7EB);
const Color errorColor = Color(0xFFEF4444);
const Color successColor = Color(0xFF10B981);
const double bottomSafePadding = 110.0;
// Increased image height
const double _imageHeight = 335.0;
// Recalculated height for the floating header card (Logo row + Chips row + Padding/Dividers)
const double _headerCardHeight = 220.0;
const double _headerCardMargin = 16.0;

// --- Performance Optimization: Define GoogleFonts TextStyles as Constants ---
final TextStyle _poppins16W600 = GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: textColor);
final TextStyle _poppins14Regular = GoogleFonts.poppins(fontSize: 14, color: textColor);
final TextStyle _poppins11W500Subtle = GoogleFonts.poppins(fontSize: 11, color: subtleTextColor, fontWeight: FontWeight.w500);
final TextStyle _poppins18W700Text = GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: textColor);
final TextStyle _poppins12Subtle = GoogleFonts.poppins(fontSize: 12, color: subtleTextColor);
final TextStyle _poppins13TextHeight = GoogleFonts.poppins(fontSize: 13, color: textColor, height: 1.5);
final TextStyle _poppinsAppBar = GoogleFonts.poppins(fontWeight: FontWeight.w600);
final TextStyle _poppinsButton = GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16);
final TextStyle _poppinsModalHeader = GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: textColor);
final TextStyle _poppinsChip = GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: primaryColor);


// TOP-LEVEL FUNCTION FOR POLICY LINK
void launchPolicyUrl(String url, BuildContext context) async {
  if (url.isNotEmpty) {
    Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      toastification.show(
        context: context,
        title: const Text('Error'),
        description: Text('Could not open the policy URL: $url'),
        type: ToastificationType.error,
        style: ToastificationStyle.minimal,
        autoCloseDuration: const Duration(seconds: 4),
      );
    }
  } else {
    toastification.show(
      context: context,
      title: const Text('Missing URL'),
      description: const Text('The partner policy document URL is currently missing.'),
      type: ToastificationType.warning,
      style: ToastificationStyle.minimal,
      autoCloseDuration: const Duration(seconds: 4),
    );
  }
}


class PetStoreDetailPage extends StatelessWidget {
  final String serviceId;

  const PetStoreDetailPage({Key? key, required this.serviceId}) : super(key: key);

  // --- Optimization: Define Icon Maps as static const ---
  static const Map<String, IconData> productIconMap = {
    'Pet Food': Icons.lunch_dining_outlined, 'Treats': Icons.cookie_outlined, 'Toys': Icons.sports_esports_outlined,
    'Clothing': Icons.checkroom_outlined, 'Accessories': Icons.backpack_outlined, 'Grooming': Icons.content_cut_outlined,
  };
  static const Map<String, IconData> paymentIconMap = {
    'Credit Card and Debit Card': Icons.credit_card_outlined, 'UPI Payments': Icons.qr_code_2_outlined, 'Cash': Icons.money_outlined,
  };


  // --- Widget Builders ---

  Widget _buildProductCategoryChips(List<String> categories) {
    if (categories.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 0, right: 16),
            child: SizedBox(
              height: 38, // Fixed height for the horizontally scrollable row
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final category = categories[index];
                  final icon = PetStoreDetailPage.productIconMap[category] ?? Icons.category_outlined;
                  return Padding(
                    padding: EdgeInsets.only(right: index == categories.length - 1 ? 0 : 8),
                    child: Chip(
                      avatar: Icon(icon, size: 18, color: primaryColor),
                      label: Text(category, style: _poppinsChip),
                      backgroundColor: primaryColor.withOpacity(0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(color: primaryColor.withOpacity(0.3), width: 1),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    ),
                  );
                },
              ),
            ),
          ),

        ],
      ),
    );
  }

  // OPTIMIZATION: Use constant TextStyles for performance.
  Widget _buildCompactIconList(String title, List<String> items, {required Map<String, IconData> iconMap, bool isChecklist = false}) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 0, left: 16, right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Use constant style
          Text(title, style: _poppins16W600),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cardBorderColor, width: 1)),
            child: Wrap(
              spacing: 16, runSpacing: 12,
              children: items.map((item) {
                final icon = iconMap[item] ?? (isChecklist ? Icons.check_circle : Icons.category_outlined);
                final useCheckIcon = isChecklist;

                return SizedBox(
                  width: 140,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Use const Icons where possible
                      Icon(useCheckIcon ? Icons.check_circle : icon, size: 18, color: useCheckIcon ? successColor : subtleTextColor),
                      const SizedBox(width: 8),
                      // Use constant style
                      Expanded(child: Text(item, style: _poppins14Regular, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }


  // OPTIMIZATION: Use constant TextStyles and avoid redundant Map lookups.
  Widget _buildStoreHoursSection(Map<String, Map<String, String>> hours, BuildContext context) {
    const daysOfWeek = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    final int todayIndex = DateTime.now().weekday % 7; // 0=Sun, 1=Mon... 6=Sat

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          // Use constant style
          Text('Operational Hours', style: _poppins16W600),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5), border: Border.all(color: cardBorderColor, width: 1)),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(daysOfWeek.length, (index) {
                final day = daysOfWeek[index];
                final isToday = index == todayIndex;
                final dayHours = hours[day];

                const String closedText = 'Closed';
                final openTime = dayHours?['open'] ?? closedText;
                final closeTime = dayHours?['close'] ?? '';
                final status = (openTime != closedText && openTime.isNotEmpty) ? '$openTime - $closeTime' : closedText;
                final isClosed = (openTime == closedText || openTime.isEmpty);

                // Optimization: Define TextStyles inside the loop only for variations
                final dayTextStyle = GoogleFonts.poppins(fontSize: 13, fontWeight: isToday ? FontWeight.w700 : FontWeight.w500, color: isToday ? primaryColor : textColor);
                final statusTextStyle = GoogleFonts.poppins(fontSize: 13, fontWeight: isToday ? FontWeight.w700 : FontWeight.w500, color: isClosed ? errorColor : textColor);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.schedule_outlined, size: 14, color: isToday ? primaryColor : subtleTextColor),
                          const SizedBox(width: 6),
                          Text(
                            isToday ? '$day (Today)' : day,
                            style: dayTextStyle,
                          ),
                        ],
                      ),
                      Text(
                        status,
                        style: statusTextStyle,
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // --- OPTIMIZED _buildCompactSection WIDGET 💥 ---
  // OPTIMIZATION: Use constant TextStyles and const widgets where possible.
  Widget _buildCompactSectionSP({
    required String title,
    required IconData icon,
    required String value,
    bool isLink = false,
    VoidCallback? onTap,
  }) {
    final TextStyle valueStyle = GoogleFonts.poppins(
      fontSize: 14,
      color: isLink ? accentColor : textColor,
      decoration: isLink ? TextDecoration.underline : TextDecoration.none,
    );

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 16),

        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Use const Icon and primaryColor
            Icon(icon, size: 18, color: primaryColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Use constant style
                  Text(title, style: _poppins11W500Subtle),
                  Text(
                    value,
                    style: valueStyle, // Use pre-calculated dynamic style
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Use const Icon and primaryColor
            if (isLink) const Icon(Icons.chevron_right, color: primaryColor, size: 18),
          ],
        ),
      ),
    );
  }



  // --- OPTIMIZED _buildCompactSection WIDGET 💥 ---
  // OPTIMIZATION: Use constant TextStyles and const widgets where possible.
  Widget _buildCompactSection({
    required IconData icon,
    required String value,
    bool isLink = false,
    VoidCallback? onTap,
  }) {
    final TextStyle valueStyle = GoogleFonts.poppins(
      fontSize: 14,
      color: isLink ? accentColor : textColor,
      decoration: isLink ? TextDecoration.underline : TextDecoration.none,
    );

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 16),

        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Use const Icon and primaryColor
            Icon(icon, size: 18, color: primaryColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: valueStyle, // Use pre-calculated dynamic style
                  ),
                ],
              ),
            ),
            // Use const Icon and primaryColor
            if (isLink) const Icon(Icons.chevron_right, color: primaryColor, size: 18),
          ],
        ),
      ),
    );
  }


  // OPTIMIZATION: Use constant TextStyles.
  Widget _buildCompactHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      // Use constant style
      child: Text(title, style: _poppins16W600),
    );
  }

  // --- NEW HELPER FUNCTION TO LAUNCH MAPS ---
  void _launchMaps(double lat, double lng) async {
    // In a real app, this should use the lat/lng. Using a placeholder as in original
    final String googleMapsUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    final Uri uri = Uri.parse(googleMapsUrl);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // Fallback for context outside of build
      // print('Could not launch map URL: $googleMapsUrl');
    }
  }

  // --- NEW: Full-Screen Image Gallery Modal ---
  void _showImageGallery(BuildContext context, List<String> imageUrls) {
    if (imageUrls.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) {
        return GalleryView(imageUrls: imageUrls);
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users-sp-store').doc(serviceId).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) { return const Scaffold(body: Center(child: CircularProgressIndicator())); }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Scaffold(body: Center(child: Text('Service ID not found.')));
        }

        final data = PetStoreDetailData.fromFirestore(snapshot.data!.data() as Map<String, dynamic>, serviceId);
        final currentStatus = getStoreStatus(data.storeHours, context);

        final VoidCallback mapLaunchAction = () => _launchMaps(data.locationGeopoint.latitude, data.locationGeopoint.longitude);

        return Scaffold(
          backgroundColor: Colors.white,

          body: Stack(
            children: [
              // --- SCROLLABLE CONTENT ---
              SingleChildScrollView(
                // Push content down past the floating header card
                // The `top` padding equals the space required for the image + the space below the image taken up by the bottom half of the floating card.
                padding: EdgeInsets.only(top: 80, bottom: bottomSafePadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                   Container(
                              padding: const EdgeInsets.only(top: 16, bottom: 0),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 10,
                                    offset: Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 🏪 Store Info Row
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Logo
                                        Container(
                                          width: 60,
                                          height: 60,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: imageBorderColor, width: 1.0),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(10),
                                            child: data.logoUrl.isNotEmpty
                                                ? Image.network(data.logoUrl, fit: BoxFit.contain)
                                                : const Icon(Icons.storefront, size: 30, color: subtleTextColor),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Name + Area + Hours
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(data.shopName, style: _poppins18W700Text),
                                              const SizedBox(height: 2),
                                              Text('${data.areaName}, ${data.district}', style: _poppins12Subtle),
                                              const SizedBox(height: 6),
                                              InkWell(
                                                onTap: () => _showHoursModal(context, data),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: currentStatus['isOpen']
                                                        ? successColor.withOpacity(0.1)
                                                        : errorColor.withOpacity(0.1),
                                                    borderRadius: BorderRadius.circular(20),
                                                    border: Border.all(
                                                      color: currentStatus['isOpen'] ? successColor : errorColor,
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        currentStatus['isOpen']
                                                            ? Icons.access_time_filled
                                                            : Icons.lock_clock,
                                                        size: 14,
                                                        color: currentStatus['isOpen'] ? successColor : errorColor,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        currentStatus['statusText'],
                                                        style: GoogleFonts.poppins(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w700,
                                                          color: currentStatus['isOpen']
                                                              ? successColor
                                                              : errorColor,
                                                        ),
                                                      ),
                                                      const Icon(Icons.arrow_drop_down,
                                                          size: 14, color: subtleTextColor),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Divider
                                  const Padding(
                                    padding: EdgeInsets.only(top: 12.0),
                                    child: Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: cardBorderColor,
                                      indent: 16,
                                      endIndent: 16,
                                    ),
                                  ),

                                  // Chips
                                  _buildProductCategoryChips(data.categories),
                                ],
                              ),
                            ),

                    PetStoreProductsList(
                      serviceId: data.serviceId,
                      shopName: data.shopName, // Pass shopName for AllProductsPage context
                    ),
                    SizedBox(height: 8),

                    // --- PLACEHOLDER FOR THE FLOATING CARD (Crucial for correct vertical alignment) ---

                    // 1. MODES OF PAYMENT (This will appear correctly under the floating card)
                    _buildCompactIconList('Modes of Payment', data.paymentModes, iconMap: PetStoreDetailPage.paymentIconMap, isChecklist: true),
                    SizedBox(height: 8),

                    // 3. DELIVERY & LOGISTICS
                    _buildCompactHeader('Delivery Info'),
                    _buildCompactSection(
                      icon: Icons.local_shipping_outlined,
                      value: 'Free delivery over ₹${data.minOrderValue}',
                    ),
                    _buildCompactSection(
                      icon: Icons.delivery_dining_outlined,
                      value: '₹${data.flatDeliveryFee}/km delivery charge',
                    ),
                    _buildCompactSection(
                      icon: Icons.map_outlined,
                      value: 'Covers up to ${data.deliveryRadiusKm} km',
                    ),
                    _buildCompactSection(
                      icon: Icons.timer_outlined,
                      value: 'Average delivery time: ${data.fulfillmentTimeMin} min',
                    ),
                    SizedBox(height: 8),

// ✅ REPLACEMENT: Use the new widget that returns a valid Widget
                    ImageGridWidget(
                      imageUrls: data.imageUrls,
                      onTap: () => _showImageGallery(context, data.imageUrls),
                    ),
                    SizedBox(height: 8),

                    _buildCompactHeader('Return/Exchange Policy'),


                    // 4. RETURN POLICY
                    _buildCompactSection(icon: Icons.assignment_return_outlined, value: '${data.returnWindowValue} ${data.returnWindowUnit}'),
                    _buildCompactSection(icon: Icons.rule_outlined, value: data.returnPolicyText),
                    SizedBox(height: 8),


                    // 5. ABOUT US
                    _buildCompactHeader('About ${data.shopName}'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                          data.description.isEmpty ? 'No detailed description available for this store.' : data.description,
                          style: _poppins13TextHeight
                      ),
                    ),
                    SizedBox(height: 8),


                    // 6. SUPPORT & POLICIES
                    _buildCompactHeader('Support & Policies'),
                    _buildCompactSectionSP(icon: Icons.support_agent_outlined, title: 'Customer Support Email', value: data.supportEmail, isLink: true, onTap: () => launchUrl(Uri.parse('mailto:${data.supportEmail}'))),
                    _buildCompactSectionSP(icon: Icons.article_outlined, title: 'Partner Terms & Conditions', value: 'View Full Policy Document', isLink: true, onTap: () => launchPolicyUrl(data.partnerPolicyUrl, context)),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              // 2. ⏪ NEW FLOATING BACK BUTTON TWEAK ⏪
              Positioned(
                top: MediaQuery.of(context).padding.top, // Use safe area + padding
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

              // --- IMAGE CAROUSEL BACKGROUND (Fixed at top, outside SingleChildScrollView) ---




              // --- BOTTOM FIXED BUTTONS ---
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: bottomSafePadding - 10,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2)),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      // Directions Button
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: mapLaunchAction,
                          icon: const Icon(Icons.location_pin, size: 20, color: Colors.white),
                          label: Text('Directions', style: _poppinsButton),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            minimumSize: const Size(0, 50),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Contact Store Button
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final String phoneNumber = data.phoneNumber.isNotEmpty ? data.phoneNumber : '+919999999999';
                            launchUrl(
                              Uri.parse('whatsapp://send?phone=$phoneNumber&text='),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          icon: const Icon(Icons.phone, size: 20, color: Colors.white),
                          label: Text('Contact', style: _poppinsButton),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            minimumSize: const Size(0, 50),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

// OPTIMIZATION: Use constant TextStyles.
  void _showHoursModal(BuildContext context, PetStoreDetailData data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      // OPTIMIZATION: Use const
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                // Use constant style
                child: Text('Full Operational Hours', style: _poppinsModalHeader),
              ),
              _buildStoreHoursSection(data.storeHours, context),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}

// --- NEW WIDGET: Full-Screen Gallery View ---
class GalleryView extends StatelessWidget {
  final List<String> imageUrls;

  const GalleryView({Key? key, required this.imageUrls}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            itemCount: imageUrls.length,
            itemBuilder: (context, index) {
              final imageUrl = imageUrls[index];
              return Center(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                            : null,
                        color: Colors.white,
                      ),
                    );
                  },
                ),
              );
            },
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 10,
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

// --- PRODUCT DATA MODEL ---
class RetailerProduct {
  final String productId;
  final String name;
  final String? imageUrl;
  final String price; // Stored as String
  final String stock; // Stored as String

  // Categories for context/search (optional, but good for linking to catalog)
  final String primaryCategory;
  final String secondaryCategory;
  final String tertiaryCategory;

  RetailerProduct({
    required this.productId,
    required this.name,
    this.imageUrl,
    required this.price,
    required this.stock,
    required this.primaryCategory,
    required this.secondaryCategory,
    required this.tertiaryCategory,
  });

  factory RetailerProduct.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // ASSUMPTION FOR OPTIMIZATION: The `retailer_product_files` document has the core display data.
    return RetailerProduct(
      productId: doc.id,
      name: data['name'] ?? 'Unknown Product',
      imageUrl: data['imageUrl'] ?? null,
      price: data['price']?.toString() ?? 'N/A', // Price needs to be added by the pet store later in the web app
      stock: data['stock']?.toString() ?? '0',
      primaryCategory: data['primaryCategory'] ?? '',
      secondaryCategory: data['secondaryCategory'] ?? '',
      tertiaryCategory: data['tertiaryCategory'] ?? '',
    );
  }
}

// --- SHARED WIDGETS AND LOGIC FOR PRODUCTS ---

Widget _buildSmallChip({required String text, required Color color, required bool isFilled}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: isFilled ? color : Colors.white,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(
        color: color,
        width: 1,
      ),
    ),
    child: Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 9, // Very small font for chips
        fontWeight: FontWeight.w600,
        color: isFilled ? Colors.white : color,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
}

// --- REUSABLE PRODUCT CARD WIDGET ---
class ProductCard extends StatelessWidget {
  final RetailerProduct product;
  final VoidCallback onAddToCart;

  const ProductCard({Key? key, required this.product, required this.onAddToCart}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final hasStock = int.tryParse(product.stock) != null && int.parse(product.stock) > 0;
    final int stockQuantity = int.tryParse(product.stock) ?? 0;
    final bool isLowStock = stockQuantity > 0 && stockQuantity <= 10;

    String stockQuantityDisplay;
    Color stockColor;
    FontWeight stockFontWeight;

    if (isLowStock) {
      stockQuantityDisplay = 'Only $stockQuantity left';
      stockColor = errorColor;
      stockFontWeight = FontWeight.w600;
    } else if (stockQuantity > 0) {
      stockQuantityDisplay = '$stockQuantity';
      stockColor = successColor;
      stockFontWeight = FontWeight.w500;
    } else {
      stockQuantityDisplay = 'Out of Stock';
      stockColor = errorColor;
      stockFontWeight = FontWeight.w600;
    }

    return Container(
      width: 125, // For horizontal list, this defines the width
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ProductDetailPage(product: product,                       onAddToCart: () => _showDeliveryNoticeDialog(context),
              ),
            ),
          );
        },        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Image Placeholder/Container (Fixed Height)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Container(
                height: 95,
                width: double.infinity,
                color: Colors.grey.shade100,
                child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                    ? CachedNetworkImage(
                  imageUrl: product.imageUrl!,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => Shimmer.fromColors(
                    baseColor: Colors.grey.shade300,
                    highlightColor: Colors.grey.shade100,
                    child: Container(color: Colors.white),
                  ),
                  errorWidget: (context, url, error) => const Icon(
                      Icons.image_not_supported_outlined, size: 40, color: subtleTextColor),
                )
                    : const Icon(Icons.image_not_supported_outlined, size: 40, color: subtleTextColor),
              ),
            ),

            // 2. Details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Chips for Categories
                    Row(
                      children: [
                        if (product.primaryCategory.isNotEmpty)
                          _buildSmallChip(
                            text: product.primaryCategory,
                            color: primaryColor,
                            isFilled: true,
                          ),
                        const SizedBox(width: 4),
                        if (product.tertiaryCategory.isNotEmpty)
                          _buildSmallChip(
                            text: product.tertiaryCategory,
                            color: accentColor,
                            isFilled: false,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Name (Max 2 lines)
                    Text(
                      product.name,
                      style: GoogleFonts.poppins(fontSize: 12.5, color: textColor, fontWeight: FontWeight.w500),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),

                    // Price (Max 1 line)
                    Text(
                      '₹${product.price}',
                      style: GoogleFonts.poppins(fontSize: 14, color: textColor, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),

                    // Stock Status
                    stockQuantity > 0
                        ? RichText(
                      text: TextSpan(
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: stockFontWeight, color: textColor),
                        children: [
                          if (stockQuantity > 10)
                            TextSpan(
                              text: 'Stock: ',
                              style: GoogleFonts.poppins(color: textColor, fontWeight: FontWeight.w500),
                            ),
                          TextSpan(
                            text: stockQuantityDisplay,
                            style: GoogleFonts.poppins(color: stockColor, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                        : Text(
                      stockQuantityDisplay,
                      style: GoogleFonts.poppins(fontSize: 12, fontWeight: stockFontWeight, color: stockColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // Spacer to push the ADD button to the bottom
                    const Spacer(),

                    // ADD Button (Fixed to Bottom)
                    Center(
                      child: Container(
                        width: double.infinity,
                        height: 30,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: hasStock ? primaryColor : Colors.grey,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: InkWell(
                          onTap: hasStock ? onAddToCart : null, // Use the provided callback
                          child: Center(
                            child: Text(
                              hasStock ? 'ADD' : 'Out of Stock',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// --- FULL PRODUCTS PAGE (GRID VIEW) ---
class AllProductsPage extends StatelessWidget {
  final String serviceId;
  final String storeName;

  const AllProductsPage({Key? key, required this.serviceId, required this.storeName}) : super(key: key);



  @override
  Widget build(BuildContext context) {
    final Query<Map<String, dynamic>> productsQuery = FirebaseFirestore.instance
        .collection('users-sp-store')
        .doc(serviceId)
        .collection('retailer_product_files')
        .where('verified', isEqualTo: true)
        .orderBy('name'); // Ordering for better list presentation

    return Scaffold(
      appBar: AppBar(
        title: Text(
          storeName,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: productsQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: primaryColor));
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error loading products: ${snapshot.error}'));
          }

          final products = (snapshot.data?.docs ?? [])
              .map((doc) => RetailerProduct.fromFirestore(doc))
              .toList();

          if (products.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Text(
                  'No verified products available from this store.',
                  style: GoogleFonts.poppins(fontStyle: FontStyle.italic, color: subtleTextColor),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, // Two cards per row
              childAspectRatio: 0.6, // Aspect ratio to fit the card content (must be adjusted)
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return ProductCard(
                product: product,
                onAddToCart: () => _showDeliveryNoticeDialog(context),
              );
            },
          );
        },
      ),
    );
  }
}


// --- HORIZONTAL PRODUCT LIST WIDGET ---
class PetStoreProductsList extends StatelessWidget {
  final String serviceId;
  final String shopName; // Added to pass shop name for navigation

  const PetStoreProductsList({
    Key? key,
    required this.serviceId,
    required this.shopName,
  }) : super(key: key);

  // --- Design Constants (Match Detail Page) ---
  static const Color primaryColor = Color(0xFF25ADAD);
  static const Color subtleTextColor = Color(0xFF6B7280);
  static const Color errorColor = Color(0xFFEF4444);


  void _showDeliveryNoticeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          backgroundColor: Colors.white,
          contentPadding: const EdgeInsets.fromLTRB(25, 25, 25, 15),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, color: primaryColor, size: 50),
              const SizedBox(height: 16),
              Text(
                "Delivery Coming Soon!",
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black, // Use textColor constant if available
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "We're working on bringing delivery to your doorstep shortly. Stay tuned!",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 14, color: subtleTextColor),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'OK',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
            ),
          ],
        );
      },
    );
  }


  // --- NEW WIDGET: Show All Products Button ---
  Widget _buildShowAllButton(BuildContext context, int productCount) {
    // Only show if there are more than 3 products to scroll through horizontally
    if (productCount <= 2) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: InkWell(
        onTap: () {
          // Navigate to the full products page
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => AllProductsPage(
              serviceId: serviceId,
              storeName: shopName, // Use the passed shopName
            ),
          ));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: primaryColor.withOpacity(0.3), width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Show All $productCount Products',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_ios, size: 14, color: primaryColor),
            ],
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    // Query without a limit to get the true total count
    final Query<Map<String, dynamic>> productsQuery = FirebaseFirestore.instance
        .collection('users-sp-store')
        .doc(serviceId)
        .collection('retailer_product_files')
        .where('verified', isEqualTo: true); // Only show verified products

    return StreamBuilder<QuerySnapshot>(
      stream: productsQuery.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: primaryColor));
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('Error loading products.', style: GoogleFonts.poppins(color: errorColor)),
          );
        }

        final productDocs = snapshot.data?.docs ?? [];
        final products = productDocs.map((doc) => RetailerProduct.fromFirestore(doc)).toList();

        // Count all verified products for the button text
        final totalProductCount = products.length;
        // Limit the horizontal list view to a reasonable number (e.g., 10 products)
        final productsToShow = products.take(10).toList();


        if (products.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'No verified products available from this store yet.',
              style: GoogleFonts.poppins(fontStyle: FontStyle.italic, color: subtleTextColor),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text(
                'Top Selling Products',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),

            // Horizontal List
            SizedBox(
              height: 255, // Fixed height to contain the cards
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: productsToShow.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: EdgeInsets.only(right: index == productsToShow.length - 1 ? 0 : 12),
                    child: ProductCard(
                      product: productsToShow[index],
                      onAddToCart: () => _showDeliveryNoticeDialog(context),
                    ),
                  );
                },
              ),
            ),

            // --- NEW: Show All Products Button (Conditional Display) ---
            _buildShowAllButton(context, totalProductCount),
          ],
        );
      },
    );
  }
}

// --- NEW WIDGET: Image Grid Placeholder (To resolve the void error) ---
class ImageGridWidget extends StatelessWidget {
  final List<String> imageUrls;
  final VoidCallback onTap;

  const ImageGridWidget({Key? key, required this.imageUrls, required this.onTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (imageUrls.isEmpty) return const SizedBox.shrink();

    // Use the first 4 images for a compact grid view
    final displayUrls = imageUrls.take(4).toList();
    final remainingCount = imageUrls.length - 4;

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 0, left: 16, right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Store Images', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black)),
          const SizedBox(height: 8),
          // Use GestureDetector to handle the tap for the gallery modal
          GestureDetector(
            onTap: onTap,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(), // Important: Prevents inner scrolling
              shrinkWrap: true,
              itemCount: displayUrls.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.5, // Wider than tall
              ),
              itemBuilder: (context, index) {
                final url = displayUrls[index];
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        url,
                        fit: BoxFit.contain,
                        errorBuilder: (c, e, s) => Container(color: Colors.grey.shade300),
                      ),
                      // Overlay for the "View More" count
                      if (index == 3 && remainingCount > 0)
                        Container(
                          color: Colors.black.withOpacity(0.5),
                          alignment: Alignment.center,
                          child: Text(
                            '+$remainingCount\nView All',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


final TextStyle _poppins14W500Subtle = GoogleFonts.poppins(fontSize: 14, color: subtleTextColor, fontWeight: FontWeight.w500);


class ProductDetailPage extends StatelessWidget {
  final RetailerProduct product;
  final VoidCallback onAddToCart;


  const ProductDetailPage({Key? key, required this.product, required this.onAddToCart}) : super(key: key);

  // --- New Helper: Category Chip Widget ---
  Widget _buildCategoryChip(String category, {required Color color, required IconData icon}) {
    if (category.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(
        avatar: Icon(icon, size: 18, color: color),
        label: Text(category, style: _poppinsChip.copyWith(color: color)),
        backgroundColor: color.withOpacity(0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: color.withOpacity(0.3), width: 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      ),
    );
  }

  // --- New Helper: Stock Status Row ---
  Widget _buildStockStatusRow() {
    final int stockQuantity = int.tryParse(product.stock) ?? 0;
    final bool hasStock = stockQuantity > 0;
    final bool isLowStock = stockQuantity > 0 && stockQuantity <= 10;

    final IconData icon = hasStock ? Icons.inventory_2_outlined : Icons.remove_shopping_cart;
    final Color color = hasStock ? (isLowStock ? accentColor : successColor) : errorColor;
    final String text = hasStock
        ? (isLowStock ? 'Only $stockQuantity left!' : 'In Stock')
        : 'Out of Stock';

    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canPurchase = int.tryParse(product.stock) != 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(product.name, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), // Add padding for bottom button
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🖼 Product Image (Large View)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 320, // Slightly taller image
                    width: double.infinity,
                    color: Colors.grey.shade100,
                    child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                        ? CachedNetworkImage(
                      imageUrl: product.imageUrl!,
                      fit: BoxFit.contain, // Changed from cover to contain for better product visibility
                      placeholder: (context, url) => Shimmer.fromColors(
                          baseColor: Colors.grey.shade300,
                          highlightColor: Colors.grey.shade100,
                          child: Container(color: Colors.white)),
                      errorWidget: (context, url, error) => const Center(
                        child: Icon(Icons.image_not_supported_outlined, size: 80, color: subtleTextColor),
                      ),
                    )
                        : const Center(
                      child: Icon(Icons.image_not_supported_outlined, size: 80, color: subtleTextColor),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            style: GoogleFonts.poppins(
                              fontSize: 18, // slightly smaller for better fit
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                            maxLines: 5, // limit lines
                            overflow: TextOverflow.ellipsis, // show "..." if too long
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₹${product.price}',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: textColor.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Stock status
                    _buildStockStatusRow(),
                  ],
                ),
                const SizedBox(height: 16),

                // 📑 Categories as Chips
                Text('Product Categories', style: _poppins16W600),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildCategoryChip(product.primaryCategory, color: primaryColor, icon: Icons.pets_outlined),
                    _buildCategoryChip(product.secondaryCategory, color: accentColor, icon: Icons.category_outlined),
                    _buildCategoryChip(product.tertiaryCategory, color: subtleTextColor, icon: Icons.label_outline),
                  ],
                ),
                const SizedBox(height: 20),


                const SizedBox(height: 30),
              ],
            ),
          ),

          // --- BOTTOM FIXED ACTION BUTTON ---
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2)),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: onAddToCart,
                icon: const Icon(Icons.shopping_bag_outlined, color: Colors.white),
                label: Text(canPurchase ? 'Add to Cart' : 'Out of Stock', style: _poppinsButton.copyWith(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: canPurchase ? primaryColor : Colors.grey,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  minimumSize: const Size(double.infinity, 55),
                  elevation: 5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _showDeliveryNoticeDialog(BuildContext context) {
  // Reusing the same dialog logic as PetStoreProductsList
  showDialog(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.fromLTRB(25, 25, 25, 15),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, color: primaryColor, size: 50),
            const SizedBox(height: 16),
            Text(
              "Delivery Coming Soon!",
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "We're working on bringing delivery to your doorstep shortly. Stay tuned!",
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 14, color: subtleTextColor),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'OK',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: primaryColor,
              ),
            ),
          ),
        ],
      );
    },
  );
}