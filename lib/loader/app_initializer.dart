// 1) new file: app_initializer.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import '../screens/Authentication/PhoneSignInPage.dart';
import '../screens/HomeScreen/HomeScreen.dart';


class AppInitializer extends StatefulWidget {
  @override
  _AppInitializerState createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  @override
  void initState() {
    super.initState();
    _preloadEverything();
  }

  Future<void> _preloadEverything() async {
    final auth = FirebaseAuth.instance;
    final firestore = FirebaseFirestore.instance;

    // 1) header image
    final headerDoc = firestore
        .collection('company_documents')
        .doc('homescreen_images')
        .get();

    // 2) user profile (only if logged in)
    Future<DocumentSnapshot?> profile = auth.currentUser != null
        ? firestore.collection('users')
        .where('uid', isEqualTo: auth.currentUser!.uid)
        .get()
        .then((snap) => snap.docs.isNotEmpty ? snap.docs.first : null)
        : Future.value(null);

    // 3) user preferences
    final prefs = auth.currentUser != null
        ? firestore.collection('users')
        .doc(auth.currentUser!.uid)
        .collection('user_preferences')
        .doc('boarding')
        .get()
        : Future.value(null);

    // 4) initial boarding centers (you can `limit(20)` for speed)
    final centers = firestore
        .collection('users-sp-boarding')
        .get();

    // 5) geolocation permission + position
    final position = Geolocator.requestPermission()
        .then((_) => Geolocator.getCurrentPosition());

    // wait for everything
    final results = await Future.wait([
      headerDoc,
      profile,
      prefs,
      centers,
      position,
    ]);

    // TODO: stash these into a Provider or a global singleton
    // so your real HomeScreen can read from cache instead of refetch.

    // then navigate into the normal auth flow
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) {
        return StreamBuilder<User?>(
          stream: auth.authStateChanges(),
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.active)
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            return snap.hasData ? HomeScreen() : PhoneAuthPage();
          },
        );
      }));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
