// lib/main.dart
import 'dart:io' show Platform;
import 'dart:ui';
import 'package:app_links/app_links.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:myfellowpet_user/preloaders/BoardingCardsForBoardingHomePage.dart';
import 'package:myfellowpet_user/preloaders/BoardingCardsProvider.dart';
import 'package:myfellowpet_user/preloaders/PetsInfoProvider.dart';
import 'package:myfellowpet_user/preloaders/TileImageProvider.dart';
import 'package:myfellowpet_user/preloaders/distance_provider.dart';
import 'package:myfellowpet_user/preloaders/favorites_provider.dart';
import 'package:myfellowpet_user/preloaders/header_media_provider.dart';
import 'package:myfellowpet_user/preloaders/hidden_services_provider.dart';
import 'package:myfellowpet_user/screens/AppBars/AllPetsPage.dart';
import 'package:myfellowpet_user/screens/Authentication/FirstTimeUserLoginDeyts.dart';
import 'package:myfellowpet_user/screens/Authentication/PhoneSignInPage.dart';
import 'package:myfellowpet_user/screens/Boarding/boarding_homepage.dart';
import 'package:myfellowpet_user/screens/Boarding/boarding_servicedetailspage.dart';
import 'package:myfellowpet_user/screens/Boarding/summary_page_boarding.dart';
import 'package:myfellowpet_user/screens/BottomBars/homebottomnavigationbar.dart';
import 'package:myfellowpet_user/screens/HomeScreen/HomeScreen.dart';
import 'package:myfellowpet_user/screens/Orders/BoardingOrders.dart';
import 'package:myfellowpet_user/screens/reviews/review_gate.dart';
import 'package:recaptcha_enterprise_flutter/recaptcha_enterprise.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:provider/provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'CustomSplashPage.dart';
import 'NoInternetPage.dart';
import 'app_colors.dart';
import 'firebase_options.dart';
import 'package:flutter/services.dart'; // <<< Required for SystemChrome
import 'package:lottie/lottie.dart'; // <<< REQUIRED FOR SPLASH PAGE

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

class HeaderData {
  final String greeting;
  final String mediaUrl;
  HeaderData({required this.greeting, required this.mediaUrl});
}

Future<AndroidMapRenderer?> initializeMapRenderer() async {
  try {
    final mapsImplementation = GoogleMapsFlutterPlatform.instance;
    if (mapsImplementation is GoogleMapsFlutterAndroid) {
      return await mapsImplementation.initializeWithRenderer(
        AndroidMapRenderer.latest,
      );
    }
  } catch (_) {}
  return null;
}

Future<void> initializeLocalNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  await flutterLocalNotificationsPlugin.initialize(
    InitializationSettings(android: android),
  );
}

Future<void> setupForegroundNotificationListener() async {
  FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
    final notif = msg.notification;
    final android = msg.notification?.android;
    if (notif != null && android != null) {
      flutterLocalNotificationsPlugin.show(
        notif.hashCode,
        notif.title,
        notif.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'booking_channel',
            'Booking Notifications',
            channelDescription:
            'This channel is used for booking confirmation notifications',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
    }
  });
}

Future<HeaderData> preloadHeaderData() async {
  final firestore = FirebaseFirestore.instance;
  final doc =
  await firestore.collection('company_documents').doc('homescreen_images').get();
  final mediaUrl = doc.data()?['boarding'] as String? ?? '';
  String greeting = 'Hello Guest 👋';
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    final userDoc = await firestore.collection('users').doc(user.uid).get();
    final name = userDoc.data()?['name'] as String?;
    if (name != null) greeting = 'Hello $name 👋';
  }
  return HeaderData(greeting: greeting, mediaUrl: mediaUrl);
}


