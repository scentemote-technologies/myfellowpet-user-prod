import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_colors.dart';
import '../../preloaders/petpreloaders.dart';
import '../Authentication/PhoneSignInPage.dart';
import '../Authentication/chatgpt_integration.dart';
import '../Boarding/hidden_boarding_services_page.dart';
import '../Help_Center/sp_general_support_help_screen.dart';
import '../MFPAI/ai_chat_page.dart';
import 'AllPetsPage.dart';
import 'EditProfilePage.dart';
import '../Pets/AddPetPage.dart';
import '../Pets/pet_profile.dart';
import '../Orders/BoardingOrders.dart';

class AccountsPage extends StatefulWidget {
  @override
  _AccountsPageState createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? _userData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final uid = _auth.currentUser!.uid;
    final doc = await _firestore.collection('users').doc(uid).get();
    setState(() {
      _userData = doc.data();
      _loading = false;
    });
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => PhoneAuthPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final user = _userData!;
    final uid = _auth.currentUser!.uid;

    return Scaffold(
      // appBar has been removed.
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 40,
        ),
        // The top padding is removed from here.
        child: Column(
          children: [
            // PROFILE HEADER BOX - This is the new widget
            // PROFILE HEADER BOX - COMPACT VERSION
            Container(
              padding: const EdgeInsets.only(top: 40, bottom: 20, left: 20, right: 20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(25),
                  bottomRight: Radius.circular(25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // TOP ICON ROW (Back + Call Center)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // BACK BUTTON
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          padding: const EdgeInsets.all(6),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Colors.black,
                            size: 18,
                          ),
                        ),
                      ),

                      // CALL CENTER ICON
                      GestureDetector(
                        onTap: () async {
                          try {
                            // 🔹 Fetch support number from Firestore
                            final doc = await FirebaseFirestore.instance
                                .collection('settings')
                                .doc('contact_details')
                                .get();

                            final whatsappNumber = doc.data()?['whatsapp_user_support_number'];
                            if (whatsappNumber == null || whatsappNumber.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Support number not found')),
                              );
                              return;
                            }

                            // 🔹 Clean the number (remove '+' for wa.me link)
                            final cleanNumber = whatsappNumber.replaceAll('+', '').trim();

                            // 🔹 Create WhatsApp deep link
                            final message = Uri.encodeComponent("Hey, I need help with my account 🐾");
                            final whatsappUrl = Uri.parse("https://wa.me/$cleanNumber?text=$message");

                            // 🔹 Open WhatsApp
                            if (await canLaunchUrl(whatsappUrl)) {
                              await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Could not open WhatsApp')),
                              );
                            }
                          } catch (e) {
                            debugPrint('❌ Error opening WhatsApp support: $e');
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Something went wrong. Please try again.')),
                            );
                          }
                        },
                        child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        padding: const EdgeInsets.all(6),
                        child: const Icon(
                          Icons.headset_mic_rounded,
                          color: Colors.black,
                          size: 18,
                        ),
                      ),),
                    ],
                  ),

                  const SizedBox(height: 18),
              /*    ElevatedButton(
                    child: Text("Test Crash"),
                    onPressed: () {
                      FirebaseCrashlytics.instance.crash();
                    },
                  ),*/

                  // USER DETAILS
                  Text(
                    user['name'] ?? 'N/A',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${user['phone_number'] ?? 'N/A'}  •  ${user['email'] ?? 'N/A'}',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.85),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // EDIT PROFILE BUTTON
                  GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditProfilePage(uid: uid, userData: user),
                        ),
                      );
                      await _loadUserData();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Edit Profile',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.edit, size: 14, color: AppColors.primary),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),


            // Spacing between the new box and the content below
            SizedBox(height: 24),

            // MY PETS SECTION (The rest of the content remains the same)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('My Pets',
                      style: GoogleFonts.poppins(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                  Spacer(),
                  GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AddPetPage()),
                      );
                      setState(() {});
                    },
                    child: Container(
                      padding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Text('Add Pet',
                              style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.primary)),
                          SizedBox(width: 6),
                          Icon(Icons.add, size: 20, color: AppColors.primary),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // PET LIST
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: PetService.instance.watchMyPetsAsMap(context),
              builder: (ctx, pSnap) {
                if (!pSnap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final pets = pSnap.data!;
                if (pets.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No pets added.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return SizedBox(
                  height: 100,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: pets.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) {
                      final pet = pets[i];
                      return Column(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PetProfile(
                                  petId: pet['pet_id'],
                                  userUid: uid,
                                ),
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 30,
                              backgroundImage: pet['pet_image'].isNotEmpty
                                  ? NetworkImage(pet['pet_image'])
                                  : null,
                              backgroundColor: Colors.grey[300],
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: 60,
                            child: Text(
                              pet['name'],
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
            ),

            // VIEW ALL BUTTON
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () async {
                    final didChange = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(builder: (_) => AllPetsPage()),
                    );
                    if (didChange == true) {
                      await _loadUserData();
                      setState(() {});
                    }
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: AppColors.background,
                    side: BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'View All',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),

            Divider(),

            // MY ORDERS
            ListTile(
              title: Text('My Orders',
                  style: GoogleFonts.poppins(
                      fontSize: 18, fontWeight: FontWeight.w600)),
              trailing:
              Icon(Icons.keyboard_arrow_right, color: AppColors.primary),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => BoardingOrders(userId: uid))),
            ),

            Divider(),
            ListTile(
              title: Text(
                'Support',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: Icon(Icons.keyboard_arrow_right, color: AppColors.primary),
              onTap: () async {
                try {
                  // 🔹 Fetch support number from Firestore
                  final doc = await FirebaseFirestore.instance
                      .collection('settings')
                      .doc('contact_details')
                      .get();

                  final whatsappNumber = doc.data()?['whatsapp_user_support_number'];
                  if (whatsappNumber == null || whatsappNumber.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Support number not found')),
                    );
                    return;
                  }

                  // 🔹 Clean the number (remove '+' for wa.me link)
                  final cleanNumber = whatsappNumber.replaceAll('+', '').trim();

                  // 🔹 Create WhatsApp deep link
                  final message = Uri.encodeComponent("Hey, I need help with my account 🐾");
                  final whatsappUrl = Uri.parse("https://wa.me/$cleanNumber?text=$message");

                  // 🔹 Open WhatsApp
                  if (await canLaunchUrl(whatsappUrl)) {
                    await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not open WhatsApp')),
                    );
                  }
                } catch (e) {
                  debugPrint('❌ Error opening WhatsApp support: $e');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Something went wrong. Please try again.')),
                  );
                }
              },
            ),

            Divider(),

            // HIDDEN SERVICES
            ListTile(
              title: Text('Hidden Services',
                  style: GoogleFonts.poppins(
                      fontSize: 18, fontWeight: FontWeight.w600)),
              trailing:
              Icon(Icons.keyboard_arrow_right, color: AppColors.primary),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => HiddenServicesPage())),
            ),
            FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('settings')
                  .doc('links')
                  .get(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return SizedBox();

                final data = snapshot.data!.data() as Map<String, dynamic>?;
                final gptData = data?['myfellowpet_gpt'];

                if (gptData == null) return SizedBox();

                final bool isActive = gptData['active'] == true;
                final String? link = gptData['link'];
                final Timestamp? ts = gptData['ts'];

                if (!isActive || link == null || link.isEmpty) return SizedBox();

                // NEW badge check
                bool showNew = false;
                if (ts != null) {
                  final now = DateTime.now();
                  final created = ts.toDate();
                  final diff = now.difference(created).inDays;
                  print("TS => ${ts.toDate()} DIFF => ${DateTime.now().difference(ts.toDate()).inDays}");


                  if (diff <= 30) showNew = true;
                }

                return Column(
                  children: [
                    Divider(),  // <-- show divider above tile

                    ListTile(
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Expanded(
                            child: Text(
                              'MyFellowPet Intelligence',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),

                          if (showNew)
                            Container(
                              margin: EdgeInsets.only(left: 8),
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.accentColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "NEW",
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      trailing:
                      Icon(Icons.keyboard_arrow_right, color: AppColors.primary),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ConnectAIPage()),
                      ),
                    ),
                  ],
                );
              },
            ),
            /*Divider(),

            ListTile(
              title: Text(
                'MyFellowPet Intelligence',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: Icon(Icons.keyboard_arrow_right, color: AppColors.primary),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AiChatPage()),
              ),
            ),*/

            Divider(),



            // SIGN OUT
            ListTile(
              leading: Icon(Icons.logout, color: AppColors.error),
              title: Text(
                'Sign Out',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
              onTap: () => _showWarningDialog(
                context: context,
                message: 'Are you sure you want to log out?',
              ),
            ),
            Divider(),

            ListTile(
              leading: Icon(Icons.delete, color: AppColors.error),
              title: Text(
                'Delete Account',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                _showDeleteAccountDialog(context);
              },

            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                Icon(Icons.warning_amber_rounded,
                    size: 48, color: Colors.red.shade600),

                const SizedBox(height: 16),

                Text(
                  "Delete Your Account?",
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 12),

                Text(
                  "This action is permanent. You will be redirected to the account deletion page.",
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // CANCEL BUTTON
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        "Cancel",
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // PROCEED BUTTON
                    ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);

                        try {
                          final doc = await FirebaseFirestore.instance
                              .collection('settings')
                              .doc('links')
                              .get();

                          final deleteLink = doc.data()?['delete_user_account'];

                          if (deleteLink == null || deleteLink.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Something went wrong. Try again.')),
                            );
                            return;
                          }

                          final uri = Uri.parse(deleteLink);

                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Something went wrong. Try again.')),
                            );
                          }
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Something went wrong. Try again.')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 10),
                      ),
                      child: Text(
                        "Proceed",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }


  void _showWarningDialog({
    required BuildContext context,
    required String message,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 48, color: Color(0xFF00C2CB)),
              SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => _signOut(),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Color(0xFF00C2CB)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: Text('OK', style: TextStyle(color: Color(0xFF00C2CB))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}