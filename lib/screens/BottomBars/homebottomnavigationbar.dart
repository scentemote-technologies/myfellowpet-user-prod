// lib/widgets/BottomNavigationBarWidget.dart

import 'package:flutter/material.dart';

class BottomNavigationBarWidget extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BottomNavigationBarWidget({
    Key? key,
    required this.currentIndex,
    required this.onTap,
  }) : super(key: key);

  static final List<Map<String, dynamic>> _items = [
    {
      'activeImage': 'assets/companylogo.png',
      'inactiveImage': 'assets/skeletoncompanylogo.png',
      'label': 'Home',
    },
    {
      'activeImage': 'assets/BottomBarBoarding/BottomBarBoardingActive.png',
      'inactiveImage': 'assets/BottomBarBoarding/BottomBarBoardingInactive.png',
      'label': 'Boarding',
    },
    {
      'activeImage': 'assets/yourpetsbottombaractive.png',
      'inactiveImage': 'assets/yourpetsbottombarinactive.jpg',
      'label': 'Pets',
    },
    {
      'activeImage': 'assets/ordersbottombaractive.png',
      'inactiveImage': 'assets/ordersbottombar.jpg',
      'label': 'Orders',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical:15),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(_items.length, (index) {
          final item = _items[index];
          final activeImagePath = item['activeImage'] as String?;
          final inactiveImagePath = item['inactiveImage'] as String?;
          final label = item['label'] as String? ?? '';

          return _NavItem(
            activeImagePath: activeImagePath,
            inactiveImagePath: inactiveImagePath,
            label: label,
            isActive: currentIndex == index,
            onTap: () {
              if (index == currentIndex) return;
              onTap(index);
            },
          );
        }),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final String? activeImagePath;
  final String? inactiveImagePath;
  final String? label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    Key? key,
    this.activeImagePath,
    this.inactiveImagePath,
    this.label,
    required this.isActive,
    required this.onTap,
  }) : super(key: key);

  @override
  __NavItemState createState() => __NavItemState();
}

class __NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final imagePath = widget.isActive ? widget.activeImagePath : widget.inactiveImagePath;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,

              ),
              child: imagePath != null
                  ? Image.asset(
                imagePath,
                width: 36,
                height: 36,
                fit: BoxFit.contain,
              )
                  : const SizedBox(),
            ),

// Optional label shown always (or you can use another condition)
            if (widget.label != null && widget.label!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Text(
                  widget.label!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),

          ],
        ),
      ),
    );
  }
}