// ✨ FIX 1: Add a robust helper function for rate maps
Map<String, int> safeRateMap(dynamic firestoreData) {
  if (firestoreData is Map) {
    return firestoreData.map(
          (k, v) => MapEntry(k.toString(), int.tryParse(v.toString()) ?? 0),
    );
  }
  return {};
}

Future<String?> getActiveBookingDocId(String userId) async {
  try {
    print('🔍 Checking active booking for user: $userId');

    final query = await FirebaseFirestore.instance
        .collectionGroup('service_request_boarding')
        .where('source', isEqualTo: 'sp')
        .where('user_id', isEqualTo: userId)
        .where('order_status', isEqualTo: 'pending_payment')
        .limit(1)
        .get();

    print('📦 Query executed successfully. Found ${query.docs.length} docs.');
    if (query.docs.isEmpty) return null;

    final doc = query.docs.first;
    final data = doc.data();

    final serviceId = data['service_id'] ?? data['sp_id'] ?? '';
    if (serviceId.isEmpty) {
      print('❌ Error: Found booking doc ${doc.id} but it has no service_id or sp_id.');
      return null;
    }

    print('📂 Found booking doc path: ${doc.reference.path}');
    print('🆔 Correct derived serviceId: $serviceId');

    return "$serviceId|${doc.id}";
  } catch (e, st) {
    print('🚨 Error checking active booking: $e');
    print(st);
    return null;
  }
}

void main() async {
  Provider.debugCheckInvalidValueType = null;
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } else {
      Firebase.app(); // just get existing instance
    }
  } catch (e) {
    debugPrint('🔥 Firebase already initialized: $e');
  }

  FlutterError.onError = (FlutterErrorDetails details) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };


  final mapsImpl = GoogleMapsFlutterPlatform.instance;
  if (mapsImpl is GoogleMapsFlutterAndroid) {
    await initializeMapRenderer();
  }

  await initializeLocalNotifications();
  await setupForegroundNotificationListener();

  final tileImageProvider = TileImageProvider();
  await tileImageProvider.loadTileImages();
  final headerData = await preloadHeaderData();

  try {
    await RecaptchaEnterprise.initClient(
      Platform.isAndroid
          ? '6LeJWAYsAAAAAKmmEvaVqbvbynZ-vK58IQBDK8mi'
          : '6LeJWAYsAAAAAKmmEvaVqbvbynZ-vK58IQBDK8mi',
      timeout: 10000,
    );
  } catch (_, st) {
    debugPrintStack(stackTrace: st);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => DistanceProvider(FirebaseFirestore.instance)),
        ChangeNotifierProvider(create: (_) => ShopDetailsProvider()..loadFirstTen()),
        ChangeNotifierProvider(create: (_) => HiddenServicesProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ChangeNotifierProvider<TileImageProvider>.value(value: tileImageProvider),
        ChangeNotifierProvider(create: (_) => PetProvider()),
        Provider<HeaderData>.value(value: headerData),
        ChangeNotifierProvider(create: (ctx) => HeaderMediaProvider(ctx)),
        ChangeNotifierProvider(create: (ctx) => BoardingCardsProvider(ctx)),
      ],
      child: const MyApp(),
    ),
  );
}


// -------------------------------------------------------------------------
// --- CUSTOM SPLASH PAGE (New Root) ---
// -------------------------------------------------------------------------

// -------------------------------------------------------------------------
// --- APP ROOT (Set Home to CustomSplashPage) ---
// -------------------------------------------------------------------------

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}
class _MyAppState extends State<MyApp> {
  bool _hasInternet = true;
  final Connectivity _connectivity = Connectivity();
  final _appLinks = AppLinks();

  // NEW STATE: Holds the URI if the app launched from a link.
  Uri? _initialDeepLinkUri;
  bool _initialLinkChecked = false; // Flag to wait for async link check

