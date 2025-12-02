import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_colors.dart';
import '../HomeScreen/HomeScreen.dart';
import 'FirstTimeUserLoginDeyts.dart';
import 'OtpInputPage.dart';

class PhoneAuthPage extends StatefulWidget {
  @override
  _PhoneAuthPageState createState() => _PhoneAuthPageState();
}

class _PhoneAuthPageState extends State<PhoneAuthPage> {
  final _phoneController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  bool _loading = false;
  bool _phoneExists = false;

  final Color _primaryColor = Color(0xFF25ADAD);
  final Color _secondaryColor = Color(0xFF1CB5A9); // Slightly different shade for gradient

  void _showError(String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
        actionsPadding: const EdgeInsets.fromLTRB(0, 0, 16, 10),

        title: Row(
          children: [
            Icon(Icons.error_rounded, color: Colors.red.shade600, size: 26),
            const SizedBox(width: 8),
            Text(
              'Error',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.red.shade600,
              ),
            ),
          ],
        ),

        content: Text(
          msg,
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: Colors.black87,
            height: 1.4,
          ),
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: Text(
              'OK',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryColor,
              ),
            ),
          )
        ],
      ),
    );
  }


  // NOTE: This _goNext function seems to be unused in the provided logic,
  // as navigation is handled after OTP verification in OtpInputPage.
  // I am leaving it in case it's needed elsewhere.
  void _goNext() {
    if (_phoneExists) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen()));
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => UserDetailsPage(phoneNumber: '+91${_phoneController.text.trim()}'),
        ),
      );
    }
  }

  Future<void> _checkAndSend() async {
    final phone = '+91' + _phoneController.text.trim();
    if (phone.isEmpty || _phoneController.text.trim().length != 10) {
      _showError('Please enter a valid 10-digit phone number.');
      return;
    }

    if (!mounted) return;
    setState(() => _loading = true);

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (cred) async {
          await _auth.signInWithCredential(cred);
          if (!mounted) return;

          // ✅ Navigate to OTP page on instant verification
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => OtpInputPage(
                initialVerificationId: '',
                phoneNumber: phone,
                phoneExists: false, // will check in OtpInputPage
              ),
            ),
          );
        },
        verificationFailed: (e) {
          if (!mounted) return;
          setState(() => _loading = false);
          _showError(e.message ?? 'OTP send failed. Please check your number.');
        },
        codeSent: (vid, _) async {
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OtpInputPage(
                initialVerificationId: vid,
                phoneNumber: phone,
                phoneExists: false, // will check in OtpInputPage
              ),
            ),
          );
          setState(() => _loading = false);
        },
        codeAutoRetrievalTimeout: (vid) {
          // We might not need to do anything here, but good practice to handle it
          if (mounted) setState(() => _loading = false);
        },
      );
    } catch (e) {
      print('Error sending code: $e');
      if (mounted) setState(() => _loading = false);
      _showError('Something went wrong. Please check your connection.');
    }
  }
  Future<String?> _getTermsLink() async {
    final doc = await FirebaseFirestore.instance
        .collection('settings')
        .doc('policies')
        .get();

    return doc.data()?['terms_and_conditions'] as String?;
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Changed to white for clean base
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 120),

            child: Column(
              children: [
                Padding(padding: EdgeInsets.fromLTRB(24, 0, 35, 0),
                child:  Image.asset(
                  'assets/web_app_logo.png', // TWEAK THIS: Your image asset path
                  height: 170, // Adjust height as needed
                )),
                // ─── Logo/App Name Header (Replaced with Image Asset) ──────
                // You must replace 'assets/images/logo.png' with your actual path.


                // ─── Input Card with Premium Styling ──────────────────────
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 40, horizontal: 28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.black87), // Subtle border
                    boxShadow: [
                      BoxShadow(
                        color: _primaryColor.withOpacity(0.1),
                        spreadRadius: 1,
                        blurRadius: 30,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [

                            Text(
                              "Enter your phone number to continue.",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade700,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 40),
                      // ─── IMPROVED TEXT FIELD ──────────────────────────────
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.transparent), // Remove border on container
                        ),
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 20, right: 8),
                              child: Text(
                                '+91',
                                style: GoogleFonts.poppins(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 30,
                              color: Colors.grey.shade300,
                              margin: EdgeInsets.symmetric(vertical: 10),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 12.0),
                                child: TextField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  maxLength: 10,
                                  cursorColor: _primaryColor, // 🔥 Makes the blinking cursor match brand color
// Added length limit
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                    fontSize: 18,
                                  ),
                                  decoration: InputDecoration(
                                    counterText: "", // Hides the counter
                                    hintText: 'Mobile Number',
                                    hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400, fontWeight: FontWeight.w400),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(vertical: 18),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // ───────────────────────────────────────────────────
                      SizedBox(height: 40),
                      // ─── GRADIENT BUTTON ──────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: _primaryColor.withOpacity(0.3),
                                blurRadius: 10,
                                offset: Offset(0, 5),
                              ),
                            ],
                            gradient: LinearGradient(
                              colors: [_primaryColor, _secondaryColor],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: ElevatedButton(
                            onPressed: _loading ? null : _checkAndSend,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent, // Important for gradient
                              shadowColor: Colors.transparent, // Remove default shadow
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: EdgeInsets.zero,
                            ),
                            child: _loading
                                ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
                            )
                                : Text(
                              'Continue',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 18),

                      FutureBuilder<String?>(
                        future: _getTermsLink(),
                        builder: (context, snapshot) {
                          final termsUrl = snapshot.data;

                          return GestureDetector(
                            onTap: () {
                              if (termsUrl != null) {
                                launchUrl(Uri.parse(termsUrl), mode: LaunchMode.externalApplication);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: RichText(
                                textAlign: TextAlign.center,
                                text: TextSpan(
                                  style: GoogleFonts.poppins(
                                    fontSize: 12.8,
                                    color: Colors.grey.shade600,
                                    height: 1.5,
                                  ),
                                  children: [
                                    const TextSpan(text: "By continuing, you agree to "),
                                    TextSpan(
                                      text: "MyFellowPet’s Terms & Conditions",
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF25ADAD),   // primary color
                                        decoration: TextDecoration.underline,  // underline link
                                      ),
                                    ),
                                    const TextSpan(text: " and all app policies."),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}