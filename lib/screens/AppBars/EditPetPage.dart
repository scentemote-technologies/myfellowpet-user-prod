import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../app_colors.dart';

// You might have this in your AddPetPage, it's needed here as well.
// It is good practice to move shared classes like this to their own file.
class PetType {
  final String id;
  final bool display;
  PetType({required this.id, required this.display});
}

class FreeFormCropSheet extends StatefulWidget {
  final File file;
  final void Function(Uint8List) onCropped;
  const FreeFormCropSheet({Key? key, required this.file, required this.onCropped}) : super(key: key);
  @override
  _FreeFormCropSheetState createState() => _FreeFormCropSheetState();
}

class _FreeFormCropSheetState extends State<FreeFormCropSheet> {
  final _controller = CropController();
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * .75,
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Text('Crop & Adjust', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Expanded(
              child: Crop(
                controller: _controller,
                image: widget.file.readAsBytesSync(),
                onCropped: (result) {
                  if (result is CropSuccess) widget.onCropped(result.croppedImage);
                  Navigator.pop(context);
                },
                interactive: true,
                baseColor: Colors.white,
                maskColor: Colors.black.withAlpha(100),
                cornerDotBuilder: (size, alignment) => const DotControl(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _controller.crop(),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3D3D3D), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 18)),
              child: const Text('Done Cropping'),
            ),
          ],
        ),
      ),
    );
  }
}

class EditPetPage extends StatefulWidget {
  final String petId;
  final String userUid;
  final Map<String, dynamic> initialData;

  const EditPetPage(
      {super.key,
        required this.petId,
        required this.userUid,
        required this.initialData});

  @override
  _EditPetPageState createState() => _EditPetPageState();
}

class _EditPetPageState extends State<EditPetPage> {

  final List<String> _sizeRanges = [
    'Small',
    'Medium',
    'Large',
    'Giant',
  ];
  String? _selectedSize;
  // UI Colors
  static const Color teal = Color(0xFF25ADAD);
  static const Color accent = Color(0xFF3D3D3D);

  // Form & State
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  // Edit Cooldown Logic
  bool _isEditLocked = false;
  int _daysLeft = 0;

  // Controllers
  late TextEditingController _nameCtl;
  late TextEditingController _ageCtl;
  late TextEditingController _historyCtl;
  late TextEditingController _allergiesCtl;
  late TextEditingController _conditionsCtl;
  late TextEditingController _dietNotesCtl;
  late TextEditingController _vetNameCtl;
  late TextEditingController _vetPhoneCtl;
  late TextEditingController _emergencyContactCtl;
  late TextEditingController _exactWeightCtl;
  late TextEditingController _customLikeCtl;
  late TextEditingController _customDislikeCtl;

  // Image Handling
  final _picker = ImagePicker();
  String? _existingImageUrl;
  Uint8List? _newCroppedProfileImage;

  List<String> _existingExtraImageUrls = [];
  List<File> _newExtraImages = [];
  List<String> _imagesToDelete = [];
  bool _loadingExtras = false;

  // State Variables
  String? _gender;
  String _weightType = 'exact';
  String? _selectedRange;
  bool _isNeutered = false;
  String? _activityLevel;
  List<String> _likes = [];
  List<String> _dislikes = [];
  String _reportType = '';
  File? _pdfReport;
  String? _pdfReportUrl;
  List<Map<String, dynamic>> _vaccines = [];

  // Dropdown Data
  List<PetType> _petTypes = [];
  List<String> _breeds = [];
  String? _selectedType;
  String? _selectedBreed;
  final List<String> _weightRanges = [
    '0 - 10 kg', '11 - 20 kg', '21 - 30 kg',
    '31 - 40 kg', '41 - 50 kg', '50+ kg'
  ];

  @override
  void initState() {
    super.initState();
    _initializeFields();
    _checkEditCooldown();
    _loadPetTypes().then((_) {
      if (_selectedType != null) {
        _loadBreeds(_selectedType!);
      }
    });
  }