  @override
  void initState() {
    super.initState();
    _checkInternet();
    _connectivity.onConnectivityChanged.listen((status) {
      setState(() => _hasInternet = status != ConnectivityResult.none);
    });

    // NEW: Start checking for the initial link immediately on cold start
    _checkInitialDeepLink();

    // Existing: Listen for warm start (App already open, this is working fine)
    _appLinks.uriLinkStream.listen(_handleWarmLink);
  }

  // NEW: Checks the link only once on app launch (Cold Start)
  Future<void> _checkInitialDeepLink() async {
    final uri = await _appLinks.getInitialLink();
    setState(() {
      _initialDeepLinkUri = uri;
      _initialLinkChecked = true; // Signal the build method to proceed
    });
  }

  // NEW: Handles navigation when the app is already open (Warm Start)
  void _handleWarmLink(Uri uri) {
    if (uri.pathSegments.contains('boarding')) {
      _performNavigation(uri);
    }
  }

  // --- Existing _handleLink logic moved here ---
  Future<void> _performNavigation(Uri uri) async {
    // Check if link contains 'boarding' (e.g., https://myfellowpet.com/boarding/SERVICE_ID)
    if (uri.pathSegments.contains('boarding')) {
      final serviceId = uri.pathSegments.last;
      final context = navigatorKey.currentContext;

      if (context == null) return;

      try {
        final doc = await FirebaseFirestore.instance
            .collection('users-sp-boarding')
            .doc(serviceId)
            .get();

        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;

          final distProv = Provider.of<DistanceProvider>(context, listen: false);
          final newDistance = distProv.distances[serviceId] ?? 0.0;

          final pets = List<String>.from(data['pets'] ?? []);
          String? initialPet;
          if (pets.isNotEmpty) {
            String p = pets.first;
            initialPet = p.isNotEmpty ? "${p[0].toUpperCase()}${p.substring(1)}" : p;
          }

          // Navigate using push (This works because this function is called OUTSIDE the main AuthGate Future)
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (context) => BoardingServiceDetailPage(
                documentId: serviceId,
                shopName: data['shop_name'] ?? 'N/A',
                shopImage: data['shop_logo'] ?? '',
                areaName: data['area_name'] ?? 'N/A',
                distanceKm: newDistance,
                pets: pets,
                mode: "1", // Assuming '1' is the correct mode constant
                rates: {},
                isOfferActive: data['isOfferActive'] ?? false,
                isCertified: data['mfp_certified'] ?? false,
                otherBranches: List<String>.from(data['other_branches'] ?? []),
                preCalculatedStandardPrices: Map<String, dynamic>.from(data['pre_calculated_standard_prices'] ?? {}),
                preCalculatedOfferPrices: Map<String, dynamic>.from(data['pre_calculated_offer_prices'] ?? {}),
                initialSelectedPet: initialPet,
              ),
            ),
          );
        }
      } catch (e) {
        print("Error handling deep link: $e");
      }
    }
  }


  Future<void> _checkInternet() async {
    final result = await _connectivity.checkConnectivity();
    setState(() => _hasInternet = result != ConnectivityResult.none);
  }

  @override
  Widget build(BuildContext context) {
    // 🛑 1. WAIT STATE: If check hasn't completed, show splash page
    if (!_initialLinkChecked) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        home: const CustomSplashPage(),
      );
    }

    // 🛑 2. MAIN APP ROUTE: Pass the checked URI to the AuthGate
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,

      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryColor,
          primary: AppColors.primaryColor,
        ),
        // ... (rest of theme unchanged) ...
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: AppColors.primaryColor,
          selectionHandleColor: AppColors.primaryColor,
          selectionColor: AppColors.primaryColor.withOpacity(0.25),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primaryColor,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryColor,
            side: BorderSide(color: AppColors.primaryColor),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        iconTheme: IconThemeData(color: AppColors.primaryColor),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0.3,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        dividerTheme: DividerThemeData(
          color: Colors.grey.shade300,
          thickness: 1,
        ),
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: AppColors.primaryColor,
          circularTrackColor: Colors.grey.shade300,
        ),
      ),

      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: _hasInternet
            ? AuthGate(initialUri: _initialDeepLinkUri) // <-- PASS THE URI HERE
            : NoInternetPage(onRetry: _checkInternet),
      ),
    );
  }
}
class AuthGate extends StatelessWidget {
  final Uri? initialUri; // <-- NEW FIELD

