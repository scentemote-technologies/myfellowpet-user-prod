import 'dart:async';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// -----------------------------------------------------------------------------
// App Imports (Adjust paths if necessary)
// -----------------------------------------------------------------------------
// Assume these imports lead to the correct files based on the project structure
import '../../app_colors.dart';
import '../../main.dart'; // Assumed to contain HomeWithTabsState
import '../../preloaders/TileImageProvider.dart';
import '../../preloaders/petpreloaders.dart'; // Assumed to contain Pet and PetService
import '../../services/vetprofile.dart';
import '../AppBars/Accounts.dart';
import '../AppBars/AllPetsPage.dart';
import '../AppBars/greeting_service.dart';
import '../Authentication/PhoneSignInPage.dart';
import '../Boarding/OpenCloseBetween.dart';
import '../Boarding/boarding_confirmation_page.dart';
import '../Boarding/boarding_homepage.dart';
import '../Pets/AddPetPage.dart';
import '../Search Bars/search_bar.dart';
import '../pet_store/PetStoreHomePage.dart';
import 'AllActiveOrdersPage.dart';

// -----------------------------------------------------------------------------
// Data Model for Services
// -----------------------------------------------------------------------------
Widget _buildHeader(BuildContext context, {String? name}) {
  final hour = DateTime.now().hour;
  String greeting = "Good Morning";
  if (hour >= 12 && hour < 17) {
    greeting = "Good Afternoon";
  } else if (hour >= 17) {
    greeting = "Good Evening";
  }

  // Extract first word of the name and trim to 12 characters max
  final fullName = (name ?? 'Guest').trim();
  final firstWord = fullName.split(' ').first;
  final truncatedName =
  firstWord.length > 12 ? '${firstWord.substring(0, 12)}...' : firstWord;
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(20, 50, 20, 0),
    decoration: const BoxDecoration(

      borderRadius: BorderRadius.vertical(
        bottom: Radius.circular(28),
      ),

    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 🌅 Greeting Section (Compact with PNG icon)
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 🖼️ Time-based icon
              Image.asset(
                'assets/applogofinalhomescreen.png',
                height: 40, // 👈 match the greeting column height
                width: 40,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 8),

              // 📝 Greeting + Name
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greeting,
                    style: GoogleFonts.poppins(
                      fontSize: 14, // 👈 smaller like Swiggy
                      fontWeight: FontWeight.w500,
                      color: AppColors.black.withOpacity(0.8),
                      height: 1.2,
                    ),
                  ),
                  Text(
                    "$truncatedName 👋",
                    style: GoogleFonts.poppins(
                      fontSize: 16, // 👈 slightly larger for name
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


        // 👤 Account Icon
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
class Service {
  final String title;
  final String imagePath;
  final Widget destination;
  final bool isComingSoon;

  const Service({
    required this.title,
    required this.imagePath,
    required this.destination,
    this.isComingSoon = false,
  });
}

// -----------------------------------------------------------------------------
// Home Screen Widget
// -----------------------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Service> _services = [];
  String _userName = "Guest";

  @override
  void initState() {
    super.initState();
    _fetchUserName(); // ✅ Fetch user name once on load
  }


  void _goToBoardingTab() {
    final parent = context.findAncestorStateOfType<HomeWithTabsState>();
    parent?.goToTab(1);
  }

  void _goToStoreTab() {
    final parent = context.findAncestorStateOfType<HomeWithTabsState>();
    parent?.goToTab(2);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initTilesIfNeeded();
  }

  Future<void> _initTilesIfNeeded() async {
    if (_services.isEmpty && mounted) {
      try {
        final provider = Provider.of<TileImageProvider>(context, listen: false);

        // if provider has nothing, reload it
        if (provider.tileImages.isEmpty) {
          debugPrint('🧩 TileImageProvider empty, reloading...');
          await provider.loadTileImages();
        }

        final tileImages = provider.tileImages;

        if (tileImages.isNotEmpty) {
          setState(() {
            _services = [
              Service(
                title: 'Boarding',
                imagePath: tileImages['boarding'] ?? '',
                destination: BoardingHomepage(),
              ),
              Service(
                title: 'Pet Store',
                imagePath: tileImages['store'] ?? '',
                destination: const PetStoreHomePage(),
              ),
              Service(
                title: 'Pet Walks',
                imagePath: tileImages['pet_walking'] ?? '',
                destination: const ComingSoonServicePage(serviceName: 'Pet Walks'),
                isComingSoon: true,
              ),
              Service(
                title: 'Pet Care',
                imagePath: tileImages['vet'] ?? '',
                destination: const ComingSoonServicePage(serviceName: 'Pet Care'),
                isComingSoon: true,
              ),
              Service(
                title: 'Grooming',
                imagePath: tileImages['grooming'] ?? '',
                destination: const ComingSoonServicePage(serviceName: 'Grooming'),
                isComingSoon: true,
              ),
              Service(
                title: 'Farewell Services',
                imagePath: tileImages['farewell_services'] ?? '',
                destination: const ComingSoonServicePage(serviceName: 'Farewell'),
                isComingSoon: true,
              ),
            ];
          });
        }
      } catch (e, st) {
        FirebaseCrashlytics.instance.recordError(e, st);
      }
    }
  }


  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(context, name: _userName)),
              _buildPetAvatarRow(),
              _buildImageCarousel(),
              _buildServicesGrid(),
              _buildFooter(),
              const SliverToBoxAdapter(child: SizedBox(height: 180)),
            ],
          ),
          // --- OPTIMIZATION: Extracted to a separate StatefulWidget ---
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ActiveOrderBanner(), // Use the new dedicated widget
          ),
          // -----------------------------------------------------------
        ],
      ),
    );
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
        final data = doc.data();
        if (data != null && (data['name'] ?? '').toString().isNotEmpty) {
          setState(() {
            _userName = data['name'];
          });
        }
      }
    } catch (e) {
      print("⚠️ Failed to fetch user name: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // SERVICES GRID
  // ---------------------------------------------------------------------------
  SliverPadding _buildServicesGrid() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 7),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.0,
        ),
        delegate: SliverChildBuilderDelegate(
              (context, index) {

            final service = _services[index];
            return _buildServiceTile(service);
          },
          childCount: _services.length,
        ),
      ),
    );
  }

  Widget _buildServiceTile(Service service) {
    var fallback = service.imagePath;
    final imageUrl =
    service.imagePath.isNotEmpty ? service.imagePath : fallback;

    return GestureDetector(
      onTap: () {
        if (service.isComingSoon) {
          Navigator.push(
              context, MaterialPageRoute(builder: (_) => service.destination));
        } else {
          if (service.title == 'Boarding') {
            _goToBoardingTab();
          } else if (service.title == 'Pet Store') {
            _goToStoreTab();
          } else {
            Navigator.push(
                context, MaterialPageRoute(builder: (_) => service.destination));
          }
        }
      },
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              color: Colors.grey.shade200,
              child: const Center(
                  child:
                  Icon(Icons.pets_outlined, size: 30, color: Colors.grey)),
            ),
            errorWidget: (context, url, error) => const Center(
              child: Icon(Icons.image_not_supported_outlined,
                  color: Colors.grey),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // IMAGE CAROUSEL
  // ---------------------------------------------------------------------------
  SliverToBoxAdapter _buildImageCarousel() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('settings')
              .doc('photos_and_videos')
              .snapshots(),
          builder: (ctx, snap) {
            if (!snap.hasData) {
              return const SizedBox(
                height: 0,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              );
            }

            // 👇 Read the list from home_screen_slides instead of flex
            final urls = List<String>.from(snap.data?.data()?['home_screen_slides'] ?? []);
            if (urls.isEmpty) return const SizedBox.shrink();

            return CarouselSlider.builder(
              itemCount: urls.length,
              itemBuilder: (context, index, realIndex) {
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 5.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedNetworkImage(
                      imageUrl: urls[index],
                      fit: BoxFit.contain,
                      placeholder: (_, __) => Container(color: Colors.grey.shade200),
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
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FOOTER
  // ---------------------------------------------------------------------------
  SliverToBoxAdapter _buildFooter() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'with love,',
              style: GoogleFonts.pacifico(
                  fontSize: 24, color: Colors.grey.shade600),
            ),
            Text(
              'MyFellowPet',
              style: GoogleFonts.pacifico(
                  fontSize: 32, color: Colors.grey.shade800),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PET ROWS
  // ---------------------------------------------------------------------------
  SliverToBoxAdapter _buildPetAvatarRow() {
    return SliverToBoxAdapter(
      child: StreamBuilder<List<Pet>>(
        stream: PetService.instance.watchMyPets(context),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Padding(
              padding:
              const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Container(
                  height: 70,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12))),
            );
          }
          final pets = snapshot.data!;
          return pets.isEmpty ? _buildAddPetButton() : _buildPetList(pets);
        },
      ),
    );
  }

  Widget _buildAddPetButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
      child: Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
              ]),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Add your first pet!',
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.black)),
                GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => AddPetPage())),
                    child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                            color: AppColors.accentColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 3,
                                  offset: Offset(0, 1))
                            ]),
                        child: const Icon(Icons.add,
                            size: 20, color: Colors.white)))
              ])),
    );
  }

  Widget _buildPetList(List<Pet> pets) {
    const int maxShown = 5;
    final displayList = pets.take(maxShown).toList();
    final extraCount = pets.length > maxShown ? pets.length - maxShown : 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Container(
          height: 70,
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border(
                  bottom: BorderSide(
                      color: AppColors.primary.withOpacity(0.5), width: 3.0),
                  right: BorderSide(
                      color: AppColors.primary.withOpacity(0.5), width: 3.0)),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
              ]),
          child: Row(children: [
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Text('Your\nPets',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.black,
                        height: 1.2))),
            const VerticalDivider(
                color: Colors.black26, thickness: 1, indent: 10, endIndent: 10),
            const SizedBox(width: 6),
            Expanded(
                child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: displayList.length + (extraCount > 0 ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == displayList.length)
                        return _buildExtraPetsIndicator(extraCount);
                      final pet = displayList[index];
                      return _buildPetAvatar(pet);
                    }))
          ])),
    );
  }

  Widget _buildPetAvatar(Pet pet) {
    return Tooltip(
      message: pet.name,
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AllPetsPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.only(right: 10.0),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryColor,
                  ),
                  child: Center(
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: ClipOval(
                        child: Image(
                          image: CachedNetworkImageProvider(
                            pet.imageUrl.isNotEmpty
                                ? pet.imageUrl
                                : 'https://via.placeholder.com/150',
                          ),
                          fit: BoxFit.contain, // 👈 This makes sure it fits nicely
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  pet.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildExtraPetsIndicator(int count) {
    return GestureDetector(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => AllPetsPage())),
        child: Padding(
            padding: const EdgeInsets.only(right: 10.0),
            child:
            Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey.shade200,
                      border: Border.all(
                          color: Colors.grey.shade400, width: 1.8)),
                  child: Center(
                      child: Text('+$count',
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.black)))),
              const SizedBox(height: 3),
              Text('More',
                  style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700))
            ])));
  }

  final _auth = FirebaseAuth.instance;
  Future<void> _signOut() async {
    await _auth.signOut();
    if (mounted) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => PhoneAuthPage()));
    }
  }
}

