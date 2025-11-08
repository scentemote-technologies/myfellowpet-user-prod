// lib/screens/Boarding/review_gate.dart
// ✨ FULLY OPTIMIZED CODE (Including Shop Name Fetch) ✨

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

// --- HELPER ENUM AND WIDGETS FOR MODERN UI ---

enum ReviewState {
  initial,
  ratingSubmitted,
}

/// A custom, visually appealing star rating widget.
class _StarRating extends StatelessWidget {
  final int rating;
  final ValueChanged<int> onRatingChanged;
  final double starSize;

  const _StarRating({
    required this.rating,
    required this.onRatingChanged,
    this.starSize = 36.0,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final starValue = i + 1;
        final filled = starValue <= rating;

        return GestureDetector(
          onTap: () => onRatingChanged(starValue),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 4.0),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_border_rounded,
              size: starSize,
              color: filled ? Colors.amber.shade700 : Colors.grey.shade300,
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------

/// Wrap your app (or part of it) with ReviewGate to automatically
/// prompt users to rate their completed overnight boarding orders.
class ReviewGate extends StatefulWidget {
  final Widget child;
  const ReviewGate({Key? key, required this.child}) : super(key: key);

  @override
  _ReviewGateState createState() => _ReviewGateState();
}

class _ReviewGateState extends State<ReviewGate> {
  late StreamSubscription<QuerySnapshot> _sub;
  final _pendingQueue = <DocumentSnapshot>[];
  final _handled = <String>{};
  bool _dialogShowing = false;

  static const Color primary = Color(0xFF2CB4B6);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _startListening());
  }

  void _startListening() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('orders')
        .doc('overnight_boarding')
        .collection('completed_orders')
        .where('user_reviewed', isEqualTo: 'false')
        .snapshots()
        .listen((snap) {
      for (var doc in snap.docs) {
        if (!_handled.contains(doc.id)) {
          _pendingQueue.add(doc);
          _handled.add(doc.id);
        }
      }
      _processNext();
    });
  }

  Future<void> _processNext() async {
    if (_dialogShowing || _pendingQueue.isEmpty) return;
    _dialogShowing = true;

    final doc = _pendingQueue.removeAt(0);
    await _showReviewDialog(doc);

    _dialogShowing = false;
    await _processNext();
  }

