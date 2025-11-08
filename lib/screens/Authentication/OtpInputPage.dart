import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

// Assuming you have a HomeWithTabs screen defined and imported correctly
// If not, replace HomeWithTabs with the actual screen you want to use.
// import '../homescreen/HomeWithTabs.dart'; // <<< Ensure this import is correct
import '../../main.dart';
import '../HomeScreen/HomeScreen.dart'; // Keeping the original import for HomeScreen just in case
// For this example, I'll use HomeScreen as a placeholder for HomeWithTabs if it's not available.
// NOTE: You should change this import to '../homescreen/HomeWithTabs.dart'
// and replace HomeScreen with HomeWithTabs in the code below.

import 'FirstTimeUserLoginDeyts.dart';

class OtpInputPage extends StatefulWidget {
  final String initialVerificationId;
  final String phoneNumber;
  final bool phoneExists;

  const OtpInputPage({
    required this.initialVerificationId,
    required this.phoneNumber,
    required this.phoneExists,
  });

  @override
  _OtpInputPageState createState() => _OtpInputPageState();
}

class _OtpInputPageState extends State<OtpInputPage> {
  late String _verificationId;
  final _pinController = TextEditingController();
  bool _verifying = false;
  Timer? _timer;
  int _secondsLeft = 60;
  bool _canResend = false;

  final Color _primaryColor = Color(0xFF25ADAD);

  @override
  void initState() {
    super.initState();
    _verificationId = widget.initialVerificationId;
    _startTimer();
  }