  void _initializeFields() {
    final data = widget.initialData;
    _selectedSize = data['size'];
    _nameCtl = TextEditingController(text: data['name'] ?? '');
    _ageCtl = TextEditingController(text: data['pet_age'] ?? '');
    _historyCtl = TextEditingController(text: data['medical_history'] ?? '');
    _allergiesCtl = TextEditingController(text: data['allergies'] ?? '');
    _conditionsCtl =
        TextEditingController(text: data['medical_conditions'] ?? '');
    _dietNotesCtl = TextEditingController(text: data['diet_notes'] ?? '');
    _vetNameCtl = TextEditingController(text: data['vet_name'] ?? '');
    _vetPhoneCtl = TextEditingController(text: data['vet_phone'] ?? '');
    _emergencyContactCtl =
        TextEditingController(text: data['emergency_contact'] ?? '');
    _exactWeightCtl =
        TextEditingController(text: data['weight']?.toString() ?? '');
    _customLikeCtl = TextEditingController();
    _customDislikeCtl = TextEditingController();

    _existingImageUrl = data['pet_image'];
    _existingExtraImageUrls = List<String>.from(data['pet_images'] ?? []);

    _selectedType = data['pet_type'];
    _selectedBreed = data['pet_breed'];
    _gender = (data['gender'] as String?)?.trim().toLowerCase();
    _weightType = data['weight_type'] ?? 'exact';
    _selectedRange = data['weight_range'];
    _isNeutered = data['is_neutered'] ?? false;
    _activityLevel = data['activity_level'];
    _likes = List<String>.from(data['likes'] ?? []);
    _dislikes = List<String>.from(data['dislikes'] ?? []);
    _reportType = data['report_type'] ?? '';
    _pdfReportUrl = data['report_url'];

    final firestoreVaccines =
    List<Map<String, dynamic>>.from(data['vaccines'] ?? []);
    _vaccines = firestoreVaccines.map((v) {
      return {
        'name': v['name'],
        'dateGiven': (v['dateGiven'] as Timestamp?)?.toDate(),
        'nextDue': (v['nextDue'] as Timestamp?)?.toDate(),
      };
    }).toList();
  }

