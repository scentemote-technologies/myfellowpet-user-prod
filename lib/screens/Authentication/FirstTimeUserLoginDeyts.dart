import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart'; // Import for Cloud Functions
import 'package:recaptcha_enterprise_flutter/recaptcha_enterprise.dart';
import 'package:recaptcha_enterprise_flutter/recaptcha_action.dart';

// Placeholder imports (Replace with your actual paths)
import '../../app_colors.dart';
import '../HomeScreen/HomeScreen.dart';
import '../../main.dart';

class UserDetailsPage extends StatefulWidget {
  final String phoneNumber;
  const UserDetailsPage({Key? key, required this.phoneNumber}) : super(key: key);

  @override
  State<UserDetailsPage> createState() => _UserDetailsPageState();
}

class _UserDetailsPageState extends State<UserDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _pinCtl = TextEditingController();
  final _confirmPinCtl = TextEditingController();

  bool _saving = false;
  bool _isSendingOtp = false; // Loading state for OTP email
  bool _isEmailVerified = false; // Has the user verified the email?

  // --- Colors ---
  static const Color primaryTeal = Color(0xFF2CB4B6);
  static const Color neutralDark = Color(0xFF37474F);
  static const Color backgroundLight = Color(0xFFF0F4F8);

  @override
  void initState() {
    super.initState();
    // Reset verification if user changes email text
    _emailCtl.addListener(() {
      if (_isEmailVerified && _emailCtl.text.trim().isNotEmpty) {
        // Optional: You could allow them to edit, but you'd need to reset verification
        // For this implementation, we lock the field after verification (readOnly),
        // so this listener is mostly a fallback safety.
      }
    });
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _emailCtl.dispose();
    _pinCtl.dispose();
    _confirmPinCtl.dispose();
    super.dispose();
  }

  // --- 1. Cloud Function Logic: Send OTP ---
  Future<void> _sendOtp() async {
    final email = _emailCtl.text.trim();

    // Basic pre-validation before calling Cloud Function
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email to verify.')),
      );
      return;
    }

    setState(() => _isSendingOtp = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No user logged in');

      // Call the function 'sendSignupOtp' defined in your index.js
      await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('sendSignupOtp')
          .call({
        'uid': user.uid,
        'email': email,
      });

      if (!mounted) return;

      // Open the OTP entry dialog
      _showOtpDialog();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verification code sent to $email')),
      );

    } catch (e) {
      debugPrint('Error sending OTP: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send email. Please try again.')),
      );
    } finally {
      if(mounted) setState(() => _isSendingOtp = false);
    }
  }

  // --- 2. Cloud Function Logic: Verify OTP ---
  Future<void> _verifyOtp(String code, Function(bool) setDialogLoading) async {
    setDialogLoading(true);
    try {
      final user = FirebaseAuth.instance.currentUser;

      // Call the function 'verifySignupOtp' defined in your index.js
      await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('verifySignupOtp')
          .call({
        'uid': user?.uid,
        'code': code,
        'email': _emailCtl.text.trim(),
      });

      // If no error thrown, we are verified!
      setState(() {
        _isEmailVerified = true;
      });

      Navigator.pop(context); // Close Dialog

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email verified successfully! ✅'),
          backgroundColor: primaryTeal,
        ),
      );

    } on FirebaseFunctionsException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Invalid Code')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification failed. Try again.')),
      );
    } finally {
      setDialogLoading(false);
    }
  }

  // --- 3. OTP Input Dialog UI (UPDATED) ---
  void _showOtpDialog() {
    final _otpCtl = TextEditingController();
    bool _dialogLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false, // Prevents closing on outside click
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            // Get screen width for responsiveness
            final double width = MediaQuery.of(context).size.width;

            return AlertDialog(
              backgroundColor: Colors.white, // White Background
              surfaceTintColor: Colors.white, // Ensure no tint
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8), // Less curvy
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),

              // Wider dialog
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),

              title: Text(
                'Verify Your Email',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: neutralDark,
                ),
              ),

              content: SizedBox(
                width: width, // Takes available width up to insetPadding
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'We’ve sent a 6-digit verification code to:',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _emailCtl.text,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: primaryTeal,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // OTP Input Box
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8), // Less curvy
                        border: Border.all(color: Colors.grey.shade300),
                        color: Colors.grey.shade50,
                      ),
                      child: TextField(
                        controller: _otpCtl,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          letterSpacing: 16, // Wide spacing for digits
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: neutralDark,
                        ),
                        decoration: InputDecoration(
                          // Shows dashes instead of dots
                          hintText: '------',
                          hintStyle: GoogleFonts.poppins(
                              letterSpacing: 16,
                              color: Colors.grey.shade300,
                              fontWeight: FontWeight.w600
                          ),
                          counterText: '',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    Text(
                      'Code expires in 15 minutes',
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),

              actionsPadding: const EdgeInsets.all(24),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.poppins(
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                              fontSize: 15
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _dialogLoading
                            ? null
                            : () {
                          if (_otpCtl.text.length == 6) {
                            _verifyOtp(
                              _otpCtl.text,
                                  (val) => setStateDialog(() => _dialogLoading = val),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryTeal,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                        child: _dialogLoading
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                            : Text(
                          'Verify',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              fontSize: 15
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- 4. Main Submit Logic (Updated) ---
  Future<bool> _runRecaptcha() async {
    try {
      final token = await RecaptchaEnterprise.execute(RecaptchaAction.custom('CREATE_PROFILE'), timeout: 10000);
      return token.isNotEmpty;
    } catch (e) { return false; }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // --- OPTIONAL EMAIL LOGIC ---
    // If user entered an email but didn't verify it yet, block them.
    // If field is empty, let them pass.
    if (_emailCtl.text.trim().isNotEmpty && !_isEmailVerified) {
      _showEmailVerificationDialog(context);
      return;
    }


    setState(() => _saving = true);

    final success = await _runRecaptcha();
    if (!success) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('reCAPTCHA failed.')));
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final hashedPin = sha256.convert(utf8.encode(_pinCtl.text.trim())).toString();
      final hasEmail = _emailCtl.text.trim().isNotEmpty;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': _nameCtl.text.trim(),
        'phone_number': widget.phoneNumber,
        'email': hasEmail ? _emailCtl.text.trim() : null, // Save null if empty
        'email_verified': hasEmail, // True if they provided one (since we checked _isEmailVerified), False if they didn't
        'pin_set': true,
        'pin_hashed': hashedPin,
        'last_login': FieldValue.serverTimestamp(),
        'account_status': 'active',
        'created_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profile created successfully! 🎉', style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: primaryTeal,
        ),
      );

      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeWithTabs()));
    } catch (e) {
      debugPrint('Firestore Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Save failed. Please try again.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showEmailVerificationDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 25, 20, 15),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Header
                Row(
                  children: [
                    Icon(Icons.info_rounded, color: Colors.orange.shade700, size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Email Verification Required",
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 19,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Message
                Text(
                  "Please verify your email address or leave it empty.",
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 25),

                // Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(
                        "Close",
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        "OK",
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
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


  Widget _buildThemedTextFormField({
    required TextEditingController controller,
    required String labelText,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    int maxLength = 255,
    String? Function(String?)? validator,
    Widget? suffixIcon,
    bool readOnly = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      readOnly: readOnly,
      maxLength: maxLength == 255 ? null : maxLength,
      style: GoogleFonts.poppins(color: neutralDark, fontWeight: FontWeight.w500),
      cursorColor: primaryTeal,
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: GoogleFonts.poppins(color: neutralDark.withOpacity(0.7)),
        filled: true,
        fillColor: readOnly ? Colors.grey.shade200 : backgroundLight,
        counterText: maxLength == 6 ? '' : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.transparent)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: primaryTeal, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.red.shade600, width: 2)),
        suffixIcon: suffixIcon,
      ),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check if we should show the verify button (only if text exists and not yet verified)
    // We use a ValueListenableBuilder for the controller to react to text changes in real-time
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: Text('Account Setup', style: GoogleFonts.poppins(color: neutralDark, fontWeight: FontWeight.w600)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: neutralDark),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Complete Your Profile 🚀', style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w800, color: neutralDark)),
              const SizedBox(height: 8),
              Text('Secure your account. Email is optional but recommended for recovery.', style: GoogleFonts.poppins(color: neutralDark.withOpacity(0.6), fontSize: 13)),
              const SizedBox(height: 32),

              // --- 1. Name Field ---
              _buildThemedTextFormField(
                controller: _nameCtl,
                labelText: 'Full Name',
                validator: (v) => v!.isEmpty ? 'Please enter your full name.' : null,
              ),
              const SizedBox(height: 18),

              // --- 2. Email Field (Optional with Verify) ---
              ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _emailCtl,
                  builder: (context, value, child) {
                    final hasText = value.text.isNotEmpty;
                    final showVerifyBtn = hasText && !_isEmailVerified;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildThemedTextFormField(
                            controller: _emailCtl,
                            keyboardType: TextInputType.emailAddress,
                            labelText: 'Email Address (Optional)',
                            readOnly: _isEmailVerified, // Lock it once verified
                            validator: (v) {
                              if (v == null || v.isEmpty) return null; // Valid if empty
                              if (!v.contains('@') || !v.contains('.')) return 'Invalid email format.';
                              return null;
                            },
                            // Show green check if verified
                            suffixIcon: _isEmailVerified
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : null,
                          ),
                        ),

                        // The VERIFY Button (Only shows if user typed something and hasn't verified yet)
                        if (showVerifyBtn) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 56,
                            child: ElevatedButton(
                              onPressed: _isSendingOtp ? null : _sendOtp,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: neutralDark,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                              child: _isSendingOtp
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : Text('Verify', style: GoogleFonts.poppins(color: Colors.white)),
                            ),
                          ),
                        ]
                      ],
                    );
                  }
              ),

              if (_isEmailVerified)
                const Padding(
                  padding: EdgeInsets.only(top: 6, left: 4),
                  child: Text('Email verified', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                ),

              const SizedBox(height: 24),

              // --- 3. PIN Fields ---
              Text('Security PIN (6 Digits)', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: neutralDark)),
              const SizedBox(height: 12),
              _buildThemedTextFormField(
                controller: _pinCtl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                labelText: 'Create a secure 6-digit PIN',
                validator: (v) => v!.length == 6 ? null : 'PIN must be exactly 6 digits.',
              ),
              const SizedBox(height: 18),
              _buildThemedTextFormField(
                controller: _confirmPinCtl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                labelText: 'Confirm PIN',
                validator: (v) => v == _pinCtl.text ? null : 'PINs do not match.',
              ),

              const SizedBox(height: 40),

              // --- Submit Button ---
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryTeal,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                    'Create Account',
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}