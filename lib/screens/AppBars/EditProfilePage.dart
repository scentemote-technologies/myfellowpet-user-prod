import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart'; // Import Cloud Functions
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:myfellowpet_user/app_colors.dart';

class EditProfilePage extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> userData;

  const EditProfilePage({
    Key? key, // Added Key
    required this.uid,
    required this.userData,
  }) : super(key: key);

  @override
  _EditProfilePageState createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtl;
  late TextEditingController _emailCtl;
  late TextEditingController _maskedPhoneCtl;
  static const Color accent = Color(0xFF3D3D3D);
  static const Color teal = Color(0xFF25ADAD);
  static const Color neutralDark = Color(0xFF37474F); // Consistent with UserDetails

  File? _pdfReportFile;
  String? _pdfReportUrl; // from firestore


  // store originals for change detection
  late String _originalName;
  late String _originalEmail;

  // Verification Logic
  String? _verifiedTempEmail; // Tracks the specifically verified new email
  bool _isEmailVerified = true; // Defaults to true (original is trusted)
  bool _isSendingOtp = false;

  bool _saving = false;
  bool _canEdit = false;
  int _daysLeft = 0;

  late String _reportType;              // “pdf”, “manually_entered”, or “never”
  late List<Map<String,dynamic>> _vaccines;

  @override
  void initState() {
    super.initState();

    // grab and store original values
    _originalName = widget.userData['name'] as String? ?? '';
    _originalEmail = widget.userData['email'] as String? ?? '';

    final rawPhone =
    (widget.userData['phone_number'] as String? ?? '').replaceFirst('+91', '');

    _nameCtl = TextEditingController(text: _originalName);
    _emailCtl = TextEditingController(text: _originalEmail);
    _maskedPhoneCtl = TextEditingController(text: rawPhone);

    // --- Email Change Listener ---
    _emailCtl.addListener(() {
      final current = _emailCtl.text.trim();
      bool isValid = false;

      // 1. Valid if empty (optional)
      if (current.isEmpty) {
        isValid = true;
      }
      // 2. Valid if it matches the original email (no change)
      else if (current == _originalEmail) {
        isValid = true;
      }
      // 3. Valid if it matches the newly verified email
      else if (current == _verifiedTempEmail) {
        isValid = true;
      }

      // Only update state if status changes to avoid rebuild loops
      if (_isEmailVerified != isValid) {
        setState(() => _isEmailVerified = isValid);
      }
    });

    _checkLastChange();
    _pdfReportUrl = widget.userData['report_url'] as String?;

    _reportType = widget.userData['report_type'] as String? ?? 'never';
    _vaccines   = List<Map<String,dynamic>>.from(
        widget.userData['vaccines'] as List? ?? <Map<String,dynamic>>[]
    );
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _emailCtl.dispose();
    _maskedPhoneCtl.dispose();
    super.dispose();
  }

  // --- 1. Cloud Function Logic: Send OTP ---
  Future<void> _sendOtp() async {
    final email = _emailCtl.text.trim();

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

      // Reuse the same Cloud Function
      await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('sendSignupOtp')
          .call({
        'uid': user.uid,
        'email': email,
      });

      if (!mounted) return;

      _showOtpDialog();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verification code sent to $email')),
      );

    } catch (e) {
      debugPrint('Error sending OTP: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send email. Please try again.')),
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

      await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('verifySignupOtp')
          .call({
        'uid': user?.uid,
        'code': code,
        'email': _emailCtl.text.trim(),
      });

      // Verification Successful
      setState(() {
        _verifiedTempEmail = _emailCtl.text.trim(); // Mark this specific email as verified
        _isEmailVerified = true;
      });

      Navigator.pop(context); // Close Dialog

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email verified successfully! ✅'),
          backgroundColor: teal,
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

  // --- 3. OTP Dialog UI ---
  void _showOtpDialog() {
    final _otpCtl = TextEditingController();
    bool _dialogLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final double width = MediaQuery.of(context).size.width;

            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),

              title: Text(
                'Verify Your Email',
                style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: neutralDark),
              ),

              content: SizedBox(
                width: width,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('We’ve sent a 6-digit verification code to:', textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54)),
                    const SizedBox(height: 4),
                    Text(_emailCtl.text, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: teal)),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                        color: Colors.grey.shade50,
                      ),
                      child: TextField(
                        controller: _otpCtl,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(letterSpacing: 16, fontSize: 24, fontWeight: FontWeight.w600, color: neutralDark),
                        decoration: InputDecoration(
                          hintText: '------',
                          hintStyle: GoogleFonts.poppins(letterSpacing: 16, color: Colors.grey.shade300, fontWeight: FontWeight.w600),
                          counterText: '',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Code expires in 15 minutes', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
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
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.grey.shade700, fontWeight: FontWeight.w600, fontSize: 15)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _dialogLoading ? null : () {
                          if (_otpCtl.text.length == 6) {
                            _verifyOtp(_otpCtl.text, (val) => setStateDialog(() => _dialogLoading = val));
                          }
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(vertical: 14), elevation: 0),
                        child: _dialogLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text('Verify', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 15)),
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

  Future<void> _checkLastChange() async {
    final docRef = FirebaseFirestore.instance.doc('users/${widget.uid}');
    final snap = await docRef.get();
    final ts = snap.data()?['change_timestamp'] as Timestamp?;

    if (ts == null) {
      setState(() => _canEdit = true);
      return;
    }

    final last = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(last).inDays;

    if (diff >= 14) {
      setState(() => _canEdit = true);
    } else {
      setState(() {
        _canEdit = false;
        _daysLeft = 14 - diff;
      });
    }
  }

  void _showConfirmDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevents tapping outside to dismiss
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        title: Text(
          'Confirm Changes',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        content: RichText(
          text: TextSpan(
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.black87,
              height: 1.4,
            ),
            children: [
              const TextSpan(text: 'You can change your profile only '),
              TextSpan(
                text: 'once every 14 days',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const TextSpan(text: '. '),
              TextSpan(
                text: 'Are you sure ',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const TextSpan(text: 'you want to proceed?'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(), // just close
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black54,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _save();
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text(
              'Yes, proceed',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF00C2CB), // for example your teal accent
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String> _uploadPdf(File f) async {
    final user = FirebaseAuth.instance.currentUser!;
    final fn = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final ref = FirebaseStorage.instance.ref().child('pets/reports/$fn');
    await ref.putFile(f);
    return ref.getDownloadURL();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // --- CHECK VERIFICATION BEFORE SAVING ---
    if (!_isEmailVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please verify your new email address first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final name = _nameCtl.text.trim();
    final email = _emailCtl.text.trim();

    // extra guard: shouldn't happen thanks to onPressed check
    if (name == _originalName && email == _originalEmail) return;

    final docRef = FirebaseFirestore.instance.doc('users/${widget.uid}');

    // Only save email if it's not empty, otherwise null
    final emailToSave = email.isEmpty ? null : email;
    final isEmailVerified = email.isNotEmpty; // If saving a non-empty email here, it must be verified due to check above.

    final data = {
      'name': name,
      'email': emailToSave,
      'email_verified': isEmailVerified,
      'change_timestamp': FieldValue.serverTimestamp(),
      'report_type': _reportType,
      if (_reportType == 'manually_entered') 'vaccines': _vaccines,
      if (_reportType == 'pdf') 'report_url': await _uploadPdf(_pdfReportFile!),
    };

    setState(() => _saving = true);
    try {
      await docRef.update(data);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Profile updated successfully',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
      Navigator.pop(context);
    } catch (e, stack) {
      debugPrint('❌ Firestore update FAILED: $e');
      debugPrintStack(stackTrace: stack);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to save. Please try again.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF6F6F6);
    const Color teal = Color(0xFF25ADAD);

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Profile', style: GoogleFonts.poppins()),
        backgroundColor: backgroundColor,
        elevation: 1,
        iconTheme: IconThemeData(color: Colors.black87),
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Name Field
                TextFormField(
                  cursorColor: AppColors.primaryColor,
                  controller: _nameCtl,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    labelStyle: GoogleFonts.poppins(),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: GoogleFonts.poppins(),
                  validator: (v) =>
                  v!.trim().isEmpty ? 'Enter your name' : null,
                ),
                const SizedBox(height: 16),

                // --- Email Field (Optional with Verify) ---
                // Inside your build method...

// --- Email Field (Optional with Verify) ---
                ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _emailCtl,
                    builder: (context, value, child) {
                      final currentText = value.text.trim();

                      // 1. UPDATE THIS LINE: Add "&& _canEdit"
                      // This ensures the Verify button never shows if the profile is locked
                      final showVerifyBtn = currentText.isNotEmpty &&
                          !_isEmailVerified &&
                          currentText != _originalEmail &&
                          _canEdit;

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _emailCtl,
                              keyboardType: TextInputType.emailAddress,

                              // 2. ADD THIS LINE:
                              // This grays out and disables typing if the 14-day lock is active
                              enabled: _canEdit,

                              // Keep your existing readOnly logic for when verification is done
                              readOnly: _isEmailVerified && currentText != _originalEmail,

                              decoration: InputDecoration(
                                labelText: 'Email',
                                labelStyle: GoogleFonts.poppins(),
                                filled: true,
                                // Update fill color logic to look "disabled" if !_canEdit
                                fillColor: (!_canEdit || (_isEmailVerified && currentText != _originalEmail))
                                    ? Colors.grey.shade200
                                    : Colors.grey.shade100,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                suffixIcon: _isEmailVerified
                                    ? const Icon(Icons.check_circle, color: Colors.green)
                                    : null,
                              ),
                              style: GoogleFonts.poppins(),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return null;
                                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v)) return 'Enter a valid email';
                                return null;
                              },
                            ),
                          ),

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
                if (_isEmailVerified && _emailCtl.text.trim() != _originalEmail && _emailCtl.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text('Email verified', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),

                const SizedBox(height: 16),

                // Phone Field (masked & disabled)
                TextFormField(
                  controller: _maskedPhoneCtl,
                  enabled: false,
                  decoration: InputDecoration(
                    labelText: 'Mobile Number',
                    labelStyle: GoogleFonts.poppins(),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: GoogleFonts.poppins(color: Colors.black87),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Phone number cannot be changed. If you want to use a new number, please log in again with that number.',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),


                // If too soon, show days-left note
                if (!_canEdit)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'You can update your profile again in $_daysLeft days.',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),


                const SizedBox(height: 24),

                // Save Button
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: (_saving || !_canEdit)
                        ? null
                        : () {
                      // Check if fields are valid first
                      if (!_formKey.currentState!.validate()) return;

                      // Check verification before opening confirm dialog
                      if (!_isEmailVerified) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please verify your new email address.')),
                        );
                        return;
                      }

                      final name = _nameCtl.text.trim();
                      final email = _emailCtl.text.trim();
                      if (name == _originalName &&
                          email == _originalEmail) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'No changes to save',
                              style: GoogleFonts.poppins(),
                            ),
                          ),
                        );
                        return;
                      }
                      _showConfirmDialog();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: teal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      disabledBackgroundColor: teal.withOpacity(0.5), // Visual feedback for disabled state
                    ),
                    child: _saving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                      'Save Changes',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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