import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';

import '../chat_helper.dart';

class BoardingChatScreen extends StatefulWidget {
  final String chatId;
  const BoardingChatScreen({Key? key, required this.chatId}) : super(key: key);

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

  static const Color primaryColor = Color(0xFF2CB4B6); // Your teal primary color
  static const Color accentColor = Color(0xFFE0F7FA); // A light, complementary color

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
      appBar: AppBar(
        title: Text('Boarding Chat', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
      ),
      body: Column(
        children: [
          if (!_userChatEnabled || !_spChatEnabled)
            Container(
              color: Colors.red.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                !_userChatEnabled
                    ? 'Admin has blocked your ability to chat.'
                    : "Admin has blocked Service Provider's ability to chat.",
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.red.shade700),
                textAlign: TextAlign.center,
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
              theme: DefaultChatTheme(
                backgroundColor: Colors.grey.shade50, // A light background for the chat
                inputBackgroundColor: Colors.white,
                inputTextColor: Colors.black87,
                inputTextCursorColor: primaryColor,
                inputBorderRadius: BorderRadius.circular(24),
                inputPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                inputTextStyle: GoogleFonts.poppins(color: Colors.black87, fontSize: 16),
                inputContainerDecoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade200, width: 1.5),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                sendButtonIcon: Icon(
                  Icons.send_rounded,
                  color: primaryColor,
                  size: 24,
                ),
                primaryColor: primaryColor,
                secondaryColor: Colors.grey.shade200,
                sentMessageBodyTextStyle: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                receivedMessageBodyTextStyle: GoogleFonts.poppins(color: Colors.black87, fontSize: 14),
                userAvatarTextStyle: GoogleFonts.poppins(fontSize: 12),
              ),
              // REPLACE your entire bubbleBuilder with this one

              bubbleBuilder: (child, {required message, required nextMessageInGroup}) {
                final isMyMessage = message.author.id == _me.id;
                final role = (message.metadata?['sent_by'] ?? '').toString();
                String label;
                Color bubbleColor;

                switch (role) {
                  case 'sp':
                    label = 'Service Provider';
                    bubbleColor = Colors.grey.shade200;
                    break;
                  case 'admin':
                    label = 'Admin';
                    bubbleColor = Colors.red.shade100;
                    break;
                  case 'user':
                  default:
                    label = 'You';
                    bubbleColor = primaryColor;
                    break;
                }

                if (isMyMessage) {
                  return Container(
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                        bottomRight: nextMessageInGroup ? Radius.circular(4) : Radius.circular(16),
                      ),
                    ),
                    // --- FIX #1: The smaller padding you already applied ---
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: child,
                  );
                } else {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
                        child: Text(
                          label,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: bubbleColor,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                            bottomLeft: nextMessageInGroup ? Radius.circular(4) : Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          ),
                        ),
                        // --- FIX #2: Apply the same smaller padding here for received messages ---
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        child: child,
                      ),
                    ],
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

