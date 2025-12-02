import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:carousel_slider/carousel_slider.dart';
import '../../app_colors.dart';
import '../AppBars/Accounts.dart';

class HeaderImageCarousel extends StatefulWidget {
  const HeaderImageCarousel({Key? key}) : super(key: key);

  @override
  State<HeaderImageCarousel> createState() => _HeaderImageCarouselState();
}

class _HeaderImageCarouselState extends State<HeaderImageCarousel> {
  bool _isLoading = true;
  List<String> _urls = [];
  String _userName = "Guest";

  @override
  void initState() {
    super.initState();
    _fetchUserName();
    _loadImagesFromFirestore();
  }

  Future<void> _fetchUserName() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      if (doc.exists) {
        final name = doc.data()?['name'];
        if (name != null && name.toString().isNotEmpty) {
          setState(() => _userName = name);
        }
      }
    } catch (e) {
      print("⚠️ Failed to fetch user name: $e");
    }
  }

  Future<void> _loadImagesFromFirestore() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('photos_and_videos')
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final urls = List<String>.from(data['boarding_home_screen_slides'] ?? []);
        setState(() {
          _urls = urls;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print("⚠️ Error fetching images: $e");
      setState(() => _isLoading = false);
    }
  }

  Widget _buildHeader(BuildContext context) {
    final hour = DateTime.now().hour;

    String greeting = "Good Morning";

    if (hour >= 12 && hour < 17) {
      greeting = "Good Afternoon";
    } else if (hour >= 17 && hour < 19) {
      greeting = "Good Evening";
    } else if (hour >= 19 && hour <= 23) {
      greeting = "Hello";
    } else {
      greeting = "Good Morning"; // After midnight (0-11 AM)
    }


    final firstName = _userName.split(' ').first;
    final displayName =
    firstName.length > 12 ? '${firstName.substring(0, 12)}...' : firstName;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/applogofinalhomescreen.png',
                  height: 40,
                  width: 40,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.black.withOpacity(0.8),
                        height: 1.2,
                      ),
                    ),
                    Text(
                      "$displayName 👋",
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.black,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AccountsPage()),
            ),
            child: const CircleAvatar(
              radius: 26,
              backgroundColor: Colors.white,
              child: Icon(
                Icons.account_circle,
                color: AppColors.black,
                size: 48,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context),
        const SizedBox(height: 10),

          if (_urls.isEmpty)
            Container(
              height: 135,
              color: Colors.grey.shade200,
              alignment: Alignment.center,
              child: const Text('No images found'),
            )
          else
            CarouselSlider.builder(
              itemCount: _urls.length,
              itemBuilder: (context, index, realIndex) {
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 5.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedNetworkImage(
                      imageUrl: _urls[index],
                      fit: BoxFit.contain,
                      placeholder: (_, __) =>
                          Container(color: Colors.grey.shade200),
                      errorWidget: (_, __, ___) =>
                      const Icon(Icons.error, color: Colors.red),
                    ),
                  ),
                );
              },
              options: CarouselOptions(
                height: 135,
                autoPlay: true,
                enlargeCenterPage: true,
                viewportFraction: 0.94,
                aspectRatio: 16 / 9,
                autoPlayInterval: const Duration(seconds: 4),
              ),
            ),
      ],
    );
  }
}
