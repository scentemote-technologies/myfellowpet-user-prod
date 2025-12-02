import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_colors.dart';
import '../../preloaders/petpreloaders.dart';
import '../Pets/AddPetPage.dart';
import '../Pets/pet_profile.dart';
import 'EditPetPage.dart';
import 'PetRemoveReasonPage.dart';



class AllPetsPage extends StatefulWidget {
  @override
  _AllPetsPageState createState() => _AllPetsPageState();
}

class _AllPetsPageState extends State<AllPetsPage> {
  // Your original instance variables are unused in the provided code,
  // but I've kept them here in case you use them elsewhere.
  final _auth = FirebaseAuth.instance;
  // final _firestore = FirebaseFirestore.instance; // Unused
  // bool _loading = true; // Unused
  // List<Map<String, dynamic>> _pets = []; // Unused

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Listener for the search bar
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const teal = AppColors.primary;
    final uid = _auth.currentUser!.uid;

    // Define the border style once at the beginning of the build method
    final OutlineInputBorder searchBarBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: Colors.grey.shade300,
        width: 1.5,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Manage Pets', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 1.5,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              style: GoogleFonts.poppins(
                  fontSize: 16, color: Colors.black87, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Search for a pet...',
                hintStyle: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
                prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.black54),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 0),
                filled: true,
                fillColor: Colors.white.withOpacity(0.9),

                // These now correctly reference the variable
                border: searchBarBorder,
                enabledBorder: searchBarBorder,
                focusedBorder: searchBarBorder.copyWith(
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
          ),
          // StreamBuilder with your original logic
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: PetService.instance.watchMyPetsAsMap(context),
              builder: (ctx, snap) {
                if (!snap.hasData) {
                  // Using your custom preloader
                  return const Center();
                }

                final allPets = snap.data!;

                if (allPets.isEmpty) {
                  return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.pets_rounded, color: Colors.grey, size: 80),
                          const SizedBox(height: 16),
                          Text(
                            'No pets added yet.',
                            style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 18),
                          ),
                        ],
                      )
                  );
                }

                // Filtering logic for the search bar (this doesn't change data source)
                final filteredPets = allPets.where((pet) {
                  final petName = pet['name']?.toLowerCase() ?? '';
                  return petName.contains(_searchQuery.toLowerCase());
                }).toList();

                if (filteredPets.isEmpty && _searchQuery.isNotEmpty) {
                  return Center(
                    child: Text(
                      'No pets found for "$_searchQuery"',
                      style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 16),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredPets.length,
                  itemBuilder: (_, i) {
                    final pet = filteredPets[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.2),
                            spreadRadius: 2,
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border(
                          bottom: BorderSide(
                            color: teal.withOpacity(0.5),
                            width: 3.0,
                          ),
                          right: BorderSide(
                            color: teal.withOpacity(0.5),
                            width: 3.0,
                          ),
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PetProfile(
                              petId: pet['pet_id'],
                              userUid: uid,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 30,
                                    backgroundImage: pet['pet_image'] != null && pet['pet_image'].isNotEmpty
                                        ? NetworkImage(pet['pet_image'])
                                        : null,
                                    backgroundColor: AppColors.primary.withOpacity(0.15),
                                    child: pet['pet_image'] == null || pet['pet_image'].isEmpty
                                        ? const Icon(Icons.pets, color: AppColors.primary)
                                        : null,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            (pet['name'] as String).split(' ').map((word) {
                                              if (word.isEmpty) return '';
                                              return word[0].toUpperCase() + word.substring(1).toLowerCase();
                                            }).join(' '),
                                            style: GoogleFonts.poppins(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.edit, size: 18, color: Colors.white,),
                                      label: Text('Edit', style: GoogleFonts.poppins(color: Colors.white)),
                                      onPressed: () async {
                                        // Fetch the full pet document
                                        final petDoc = await FirebaseFirestore.instance
                                            .collection('users')
                                            .doc(uid)
                                            .collection('users-pets')
                                            .doc(pet['pet_id'])
                                            .get();

                                        if (petDoc.exists) {
                                          final fullPetData = petDoc.data() as Map<String, dynamic>;

                                          await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => EditPetPage(
                                                petId: pet['pet_id'],
                                                initialData: fullPetData,
                                                userUid: uid,
                                              ),
                                            ),
                                          );
                                        } else {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Pet profile not found.')),
                                          );
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: teal,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                      label: Text('Remove', style: GoogleFonts.poppins(color: Colors.red)),
                                      onPressed: () async {
                                        final removed = await Navigator.push<bool>(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => PetRemoveReasonPage(
                                              petId: pet['pet_id'],
                                              petName: pet['name'],
                                            ),
                                          ),
                                        );
                                        if (removed == true && context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                "'${pet['name']}' has been removed.",
                                                style: GoogleFonts.poppins(),
                                              ),
                                              backgroundColor: Colors.green,
                                            ),
                                          );
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: Colors.red,
                                        elevation: 2,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        shadowColor: Colors.grey.withOpacity(0.5),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Go to Add Pet page
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AddPetPage()), // or your AddPetPage()
          );
        },
        backgroundColor: AppColors.primaryColor,
        elevation: 4,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,

    );
  }
}