  const AuthGate({Key? key, this.initialUri}) : super(key: key);

  // NEW HELPER: Fetches deep link data and builds the target page
  Future<Widget?> _fetchAndBuildDeepLinkPage(Uri uri, BuildContext context) async {
    // Duplicates the navigation logic from _MyAppState, but now returns the page itself.
    // This is necessary because AuthGate controls the root widget, not just a push.
    final serviceId = uri.pathSegments.last;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users-sp-boarding')
          .doc(serviceId)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;

        final distProv = Provider.of<DistanceProvider>(context, listen: false);
        final newDistance = distProv.distances[serviceId] ?? 0.0;

        final pets = List<String>.from(data['pets'] ?? []);
        String? initialPet;
        if (pets.isNotEmpty) {
          String p = pets.first;
          initialPet = p.isNotEmpty ? "${p[0].toUpperCase()}${p.substring(1)}" : p;
        }

        return BoardingServiceDetailPage(
          documentId: serviceId,
          shopName: data['shop_name'] ?? 'N/A',
          shopImage: data['shop_logo'] ?? '',
          areaName: data['area_name'] ?? 'N/A',
          distanceKm: newDistance,
          pets: pets,
          mode: "1",
          rates: {},
          isOfferActive: data['isOfferActive'] ?? false,
          isCertified: data['mfp_certified'] ?? false,
          otherBranches: List<String>.from(data['other_branches'] ?? []),
          preCalculatedStandardPrices: Map<String, dynamic>.from(data['pre_calculated_standard_prices'] ?? {}),
          preCalculatedOfferPrices: Map<String, dynamic>.from(data['pre_calculated_offer_prices'] ?? {}),
          initialSelectedPet: initialPet,
        );
      }
    } catch (e) {
      print("Error building cold start deep link page: $e");
    }
    return null;
  }

  // UPDATED handlePostLoginRouting: Now accepts context
  Future<Widget> handlePostLoginRouting(User user, BuildContext context) async {

    // 🛑 1. DEEP LINK GATING (Cold Start Priority)
    if (initialUri != null && initialUri!.pathSegments.contains('boarding')) {
      final targetPage = await _fetchAndBuildDeepLinkPage(initialUri!, context);
      if (targetPage != null) {
        print('🚀 Redirecting to deep linked page from Cold Start.');
        return targetPage; // Pushes deep link page as the root widget
      }
    }

    print('🧠 AuthGate: Logged in as ${user.phoneNumber}. Checking status...');
    final firestore = FirebaseFirestore.instance;
    final userRef = firestore.collection('users').doc(user.uid);
    final userDoc = await userRef.get();

    // ... (Your existing inactivity lock logic) ...

    DateTime? lastLogin;
    if (userDoc.exists) {
      final ts = userDoc.data()?['last_login'];
      if (ts is Timestamp) {
        lastLogin = ts.toDate();
      }
    }

    bool shouldLock = false;
    if (lastLogin != null) {
      final daysSinceLast = DateTime.now().difference(lastLogin).inDays;
      if (daysSinceLast > 90) {
        shouldLock = true;
      }
    }

    if (shouldLock) {
      await userRef.update({
        'account_status': 'locked',
      });
      print('🔒 Account locked due to inactivity.');
      return PhoneAuthPage();
    }

    if (userDoc.exists) {
      await userRef.update({
        'last_login': FieldValue.serverTimestamp(),
        'account_status': 'active',
      });
    }

    final accountStatus = userDoc.data()?['account_status'] ?? 'active';
    if (accountStatus == 'locked') {
      print('🔒 Account already locked. Redirecting...');
      return PhoneAuthPage();
    }

    // 🛑 2. ACTIVE BOOKING CHECK (Existing Logic)
    final activeBooking = await getActiveBookingDocId(user.uid);
    if (activeBooking != null) {
      final parts = activeBooking.split('|');
      final serviceId = parts[0];
      final bookingId = parts[1];

      try {
        final doc = await firestore
            .collection('users-sp-boarding')
            .doc(serviceId)
            .collection('service_request_boarding')
            .doc(bookingId)
            .get();

        if (doc.exists) {
          print('🚀 Redirecting to active SummaryPage...');
          final data = doc.data()!;

          final Map<String, int> dailyRates = safeRateMap(data['rates_daily']);
          final Map<String, int> walkingRates = safeRateMap(data['walkingRates']);
          final Map<String, int> mealRates = safeRateMap(data['mealRates']);

          final Map<String, Map<String, dynamic>> perDayServices = {};

          final petServicesSnapshot = await doc.reference.collection('pet_services').get();

          for (var petDoc in petServicesSnapshot.docs) {
            final petDocData = petDoc.data();
            if (petDocData.isNotEmpty) {
              perDayServices[petDoc.id] = petDocData.map(
                    (k, v) => MapEntry(k.toString(), v is Map ? Map<String, dynamic>.from(v) : v),
              );
            }
          }

          final petSizesList = List<Map<String, dynamic>>.from(
              (data['pet_sizes'] ?? data['petSizesList'] ?? [])
          );

          return SummaryPage(
            spServiceFeeExcGst: data['sp_service_fee_exc_gst']?.toDouble() ?? 0,
            spServiceFeeIncGst: data['sp_service_fee_inc_gst']?.toDouble() ?? 0,
            gstOnSpService: data['gst_on_sp_service']?.toDouble() ?? 0,
            platformFeeExcGst: data['platform_fee_exc_gst']?.toDouble() ?? 0,
            platformFeeIncGst: data['platform_fee_inc_gst']?.toDouble() ?? 0,
            gstOnPlatformFee: data['gst_on_platform_fee']?.toDouble() ?? 0,
            totalAmountPaid: data['total_amount_paid']?.toDouble() ?? 0,
            remainingRefundableAmount: data['remaining_refundable_amount']?.toDouble() ?? 0,
            totalRefundedAmount: data['total_refunded_amount']?.toDouble() ?? 0,
            adminFeeTotal: data['admin_fee_collected_total']?.toDouble() ?? 0,
            adminFeeGstTotal: data['admin_fee_gst_collected_total']?.toDouble() ?? 0,
            serviceId: serviceId,
            bookingId: bookingId,
            shopName: data['shopName'] ?? '',
            shopImage: data['shop_image'] ?? '',
            sp_id: data['sp_id'] ?? data['service_id'] ?? '',
            totalCost: double.tryParse(data['original_total_amount']?.toString() ?? '0') ?? 0,
            startDate: (data['selectedDates'] as List?)?.isNotEmpty == true
                ? (data['selectedDates'][0] as Timestamp).toDate()
                : null,
            endDate: (data['selectedDates'] as List?)?.isNotEmpty == true
                ? (data['selectedDates'].last as Timestamp).toDate()
                : null,
            selectedDates: (data['selectedDates'] as List<dynamic>?)
                ?.map((e) => (e as Timestamp).toDate())
                .toList() ?? [],
            petIds: List<String>.from(data['pet_id'] ?? []),
            petNames: List<String>.from(data['pet_name'] ?? []),
            petImages: List<String>.from(data['pet_images'] ?? []),
            perDayServices: perDayServices,
            foodCost: double.tryParse(data['cost_breakdown']?['meals_cost']?.toString() ?? '0'),
            walkingCost: double.tryParse(data['cost_breakdown']?['daily_walking_cost']?.toString() ?? '0'),
            transportCost: double.tryParse(data['transportCost']?.toString() ?? '0'),
            openTime: data['openTime'] ?? '',
            closeTime: data['closeTime'] ?? '',
            areaName: data['areaName'] ?? '',
            areaNameOnly: data['areaName'] ?? '',
            boarding_rate: double.tryParse(data['cost_breakdown']?['boarding_cost']?.toString() ?? '0') ?? 0,
            foodOption: data['foodOption'] ?? '',
            foodInfo: Map<String, dynamic>.from(data['foodInfo'] ?? {}),
            mode: 'resume',
            walkingFee: data['walkingFee']?.toString() ?? '',
            numberOfPets: data['numberOfPets'] ?? 0,
            availableDaysCount: (data['selectedDates'] as List?)?.length ?? 0,
            sp_location: data['shop_location'] ?? const GeoPoint(0, 0),
            mealRates: mealRates,
            walkingRates: walkingRates,
            dailyRates: dailyRates,
            refundPolicy: Map<String, int>.from(data['refund_policy'] ?? {}),
            fullAddress: data['full_address'] ?? '',
            petSizesList: petSizesList,
            petCostBreakdown: List<Map<String, dynamic>>.from(data['petCostBreakdown'] ?? []),
            gstNumber: data['gst_number'] ?? 'NA', gstRegistered: data['gst_registered'] ?? false,
          );
        }
      } catch (e, st) {
        print('🚨 Error fetching active booking: $e');
        print(st);
      }
    }

    // 3. FINAL DEFAULT ROUTE (Home page)
    if (userDoc.exists) {
      return ReviewGate(child: HomeWithTabs());
    } else {
      return UserDetailsPage(phoneNumber: user.phoneNumber ?? '');
    }
  }


  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.active) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary,)));
        }

        final user = snap.data;
        if (user == null) {
          return PhoneAuthPage();
        }

        return FutureBuilder<Widget>(
          // Note: Passing context to handlePostLoginRouting
          future: handlePostLoginRouting(user, ctx),
          builder: (ctx, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary,)));
            }
            return snapshot.data!;
          },
        );
      },
    );
  }
}