  // ✨ NEW: Function to fetch the shop name
  Future<String> _fetchShopName(String serviceId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users-sp-boarding')
          .doc(serviceId)
          .get();
      // Use shopName if available, otherwise fallback to the serviceId
      return doc.data()?['shop_name'] ?? 'Boarding Center ($serviceId)';
    } catch (e) {
      debugPrint("Error fetching shop name for $serviceId: $e");
      return 'Boarding Center'; // Safe fallback
    }
  }

  /// ✨ The modern, full-screen review dialog implementation.
  Future<void> _showReviewDialog(DocumentSnapshot orderDoc) async {
    final data = orderDoc.data()! as Map<String, dynamic>;
    final serviceId = data['service_id'] as String? ?? 'N/A';

    // 1. Fetch the shop name before showing the dialog
    final shopName = await _fetchShopName(serviceId);

    int rating = 0;
    String remarks = '';

    // ShowDialog now returns a bool: true if submitted, false otherwise.
    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setState2) {
            ReviewState reviewState = ReviewState.initial;
            // Use the last 4 characters of the ID for a cleaner display
            final orderId = orderDoc.id.substring(orderDoc.id.length - 4);

            // Determine if it's a small screen (e.g., mobile)
            final isSmallScreen = MediaQuery.of(ctx2).size.width < 600;

            return Dialog(
              insetPadding: isSmallScreen
                  ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
                  : const EdgeInsets.symmetric(horizontal: 60, vertical: 60),
              backgroundColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Scaffold(
                  backgroundColor: Colors.white,
                  appBar: AppBar(
                    backgroundColor: Colors.white,
                    elevation: 0,
                    leading: IconButton(
                      icon: const Icon(Icons.close, color: Colors.black54),
                      onPressed: () => Navigator.of(ctx).pop(false), // Ignore
                    ),
                    title: Text(
                      'Review Order #$orderId',
                      style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black87),
                    ),
                    centerTitle: true,
                  ),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Primary Prompt - ✨ UPDATED to mention the pet's experience and shop name
                        Text(
                          'How was your pet’s overnight stay at $shopName?',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: isSmallScreen ? 18 : 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Sub-Title - ✨ UPDATED to be pet-centric
                        Text(
                          "Your feedback helps us improve our service providers.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),

                        const SizedBox(height: 30),
                        // Star Rating Widget
                        _StarRating(
                          rating: rating,
                          onRatingChanged: (newRating) {
                            setState2(() {
                              rating = newRating;
                              reviewState = ReviewState.initial; // Reset state on change
                            });
                          },
                          starSize: isSmallScreen ? 44 : 52,
                        ),

                        const SizedBox(height: 30),

                        // Remarks Input Field
                        Text(
                          'Share your detailed thoughts (Optional)',
                          style: GoogleFonts.poppins(
                              fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          cursorColor: primary,
                          onChanged: (v) => remarks = v,
                          minLines: 3,
                          maxLines: 5,
                          style: GoogleFonts.poppins(
                              fontSize: 13, color: Colors.black87),
                          decoration: InputDecoration(
                            hintText: 'What did your pet like or what could be better?',
                            hintStyle: GoogleFonts.poppins(color: Colors.black38, fontSize: 13),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: primary, width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.all(14),
                          ),
                        ),

                        const SizedBox(height: 30),

                        // Submit Button (CTA)
                        SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: rating > 0
                                ? () {
                              setState2(() => reviewState = ReviewState.ratingSubmitted);
                              Future.delayed(const Duration(milliseconds: 300), () {
                                Navigator.of(ctx).pop(true);
                              });
                            }
                                : null, // Disable if rating is 0
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              disabledBackgroundColor: primary.withOpacity(0.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                            icon: reviewState == ReviewState.ratingSubmitted
                                ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                                : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                            label: Text(
                              reviewState == ReviewState.ratingSubmitted
                                  ? 'Submitting...'
                                  : 'Submit My Review',
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Skip for now button
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: Text(
                            'Maybe Later',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.black45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ) ?? false;   // default to false if dialog dismissed otherwise

    // Convert boolean to your string flags
    final status = submitted ? 'true' : 'ignored';

    // And now save
    await _saveReview(orderDoc, rating, remarks, reviewed: status);
  }


  Future<void> _saveReview(
      DocumentSnapshot orderDoc,
      int rating,
      String remarks, {
        required String reviewed,
      }) async {
    final user = FirebaseAuth.instance.currentUser!;
    final now = FieldValue.serverTimestamp();
    final orderId = orderDoc.id;
    final data = orderDoc.data()! as Map<String, dynamic>;
    final serviceId = data['service_id'] as String;

    final feedback = {
      'rating': rating,
      'remarks': remarks,
      'user_uid': user.uid,
      'timestamp': now,
      'order_id': orderId,
    };

    final db = FirebaseFirestore.instance;
    final batch = db.batch();

    // 1️⃣ SP’s completed_orders entry (merge so it never fails)
    final spRef = db
        .collection('users-sp-boarding')
        .doc(serviceId)
        .collection('completed_orders')
        .doc(orderId);
    batch.set(spRef, {
      'user_feedback': feedback,
      'user_reviewed': reviewed,
    }, SetOptions(merge: true));

    // 2️⃣ Public reviews (Only write if submitted, not if ignored)
    if (reviewed == 'true') {
      final pubRef = db
          .collection('public_review')
          .doc('service_providers')
          .collection('sps')
          .doc(serviceId)
          .collection('reviews')
          .doc();
      batch.set(pubRef, feedback);
    }

    // 3️⃣ **Always** update the user's own order doc with whatever flag we got
    final userOrderRef = db
        .collection('users')
        .doc(user.uid)
        .collection('orders')
        .doc('overnight_boarding')
        .collection('completed_orders')
        .doc(orderId);
    batch.set(userOrderRef, {
      'user_reviewed': reviewed,  // now 'true' or 'ignored'
    }, SetOptions(merge: true));

    // Commit and log
    try {
      await batch.commit();
      debugPrint('✅ Marked order $orderId as reviewed="$reviewed"');
    } catch (e, st) {
      debugPrint('❌ Failed to mark order $orderId: $e\n$st');
    }
  }


  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}