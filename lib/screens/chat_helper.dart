// lib/utils/chat_helper.dart

import 'package:flutter/material.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatHelper {
  // 1) 6+ digit runs (phone‐style or account numbers)
  static final RegExp _longDigits = RegExp(r'\b\d{6,}\b');

  // 2) Simple domain‐pattern: word + dot + at least 2 letters (e.g. foo.com, bar.co.uk)
  static final RegExp _domain = RegExp(
    r'\b[\w-]+(?:\.[\w-]+)+\b',
    caseSensitive: false,
  );

  /// Returns true if [text] passes our rules.
  static bool isValid(String text) {
    if (_longDigits.hasMatch(text)) return false;
    if (_domain.hasMatch(text))    return false;
    return true;
  }

  /// Call this from your ChatScreen's `onSendPressed`.
  static Future<void> sendMessage({
    required BuildContext context,
    required String chatId,
    required types.PartialText message,
    String sentBy = 'user',
  }) async {
    final text = message.text.trim();
    if (!isValid(text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please avoid sharing long digit sequences or domain names.',
          ),
        ),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final chatDoc = FirebaseFirestore.instance.collection('chats').doc(chatId);

    // save the message
    final msgRef = chatDoc.collection('messages').doc();
    await msgRef.set({
      'text':      text,
      'sent_by': sentBy,
      'senderId':  uid,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // update the chat header
    await chatDoc.set({
      'lastMessage': text,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
