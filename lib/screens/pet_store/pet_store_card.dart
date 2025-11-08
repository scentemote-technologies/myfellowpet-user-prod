// --- 💳 lib/widgets/pet_store_card.dart (OPTIMIZED) ---

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:myfellowpet_user/screens/pet_store/pet_store_card_data.dart';
// NOTE: Assuming PetStoreDetailPage and getStoreStatus are correctly available
import 'PetStoreDetailPage.dart';

// --- GLOBAL CONSTANTS (Defined locally for self-contained widget optimization) ---
const Color _textColor = Colors.black;
const Color _subtleTextColor = Color(0xFF6B7280);
const Color _primaryColor = Color(0xFF25ADAD);
const Color _errorColor = Color(0xFFEF4444);
const Color _successColor = Color(0xFF10B981);
const Color _cardBorderColor = Color(0xFFD1D5DB);
const Color _imageBorderColor = Colors.black;

// --- Performance Optimization: Define TextStyles as Constants ---
final TextStyle _poppins18W700Text = GoogleFonts.poppins(
  fontSize: 16,
  fontWeight: FontWeight.w700,
  color: _textColor,
);
final TextStyle _poppins13W500Subtle = GoogleFonts.poppins(
  fontSize: 12,
  color: _subtleTextColor,
  fontWeight: FontWeight.w500,
);
final TextStyle _poppins13W600 = GoogleFonts.poppins(
  fontSize: 12,
  fontWeight: FontWeight.w600,
);
final TextStyle _poppinsChip = GoogleFonts.poppins(
  fontSize: 10,
  fontWeight: FontWeight.w600,
  color: _primaryColor,
);
final TextStyle _poppins12W500Subtle = GoogleFonts.poppins(
  fontSize: 11,
  fontWeight: FontWeight.w500,
  color: _subtleTextColor,
);


class PetStoreCard extends StatelessWidget {
  final PetStoreCardData store;

