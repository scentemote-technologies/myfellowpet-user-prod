
// lib/screens/Search Bars/pet_search_bar.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_colors.dart';
import '../Boarding/boarding_homepage.dart';
import '../Boarding/boarding_searchbar.dart';

class PetSearchBar extends StatelessWidget {
  const PetSearchBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Left & right padding of 16
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      child: Container(
        // Stretch to fill the padded width
        width: double.infinity,
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.shade300, // or any custom color
            width: 1.5,                  // thickness of the border
          ),
        ),

        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchResultsPage()),
            );
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.search, color: AppColors.primaryColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Search for Daycare...',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade600,
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

