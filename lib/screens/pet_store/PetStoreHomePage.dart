// --- 🏠 lib/screens/pet_store_homepage.dart ---
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myfellowpet_user/screens/pet_store/pet_header_media.dart';
import 'package:myfellowpet_user/screens/pet_store/pet_store_card.dart';
import 'package:myfellowpet_user/screens/pet_store/pet_store_card_data.dart';
import 'package:myfellowpet_user/screens/pet_store/pet_store_search_bar.dart';
import 'package:shimmer/shimmer.dart';
import 'package:google_fonts/google_fonts.dart';

import '../AppBars/Accounts.dart';
import '../AppBars/greeting_service.dart';
import '../Boarding/HeaderMedia.dart';
import '../Search Bars/live_searchbar.dart';

// Assuming you have PetStoreCardData and PetStoreCard available
// import '../models/pet_store_card_data.dart';
// import '../widgets/pet_store_card.dart';

class PetStoreHomePage extends StatefulWidget {
  const PetStoreHomePage({Key? key}) : super(key: key);

  @override
  _PetStoreHomePageState createState() => _PetStoreHomePageState();
}

class _PetStoreHomePageState extends State<PetStoreHomePage> {
  Position? _currentPosition;
  bool _isLoadingLocation = true;
  Stream<QuerySnapshot>? _storeStream;
  String _searchQuery = ''; // The state variable for the search query

  // This is the new method to handle search query changes from the PetSearchBar
  void _handleSearch(String query) {
    setState(() {
      _searchQuery = query;
    });
  }
  final FocusNode _searchFocusNode = FocusNode();


  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
    _storeStream = FirebaseFirestore.instance.collection('users-sp-store').snapshots();
  }

  Future<void> _fetchCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if(mounted) setState(() => _isLoadingLocation = false);
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if(mounted) setState(() => _isLoadingLocation = false);
        return;
      }
    }

    try {
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
      if(mounted) {
        setState(() {
          _currentPosition = position;
          _isLoadingLocation = false;
        });
      }
    } catch (e) {
      if(mounted) setState(() => _isLoadingLocation = false);
    }
  }

  // Helper to calculate distance (in km) between user and store location
  double _calculateDistance(GeoPoint storeLocation) {
    if (_currentPosition == null) return double.infinity;

    final distanceInMeters = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      storeLocation.latitude,
      storeLocation.longitude,
    );
    return distanceInMeters / 1000.0;
  }
  Widget _buildHeader(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.45;
    final paddingTop = MediaQuery.of(context).padding.top;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background video or image
          PetHeaderMedia(),
          // Semi-transparent overlay
          Container(color: Colors.transparent),
          // Foreground content
          Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              right: 20,
              bottom: 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Greeting only, no avatar here
               /* const GreetingHeader(
                ),*/

                const SizedBox(height: 10),

                // Pet search bar
                // ✅ Corrected: Pass the _searchFocusNode to LiveSearchBar
                PetStoreLiveSearchBar(
                  onSearch: _handleSearch,
                  focusNode: _searchFocusNode,
                ),
                const SizedBox(height: 7),
              ],
            ),
          ),

          // Account icon with its own top position
          Positioned(
            top: MediaQuery.of(context).padding.top + 12, // independent top padding
            right: 20,
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AccountsPage()),
              ),
              child: const CircleAvatar(
                radius: 22,
                backgroundColor: Colors.transparent,
                child: Icon(
                  Icons.account_circle,
                  color: Colors.white,
                  size: 50,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF25ADAD);
    const Color subtleTextColor = Colors.grey;

    return Scaffold(
      backgroundColor: Colors.white,

      body:Column(
        children: [
          _buildHeader(context),
          Expanded(
              child:  StreamBuilder<QuerySnapshot>(
                stream: _storeStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return _buildShimmerLoading(); // Show shimmer while loading
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error loading stores: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(child: Text('No pet stores registered yet.', style: GoogleFonts.poppins(color: subtleTextColor)));
                  }

                  // 1. Process data & calculate distances
                  final stores = snapshot.data!.docs.map((doc) {
                    final data = PetStoreCardData.fromMap(doc.data() as Map<String, dynamic>, doc.id);
                    data.distanceKm = _calculateDistance(data.location);
                    return data;
                  }).toList();

                  // 2. Sort stores by distance (closest first)
                  stores.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

                  return ListView.builder(
                    padding: EdgeInsets.zero, // <--- Add this line!
                    itemCount: stores.length,
                    itemBuilder: (context, index) {
                      return PetStoreCard(store: stores[index]);
                    },
                  );
                },
              ),
          )
        ],
      )
    );
  }

  // Minimal Shimmer Placeholder
  Widget _buildShimmerLoading() {
    return ListView.builder(
      itemCount: 4,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            height: 160,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      },
    );
  }
}