// -------------------------------------------------------------------------
// --- HOME WITH TABS (Unchanged) ---
// -------------------------------------------------------------------------

class HomeWithTabs extends StatefulWidget {
  final int initialTabIndex;
  final Map<String, dynamic>? initialBoardingFilter;

  const HomeWithTabs({
    Key? key,
    this.initialTabIndex = 0,
    this.initialBoardingFilter,
  }) : super(key: key);

  @override
  HomeWithTabsState createState() => HomeWithTabsState();
}
class HomeWithTabsState extends State<HomeWithTabs> {
  late int _currentIndex;
  Map<String, dynamic>? _boardingFilterData;

  // ✨ Store the list of pages here
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex;
    _boardingFilterData = widget.initialBoardingFilter;

    // ✨ Initialize the pages list ONCE in initState
    _pages = [
      HomeScreen(),
      BoardingHomepage(
        initialSearchFocus: _boardingFilterData != null,
        initialBoardingFilter: _boardingFilterData,
      ),
     // PetStoreHomePage(),
      AllPetsPage(),
      BoardingOrders(userId: FirebaseAuth.instance.currentUser?.uid ?? ''),
    ];

    // ✨ Clear the filter data immediately after using it
    _boardingFilterData = null;
  }

  void goToTab(int idx) => setState(() => _currentIndex = idx);

  Future<bool> _onWillPop() async {
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _pages,
        ),
        bottomNavigationBar: SafeArea(
          top: false,  // protect only the bottom
          child: BottomNavigationBarWidget(
            currentIndex: _currentIndex,
            onTap: (i) => setState(() => _currentIndex = i),
          ),
        ),
      ),
    );
  }
}