  const PetStoreCard({Key? key, required this.store}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 💡 OPTIMIZATION: Calculate status and derived URLs once
    final status = getStoreStatus(store.storeHours, context);
    final bool isOpen = status['isOpen'] as bool;
    final String statusText = status['statusText'] as String;

    final String displayLogoUrl = store.logoUrl.isNotEmpty
        ? store.logoUrl
        : (store.imageUrls.isNotEmpty ? store.imageUrls.first : ''); // Fallback for the main logo

    // 💡 OPTIMIZATION: Pre-calculate status colors/styles
    final Color statusColor = isOpen ? _successColor : _errorColor;
    final IconData statusIcon = isOpen ? Icons.access_time_filled : Icons.lock_clock;

    // The entire card now uses `Card` and `InkWell` with optimized constants
    return Card(
      // OPTIMIZATION: Use const for static fields
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      elevation: 4,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        // OPTIMIZATION: Use const BorderSide
        side: const BorderSide(color: _cardBorderColor, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PetStoreDetailPage(
                serviceId: store.serviceId, // Pass the unique ID
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- HORIZONTALLY SCROLLABLE STORE IMAGES ---


            // --- MAIN CONTENT ROW (Logo + Details) ---
            // 💥 OPTIMIZATION: REMOVED EXPENSIVE IntrinsicHeight
            Row(
              crossAxisAlignment: CrossAxisAlignment.start, // Align to top for a better baseline
              children: [
                // --- LEFT SIDE: LOGO/IMAGE (Fixed Width) ---
                Container(
                  width: 110,
                  // OPTIMIZATION: Removed color for marginal gain; relying on image background

                  // OPTIMIZATION: Removed ClipRRect and kept logic simple
                  child: displayLogoUrl.isNotEmpty
                      ? Image.network(
                    displayLogoUrl,
                    fit: BoxFit.contain,
                    // Retain loading builder for user experience, but keep it simple
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return SizedBox(
                        height: 120, // Give it a placeholder size
                        child: Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                : null,
                            color: _primaryColor,
                            strokeWidth: 2,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (ctx, err, stack) => const SizedBox(
                      height: 120, // Maintain placeholder size
                      child: Center(
                        child: Icon(Icons.storefront_outlined, size: 45, color: _subtleTextColor),
                      ),
                    ),
                  )
                      : const SizedBox(
                    height: 120, // Maintain placeholder size
                    child: Center(
                      child: Icon(Icons.storefront_outlined, size: 45, color: _subtleTextColor),
                    ),
                  ),
                ),

                // --- RIGHT SIDE: DETAILS COLUMN ---
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      // OPTIMIZATION: Changed to start to avoid IntrinsicHeight cost
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        // 1. Store Name & Location (Top Block)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              store.shopName,
                              // Use constant style
                              style: _poppins18W700Text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${store.areaName}, ${store.district}',
                              // Use constant style
                              style: _poppins13W500Subtle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),

                        // 2. Status (Open/Closed)
                        Padding(
                          padding: const EdgeInsets.only(top: 3.0), // Slightly more top padding
                          child: Row(
                            children: [
                              Icon(
                                statusIcon, // Use pre-calculated icon
                                size: 15,
                                color: statusColor, // Use pre-calculated color
                              ),
                              const SizedBox(width: 4),
                              Text(
                                statusText,
                                style: _poppins13W600.copyWith(color: statusColor), // Combine constant style with dynamic color
                              ),
                            ],
                          ),
                        ),

                        // 3. Categories (Horizontal Chips)
                        // The surrounding Padding and SizedBox are fine, the change is inside the ListView.builder:

                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: SizedBox(
                            height: 32, // Slightly increased height for better visual spacing
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: store.categories.length,
                              itemBuilder: (context, index) {
                                final category = store.categories[index];
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8.0), // Increased spacing between chips
                                  child: Chip(
                                    label: Text(
                                      category,
                                      style: _poppinsChip, // Assuming this style has the teal color and bold font
                                    ),

                                    // 💡 Key Changes Below 💡

                                    // 1. Use a custom shape for the pill look
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20), // High radius for pill shape
                                    ),

                                    // 2. Set background and border
                                    backgroundColor: _primaryColor.withOpacity(0.1),
                                    side: BorderSide(color: _primaryColor, width: 1.0), // Slightly thicker border

                                    // 3. Control padding to make the chip compact
                                    // Vertical padding is small, letting the shape control the height
                                    labelPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: -2),
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        // 4. Distance (Bottom aligned)
                        // Padded to match the original layout's vertical alignment appearance
                        Padding(
                          padding: const EdgeInsets.only(top: 0.0),
                          child: Row(
                            children: [
                              const Icon(Icons.near_me_outlined, size: 14, color: _subtleTextColor),
                              const SizedBox(width: 4),
                              Text(
                                store.distanceKm.isInfinite
                                    ? 'Loading..'
                                    : '${store.distanceKm.toStringAsFixed(1)} km away',
                                style: _poppins12W500Subtle, // Use constant style
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // OPTIMIZATION: Use const Divider
            const Divider(height: 1, thickness: 1, color: _cardBorderColor, indent: 12, endIndent: 12),

            if (store.imageUrls.isNotEmpty) ...[
              SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: store.imageUrls.length,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemBuilder: (context, index) {
                    final imageUrl = store.imageUrls[index];

                    return Padding(
                      // OPTIMIZATION: Use const Padding
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _imageBorderColor, width: 1.0),
                          color: Colors.white,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: Image.network(
                            imageUrl,
                            // OPTIMIZATION: Use BoxFit.cover for better visual consistency
                            // unless you specifically need the image contained.
                            // Switching to .cover is often preferred in cards.
                            fit: BoxFit.contain,
                            errorBuilder: (ctx, err, stack) => const Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                size: 30,
                                color: _subtleTextColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}