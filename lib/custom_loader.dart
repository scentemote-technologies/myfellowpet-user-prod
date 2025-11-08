
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Use a consistent color for the brand look
const Color kPrimaryBrandColor = Color(0xFF25ADAD);

class CustomLoader extends StatelessWidget {
  final String message;
  final bool showIndicator;

  const CustomLoader({
    super.key,
    this.message = 'Loading data, please wait...',
    this.showIndicator = true,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        // Stylish Card Design
        padding: const EdgeInsets.all(24.0),
        margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 15,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showIndicator) ...[
              // Custom CircularProgressIndicator style
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  valueColor: const AlwaysStoppedAnimation<Color>(kPrimaryBrandColor),
                  backgroundColor: kPrimaryBrandColor.withOpacity(0.2),
                  strokeWidth: 4.0,
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Poppins Text Style
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
