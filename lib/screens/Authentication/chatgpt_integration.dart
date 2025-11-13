import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:myfellowpet_user/app_colors.dart';

class ConnectAIPage extends StatefulWidget {
  const ConnectAIPage({super.key});

  @override
  State<ConnectAIPage> createState() => _ConnectAIPageState();
}

class _ConnectAIPageState extends State<ConnectAIPage> {
  String? _currentCode;
  bool _isLoading = false;
  DateTime? _expiresAt;

  // Generate a random 6-digit string
  String _generateRandomCode() {
    final random = Random();
    // Generates number between 100000 and 999999
    int code = 100000 + random.nextInt(900000);
    return code.toString();
  }

  Future<void> _generateAndSaveCode() async {
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final code = _generateRandomCode();
      final expiry = DateTime.now().add(const Duration(minutes: 10));

      // Structure suggested: Store in the user doc inside a map
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'magic_auth': {
          'code': code,
          'created_at': Timestamp.now(),
          'expires_at': Timestamp.fromDate(expiry),
          'used': false,
        }
      });

      setState(() {
        _currentCode = code;
        _expiresAt = expiry;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error generating code: $e")),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // Light grey background
      appBar: AppBar(
        title: Text(
          "Connect AI",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.black),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            Icon(Icons.auto_awesome, size: 60, color: AppColors.primaryColor),
            const SizedBox(height: 24),
            Text(
              "Link MyFellowPet to ChatGPT",
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF2D3436),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Generate a one-time code to verify your account securely within the chat.",
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 15,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 40),

            // The Code Display Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  if (_isLoading)
                    const CircularProgressIndicator()
                  else if (_currentCode != null) ...[
                    Text(
                      "YOUR MAGIC CODE",
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _currentCode!.substring(0, 3),
                          style: GoogleFonts.poppins(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryColor,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _currentCode!.substring(3),
                          style: GoogleFonts.poppins(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryColor,
                            letterSpacing: 4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Expires in 10 minutes",
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ] else
                    Text(
                      "Ready to generate",
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Colors.grey.shade400,
                      ),
                    ),
                ],
              ),
            ),

            const Spacer(),

            // Buttons
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _generateAndSaveCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _currentCode == null ? "Generate Code" : "Generate New Code",
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            if (_currentCode != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _currentCode!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Code copied!")),
                  );
                },
                icon: const Icon(Icons.copy, size: 18, color: Colors.black87),
                label: Text(
                  "Copy to Clipboard",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: Colors.black87),
                ),
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}