  // New method to fetch the cooldown days from Firestore
  Future<int> _fetchEditCooldownDays() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('pet_last_edit')
          .get();
      if (doc.exists && doc.data() != null) {
        // Retrieve the 'days' field, default to 14 if it's not a valid number
        return (doc.data()!['days'] as int?) ?? 14;
      }
      return 14; // Default to 14 if document doesn't exist
    } catch (e) {
      print('Error fetching cooldown days: $e');
      return 14; // Default to 14 on any error
    }
  }

  // Modified _checkEditCooldown method to use the fetched value
  Future<void> _checkEditCooldown() async {
    final cooldownDays = await _fetchEditCooldownDays();
    final lastEdited = (widget.initialData['lastEditedAt'] as Timestamp?)?.toDate();
    if (lastEdited == null) return;

    final now = DateTime.now();
    final difference = now.difference(lastEdited);

    if (difference.inDays < cooldownDays) {
      setState(() {
        _isEditLocked = true;
        _daysLeft = cooldownDays - difference.inDays;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
            backgroundColor: Colors.white,
            title: Text(
              "Editing Locked",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            content: Text(
              "You can make changes to this profile again in $_daysLeft days.",
              style: GoogleFonts.poppins(
                color: Colors.grey.shade700,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  "OK",
                  style: GoogleFonts.poppins(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _ageCtl.dispose();
    _historyCtl.dispose();
    _allergiesCtl.dispose();
    _conditionsCtl.dispose();
    _dietNotesCtl.dispose();
    _vetNameCtl.dispose();
    _vetPhoneCtl.dispose();
    _emergencyContactCtl.dispose();
    _exactWeightCtl.dispose();
    _customLikeCtl.dispose();
    _customDislikeCtl.dispose();
    super.dispose();
  }

  Future<void> _loadPetTypes() async {
    final snapshot =
    await FirebaseFirestore.instance.collection('pet_types').get();
    if (!mounted) return;
    setState(() {
      _petTypes = snapshot.docs
          .map((d) => PetType(
        id: d.id,
        display: (d.data()['display'] as bool? ?? false),
      ))
          .toList();
    });
  }

  Future<void> _loadBreeds(String typeId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('pet_types')
        .doc(typeId)
        .collection('breeds')
        .get();
    if (!mounted) return;
    setState(() {
      _breeds = snapshot.docs.map((d) => d['name'] as String).toList();
    });
  }

  Future<void> _pickProfileImage() async {
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FreeFormCropSheet(
        file: File(picked.path),
        onCropped: (bytes) => setState(() => _newCroppedProfileImage = bytes),
      ),
    );
  }

  Future<void> _pickExtraImages() async {
    final available =
        5 - (_existingExtraImageUrls.length + _newExtraImages.length);
    if (available <= 0) return;

    final picked = await _picker.pickMultiImage();
    if (picked.isEmpty || !mounted) return;

    setState(() => _loadingExtras = true);
    for (final xFile in picked.take(available)) {
      final tempDir = await getTemporaryDirectory();
      final compressed = await FlutterImageCompress.compressAndGetFile(
          xFile.path, '${tempDir.path}/${xFile.name}_cmp.jpg',
          quality: 70);
      if (compressed != null) {
        _newExtraImages.add(File(compressed.path));
      }
    }
    if (!mounted) return;
    setState(() => _loadingExtras = false);
  }

  void _removeNewExtraImage(int index) =>
      setState(() => _newExtraImages.removeAt(index));
  void _removeExistingExtraImage(String url) {
    setState(() {
      _existingExtraImageUrls.remove(url);
      _imagesToDelete.add(url);
    });
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate() || _isEditLocked) return;
    setState(() => _saving = true);

    // 1. Reference to the specific Pet Document
    final petDocRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userUid)
        .collection('users-pets')
        .doc(widget.petId);

    // 2. Reference to the Main User Document (for the tracking map)
    final userDocRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userUid);

    Map<String, dynamic> dataToUpdate = {
      'name': _nameCtl.text.trim(),
      'pet_age': _ageCtl.text.trim(),
      'pet_type': _selectedType,
      'pet_breed': _selectedBreed,

      'size': _selectedSize, // ✨ ADDED: Save the size

      'gender': _gender,
      'is_neutered': _isNeutered,
      'weight_type': _weightType,
      'weight': _weightType == 'exact'
          ? double.tryParse(_exactWeightCtl.text)
          : FieldValue.delete(),
      'weight_range':
      _weightType == 'range' ? _selectedRange : FieldValue.delete(),
      'activity_level': _activityLevel,
      'likes': _likes,
      'dislikes': _dislikes,
      'medical_history': _historyCtl.text.trim(),
      'allergies': _allergiesCtl.text.trim(),
      'medical_conditions': _conditionsCtl.text.trim(),
      'diet_notes': _dietNotesCtl.text.trim(),
      'report_type': _reportType,
      'vaccines': _reportType == 'manually_entered'
          ? _vaccines
          : FieldValue.delete(),
      'vet_name': _vetNameCtl.text.trim(),
      'vet_phone': _vetPhoneCtl.text.trim(),
      'emergency_contact': _emergencyContactCtl.text.trim(),

      // We still update the pet's own timestamp
      'lastEditedAt': FieldValue.serverTimestamp(),
    };

    // --- Image & PDF Upload Logic (Unchanged) ---
    if (_newCroppedProfileImage != null) {
      final ref =
      FirebaseStorage.instance.ref('pets/${widget.petId}_profile.jpg');
      await ref.putData(_newCroppedProfileImage!);
      dataToUpdate['pet_image'] = await ref.getDownloadURL();
    }

    if (_reportType == 'pdf' && _pdfReport != null) {
      final ref =
      FirebaseStorage.instance.ref('pets/reports/${widget.petId}.pdf');
      await ref.putFile(_pdfReport!);
      dataToUpdate['report_url'] = await ref.getDownloadURL();
    } else if (_reportType != 'pdf') {
      dataToUpdate['report_url'] = FieldValue.delete();
    }

    for (String url in _imagesToDelete) {
      await FirebaseStorage.instance.refFromURL(url).delete().catchError((_) {});
    }
    for (File file in _newExtraImages) {
      final ref = FirebaseStorage.instance
          .ref('pets/${widget.petId}_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(file);
      _existingExtraImageUrls.add(await ref.getDownloadURL());
    }
    dataToUpdate['pet_images'] = _existingExtraImageUrls;
    // ---------------------------------------------

    try {
      // 1. Update the Pet Document
      await petDocRef.update(dataToUpdate);

      // 2. ✨ ADDED: Update the User Document with the Tracking Map
      // This allows you to track specific pet edits without reading every pet doc.
      await userDocRef.set({
        'pet_edit_tracking': {
          widget.petId: FieldValue.serverTimestamp() // Key: PetID, Value: Time
        }
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Profile updated successfully!"),
              backgroundColor: Colors.green),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Error updating profile: $e"),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text('Edit Pet Profile',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: accent)),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: accent),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSection(
                  title: 'Basic Info',
                  icon: Icons.pets,
                  child: _buildBasicInfoFields()),
              _buildSection(
                  title: 'Personality',
                  icon: Icons.psychology_outlined,
                  child: _buildPersonalityFields()),
              _buildSection(
                  title: 'Health & Wellness',
                  icon: Icons.health_and_safety_outlined,
                  child: _buildHealthFields()),
              _buildSection(
                  title: 'Contacts',
                  icon: Icons.contact_phone_outlined,
                  child: _buildContactsFields()),
              _buildSection(
                  title: 'Photos',
                  icon: Icons.photo_library_outlined,
                  child: _buildPhotosManager()),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // MARK: - UI Builder Widgets

  Widget _buildSection({required String title, required IconData icon, required Widget child}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.white, // Set the card background to white
      elevation: 1,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        initiallyExpanded: title == 'Basic Info',
        leading: Icon(icon, color: teal), // Teal icon color
        title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: accent)), // Dark accent text color
        children: [
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: child,
          )
        ],
      ),
    );
  }

  Widget _buildBasicInfoFields() {
    return Column(
      children: [
        // Profile Image
        Center(
          child: Stack(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: _newCroppedProfileImage != null
                    ? MemoryImage(_newCroppedProfileImage!)
                    : (_existingImageUrl != null && _existingImageUrl!.isNotEmpty
                    ? NetworkImage(_existingImageUrl!)
                    : null) as ImageProvider?,
                child: _newCroppedProfileImage == null && (_existingImageUrl == null || _existingImageUrl!.isEmpty)
                    ? const Icon(Icons.pets, size: 40, color: Colors.grey)
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: InkWell(
                  onTap: _isEditLocked ? null : _pickProfileImage,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: _isEditLocked ? Colors.grey : teal,
                    child: const Icon(Icons.edit, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Name
        _buildTextFormField(_nameCtl, 'Pet Name', validator: (v) => v!.isEmpty ? 'Name is required' : null),
        const SizedBox(height: 16),
        // Age
        _buildTextFormField(_ageCtl, 'Age (years)', keyboardType: TextInputType.number),
        const SizedBox(height: 16),
        // Type

        _buildDropdown(_selectedType, _petTypes.where((t) => t.display).map((t) => t.id).toList(), 'Pet Type', (val) {
          setState(() {
            _selectedType = val;
            _selectedBreed = null;
            _breeds.clear();
            if (val != null) _loadBreeds(val);
          });
        }),
        const SizedBox(height: 16),
        // Breed
        _buildDropdown(_selectedBreed, _breeds, 'Breed', (val) => setState(() => _selectedBreed = val)),
        const SizedBox(height: 16),
        // Gender
        _buildHeader('Gender'),
        Row(
          children: ['Male', 'Female'].map((g) {
            final buttonValue = g.toLowerCase();
            return Expanded(
              child: RadioListTile<String>(
                title: Text(g),
                value: buttonValue,
                groupValue: _gender,
                activeColor: teal,
                onChanged: _isEditLocked ? null : (v) => setState(() => _gender = v),
              ),
            );
          }).toList(),
        ),
        // Neutered
        SwitchListTile(
          title: Text(_gender == 'Female' ? 'Spayed?' : 'Neutered?'),
          value: _isNeutered,
          activeColor: teal,
          onChanged: _isEditLocked ? null : (v) => setState(() => _isNeutered = v),
        ),
        const SizedBox(height: 16),

        // ✨ ADD THIS: Size Dropdown
        _buildDropdown(
            _selectedSize,
            _sizeRanges,
            'Size Range',
                (val) => setState(() => _selectedSize = val)
        ),
        const SizedBox(height: 16),        // Weight
        _buildHeader('Weight'),
        Row(
          children: ['exact', 'range'].map((g) => Expanded(
            child: RadioListTile<String>(
              title: Text(g[0].toUpperCase() + g.substring(1)), value: g, groupValue: _weightType,
              activeColor: teal,
              onChanged: _isEditLocked ? null : (v) => setState(() => _weightType = v!),
            ),
          )).toList(),
        ),
        if (_weightType == 'exact')
          _buildTextFormField(_exactWeightCtl, 'Weight (kg)', keyboardType: TextInputType.number),
        if (_weightType == 'range')
          _buildDropdown(_selectedRange, _weightRanges, 'Weight Range', (val) => setState(() => _selectedRange = val)),
      ],
    );
  }

  Widget _buildPersonalityFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader('Activity Level'),
        Wrap(
          spacing: 8,
          children: ['Low', 'Moderate', 'High'].map((lvl) {
            return ChoiceChip(
              label: Text(lvl),
              selected: _activityLevel == lvl,
              selectedColor: teal,
              labelStyle: TextStyle(color: _activityLevel == lvl ? Colors.white : accent),
              onSelected: _isEditLocked ? null : (_) => setState(() => _activityLevel = lvl),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        // Likes
        _buildChipManager('Likes', _likes, _customLikeCtl, () {
          final text = _customLikeCtl.text.trim();
          if (text.isNotEmpty && !_likes.contains(text)) setState(() => _likes.add(text));
          _customLikeCtl.clear();
        }),
        const SizedBox(height: 24),
        // Dislikes
        _buildChipManager('Dislikes', _dislikes, _customDislikeCtl, () {
          final text = _customDislikeCtl.text.trim();
          if (text.isNotEmpty && !_dislikes.contains(text)) setState(() => _dislikes.add(text));
          _customDislikeCtl.clear();
        }),
      ],
    );
  }

  Widget _buildHealthFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTextFormField(_historyCtl, 'Medical History', maxLines: 3),
        const SizedBox(height: 16),
        _buildTextFormField(_allergiesCtl, 'Allergies', maxLines: 2),
        const SizedBox(height: 16),
        _buildTextFormField(_conditionsCtl, 'Existing Conditions', maxLines: 2),
        const SizedBox(height: 16),
        _buildTextFormField(_dietNotesCtl, 'Dietary Notes', maxLines: 2),
        const SizedBox(height: 24),
        _buildHeader('Vaccination Report'),
        _buildVaccinationManager(),
      ],
    );
  }

  // PASTE THIS ENTIRE SNIPPET INTO YOUR _EditPetPageState CLASS, REPLACING THE OLD METHODS

  Widget _buildVaccinationManager() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: _isEditLocked ? null : _showVaccinationOptions,
          style: ElevatedButton.styleFrom(
            backgroundColor: teal,
            foregroundColor: Colors.white,
            textStyle: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text('Edit Vaccination Report', style: GoogleFonts.poppins()),
        ),
        const SizedBox(height: 16),

        // *** THIS IS THE MODIFIED LOGIC ***
        if (_reportType == 'pdf' && (_pdfReport != null || _pdfReportUrl != null))
          _buildReportDisplay(
            // We now pass a child widget for more flexibility
            child: Row(
              children: [
                const Icon(Icons.picture_as_pdf, color: teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    // If a new report file exists, show its name.
                    // Otherwise, show a generic message for the existing URL.
                    _pdfReport != null
                        ? _pdfReport!.path.split('/').last
                        : 'PDF Report Attached',
                    style: GoogleFonts.poppins(),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            isEditable: true,
          )
        else if (_reportType == 'manually_entered' && _vaccines.isNotEmpty)
          _buildManualVaccineList()
        else if (_reportType == 'never')
            _buildReportDisplay(
              child: Row(
                children: [
                  const Icon(Icons.not_interested, color: teal),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text('Never Vaccinated', style: GoogleFonts.poppins())
                  ),
                ],
              ),
              isEditable: true,
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                'No vaccination report added.',
                style: GoogleFonts.poppins(color: Colors.grey.shade600),
              ),
            ),
      ],
    );
  }

// This helper widget is slightly modified to be more flexible
  Widget _buildReportDisplay({required Widget child, required bool isEditable}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: teal),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: child), // Display the child widget we passed in
          if (isEditable && !_isEditLocked)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit, color: accent, size: 20),
              onPressed: _showVaccinationOptions,
            ),
          if (isEditable && !_isEditLocked)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete, color: Colors.red, size: 20),
              onPressed: () {
                setState(() {
                  _reportType = '';
                  _pdfReport = null;
                  _pdfReportUrl = null;
                  _vaccines = [];
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _buildManualVaccineList() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: teal),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Vaccines Entered:',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: teal,
                ),
              ),
              if (!_isEditLocked)
                IconButton(
                  icon: const Icon(Icons.edit, color: accent),
                  onPressed: _showVaccinationOptions,
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (var v in _vaccines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Text(
                '• ${v['name']} – Given: ${DateFormat.yMMMd().format(v['dateGiven'])}',
                style: GoogleFonts.poppins(),
              ),
            ),
        ],
      ),
    );
  }



  void _showVaccinationOptions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return Padding(
          padding: MediaQuery.of(sheetCtx).viewInsets,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text('Vaccination Report', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: teal)),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: teal),
                title: Text('Upload PDF', style: GoogleFonts.poppins()),
                onTap: () async {
                  final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
                  if (res?.files.single.path != null) {
                    final file = File(res!.files.single.path!);
                    setState(() {
                      _reportType = 'pdf';
                      _pdfReport = file;
                      _pdfReportUrl = null;
                      _vaccines = [];
                    });
                    if (mounted) Navigator.pop(sheetCtx);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit, color: teal),
                title: Text('Enter Manually', style: GoogleFonts.poppins()),
                onTap: () {
                  _showManualEntry(sheetCtx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.not_interested, color: teal),
                title: Text('Never Vaccinated', style: GoogleFonts.poppins()),
                onTap: () {
                  setState(() {
                    _reportType = 'never';
                    _pdfReport = null;
                    _pdfReportUrl = null;
                    _vaccines = [];
                  });
                  if (mounted) Navigator.pop(sheetCtx);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showManualEntry(BuildContext sheetCtx) {
    showDialog<void>(
      context: sheetCtx,
      barrierDismissible: false,
      builder: (dialogCtx) {
        final tempList = List<Map<String, dynamic>>.from(_vaccines);

        return StatefulBuilder(builder: (ctx, setSt) {
          // Updated validation: nextDue is now truly optional
          bool allFilled() {
            return tempList.every((v) =>
            (v['name'] as String).trim().isNotEmpty &&
                v['dateGiven'] is DateTime);
          }

          return AlertDialog(
            insetPadding: EdgeInsets.zero,
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            actionsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: Text(
              'Enter Vaccines',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: teal,
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: tempList.length + 1,
                itemBuilder: (_, i) {
                  if (i == tempList.length && tempList.length < 30) {
                    return TextButton.icon(
                      onPressed: () => setSt(() {
                        tempList.add({'name': '', 'dateGiven': null, 'nextDue': null});
                      }),
                      icon: Icon(Icons.add, color: teal),
                      label: Text('Add Vaccine', style: GoogleFonts.poppins(color: teal)),
                    );
                  }
                  final vac = tempList[i];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Vaccine Name with validation
                          TextFormField(
                            initialValue: vac['name'],
                            style: GoogleFonts.poppins(),
                            decoration: InputDecoration(
                              labelText: 'Vaccine Name',
                              labelStyle: GoogleFonts.poppins(color: accent),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: accent, width: 1.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: teal, width: 2.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            // Validation to prevent empty name
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Name is required';
                              }
                              return null;
                            },
                            onChanged: (v) => setSt(() => vac['name'] = v),
                          ),
                          const SizedBox(height: 12),
                          // Date Given (required)
                          _buildDateInput(
                            context: ctx,
                            label: 'Date Given',
                            date: vac['dateGiven'],
                            onDateSelected: (d) => setSt(() => vac['dateGiven'] = d),
                          ),
                          const SizedBox(height: 12),
                          // Next Due Date (optional)
                          _buildDateInput(
                            context: ctx,
                            label: 'Next Due Date (Optional)',
                            date: vac['nextDue'],
                            onDateSelected: (d) => setSt(() => vac['nextDue'] = d),
                          ),
                          Align(
                            alignment: Alignment.topRight,
                            child: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => setSt(() => tempList.removeAt(i)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text('Cancel', style: GoogleFonts.poppins(color: accent)),
              ),
              TextButton(
                onPressed: allFilled()
                    ? () {
                  setState(() {
                    _reportType = 'manually_entered';
                    _pdfReport = null;
                    _pdfReportUrl = null;
                    _vaccines = tempList;
                  });
                  Navigator.pop(dialogCtx);
                  Navigator.pop(sheetCtx);
                }
                    : null, // Button is disabled if validation fails
                child: Text('OK', style: GoogleFonts.poppins(color: allFilled() ? teal : Colors.grey)),
              ),
            ],
          );
        });
      },
    );
  }

  // NEW CODE - PASTE THIS
  Widget _buildDateInput({
    required BuildContext context,
    required String label,
    required DateTime? date,
    required Function(DateTime?) onDateSelected,
  }) {
    return InkWell(
      onTap: () async {
        final pickedDate = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.light(
                  primary: AppColors.primary, // This sets the main color of the calendar (header, selected date)
                  onPrimary: Colors.white,   // This sets the text color on the primary color
                  onSurface: Colors.black87, // This sets the text color for the dates
                ),
                textButtonTheme: TextButtonThemeData(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary, // This sets the color of the "Cancel" and "OK" buttons
                  ),
                ),
                dialogTheme: DialogTheme(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                ),
              ),
              child: child!,
            );
          },
        );
        if (pickedDate != null) onDateSelected(pickedDate);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.poppins(color: accent),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: accent, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: accent, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: teal, width: 2),
          ),
        ),
        child: Text(
          date != null ? DateFormat.yMMMd().format(date) : 'Tap to select date',
          style: GoogleFonts.poppins(color: date != null ? Colors.black : Colors.grey),
        ),
      ),
    );
  }

  Widget _buildContactsFields() {
    return Column(
      children: [
        _buildTextFormField(_vetNameCtl, 'Vet / Clinic Name'),
        const SizedBox(height: 16),
        _buildTextFormField(_vetPhoneCtl, 'Vet Phone', keyboardType: TextInputType.phone),
        const SizedBox(height: 16),
        _buildTextFormField(_emergencyContactCtl, 'Emergency Contact', keyboardType: TextInputType.phone),
      ],
    );
  }

  Widget _buildPhotosManager() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Profile Image
        Center(
          child: Stack(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: _newCroppedProfileImage != null
                    ? MemoryImage(_newCroppedProfileImage!)
                    : (_existingImageUrl != null && _existingImageUrl!.isNotEmpty
                    ? NetworkImage(_existingImageUrl!)
                    : null) as ImageProvider?,
                child: _newCroppedProfileImage == null && (_existingImageUrl == null || _existingImageUrl!.isEmpty)
                    ? const Icon(Icons.pets, size: 40, color: Colors.grey)
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: InkWell(
                  onTap: _isEditLocked ? null : _pickProfileImage,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: _isEditLocked ? Colors.grey : teal,
                    child: const Icon(Icons.edit, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildHeader('Extra Photos (Max 5)'),
        // Display existing extra photos
        if (_existingExtraImageUrls.isNotEmpty || _newExtraImages.isNotEmpty)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ..._existingExtraImageUrls.map((url) => _buildEditablePhoto(
                isNew: false,
                imageProvider: NetworkImage(url),
                onDelete: () => _removeExistingExtraImage(url),
              )),
              ..._newExtraImages.map((file) => _buildEditablePhoto(
                isNew: true,
                imageProvider: FileImage(file),
                onDelete: () => _removeNewExtraImage(_newExtraImages.indexOf(file)),
              )),
            ],
          ),
        const SizedBox(height: 16),
        // Add new photo button
        if ((_existingExtraImageUrls.length + _newExtraImages.length) < 5)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _isEditLocked ? null : _pickExtraImages,
              icon: _loadingExtras
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add, color: teal),
              label: Text('Add Photo', style: GoogleFonts.poppins(color: teal)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: teal.withOpacity(0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        if (_loadingExtras) const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildEditablePhoto({
    required ImageProvider imageProvider,
    required VoidCallback onDelete,
    required bool isNew,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            image: DecorationImage(
              image: imageProvider,
              fit: BoxFit.cover,
            ),
          ),
        ),
        if (!_isEditLocked)
          Positioned(
            top: -10,
            right: -10,
            child: InkWell(
              onTap: onDelete,
              child: const CircleAvatar(
                radius: 12,
                backgroundColor: Colors.red,
                child: Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }

  // Paste this entire block into your _EditPetPageState class.

// MARK: - Photo Management Widgets

  Widget _buildAddPhotoButton() {
    final int currentPhotoCount = (_existingImageUrl != null || _newCroppedProfileImage != null ? 1 : 0) +
        _existingExtraImageUrls.length + _newExtraImages.length;

    if (currentPhotoCount >= 6) {
      return const SizedBox.shrink(); // Hide if max photos reached
    }

    return InkWell(
      onTap: _isEditLocked ? null : () {
        final bool canAddProfilePhoto = _existingImageUrl == null && _newCroppedProfileImage == null;
        if (canAddProfilePhoto) {
          _pickProfileImage();
        } else {
          _pickExtraImages();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Center(
          child: Icon(
            Icons.add_a_photo_rounded,
            size: 40,
            color: Colors.grey.shade500,
          ),
        ),
      ),
    );
  }


  // MARK: - Reusable Form Field Widgets

  Widget _buildTextFormField(TextEditingController controller, String label, {TextInputType? keyboardType, int maxLines = 1, String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      enabled: !_isEditLocked,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(color: _isEditLocked ? Colors.grey.shade700 : accent),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: teal, width: 2),
        ),
        filled: _isEditLocked,
        fillColor: Colors.grey.shade100,
      ),
      validator: validator,
    );
  }

  Widget _buildDropdown(String? value, List<String> items, String label, void Function(String?) onChanged) {
    return DropdownButtonFormField<String>(
      value: items.contains(value) ? value : null,
      items: items.map((item) => DropdownMenuItem(
        value: item,
        child: Text(
          item,
          style: GoogleFonts.poppins(color: accent),
        ),
      )).toList(),
      onChanged: _isEditLocked ? null : onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(color: _isEditLocked ? Colors.grey.shade700 : accent),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: teal, width: 2),
        ),
        filled: _isEditLocked,
        fillColor: Colors.grey.shade100,
      ),
      style: GoogleFonts.poppins(color: accent),
    );
  }

  Widget _buildHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: accent)),
    );
  }

  Widget _buildChipManager(String title, List<String> list, TextEditingController controller, VoidCallback onAdd) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(title),
        if (list.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: list.map((item) => Chip(
              label: Text(item),
              onDeleted: _isEditLocked ? null : () => setState(() => list.remove(item)),
            )).toList(),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildTextFormField(controller, 'Add a ${title.toLowerCase().substring(0, title.length -1)}')),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_circle, color: teal),
              onPressed: _isEditLocked ? null : onAdd,
            )
          ],
        )
      ],
    );
  }

  Widget _buildBottomBar() {
    if (_isEditLocked) {
      return Container(
        padding: const EdgeInsets.all(24),
        color: Colors.grey.shade200,
        child: Text(
          'You can edit again in $_daysLeft day(s).',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
              color: Colors.grey.shade700, fontWeight: FontWeight.w500),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, -10))
        ],
      ),
      child: _saving
          ? const Center(child: CircularProgressIndicator(color: teal))
          : ElevatedButton.icon(
        onPressed: _saveChanges,
        icon: const Icon(Icons.save_alt_outlined, color: Colors.white,),
        label: const Text("Save Changes"),
        style: ElevatedButton.styleFrom(
          backgroundColor: teal,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}