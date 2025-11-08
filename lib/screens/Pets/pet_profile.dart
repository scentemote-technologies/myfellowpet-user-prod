import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../AppBars/EditPetPage.dart'; // Add url_launcher to your pubspec.yaml

class PetProfile extends StatefulWidget {
  final String petId;
  final String userUid;
  const PetProfile({Key? key, required this.petId, required this.userUid})
      : super(key: key);

  @override
  _PetProfileState createState() => _PetProfileState();
}

class _PetProfileState extends State<PetProfile>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  DocumentSnapshot? petData;
  bool isLoading = true;
  String? errorMessage;

  late TabController _tabController;

  static const Color accent = Color(0xFF3D3D3D);
  static const Color teal = Color(0xFF25ADAD);
  static const Color lightGrey = Color(0xFFF5F5F5);

  @override
  void initState() {
    super.initState();
    _fetchPetData();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchPetData() async {
    // Reset state for refresh
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final doc = await _firestore
          .collection('users')
          .doc(widget.userUid)
          .collection('users-pets')
          .doc(widget.petId)
          .get();
      if (doc.exists) {
        setState(() {
          petData = doc;
          isLoading = false;
        });
      } else {
        throw Exception('Pet profile not found. It may have been removed.');
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load pet data: $e';
        isLoading = false;
      });
    }
  }

  void _navigateToEdit() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditPetPage(
          petId: widget.petId,
          userUid: widget.userUid,
          initialData: petData!.data() as Map<String, dynamic>,
        ),
      ),
    ).then((didUpdate) {
      // Refresh data if the edit page returns true
      if (didUpdate == true) {
        _fetchPetData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return _buildLoading();
    if (errorMessage != null) return _buildError();

    final data = petData!.data() as Map<String, dynamic>;
    final name = data['name'] ?? 'Unnamed Pet';
    final breed = data['pet_breed'] ?? 'N/A';
    final age = data['pet_age'] ?? 'N/A';
    final profileImageUrl = data['pet_image'] as String?;
    final galleryImages = List<String>.from(data['pet_images'] ?? []);

    return Scaffold(
      backgroundColor: Colors.white,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 320.0,
              floating: false,
              pinned: true,
              stretch: true,
              backgroundColor: accent,
              iconTheme: const IconThemeData(color: Colors.white),
              actions: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _navigateToEdit,
                  tooltip: 'Edit Profile',
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                centerTitle: true,
                titlePadding:
                const EdgeInsets.symmetric(horizontal: 48, vertical: 12),
                title: Text(
                  name,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    profileImageUrl != null && profileImageUrl.isNotEmpty && profileImageUrl.startsWith('http')
                        ? Image.network(
                      profileImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.broken_image,
                          size: 100, color: Colors.white24),
                    )
                        : Container( // This block handles null, empty, or invalid/local file URIs
                      color: Colors.grey.shade400,
                      child: const Icon(Icons.pets,
                          size: 100, color: Colors.white54),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black54,
                            Colors.black87
                          ],
                          stops: [0.4, 0.8, 1.0],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 50,
                      left: 0,
                      right: 0,
                      child: Text(
                        '$breed • Age: $age',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              delegate: _SliverAppBarDelegate(
                TabBar(
                  controller: _tabController,
                  labelColor: teal,
                  unselectedLabelColor: Colors.grey.shade600,
                  indicatorColor: teal,
                  indicatorWeight: 3.0,
                  labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  tabs: [
                    const Tab(icon: Icon(Icons.info_outline), text: 'About'),
                    const Tab(
                        icon: Icon(Icons.health_and_safety_outlined),
                        text: 'Health'),
                    Tab(
                        icon: const Icon(Icons.photo_library_outlined),
                        text: 'Gallery (${galleryImages.length})'),
                  ],
                ),
              ),
              pinned: true,
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildAboutTab(data),
            _buildHealthTab(data),
            _buildGalleryTab(galleryImages),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() => const Scaffold(
    body: Center(child: CircularProgressIndicator(color: teal)),
  );

  Widget _buildError() => Scaffold(
    appBar: AppBar(backgroundColor: Colors.white, elevation: 0),
    body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(errorMessage!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: Colors.red.shade700)),
        )),
  );

  // MARK: - Tab Widgets
  Widget _buildAboutTab(Map<String, dynamic> data) {
    final gender = data['gender'] as String?;
    final weightType = data['weight_type'] as String?;
    String weightDisplay;
    if (weightType == 'exact') {
      weightDisplay = '${data['weight']} kg';
    } else if (weightType == 'range') {
      weightDisplay = data['weight_range'] ?? 'N/A';
    } else {
      weightDisplay = 'N/A';
    }
    final isNeutered = data['is_neutered'] as bool?;
    final activityLevel = data['activity_level'] as String?;
    final likes = List<String>.from(data['likes'] ?? []);
    final dislikes = List<String>.from(data['dislikes'] ?? []);
    final notes = data['notes'] as String?;
    final history = data['medical_history'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            title: 'Key Info',
            icon: Icons.person_outline,
            children: [
              _buildInfoRow(Icons.wc, 'Gender', gender),
              _buildInfoRow(Icons.monitor_weight_outlined, 'Weight', weightDisplay),
              _buildInfoRow(
                  Icons.cut,
                  isNeutered == true ? 'Neutered / Spayed' : 'Not Neutered',
                  null),
              _buildInfoRow(Icons.directions_run, 'Activity Level', activityLevel),
            ],
          ),
          if (likes.isNotEmpty)
            _buildChipCard(
                'Likes', likes, Icons.favorite, Colors.green.shade400),
          if (dislikes.isNotEmpty)
            _buildChipCard('Dislikes', dislikes, Icons.thumb_down,
                Colors.orange.shade400),
          if (notes != null && notes.isNotEmpty)
            _buildTextCard('Notes', notes, Icons.note_alt_outlined),
          if (history != null && history.isNotEmpty)
            _buildTextCard(
                'Medical History', history, Icons.history_edu_outlined),
          const SizedBox(height: 80), // Extra space for FAB
        ],
      ),
    );
  }

  Widget _buildHealthTab(Map<String, dynamic> data) {
    final allergies = data['allergies'] as String?;
    final conditions = data['medical_conditions'] as String?;
    final diet = data['diet_notes'] as String?;
    final vetName = data['vet_name'] as String?;
    final vetPhone = data['vet_phone'] as String?;
    final emergencyContact = data['emergency_contact'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildVaccinationCard(data),
          _buildInfoCard(
            title: 'Health Profile',
            icon: Icons.medical_services_outlined,
            children: [
              _buildInfoRow(
                  Icons.warning_amber_rounded, 'Allergies', allergies),
              _buildInfoRow(Icons.coronavirus_outlined,
                  'Existing Conditions', conditions),
              _buildInfoRow(Icons.restaurant_menu, 'Dietary Notes', diet),
            ],
          ),
          _buildInfoCard(
            title: 'Veterinary Details',
            icon: Icons.local_hospital_outlined,
            children: [
              _buildInfoRow(Icons.person_pin_circle_outlined, 'Vet Name', vetName),
              _buildInfoRow(
                Icons.phone_outlined,
                'Vet Phone',
                vetPhone,
                isPhone: true,
              ),
            ],
          ),
          _buildInfoCard(
            title: 'Emergency Contact',
            icon: Icons.contact_phone_outlined,
            children: [
              _buildInfoRow(Icons.phone_in_talk_outlined, 'Contact Info',
                  emergencyContact,
                  isPhone: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGalleryTab(List<String> images) {
    if (images.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.photo_library_outlined,
                size: 60, color: Colors.grey),
            const SizedBox(height: 16),
            Text('No additional photos yet',
                style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey)),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () => _showImageDialog(context, images[index]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              images[index],
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(child: CircularProgressIndicator(strokeWidth: 2));
              },
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.grey.shade200,
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          ),
        );
      },
    );
  }

  // MARK: - Helper & Component Widgets
  // MARK: - Helper & Component Widgets
  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final filteredChildren =
    children.where((child) => child is SizedBox == false).toList();
    if (filteredChildren.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: teal.withOpacity(0.5),
            offset: const Offset(4, 0), // Right border
            blurRadius: 0,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: teal.withOpacity(0.5),
            offset: const Offset(0, 4), // Bottom border
            blurRadius: 0,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: teal, size: 22),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                      fontSize: 18, fontWeight: FontWeight.w600, color: accent),
                ),
              ],
            ),
            const Divider(height: 24),
            ...filteredChildren,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String? value,
      {bool isPhone = false}) {
    if (value == null || value.isEmpty || value == 'N/A') {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.grey.shade600, size: 20),
          const SizedBox(width: 16),
          Text(
            '$label:',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: accent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: isPhone
                ? InkWell(
              onTap: () => launchUrl(Uri.parse('tel:$value')),
              child: Text(
                value,
                style: GoogleFonts.poppins(
                  color: teal,
                  decoration: TextDecoration.underline,
                ),
              ),
            )
                : Text(value, style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  Widget _buildChipCard(
      String title, List<String> items, IconData icon, Color color) {
    return _buildInfoCard(
      title: title,
      icon: icon,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: items
              .map((item) => Chip(
            label: Text(item, style: GoogleFonts.poppins(color: accent)),
            backgroundColor: lightGrey,
            side: BorderSide(color: Colors.grey.shade300),
          ))
              .toList(),
        )
      ],
    );
  }

  Widget _buildTextCard(String title, String text, IconData icon) {
    return _buildInfoCard(
      title: title,
      icon: icon,
      children: [
        Text(text, style: GoogleFonts.poppins(height: 1.5)),
      ],
    );
  }

  Widget _buildVaccinationCard(Map<String, dynamic> data) {
    final type = data['report_type'] as String?;
    final url = data['report_url'] as String?;
    final vaccines = List<Map<String, dynamic>>.from(data['vaccines'] ?? []);

    Widget content;
    switch (type) {
      case 'pdf':
        content = ListTile(
          leading: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
          title: Text('View Vaccination PDF',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
          trailing: const Icon(Icons.open_in_new, color: teal),
          onTap: () =>
          url != null ? launchUrl(Uri.parse(url)) : ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open PDF.'))),
        );
        break;
      case 'manually_entered':
        content = Column(
          children: vaccines.map((v) {
            final name = v['name'] ?? 'N/A';
            final dateGiven = (v['dateGiven'] as Timestamp?)?.toDate();
            final nextDue = (v['nextDue'] as Timestamp?)?.toDate();
            return ListTile(
              dense: true,
              leading: const Icon(Icons.vaccines, color: teal),
              title: Text(name,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
              subtitle: Text(
                'Given: ${dateGiven != null ? DateFormat.yMMMd().format(dateGiven) : 'N/A'}\n'
                    'Next Due: ${nextDue != null ? DateFormat.yMMMd().format(nextDue) : 'None'}',
                style: GoogleFonts.poppins(fontSize: 12),
              ),
            );
          }).toList(),
        );
        break;
      case 'never':
        content = ListTile(
          leading: const Icon(Icons.not_interested, color: Colors.orange),
          title: Text('Never Vaccinated',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
        );
        break;
      default:
        content = ListTile(
          leading: const Icon(Icons.help_outline, color: Colors.grey),
          title: Text('No vaccination information provided.',
              style: GoogleFonts.poppins()),
        );
    }

    return _buildInfoCard(
      title: 'Vaccination Status',
      icon: Icons.shield_outlined,
      children: [content],
    );
  }

  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: InteractiveViewer(
            child: Image.network(imageUrl),
          ),
        ),
      ),
    );
  }
}

// Helper class to make the TabBar stick under the SliverAppBar
class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}