  void _startTimer() {
    _secondsLeft = 60;
    _canResend = false;
    _timer?.cancel();
    if (mounted) {
      setState(() {});
    }
    _timer = Timer.periodic(Duration(seconds: 1), (t) {
      if (_secondsLeft == 0) {
        if (mounted) setState(() => _canResend = true);
        t.cancel();
      } else {
        if (mounted) setState(() => _secondsLeft--);
      }
    });
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(),
        ),
        backgroundColor: _primaryColor,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _verifyPin(String code) async {
    if (code.length != 6) return;
    setState(() => _verifying = true);

    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: code,
      );
      await FirebaseAuth.instance.signInWithCredential(cred);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackbar("Something went wrong. Please try again.");
        setState(() => _verifying = false);
        return;
      }

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

      if (userDoc.exists) {
        final data = userDoc.data()!;
        final lastLoginTs = data['last_login'] as Timestamp?;
        final accountStatus = (data['account_status'] as String?) ?? 'active';
        final pinSet = data['pin_set'] == true;

        // 🔒 If locked, show Try With PIN option instead of blocking
        if (accountStatus == 'locked') {
          setState(() => _verifying = false);

          showModalBottomSheet(
            context: context,
            shape: const RoundedRectangleBorder( // Added const
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            backgroundColor: Colors.white,
            builder: (_) => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, color: Colors.redAccent, size: 48), // Added const
                  const SizedBox(height: 12), // Added const
                  Text(
                    // --- THIS LINE IS NOW CENTERED ---
                    'Your account is temporarily locked.',
                    textAlign: TextAlign.center, // <--- ADDED textAlign: TextAlign.center
                    style: GoogleFonts.poppins(
                        fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6), // Added const
                  Text(
                    'But you can try verifying yourself with your 6-digit PIN.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24), // Added const
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context); // close bottom sheet
                        // NOTE: user and _primaryColor are undefined here,
                        // assuming they are available in the scope where this code is used.
                        // Navigator.push(
                        //   context,
                        //   MaterialPageRoute(
                        //     builder: (_) => PinGatePage(uid: user.uid),
                        //   ),
                        // );
                      },
                      style: ElevatedButton.styleFrom(
                        // backgroundColor: _primaryColor, // undefined
                        backgroundColor: Colors.teal, // Placeholder color
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Try with PIN',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12), // Added const
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.poppins(color: Colors.grey[700]),
                    ),
                  ),
                ],
              ),
            ),
          );

          return; // stop execution
        }

        // 🕒 Check days since last login
        final now = DateTime.now();
        final lastLogin = lastLoginTs?.toDate() ?? now;
        final diffDays = now.difference(lastLogin).inDays;

        if (pinSet && diffDays > 60) {
          // Redirect to PIN gate if inactive > 60 days
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => PinGatePage(uid: user.uid)),
          );
        } else {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
            'last_login': FieldValue.serverTimestamp(),
          });
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => HomeWithTabs()),
          );
        }
      } else {
        // 🆕 first-time signup
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => UserDetailsPage(phoneNumber: widget.phoneNumber),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ OTP Verification Error: $e');
      if (mounted) setState(() => _verifying = false);
      _showSnackbar('Invalid code or something went wrong. Please try again.');
    }
  }

  void _resendCode() {
    if (!_canResend) return;

    _showSnackbar('Resending code to ${widget.phoneNumber}...');
    _startTimer();

    FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: widget.phoneNumber,
      verificationCompleted: (_) {},
      verificationFailed: (e) {
        if (mounted) setState(() => _verifying = false);
        _showSnackbar('Resend failed: ${e.message}');
      },
      codeSent: (newVid, _) {
        if (mounted) {
          setState(() {
            _verificationId = newVid;
            _verifying = false;
          });
        }
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Verification',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: Colors.black87,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter the 6-digit verification code sent to',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey.shade600),
              ),
              Text(
                widget.phoneNumber,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              SizedBox(height: 48),

              // ─── OTP Pin Fields ──────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0),
                child: PinCodeTextField(
                  appContext: context,
                  length: 6,
                  controller: _pinController,
                  animationType: AnimationType.fade,
                  keyboardType: TextInputType.number,
                  autoFocus: true,
                  obscureText: false,
                  cursorColor: _primaryColor,
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  onChanged: (value) {},
                  onCompleted: _verifyPin,
                  pinTheme: PinTheme(
                    shape: PinCodeFieldShape.box,
                    fieldHeight: 55,
                    fieldWidth: 45,
                    borderRadius: BorderRadius.circular(12),
                    activeColor: _primaryColor, // Filled color for active field
                    selectedColor: _primaryColor.withOpacity(0.5), // Color when selected
                    inactiveColor: Colors.grey.shade300, // Border color for inactive
                    activeFillColor: _primaryColor.withOpacity(0.05), // Light background when active
                    selectedFillColor: Colors.white, // Background when selected
                    inactiveFillColor: Colors.grey.shade50, // Background for inactive
                    fieldOuterPadding: EdgeInsets.zero,
                  ),
                  textStyle: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  enableActiveFill: true,
                  autoDismissKeyboard: true,
                ),
              ),
              SizedBox(height: 32),

              // ─── Resend/Loading Section ──────────────────────────────
              Center(
                child: _verifying
                    ? CircularProgressIndicator(
                  color: _primaryColor,
                  strokeWidth: 4,
                )
                    : Column(
                  children: [
                    Text(
                      "Didn't receive the code?",
                      style: GoogleFonts.poppins(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _canResend
                        ? TextButton(
                      onPressed: _resendCode,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      child: Text(
                        'Resend Code',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _primaryColor,
                        ),
                      ),
                    )
                        : Text(
                      'Resend available in $_secondsLeft seconds',
                      style: GoogleFonts.poppins(
                        color: Colors.grey.shade500,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 💡 Added “Try with PIN” persistent option
                    TextButton(
                      onPressed: () async {
                        final user = FirebaseAuth.instance.currentUser;
                        if (user == null) {
                          _showSnackbar("Please verify your number again.");
                          return;
                        }

                        final userDoc = await FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .get();

                        if (userDoc.exists &&
                            (userDoc.data()?['account_status'] == 'locked')) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PinGatePage(uid: user.uid),
                            ),
                          );
                        } else {
                          _showSnackbar("Your account is not locked. Please verify OTP.");
                        }
                      },
                      child: Text(
                        'Try with your PIN instead',
                        style: GoogleFonts.poppins(
                          color: _primaryColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }
}


class PinGatePage extends StatefulWidget {
  final String uid;
  const PinGatePage({Key? key, required this.uid}) : super(key: key);

  @override
  State<PinGatePage> createState() => _PinGatePageState();
}

class _PinGatePageState extends State<PinGatePage> {
  final _pinCtl = TextEditingController();
  bool _loading = false;

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg, style: GoogleFonts.poppins())));

  Future<void> _verifyPin() async {
    final pin = _pinCtl.text.trim();
    if (pin.length != 6) return _snack('Enter 6-digit PIN');

    setState(() => _loading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .get();

      if (!doc.exists) {
        _snack('Account not found.');
        setState(() => _loading = false);
        return;
      }

      final storedPin = doc.data()?['pin_hashed'] ?? '';
      if (storedPin.isEmpty) {
        _snack('No PIN set for this account.');
        setState(() => _loading = false);
        return;
      }

      // ✅ Hash entered PIN and compare
      final enteredHash = sha256.convert(utf8.encode(pin)).toString();

      if (enteredHash != storedPin) {
        _snack('Wrong PIN');
        setState(() => _loading = false);
        return;
      }

      // ✅ PIN correct → update login time
      await doc.reference.update({
        'last_login': FieldValue.serverTimestamp(),
        'account_status': 'active',
      });

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeWithTabs()),
      );
    } catch (e) {
      _snack('Something went wrong.');
      print('❌ Error verifying PIN: $e');
    } finally {
      setState(() => _loading = false);
    }
  }


  Future<void> _forgotPin() async {
    print('🔹 [ForgotPin] Triggered for UID: ${widget.uid}');

    setState(() => _loading = true); // show loading CPI

    // Show a small loading dialog (CPI)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(
          color: const Color(0xFF25ADAD), // your primary color
          strokeWidth: 4,
        ),
      ),
    );

    try {
      // Fetch user document
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .get();

      if (!doc.exists) {
        print('❌ [ForgotPin] No user document found for UID: ${widget.uid}');
        Navigator.pop(context); // Close loader
        setState(() => _loading = false);
        return _snack('Account not found.');
      }

      final email = doc.data()?['email'];
      print('📧 [ForgotPin] Retrieved email: $email');

      if (email == null || email.isEmpty) {
        print('⚠️ [ForgotPin] No recovery email set for user.');
        Navigator.pop(context); // Close loader
        setState(() => _loading = false);
        return _snack('No recovery email set.');
      }

      print('🚀 [ForgotPin] Preparing to call Cloud Function (sendEmailOtp)...');

      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('sendEmailOtp');

      print('📡 [ForgotPin] Sending request → {uid: ${widget.uid}, email: $email}');
      final result = await callable.call({'uid': widget.uid, 'email': email});

      print('✅ [ForgotPin] Cloud Function response: ${result.data}');

      // Close the loader before navigation
      Navigator.pop(context);
      setState(() => _loading = false);

      // Navigate after successful call
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EmailOtpVerificationPage(uid: widget.uid, email: email),
        ),
      );
    } catch (e, st) {
      print('❌ [ForgotPin] Failed to send email OTP: $e');
      print('🧩 [StackTrace] $st');
      Navigator.pop(context); // Close loader
      setState(() => _loading = false);
      _snack('Could not send email. Please try again.');
    }
  }


  // 🔐 Try another way (Locks the account with professional feedback)
  // 🔐 Try another way (Locks the account with professional feedback)
  Future<void> _tryAnotherWay() async {
    // Define the color palette for a clean, secure look
    const Color primaryColor = Color(0xFF2CB4B6); // Professional Teal
    const Color dangerColor = Color(0xFFD32F2F); // Clear Red for critical action
    const Color neutralDark = Color(0xFF37474F); // Dark text
    const Color lightBackground = Color(0xFFF0F4F8); // A very light, professional blue-grey

    // 1. Update the account status in Firestore immediately
    await FirebaseFirestore.instance.collection('users').doc(widget.uid).update({
      'account_status': 'locked',
      'lockout_timestamp': FieldValue.serverTimestamp(),
    });

    // 2. Display the critical information dialog
    if (mounted) {
      showDialog(
        context: context,
        // Ensures the dialog itself is centered and allows for internal scrolling
        barrierDismissible: false,
        builder: (_) {
          // Use a LayoutBuilder to ensure the dialog content respects screen constraints
          return LayoutBuilder(
              builder: (context, constraints) {
                // Calculate responsive padding (e.g., smaller on very narrow screens)
                final double horizontalPadding = constraints.maxWidth < 400 ? 16.0 : 24.0;

                return AlertDialog(
                  // Max width control for large screens (desktop/tablet)
                  // Ensures the dialog never gets awkwardly wide
                  insetPadding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 24),

                  // Use a modern, deep rounded shape
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  backgroundColor: Colors.white,

                  // Wrap content in a SingleChildScrollView for responsiveness on small screens
                  content: SingleChildScrollView(
                    // We removed the title property and put it into the content for full control
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- Icon and Title Block ---
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.lock_person_rounded, color: dangerColor, size: 30),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Account Locked for Security',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700,
                                  color: neutralDark,
                                  fontSize: 20, // Slightly larger, clear title
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 30, thickness: 1, color: Colors.black12),

                        // --- Core Message ---
                        Text.rich(
                          TextSpan(
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              height: 1.6, // Increased line height for readability
                              color: neutralDark.withOpacity(0.8),
                            ),
                            children: [
                              const TextSpan(
                                text: 'To protect your data, your account has been temporarily locked. ',
                              ),
                              TextSpan(
                                text: 'A critical security notification has been sent to your registered email.',
                                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                              ),
                              const TextSpan(
                                text: '\n\nIf no action is taken, your account will be permanently deactivated and your number released for a new registration after ',
                              ),
                              TextSpan(
                                text: '72 hours.',
                                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: dangerColor),
                              ),
                              const TextSpan(
                                text: '\n\nPlease check your email immediately.',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // --- Important Note Block ---
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: lightBackground,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.warning_amber_rounded, color: dangerColor.withOpacity(0.8), size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Attempting further logins without the correct PIN will not reduce the 72-hour lockout period.",
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: neutralDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- Action Button ---
                  actions: [
                      SizedBox(
                        width: double.infinity, // Ensures the button stretches across the dialog width
                        child: ElevatedButton(
                          onPressed: () {
                            // Navigate completely away from the secure screen
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 3,
                          ),
                          child: Text(
                            'Okay',
                            style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                  // Remove actionsPadding if using a full-width button in the actions list
                  actionsPadding: EdgeInsets.only(left: horizontalPadding, right: horizontalPadding, bottom: 20, top: 0),
                );
              }
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Define your color palette for a smooth, decent, and professional look
    const Color primaryColor = Color(0xFF2CB4B6); // A calm, professional teal/cyan
    const Color accentColor = Color(0xFFE57373);  // A subtle, non-aggressive red for "Try another way"
    const Color neutralDark = Color(0xFF37474F);   // Dark text for high contrast
    const Color neutralGrey = Color(0xFF90A4AE);  // Light grey for hints/secondary text

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Confirm Your Identity',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: neutralDark,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0, // Removes the shadow for a cleaner look
        iconTheme: const IconThemeData(color: neutralDark),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Main Instruction Text ---
            Text(
              'For your security, please enter your 6-digit PIN to continue.',
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: neutralDark,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),

            // --- PIN Input Field ---
            TextField(
              cursorColor: primaryColor,
              controller: _pinCtl,
              maxLength: 6,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center, // Center the input for better visibility of 6 digits
              style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: primaryColor),
              obscureText: true, // Use dots for security
              decoration: InputDecoration(
                counterText: '',
                hintText: '• • • • • •', // Visual hint
                hintStyle: GoogleFonts.poppins(fontSize: 24, color: neutralGrey.withOpacity(0.5)),
                contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: neutralGrey.withOpacity(0.5), width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: primaryColor, width: 2), // Highlight when focused
                ),
              ),
            ),
            const SizedBox(height: 24),

            // --- Continue Button (Primary Action) ---
            ElevatedButton(
              onPressed: _loading ? null : _verifyPin,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52), // Slightly taller button
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 4, // Subtle lift
                shadowColor: primaryColor.withOpacity(0.4),
              ),
              child: _loading
                  ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              )
                  : Text(
                'Continue',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // --- Secondary Actions ---
            TextButton(
              onPressed: _forgotPin,
              child: Text(
                'Forgot PIN?',
                style: GoogleFonts.poppins(
                  color: neutralDark.withOpacity(0.8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: _tryAnotherWay,
              child: Text(
                'Try another way',
                style: GoogleFonts.poppins(
                  color: accentColor,
                  fontWeight: FontWeight.w600, // Stronger emphasis for an alternative
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class EmailOtpVerificationPage extends StatefulWidget {
  final String uid;
  final String email;

  const EmailOtpVerificationPage({
    Key? key,
    required this.uid,
    required this.email,
  }) : super(key: key);

  @override
  State<EmailOtpVerificationPage> createState() => _EmailOtpVerificationPageState();
}

class _EmailOtpVerificationPageState extends State<EmailOtpVerificationPage> {
  final _otpCtl = TextEditingController();
  bool _verifying = false;
  bool _resending = false;

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg, style: GoogleFonts.poppins())),
  );
// 🔹 Verify the OTP code via Cloud Function
  Future<void> _verifyOtp() async {
    final code = _otpCtl.text.trim();
    print('🔹 [VerifyOtp] Entered code: $code');

    if (code.length != 6) {
      print('⚠️ [VerifyOtp] Invalid code length: ${code.length}');
      return _snack('Enter a valid 6-digit code.');
    }

    setState(() => _verifying = true);

    try {
      print('🚀 [VerifyOtp] Calling Cloud Function: verifyUserEmailOtp');
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('verifyUserEmailOtp');

      print('📡 [VerifyOtp] Sending data → {code: $code, uid: ${widget.uid}}');
      final result = await callable.call({'code': code, 'uid': widget.uid});

      print('✅ [VerifyOtp] Function response: ${result.data}');

      if (result.data['success'] == true) {
        print('🎉 [VerifyOtp] OTP verified successfully! Updating Firestore user doc...');

        await FirebaseFirestore.instance.collection('users').doc(widget.uid).update({
          'account_status': 'active',
          'last_login': FieldValue.serverTimestamp(),
        });

        print('✅ [VerifyOtp] Firestore user document updated!');
        _snack('Email verified successfully!');

        print('➡️ [VerifyOtp] Navigating to HomeWithTabs...');
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => HomeWithTabs()),
              (_) => false,
        );
      } else {
        print('❌ [VerifyOtp] Verification failed with message: ${result.data['message']}');
        _snack(result.data['message'] ?? 'Invalid code.');
      }
    } catch (e, st) {
      print('🔥 [VerifyOtp] ERROR: $e');
      print('🧩 [StackTrace] $st');
      _snack('Invalid or expired code. Please try again.');
    } finally {
      print('🕓 [VerifyOtp] Verification process completed.');
      setState(() => _verifying = false);
    }
  }

  // 🔹 Resend new OTP
  Future<void> _resendOtp() async {
    setState(() => _resending = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('sendEmailOtp');
      await callable.call({'uid': widget.uid, 'email': widget.email});
      _snack('New code sent to ${widget.email}');
    } catch (e) {
      debugPrint('⚠️ Resend error: $e');
      _snack('Could not resend code. Try again.');
    } finally {
      setState(() => _resending = false);
    }
  }

  // 🔐 Try another way (Locks the account with professional feedback)
  Future<void> _tryAnotherWay() async {
    // Define the colors for consistency and decency
    const Color primaryColor = Color(0xFF2CB4B6); // Professional Teal
    const Color dangerColor = Color(0xFFD32F2F); // Clear Red for critical action
    const Color neutralDark = Color(0xFF37474F); // Dark text

    // 1. Update the account status in Firestore immediately
    await FirebaseFirestore.instance.collection('users').doc(widget.uid).update({
      'account_status': 'locked',
      'lockout_timestamp': FieldValue.serverTimestamp(), // Optional but highly recommended for tracking 72 hours
    });

    // 2. Display the critical information dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false, // User must acknowledge the lock
        builder: (_) => AlertDialog(
          // Use a modern, rounded shape
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),

          // --- Title Section ---
          title: Row(
            children: [
              Icon(Icons.lock_person_rounded, color: dangerColor, size: 28),
              const SizedBox(width: 10),
              Text(
                'Account Locked for Security',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  color: neutralDark,
                  fontSize: 18,
                ),
              ),
            ],
          ),

          // --- Content Section ---
          content: Text.rich(
            TextSpan(
              style: GoogleFonts.poppins(fontSize: 15, height: 1.5, color: neutralDark.withOpacity(0.8)),
              children: [
                const TextSpan(
                  text: 'To protect your data, your account has been temporarily locked. ',
                ),
                TextSpan(
                  text: 'A critical security notification has been sent to your registered email.',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
                const TextSpan(
                  text: '\n\nIf no action is taken, your account will be permanently deactivated and your number released for a new registration after ',
                ),
                TextSpan(
                  text: '72 hours.',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: dangerColor),
                ),
                const TextSpan(
                  text: '\n\nPlease check your email immediately.',
                ),
              ],
            ),
          ),

          // --- Action Button ---
          actions: [
            TextButton(
              onPressed: () {
                // Navigate completely away from the secure screen
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: Text(
                'ACKNOWLEDGE & EXIT',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                  fontSize: 16,
                ),
              ),
            ),
          ],
          actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF25ADAD);
    return Scaffold(
      appBar: AppBar(
        title: Text('Verify your email', style: GoogleFonts.poppins()),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'We’ve sent a 6-digit verification code to:',
              style: GoogleFonts.poppins(fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              widget.email,
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 40),
            TextField(
              controller: _otpCtl,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                hintText: 'Enter 6-digit code',
                counterText: '',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _verifying ? null : _verifyOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _verifying
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text('Verify', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _resending ? null : _resendOtp,
              child: Text(
                _resending ? 'Resending...' : 'Resend new code',
                style: GoogleFonts.poppins(color: primaryColor, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _tryAnotherWay,
              child: Text(
                'Try another way',
                style: GoogleFonts.poppins(color: Colors.red.shade600, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PinVerificationPage extends StatefulWidget {
  final String phoneNumber;
  const PinVerificationPage({Key? key, required this.phoneNumber}) : super(key: key);

  @override
  State<PinVerificationPage> createState() => _PinVerificationPageState();
}

class _PinVerificationPageState extends State<PinVerificationPage> {
  final _pinCtl = TextEditingController();
  bool _loading = false;
  String? _errorText;

  Future<void> _verifyPin() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _errorText = 'User not logged in.');
        return;
      }

      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        setState(() => _errorText = 'Account not found.');
        return;
      }

      final pinHashed = doc['pin_hashed'] ?? '';
      if (pinHashed.isEmpty) {
        setState(() => _errorText = 'PIN not set.');
        return;
      }

      // Hash input PIN with SHA256
      final enteredHash = sha256.convert(utf8.encode(_pinCtl.text.trim())).toString();

      if (enteredHash == pinHashed) {
        // ✅ PIN correct
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'last_login': FieldValue.serverTimestamp(),
          'account_status': 'active',
        });

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomeWithTabs()),
        );
      } else {
        setState(() => _errorText = 'Incorrect PIN. Try again.');
      }
    } catch (e) {
      setState(() => _errorText = 'Error verifying PIN. Try again.');
      print(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF25ADAD);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Verify Your PIN', style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: teal,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Welcome back!', style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Please enter your 6-digit security PIN to continue.',
              style: GoogleFonts.poppins(color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _pinCtl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: 'Enter PIN',
                errorText: _errorText,
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _loading ? null : _verifyPin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: teal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text('Verify', style: GoogleFonts.poppins(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                final user = FirebaseAuth.instance.currentUser;
                if (user == null) return;

                final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
                final email = doc.data()?['email'] ?? '';

                if (email.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('No recovery email found', style: GoogleFonts.poppins())),
                  );
                  return;
                }

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EmailOtpVerificationPage(uid: user.uid, email: email),
                  ),
                );
              },
              child: Text('Forgot PIN?', style: GoogleFonts.poppins(color: teal)),
            ),
          ],
        ),
      ),
    );
  }
}