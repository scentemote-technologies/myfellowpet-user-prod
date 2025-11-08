import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:petproject_test_g/main.dart'; // Ensure this is imported correctly if needed
// import '../HomeScreen/HomeScreen.dart'; // Ensure this is imported correctly if needed

// Placeholder imports for demonstration (replace with your actual imports)
import '../HomeScreen/HomeScreen.dart'; // Assuming this points to a valid file
import '../../main.dart'; // Assuming this points to a valid file

// External dependencies (assuming these are already configured)
import 'package:recaptcha_enterprise_flutter/recaptcha_enterprise.dart';
import 'package:recaptcha_enterprise_flutter/recaptcha_action.dart';

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

  // --- Color Palette and Constants ---
  static const Color primaryTeal = Color(0xFF2CB4B6); // A softer, modern teal
  static const Color accentYellow = Color(0xFFFFCC80); // Subtle accent color
  static const Color neutralDark = Color(0xFF37474F); // Dark text
  static const Color backgroundLight = Color(0xFFF0F4F8); // Very light background for fields

  @override
  void dispose() {
    _nameCtl.dispose();
    _emailCtl.dispose();
    _pinCtl.dispose();
    _confirmPinCtl.dispose();
    super.dispose();
  }

  // --- Unchanged Logic for Recaptcha and Submission ---
  // (Logic remains the same, only UI elements are changed in build method)

  Future<bool> _runRecaptcha() async {
    try {
      final token = await RecaptchaEnterprise.execute(
        RecaptchaAction.custom('CREATE_PROFILE'),
        timeout: 10000,
      );
      return token.isNotEmpty;
    } catch (e) {
      debugPrint('reCAPTCHA failed: $e');
      return false;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final success = await _runRecaptcha();
    if (!success) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('reCAPTCHA validation failed. Try again.', style: GoogleFonts.poppins())),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User not logged in. Try again.')),
      );
      return;
    }

    try {
      final hashedPin = sha256.convert(utf8.encode(_pinCtl.text.trim())).toString();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': _nameCtl.text.trim(),
        'phone_number': widget.phoneNumber,
        'email': _emailCtl.text.trim(),
        'pin_set': true,
        'pin_hashed': hashedPin,
        'last_login': FieldValue.serverTimestamp(),
        'account_status': 'active',
        'locked_until': null,
        'created_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profile created successfully! 🎉', style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: primaryTeal,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Make sure HomeWithTabs is a valid class name in your project
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeWithTabs()),
      );
    } catch (e) {
      debugPrint('Firestore Save Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed. Please try again.', style: GoogleFonts.poppins()),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // --- Reusable Themed Text Field Widget ---
  Widget _buildThemedTextFormField({
    required TextEditingController controller,
    required String labelText,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    int maxLength = 255,
    String? Function(String?)? validator,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLength: maxLength == 255 ? null : maxLength, // Use null for standard max length
      style: GoogleFonts.poppins(color: neutralDark, fontWeight: FontWeight.w500),
      cursorColor: primaryTeal,
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: GoogleFonts.poppins(color: neutralDark.withOpacity(0.7)),
        filled: true,
        fillColor: backgroundLight,
        counterText: maxLength == 6 ? '' : null, // Only hide for PIN fields

        // --- Input Borders (Focus on Clean Lines) ---
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none, // Hide default border
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.transparent), // Looks cleaner
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryTeal, width: 2), // Focus glow
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.shade600, width: 2),
        ),
        suffixIcon: suffixIcon,
      ),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        // Use a clean, non-colored background and subtle shadow
        backgroundColor: Colors.white,
        elevation: 1, // Subtle elevation for depth
        shadowColor: Colors.black.withOpacity(0.05),
        title: Text('Account Setup', style: GoogleFonts.poppins(color: neutralDark, fontWeight: FontWeight.w600)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: neutralDark),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Header Text ---
              Text(
                'Complete Your Profile 🚀',
                style: GoogleFonts.poppins(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: neutralDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Just a few quick steps to secure and personalize your account.',
                style: GoogleFonts.poppins(color: neutralDark.withOpacity(0.6), fontSize: 15),
              ),
              const SizedBox(height: 32),

              // --- 1. Name Field ---
              _buildThemedTextFormField(
                controller: _nameCtl,
                labelText: 'Full Name',
                validator: (v) => v!.isEmpty ? 'Please enter your full name.' : null,
              ),
              const SizedBox(height: 18),

              // --- 2. Email Field ---
              _buildThemedTextFormField(
                controller: _emailCtl,
                keyboardType: TextInputType.emailAddress,
                labelText: 'Email Address',
                validator: (v) {
                  if (v!.isEmpty) return 'Email is required.';
                  if (!v.contains('@') || !v.contains('.')) return 'Please enter a valid email.';
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // --- PIN Section Header ---
              Text(
                'Security PIN (6 Digits)',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: neutralDark,
                ),
              ),
              const SizedBox(height: 12),

              // --- 3. Create PIN Field ---
              _buildThemedTextFormField(
                controller: _pinCtl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                labelText: 'Create a secure 6-digit PIN',
                validator: (v) => v!.length == 6 ? null : 'PIN must be exactly 6 digits.',
                suffixIcon: const Icon(Icons.lock_rounded, color: primaryTeal, size: 20),
              ),
              const SizedBox(height: 18),

              // --- 4. Confirm PIN Field ---
              _buildThemedTextFormField(
                controller: _confirmPinCtl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                labelText: 'Confirm PIN',
                validator: (v) => v == _pinCtl.text ? null : 'PINs do not match.',
                suffixIcon: const Icon(Icons.check_circle_outline, color: primaryTeal, size: 20),
              ),
              const SizedBox(height: 10),

              // --- PIN Hint Text ---
              Text(
                'This PIN secures your account for transactions and long periods of inactivity.',
                style: GoogleFonts.poppins(fontSize: 13, color: neutralDark.withOpacity(0.5)),
              ),

              const SizedBox(height: 40),

              // --- Submit Button (Primary Action) ---
              SizedBox(
                height: 54, // Slightly taller for better feel
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryTeal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), // Larger border radius
                    elevation: 4, // Subtle lift
                    shadowColor: primaryTeal.withOpacity(0.4),
                  ),
                  child: _saving
                      ? const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                  )
                      : Text(
                    'Create Account',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
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