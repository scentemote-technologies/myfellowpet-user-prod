import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_colors.dart';

class LiveSearchBar extends StatefulWidget {
  // This callback function receives the search query from the text field
  final Function(String) onSearch;
  // ✅ NEW: Optional FocusNode to allow a parent to control the focus
  final FocusNode? focusNode;

  const LiveSearchBar({
    Key? key,
    required this.onSearch,
    this.focusNode, // ✅ The new parameter
  }) : super(key: key);

  @override
  _LiveSearchBarState createState() => _LiveSearchBarState();
}

class _LiveSearchBarState extends State<LiveSearchBar> {
  final TextEditingController _searchController = TextEditingController();
  // We use a late variable so we can either use the passed-in FocusNode or create a new one.
  late FocusNode _localFocusNode;

  @override
  void initState() {
    super.initState();
    // ✅ If a focusNode is provided, use it. Otherwise, create a new one.
    _localFocusNode = widget.focusNode ?? FocusNode();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    // Send the current text to the parent widget (BoardingHomepage)
    widget.onSearch(_searchController.text);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    // ✅ Only dispose of the FocusNode if we created it ourselves.
    // The parent is responsible for disposing of the one it passed in.
    if (widget.focusNode == null) {
      _localFocusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Replicating the container style of the original PetSearchBar
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      child: Container(
        width: double.infinity,
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.shade300,
            width: 1.5,
          ),
        ),

        // Use a TextField here instead of InkWell
        child: TextField(
          controller: _searchController,
          // ✅ Pass the _localFocusNode to the TextField
          focusNode: _localFocusNode,
          decoration: InputDecoration(
            border: InputBorder.none, // Remove default TextField underline
            hintText: 'Search for Daycare...',
            hintStyle: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
            icon: const Icon(Icons.search, color: AppColors.primaryColor),

            // Add a clear button that appears when text is present
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
              icon: const Icon(Icons.clear, color: Colors.grey),
              onPressed: () {
                _searchController.clear();
                widget.onSearch(''); // Clear search filter in the homepage
              },
            )
                : null,
          ),
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}