import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';

class PetHeaderMedia extends StatefulWidget {
  const PetHeaderMedia({Key? key}) : super(key: key);

  @override
  _PetHeaderMediaState createState() => _PetHeaderMediaState();
}

class _PetHeaderMediaState extends State<PetHeaderMedia> {
  // State variables to hold the media details
  bool _isLoading = true;
  String? _mediaUrl;
  String? _fallbackImageUrl; // NEW: To store the fallback URL
  bool _isImage = true;
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    _loadMediaFromFirestore();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  /// Fetches media URLs from Firestore and determines media type.
  Future<void> _loadMediaFromFirestore() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('photos_and_videos')
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;

        // NEW: Fetch the fallback URL first.
        _fallbackImageUrl = data['pet_store_homepage_fallback'] as String?;

        // Continue with the primary media URL.
        if (data.containsKey('pet_store_homepage')) {
          final url = data['pet_store_homepage'] as String?;

          if (url != null && url.isNotEmpty) {
            _mediaUrl = url;
            if (url.toLowerCase().endsWith('.mp4') || url.toLowerCase().endsWith('.mov')) {
              _isImage = false;
              _videoController = VideoPlayerController.networkUrl(Uri.parse(url))
                ..initialize().then((_) {
                  if (mounted) setState(() {});
                  _videoController!.setLooping(true);
                  _videoController!.setVolume(0.0);
                  _videoController!.play();
                });
            } else {
              _isImage = true;
            }
          }
        }
      }
    } catch (e) {
      print("Error loading header media: $e");
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Builds the fallback widget. Tries Firestore URL first, then local asset.
  Widget _buildFallback() {
    // Check if we have a valid fallback URL from Firestore
    if (_fallbackImageUrl != null && _fallbackImageUrl!.isNotEmpty) {
      return Image.network(
        _fallbackImageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        // If even the Firestore fallback fails, use the local asset
        errorBuilder: (context, error, stackTrace) {
          return Image.asset(
            'assets/skeletoncompanylogo.png',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          );
        },
      );
    } else {
      // If no fallback URL was found, use the local asset directly
      return Image.asset(
        'assets/skeletoncompanylogo.png',
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildFallback(); // UPDATED
    }

    if (_mediaUrl == null) {
      return _buildFallback(); // UPDATED
    }

    if (_isImage) {
      return Image.network(
        _mediaUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildFallback(); // UPDATED
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildFallback(); // UPDATED
        },
      );
    } else {
      if (_videoController != null && _videoController!.value.isInitialized) {
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _videoController!.value.size.width,
              height: _videoController!.value.size.height,
              child: VideoPlayer(_videoController!),
            ),
          ),
        );
      } else {
        return _buildFallback(); // UPDATED
      }
    }
  }
}