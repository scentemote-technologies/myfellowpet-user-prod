import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart'; // REQUIRED: Add intl to pubspec.yaml

import '../Tickets/chat_support.dart';
import '../chat_helper.dart';

class BoardingChatScreen extends StatefulWidget {
  final String chatId;
  final String shopName;
  final String bookingId;
  final String serviceId;

  const BoardingChatScreen({Key? key, required this.chatId, required this.shopName, required this.bookingId, required this.serviceId}) : super(key: key);

  @override
  _BoardingChatScreenState createState() => _BoardingChatScreenState();
}

class _BoardingChatScreenState extends State<BoardingChatScreen> {
  final _db = FirebaseFirestore.instance;
  final _messaging = FirebaseMessaging.instance;
  late final types.User _me;
  List<types.Message> _messages = [];
  bool _userChatEnabled = true;
  bool _spChatEnabled = true;

  // --- Design Constants ---
  static const Color primaryColor = Color(0xFF2CB4B6);
  static const Color primaryDark = Color(0xFF1F8E90);
  static const Color bgGrey = Color(0xFFF2F4F7); // WhatsApp-like background grey

  @override
  void initState() {
    super.initState();
    _me = types.User(id: FirebaseAuth.instance.currentUser!.uid);

    final chatDoc = _db.collection('chats').doc(widget.chatId);

    // subscribe + mark read
    _messaging.subscribeToTopic('chat_${widget.chatId}');
    chatDoc.set({'lastReadBy_${_me.id}': FieldValue.serverTimestamp()}, SetOptions(merge: true));

    // watch for chat toggles
    chatDoc.snapshots().listen((snap) {
      final data = snap.data() as Map<String, dynamic>? ?? {};
      setState(() {
        _userChatEnabled = data['user_chat'] as bool? ?? true;
        _spChatEnabled = data['sp_chat'] as bool? ?? true;
      });
    });

    // live messages
    chatDoc
        .collection('messages')
        .orderBy('timestamp')
        .snapshots()
        .listen((snap) {
      final msgs = snap.docs.map((d) {
        final data = d.data();
        return types.TextMessage(
          id: d.id,
          author: types.User(id: data['senderId'] as String),
          text: data['text'] as String,
          createdAt: (data['timestamp'] as Timestamp).millisecondsSinceEpoch,
          metadata: {'sent_by': data['sent_by']},
        );
      }).toList();

      setState(() => _messages = msgs.reversed.toList());
      chatDoc.update({'lastReadBy_${_me.id}': FieldValue.serverTimestamp()});
    });
  }

  @override
  void dispose() {
    _messaging.unsubscribeFromTopic('chat_${widget.chatId}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGrey, // Light grey background like modern chat apps
      appBar: _buildModernAppBar(),
      body: Column(
        children: [
          if (!_userChatEnabled || !_spChatEnabled)
            Container(
              width: double.infinity,
              color: Colors.red.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: Colors.red.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      !_userChatEnabled
                          ? 'Messaging disabled by Admin.'
                          : "Service Provider cannot reply right now.",
                      style: GoogleFonts.poppins(fontSize: 13, color: Colors.red.shade800, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Chat(
              messages: _messages,
              user: _me,
              onSendPressed: (types.PartialText msg) {
                if (!_userChatEnabled) return;
                ChatHelper.sendMessage(
                  context: context,
                  chatId: widget.chatId,
                  message: msg,
                );
              },
              // 1. Theme Configuration
              theme: DefaultChatTheme(
                backgroundColor: bgGrey,

                // Input Bar Styling
                inputBackgroundColor: Colors.white,
                inputTextColor: Colors.black87,
                inputPadding: const EdgeInsets.all(14),
                inputBorderRadius: BorderRadius.circular(24),
                inputContainerDecoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                inputTextCursorColor: primaryColor,

                // Send Button Styling
                sendButtonIcon: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),

                // 👇👇👇 CRITICAL FIX: Change color to Colors.black87 👇👇👇
                sentMessageBodyTextStyle: GoogleFonts.poppins(
                  color: Colors.black87, // <--- WAS WHITE, NOW BLACK
                  fontSize: 14.5,
                  height: 1.5,
                ),

                receivedMessageBodyTextStyle: GoogleFonts.poppins(
                  color: Colors.black87,
                  fontSize: 14.5,
                  height: 1.5,
                ),

                // Date Separators
                dateDividerTextStyle: GoogleFonts.poppins(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),

              // 2. Custom Bubble Builder
              bubbleBuilder: _buildCustomBubble,

              // 3. Remove default avatars (we handle labels inside bubbles for clarity)
              showUserAvatars: false,
              showUserNames: false,
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGET HELPERS ---

  PreferredSizeWidget _buildModernAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 2,
      shadowColor: Colors.black.withOpacity(0.1),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Colors.black87),
        onPressed: () => Navigator.pop(context),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          // Avatar
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: primaryColor, width: 1.5),
            ),
            child: const CircleAvatar(
              radius: 18,
              backgroundColor: Colors.grey,
              child: Icon(Icons.store, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          // Name & Status
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Boarding Service', // Ideally pass shopName to widget
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Support',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserOrderSupportPage(
                  initialOrderId: widget.bookingId,
                  serviceId: widget.serviceId,
                  shop_name: widget.shopName,
                  user_phone_number: FirebaseAuth.instance.currentUser?.phoneNumber,
                  user_uid: FirebaseAuth.instance.currentUser?.uid, // if you don’t store email, keep blank
                ),
              ),
            );
          },


          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                FontAwesomeIcons.headset,
                size: 20,
                color: Colors.black87,
              ),
            ],
          ),
        )
      ],
    );
  }
  Widget _buildCustomBubble(
      Widget child, {
        required types.Message message,
        required bool nextMessageInGroup,
      }) {
    final isMyMessage = message.author.id == _me.id;
    final role = (message.metadata?['sent_by'] ?? '').toString();

    final time = DateFormat('hh:mm a').format(
      DateTime.fromMillisecondsSinceEpoch(message.createdAt ?? 0),
    );

    String label = '';
    Color labelColor = Colors.grey;

    if (!isMyMessage) {
      if (role == 'sp') {
        label = 'Service Provider';
        labelColor = primaryColor;
      } else if (role == 'admin') {
        label = 'Admin';
        labelColor = Colors.orange.shade800;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Column(
        crossAxisAlignment:
        isMyMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // ---------------------------
          //   CHAT BUBBLE
          // ---------------------------
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.88,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                color: isMyMessage ? primaryColor : Colors.grey.shade300,
                width: 1.3,
              ),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft:
                isMyMessage ? const Radius.circular(16) : const Radius.circular(3),
                bottomRight:
                isMyMessage ? const Radius.circular(3) : const Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                )
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,   // ↓ tightened
                vertical: 3,     // ↓ tightened
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ultra-tight label
                  if (!isMyMessage && label.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: Text(
                        label,
                        style: GoogleFonts.poppins(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: labelColor,
                        ),
                      ),
                    ),

                  child,
                ],
              ),
            ),
          ),

          // ---------------------------
          //   TIME BELOW THE BUBBLE
          // ---------------------------
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 10, left: 10),
            child: Text(
              time,
              style: GoogleFonts.poppins(
                fontSize: 9,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

}