import 'package:flutter/material.dart';

class LikeButton extends StatefulWidget {
  final String serviceId;
  final bool initiallyLiked;
  final Function(String serviceId) onToggle;

  const LikeButton({
    Key? key,
    required this.serviceId,
    required this.initiallyLiked,
    required this.onToggle,
  }) : super(key: key);

  @override
  _LikeButtonState createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> {
  late bool isLiked;

  @override
  void initState() {
    super.initState();
    isLiked = widget.initiallyLiked;
  }

  @override
  void didUpdateWidget(covariant LikeButton oldWidget) {
    // Ensure the internal state is updated if the parent changes the initiallyLiked value.
    if (oldWidget.initiallyLiked != widget.initiallyLiked) {
      isLiked = widget.initiallyLiked;
    }
    super.didUpdateWidget(oldWidget);
  }

  void toggle() {
    setState(() {
      isLiked = !isLiked;
    });
    widget.onToggle(widget.serviceId);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFFF5B20)),
        color: Colors.white,
      ),
      height: 45,
      width: 45,
      child: IconButton(
        onPressed: toggle,
        // AnimatedSwitcher animates changes between icons.
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) {
            return ScaleTransition(
              scale: animation,
              child: child,
            );
          },
          // The key differentiates the two icon states.
          child: Icon(
            isLiked ? Icons.favorite : Icons.favorite_border,
            key: ValueKey<bool>(isLiked),
            color: isLiked ? const Color(0xFFFF5B20) : Colors.grey,
          ),
        ),
      ),
    );
  }
}
