import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Assuming you have these defined somewhere
class AppColors {
  static const primary = Color(0xFF008585);
  static const primaryLight = Color(0xFFE0F2F2);
  static const text = Colors.black87;
}

class AppDimensions {
  static const double radiusMd = 12.0;
  static const double spacingMd = 12.0;
  static const double spacingLg = 24.0;
}

// Mocked for demonstration
class AddPetPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text('Add Pet')));
}
class StageProgressBar extends StatelessWidget {
  final int currentStage;
  final int totalStages;
  final Function(int) onStepTap;
  const StageProgressBar({required this.currentStage, required this.totalStages, required this.onStepTap});
  @override
  Widget build(BuildContext context) => Container(height: 20, color: Colors.grey[300]);
}

// Your refactored widget
class PetSelectorWidget extends StatefulWidget {
  @override
  _PetSelectorWidgetState createState() => _PetSelectorWidgetState();
}

class _PetSelectorWidgetState extends State<PetSelectorWidget> {
  // Mock data for demonstration
  final List<Map<String, dynamic>> _allPets = [
    {'pet_id': '1', 'name': 'Buddy', 'pet_image': 'https://i.imgur.com/bB4Y2Qw.jpg'},
    {'pet_id': '2', 'name': 'Lucy', 'pet_image': 'https://i.imgur.com/p1u42hE.jpg'},
    {'pet_id': '3', 'name': 'Max', 'pet_image': 'https://i.imgur.com/sC4j4iS.jpg'},
    {'pet_id': '4', 'name': 'Bella', 'pet_image': null}, // Pet with no image
  ];
  final Set<String> _selectedPetIds = {'1'};
  String _searchTerm = '';
  final TextEditingController _searchController = TextEditingController();

  // Mock methods
  void _handleStepTap(int step) {}
  void _refreshAllPets() {}
  void _handlePetSelection(Map<String, dynamic> pet) {
    setState(() {
      final petId = pet['pet_id'];
      if (_selectedPetIds.contains(petId)) {
        _selectedPetIds.remove(petId);
      } else {
        _selectedPetIds.add(petId);
      }
    });
  }

  // Your main build method is now clean and high-level
  @override
  Widget build(BuildContext context) {
    // The filtering logic is clean and stays here
    final displayList = _searchTerm.isEmpty
        ? _allPets
        : _allPets.where((p) {
      return (p['name'] as String)
          .toLowerCase()
          .contains(_searchTerm.toLowerCase());
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingMd,
        vertical: AppDimensions.spacingLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Section
          Text(
            'Select a Pet',
            style: GoogleFonts.poppins(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          StageProgressBar(
            currentStage: 1, // Example value
            totalStages: 3,  // Example value
            onStepTap: _handleStepTap,
          ),
          const SizedBox(height: AppDimensions.spacingLg),

          // Search Bar Section
          _buildSearchBarAndRefresh(),
          const SizedBox(height: AppDimensions.spacingLg),

          // Pet Grid or Empty State
          displayList.isEmpty
              ? _buildEmptyState()
              : _buildPetGrid(displayList),
          const SizedBox(height: AppDimensions.spacingLg),

          // Add New Pet Button
          _buildAddPetButton(),
        ],
      ),
    );
  }

  /// Builds a stylish and modern search bar.
  Widget _buildSearchBarAndRefresh() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search your pets…',
              hintStyle: GoogleFonts.poppins(),
              prefixIcon: const Icon(Icons.search, color: AppColors.primary),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 15),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                borderSide: BorderSide.none, // Clean look
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                borderSide: const BorderSide(color: AppColors.primary, width: 2),
              ),
            ),
            onChanged: (term) => setState(() => _searchTerm = term),
          ),
        ),
        const SizedBox(width: AppDimensions.spacingMd),
        IconButton.filledTonal(
          icon: const Icon(Icons.refresh),
          onPressed: _refreshAllPets,
          tooltip: 'Refresh',
          style: IconButton.styleFrom(
            minimumSize: const Size(55, 55),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            ),
          ),
        ),
      ],
    );
  }

  /// Builds the responsive grid of pets.
  Widget _buildPetGrid(List<Map<String, dynamic>> displayList) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 160).floor().clamp(2, 4);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: displayList.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: AppDimensions.spacingMd,
            mainAxisSpacing: AppDimensions.spacingMd,
            childAspectRatio: 0.9, // Taller cards
          ),
          itemBuilder: (context, i) {
            final pet = displayList[i];
            final isSelected = _selectedPetIds.contains(pet['pet_id']);
            return _buildPetCard(pet, isSelected);
          },
        );
      },
    );
  }

  /// Builds the animated and visually rich pet card. This is where the magic happens!
  Widget _buildPetCard(Map<String, dynamic> pet, bool isSelected) {
    return GestureDetector(
      onTap: () => _handlePetSelection(pet),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? AppColors.primary.withOpacity(0.3)
                  : Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd - 3),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Pet Image or Placeholder
              pet['pet_image'] != null
                  ? Image.network(
                pet['pet_image'],
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _buildImagePlaceholder(),
              )
                  : _buildImagePlaceholder(),

              // Gradient for text readability
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.6),
                    ],
                    stops: const [0.5, 1.0],
                  ),
                ),
              ),

              // Pet Name
              Positioned(
                bottom: 10,
                left: 10,
                right: 10,
                child: Text(
                  pet['name'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // Animated Checkmark Icon
              if (isSelected)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, color: Colors.white, size: 16),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// A visually appealing "Add Pet" button.
  Widget _buildAddPetButton() {
    return Center(
      child: OutlinedButton.icon(
        icon: const Icon(Icons.add),
        label: Text(
          'Add a New Pet',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AddPetPage()),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: const StadiumBorder(),
        ),
      ),
    );
  }

  /// A friendly placeholder for pets without images.
  Widget _buildImagePlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      child: const Icon(
        Icons.pets_rounded,
        color: AppColors.primary,
        size: 50,
      ),
    );
  }

  /// A helpful message when no search results are found.
  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingLg * 2),
      child: Column(
        children: [
          const Icon(Icons.search_off_rounded, size: 80, color: Colors.grey),
          const SizedBox(height: AppDimensions.spacingMd),
          Text(
            'No Pets Found',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try searching for another name, or add a new pet to your family!',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}