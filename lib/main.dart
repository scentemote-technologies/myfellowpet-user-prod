// lib/main.dart
import 'dart:io' show Platform;
import 'dart:ui';
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
import 'package:myfellowpet_user/screens/Boarding/summary_page_boarding.dart';
import 'package:myfellowpet_user/screens/BottomBars/homebottomnavigationbar.dart';
import 'package:myfellowpet_user/screens/HomeScreen/HomeScreen.dart';
import 'package:myfellowpet_user/screens/Orders/BoardingOrders.dart';
import 'package:myfellowpet_user/screens/pet_store/PetStoreHomePage.dart';
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

  @override
  void initState() {
    super.initState();
    _checkInternet();
    _connectivity.onConnectivityChanged.listen((status) {
      setState(() => _hasInternet = status != ConnectivityResult.none);
    });
  }

  Future<void> _checkInternet() async {
    final result = await _connectivity.checkConnectivity();
    setState(() => _hasInternet = result != ConnectivityResult.none);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: _hasInternet
            ? const CustomSplashPage()
            : NoInternetPage(onRetry: _checkInternet),
      ),
    );
  }
}


// -------------------------------------------------------------------------
// --- AUTH GATE (No Changes Needed) ---
// -------------------------------------------------------------------------

class AuthGate extends StatelessWidget {
  const AuthGate({Key? key}) : super(key: key);

  Future<Widget> handlePostLoginRouting(User user) async {
    print('🧠 AuthGate: Logged in as ${user.phoneNumber}');
    final firestore = FirebaseFirestore.instance;
    final userRef = firestore.collection('users').doc(user.uid);
    final userDoc = await userRef.get();

    DateTime? lastLogin;
    if (userDoc.exists) {
      final ts = userDoc.data()?['last_login'];
      if (ts is Timestamp) {
        lastLogin = ts.toDate();
      }
    }

    // 🔍 1️⃣ Check inactivity duration before updating
    bool shouldLock = false;
    if (lastLogin != null) {
      final daysSinceLast = DateTime.now().difference(lastLogin).inDays;
      print('📅 Days since last login: $daysSinceLast');
      if (daysSinceLast > 90) {
        shouldLock = true;
      }
    }

    // 🔒 2️⃣ If inactive > 90 days, lock account
    if (shouldLock) {
      await userRef.update({
        'account_status': 'locked',
      });
      print('🔒 Account locked due to inactivity.');
      // Redirect to PIN/Lock screen (or a reactivation screen)
      return PhoneAuthPage(); // replace with your lock/reactivation page
    }

    // ✅ 3️⃣ Otherwise, mark active and update last_login
    if (userDoc.exists) {
      await userRef.update({
        'last_login': FieldValue.serverTimestamp(),
        'account_status': 'active',
      });
    }

    // 4️⃣ Proceed as usual if active
    final accountStatus = userDoc.data()?['account_status'] ?? 'active';
    if (accountStatus == 'locked') {
      print('🔒 Account already locked. Redirecting...');
      return PhoneAuthPage();
    }

    // 5️⃣ Active booking check (unchanged logic, modified return structure)
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

          // ✨ CRITICAL FIX 2 & 3: Safely retrieve all rates and the petSizesList

          final Map<String, int> dailyRates = safeRateMap(data['rates_daily']);
          final Map<String, int> walkingRates = safeRateMap(data['walkingRates']);
          final Map<String, int> mealRates = safeRateMap(data['mealRates']);

          final Map<String, Map<String, dynamic>> perDayServices = {};

          final petServicesSnapshot = await doc.reference.collection('pet_services').get();

          for (var petDoc in petServicesSnapshot.docs) {
            final petDocData = petDoc.data();
            // Ensure petDocData exists and convert the inner map safely
            if (petDocData.isNotEmpty) {
              perDayServices[petDoc.id] = petDocData.map(
                    (k, v) => MapEntry(k.toString(), v is Map ? Map<String, dynamic>.from(v) : v),
              );
            }
          }
          // *******************************************************

          // Ensure petSizesList is correctly cast as List<Map<String, dynamic>>
          final petSizesList = List<Map<String, dynamic>>.from(
              (data['pet_sizes'] ?? data['petSizesList'] ?? [])
          );

          // Calculate single-day boarding rate (for the legacy boarding_rate field)
          // This is generally unreliable but kept for compatibility.
          double singleDayBoardingRate = 0.0;
          if (petSizesList.isNotEmpty) {
            final firstPet = petSizesList.first;
            singleDayBoardingRate = (firstPet['price'] as double?) ?? 0.0;
          }

          return SummaryPage(
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
                .toList() ??
                [],
            petIds: List<String>.from(data['pet_id'] ?? []),
            petNames: List<String>.from(data['pet_name'] ?? []),
            petImages: List<String>.from(data['pet_images'] ?? []),
            perDayServices: perDayServices,
            // The following costs are totals for the entire booking duration, already calculated in the document:
            foodCost: double.tryParse(data['cost_breakdown']?['meals_cost']?.toString() ?? '0'),
            walkingCost: double.tryParse(data['cost_breakdown']?['daily_walking_cost']?.toString() ?? '0'),
            transportCost: double.tryParse(data['transportCost']?.toString() ?? '0'),
            openTime: data['openTime'] ?? '',
            closeTime: data['closeTime'] ?? '',
            areaName: data['areaName'] ?? '',
            // Use the total boarding cost from the cost breakdown
            boarding_rate: double.tryParse(data['cost_breakdown']?['boarding_cost']?.toString() ?? '0') ?? 0,
            foodOption: data['foodOption'] ?? '',
            foodInfo: Map<String, dynamic>.from(data['foodInfo'] ?? {}),
            mode: 'resume',
            walkingFee: data['walkingFee']?.toString() ?? '',
            numberOfPets: data['numberOfPets'] ?? 0,
            availableDaysCount: (data['selectedDates'] as List?)?.length ?? 0,
            sp_location: data['shop_location'] ?? const GeoPoint(0, 0),

            // 👇 PASS THE SAFELY CONVERTED MAPS
            mealRates: mealRates,
            walkingRates: walkingRates,
            dailyRates: dailyRates,

            refundPolicy: Map<String, int>.from(data['refund_policy'] ?? {}),
            fullAddress: data['full_address'] ?? '',

            // 👇 PASS THE CORRECTLY CAST PET SIZES LIST
            petSizesList: petSizesList,

            // ✨ NEW: Retrieve and pass the petCostBreakdown array
            petCostBreakdown: List<Map<String, dynamic>>.from(data['petCostBreakdown'] ?? []),
          );
        }
      } catch (e, st) {
        print('🚨 Error fetching active booking: $e');
        print(st);
      }
    }

    // 6️⃣ Default route
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
          // 💡 FIX: Return nothing visually, relying on the Native/Custom Splash
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary,)));
        }

        final user = snap.data;
        if (user == null) {
          print('🔓 Not logged in. Going to PhoneAuthPage.');
          return PhoneAuthPage();
        }

        // This FutureBuilder now swaps pages *inside* the main MaterialApp
        return FutureBuilder<Widget>(
          future: handlePostLoginRouting(user),
          builder: (ctx, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              // 💡 FIX: Return nothing visually, relying on the Native/Custom Splash
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
        bottomNavigationBar: BottomNavigationBarWidget(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() {
            _currentIndex = i;
          }),
        ),
      ),
    );
  }
}