// ---------------------------------------------------------------------------
// DEDICATED ACTIVE ORDER BANNER WIDGET (Optimization for rebuilds)
// ---------------------------------------------------------------------------

class ActiveOrderBanner extends StatefulWidget {
  const ActiveOrderBanner({Key? key}) : super(key: key);

  @override
  _ActiveOrderBannerState createState() => _ActiveOrderBannerState();
}

class _ActiveOrderBannerState extends State<ActiveOrderBanner> with SingleTickerProviderStateMixin {
  bool _isBannerCollapsed = false;
  bool _bannerHasBeenShown = false;
  Timer? _bannerCollapseTimer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _bannerCollapseTimer?.cancel();
    if (_pulseController.isAnimating) _pulseController.stop();
    _pulseController.dispose();
    super.dispose();
  }

  bool isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collectionGroup('service_request_boarding')
          .where('user_id', isEqualTo: uid)
          .where('order_status', isEqualTo: 'confirmed')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          // --- Optimization: Only call setState if the state is NOT already collapsed ---
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && (_bannerHasBeenShown || !_isBannerCollapsed)) {
              _bannerCollapseTimer?.cancel();
              setState(() {
                _bannerHasBeenShown = false;
                _isBannerCollapsed = true;
              });
            }
          });
          return const SizedBox.shrink();
        }

        final today = DateTime.now();
        final ongoingDocs = snapshot.data!.docs.where((doc) {
          final dynamic rawDates = doc['selectedDates'];
          if (rawDates is List) {
            final dates =
            rawDates.whereType<Timestamp>().map((ts) => ts.toDate());
            // Check if today is between (inclusive) the min and max selected date
            if (dates.isNotEmpty) {
              final minDate = dates.reduce((a, b) => a.isBefore(b) ? a : b);
              final maxDate = dates.reduce((a, b) => a.isAfter(b) ? a : b);

              final todayNormalized = DateTime(today.year, today.month, today.day);
              final minDateNormalized = DateTime(minDate.year, minDate.month, minDate.day);
              final maxDateNormalized = DateTime(maxDate.year, maxDate.month, maxDate.day);

              return todayNormalized.isAtSameMomentAs(minDateNormalized) ||
                  todayNormalized.isAfter(minDateNormalized) &&
                      (todayNormalized.isBefore(maxDateNormalized) || todayNormalized.isAtSameMomentAs(maxDateNormalized));
            }
          }
          return false;
        }).toList();

        if (ongoingDocs.isEmpty) {
          // --- Optimization: Only call setState if the state is NOT already collapsed ---
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && (_bannerHasBeenShown || !_isBannerCollapsed)) {
              _bannerCollapseTimer?.cancel();
              setState(() {
                _bannerHasBeenShown = false;
                _isBannerCollapsed = true;
              });
            }
          });
          return const SizedBox.shrink();
        }

        // Handle initial show and collapse timer logic
        if (!_bannerHasBeenShown) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _bannerCollapseTimer?.cancel();
            _bannerCollapseTimer = Timer(const Duration(seconds: 4), () { // Increased timer to 4s for better UX
              if (mounted && !_isBannerCollapsed) {
                setState(() => _isBannerCollapsed = true);
              }
            });
            if (mounted && !_bannerHasBeenShown) { // Check before setting to prevent extra rebuilds
              setState(() => _bannerHasBeenShown = true);
              _isBannerCollapsed = false; // Ensure it starts expanded
            }
          });
        }

        return AnimatedPositioned(
          duration: const Duration(milliseconds: 1000),
          curve: Curves.fastOutSlowIn,
          // Move the banner up from the bottom when collapsed
          bottom: _isBannerCollapsed ? 16 : 0,
          right: _isBannerCollapsed ? 16 : 0,
          left: _isBannerCollapsed ? null : 0, // Expanded banner uses full width
          child: GestureDetector(
            onTap: () {
              if (_isBannerCollapsed) {
                // Re-expand and reset timer
                _bannerCollapseTimer?.cancel();
                _bannerCollapseTimer = Timer(const Duration(seconds: 10), () { // Longer timer on manual expand
                  if (mounted && !_isBannerCollapsed) {
                    setState(() => _isBannerCollapsed = true);
                  }
                });
                setState(() => _isBannerCollapsed = false);
              } else {
                // Handle navigation on full tap
                if (ongoingDocs.length > 1) {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => AllActiveOrdersPage(docs: ongoingDocs)));
                } else if (ongoingDocs.length == 1) {
                  // Navigate to the ConfirmationPage (requires fetching all details)
                  _navigateToConfirmationPage(ongoingDocs.first);
                }
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              width: _isBannerCollapsed ? 64 : MediaQuery.of(context).size.width,
              height: _isBannerCollapsed ? 64 : null,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius:
                BorderRadius.circular(_isBannerCollapsed ? 32 : 0),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: _isBannerCollapsed
                    ? _buildCollapsedBanner(ongoingDocs.length)
                    : _buildExpandedBanner(ongoingDocs),
              ),
            ),
          ),
        );
      },
    );
  }


  // ✨ NEW: Navigation logic extracted from AllActiveOrdersPage to handle single order tap
  Future<void> _navigateToConfirmationPage(DocumentSnapshot doc) async {
    if (!mounted) return;
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

      // Extract Rates (requires proper structure in DB for simplicity here)
      final Map<String, int> mealRates = {};
      final Map<String, int> walkingRates = {};
      final List<dynamic> petSizesList = data['pet_sizes'] ?? [];

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

      if (!mounted) return;

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
            serviceId: serviceId,
          ),
        ),
      );
    } catch (e, s) {
      FirebaseCrashlytics.instance.recordError(e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load order details. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  Widget _buildCollapsedBanner(int orderCount) {
    return ScaleTransition(
      key: const ValueKey('collapsed_banner'),
      scale: _pulseAnimation,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [AppColors.primaryColor, AppColors.primaryDark],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 5))
          ],
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
        ),
        child: Center(
          child: Text(
            orderCount.toString(),
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 24,
                shadows: const [
                  Shadow(
                      color: Colors.black38,
                      blurRadius: 3,
                      offset: Offset(0, 1))
                ]),
          ),
        ),
      ),
    );
  }

  // ✨ UPDATED: _buildExpandedBanner for better responsiveness and styling
  Widget _buildExpandedBanner(List<QueryDocumentSnapshot> ongoingDocs) {
    final firstDoc = ongoingDocs.first;
    final totalOngoingOrders = ongoingDocs.length;
    final data = firstDoc.data() as Map<String, dynamic>;
    final petImages = (data['pet_images'] as List<dynamic>? ?? []);
    final petNamesList = (data['pet_name'] as List<dynamic>? ?? []);
    final shopName = data['shopName'] ?? 'Provider';
    final shopImageUrl = data['shop_image'] as String? ?? '';
    final openTime = data['openTime'] ?? 'N/A';
    final closeTime = data['closeTime'] ?? 'N/A';
    final rawDates = data['selectedDates'];
    final isStartPinUsed = data['isStartPinUsed'] as bool? ?? false;
    String statusText = 'Ongoing Stay';
    IconData statusIcon = Icons.night_shelter_outlined;
    String? pickupMessage;
    int currentDay = 0;
    int totalDays = 0;
    final today = DateTime.now();

    final dates = (rawDates is List)
        ? rawDates.whereType<Timestamp>().map((ts) => ts.toDate()).toList()
        : <DateTime>[];
    if (dates.isNotEmpty) {
      totalDays = dates.length;
      dates.sort();
      final todayIndex = dates.indexWhere((d) => isSameDay(d, today));
      if (todayIndex != -1) currentDay = todayIndex + 1;
      final bool isFirstDay = isSameDay(dates.first, today);
      final bool isLastDay = isSameDay(dates.last, today);

      if (isFirstDay && !isStartPinUsed) {
        statusText = 'Drop-off Window: $openTime – $closeTime';
        statusIcon = Icons.login_rounded;
      } else if (isLastDay) {
        statusText = 'Final Day of Stay';
        statusIcon = Icons.home_rounded; // Changed icon to home
        pickupMessage = 'Pick-up window closes at $closeTime';
      } else if (currentDay > 0) {
        statusText = 'Ongoing Stay';
        statusIcon = Icons.night_shelter_outlined;
      }
    }

    String petDisplayName;
    if (petNamesList.isEmpty) {
      petDisplayName = 'Your Pet';
    } else {
      String firstName = petNamesList.first.toString();
      String capitalizedFirstName = firstName.isNotEmpty
          ? "${firstName[0].toUpperCase()}${firstName.substring(1)}"
          : "";
      petDisplayName = petNamesList.length > 1
          ? '$capitalizedFirstName (+${petNamesList.length - 1} more)'
          : capitalizedFirstName;
    }

    return Container(
      key: const ValueKey('expanded_banner'),
      padding: const EdgeInsets.all(16), // Increased padding
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16), // Increased margin
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20), // More rounded corners
        border: Border.all(color: AppColors.primary, width: 3),
        boxShadow: const [
          BoxShadow(
              color: Colors.black38, blurRadius: 15, offset: Offset(0, 5))
        ], // Stronger shadow
      ),
      child: Stack(children: [
        Padding(
          padding: const EdgeInsets.only(right: 32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- ROW 1: Title and Shop Info ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Row(
                      children: [
                    Text(shopName,
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      radius: 16,
                      backgroundImage: shopImageUrl.isNotEmpty
                          ? CachedNetworkImageProvider(shopImageUrl)
                          : null,
                      backgroundColor: Colors.grey.shade200,
                      child: shopImageUrl.isEmpty
                          ? const Icon(Icons.storefront,
                          size: 16, color: Colors.grey)
                          : null,
                    )
                  ])
                ],
              ),
              const Divider(height: 20),

              // --- ROW 2: Pet Avatar and Name ---
              Row(children: [
                if (petImages.isNotEmpty)
                  _buildOverlappingPetAvatars(petImages)
                else
                  _buildNoPetIndicator(),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(petDisplayName,
                        style: GoogleFonts.poppins(
                            fontSize: 16,
                            color: Colors.black,
                            fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis)),
              ]),

              const SizedBox(height: 16),

              // --- ROW 3: Status and Day Count ---
              Row(children: [
                Expanded(
                    child: Container(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: AppColors.primaryColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(25)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(statusIcon,
                            color: AppColors.primaryColor, size: 16),
                        const SizedBox(width: 8),
                        Flexible(
                            child: Text(statusText,
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primaryColor))),
                      ]),
                    )),
                if (totalDays > 0) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(25)),
                    child: Text('Day $currentDay of $totalDays',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700)),
                  )
                ]
              ]),

              // --- Progress Bar ---
              if (totalDays > 1) ...[
                const SizedBox(height: 12),
                ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                        value: currentDay / totalDays,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.primaryColor),
                        minHeight: 8))
              ],

              // --- Multi-Order Indicator ---
              if (totalOngoingOrders > 1) ...[
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => AllActiveOrdersPage(docs: ongoingDocs))),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.accentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.accentColor),
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('View all ${totalOngoingOrders} active bookings',
                              style: GoogleFonts.poppins(
                                  color: AppColors.accentColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_ios,
                              size: 14, color: AppColors.accentColor)
                        ]),
                  ),
                )
              ],
              // --- Pickup Message ---
              if (pickupMessage != null && totalOngoingOrders == 1) ...[
                const SizedBox(height: 16),
                Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.yellow.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.yellow.shade300)),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.amber.shade700, size: 18),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(pickupMessage,
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w500)),
                          )
                        ]))
              ]
            ],
          ),
        ),
        // --- Collapse Button ---
        Positioned(
            top: -4,
            right: -4,
            child: IconButton(
                icon: const Icon(Icons.close,
                    color: AppColors.black, size: 22),
                onPressed: () {
                  _bannerCollapseTimer?.cancel();
                  setState(() => _isBannerCollapsed = true);
                })),
      ]),
    );
  }

  Widget _buildNoPetIndicator() {
    return Padding(
      padding: const EdgeInsets.only(right: 10.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: AppColors.primaryColor,
            child: const Icon(
              Icons.pets,
              size: 24,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Your Pet',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildOverlappingPetAvatars(List<dynamic> petImages) {
    const double avatarRadius = 20;
    const double overlap = 15;
    final itemsToShow = petImages.length > 2 ? 2 : petImages.length;
    if (petImages.isEmpty) {
      return const CircleAvatar(radius: avatarRadius, child: Icon(Icons.pets));
    }

    return SizedBox(
      width: (itemsToShow * (avatarRadius * 2 - overlap)) +
          (petImages.length > itemsToShow ? avatarRadius * 2 : 0), // Fix width calculation
      height: avatarRadius * 2,
      child: Stack(
        children: [
          ...List.generate(itemsToShow, (index) {
            return Positioned(
                left: index * (avatarRadius * 2 - overlap),
                child: CircleAvatar(
                    radius: avatarRadius,
                    backgroundColor: Colors.white,
                    child: CircleAvatar(
                        radius: avatarRadius - 1.5,
                        backgroundImage:
                        CachedNetworkImageProvider(petImages[index]))));
          }),
          if (petImages.length > itemsToShow)
            Positioned(
                left: itemsToShow * (avatarRadius * 2 - overlap),
                child: CircleAvatar(
                    radius: avatarRadius,
                    backgroundColor: AppColors.primaryColor,
                    child: Text('+${petImages.length - itemsToShow}',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14))))
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// COMING SOON PAGE
// ---------------------------------------------------------------------------
class ComingSoonServicePage extends StatefulWidget {
  final String serviceName;
  const ComingSoonServicePage({Key? key, required this.serviceName})
      : super(key: key);

  @override
  _ComingSoonServicePageState createState() => _ComingSoonServicePageState();
}

class _ComingSoonServicePageState
    extends State<ComingSoonServicePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
            title: Text(widget.serviceName),
            backgroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
            iconTheme:
            const IconThemeData(color: AppColors.textPrimary),
            titleTextStyle: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
        body: Stack(children: [
          Positioned(
              top: -100,
              left: -100,
              child: CircleAvatar(
                  radius: 150,
                  backgroundColor:
                  AppColors.primaryColor.withOpacity(0.05))),
          Positioned(
              bottom: -120,
              right: -150,
              child: CircleAvatar(
                  radius: 200,
                  backgroundColor:
                  AppColors.accentColor.withOpacity(0.05))),
          Center(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.rocket_launch_outlined,
                            size: 100,
                            color: AppColors.primaryColor),
                        const SizedBox(height: 32),
                        Text("Launching Soon!",
                            style: GoogleFonts.poppins(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        Text(
                            "Our amazing '${widget.serviceName}' service is getting ready. We're working hard to bring it to you and your furry friends!",
                            style: GoogleFonts.poppins(
                                fontSize: 16,
                                color: AppColors.textSecondary,
                                height: 1.6),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 40),
                        ElevatedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                  behavior:
                                  SnackBarBehavior.floating,
                                  backgroundColor:
                                  AppColors.textPrimary,
                                  content: Text(
                                      "You're on the list! We'll notify you first.",
                                      style: GoogleFonts.poppins(
                                          color: Colors.white))));
                            },
                            icon: const Icon(
                                Icons.notifications_active_outlined,
                                color: Colors.white),
                            label: Text("Notify Me",
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                                backgroundColor:
                                AppColors.primaryColor,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 32, vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(30)),
                                elevation: 2,
                                shadowColor: AppColors.primaryColor
                                    .withOpacity(0.4)))
                      ])))
        ]));
  }
}

// ---------------------------------------------------------------------------
// BLINKING BUTTON
// ---------------------------------------------------------------------------
class BlinkingButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const BlinkingButton(
      {required this.label, required this.onTap, Key? key})
      : super(key: key);

  @override
  State<BlinkingButton> createState() => _BlinkingButtonState();
}

class _BlinkingButtonState extends State<BlinkingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
        opacity: Tween(begin: 1.0, end: 0.4).animate(_controller),
        child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
                margin: const EdgeInsets.only(left: 10),
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: AppColors.accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border:
                    Border.all(color: AppColors.accentColor)),
                child: Text(widget.label,
                    style: GoogleFonts.poppins(
                        color: AppColors.accentColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)))));
  }
}