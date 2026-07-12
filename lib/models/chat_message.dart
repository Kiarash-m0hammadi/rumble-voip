import 'package:rumble/src/rust/api/client.dart';

class ChatMessage {
  final String senderName;
  final String content;
  final DateTime timestamp;
  final bool isSelf;
  final bool isSystem;
  final bool isPrivate;
  final int? recipientSession; // Only for outgoing PMs
  final int? senderSession; // For incoming PMs
  final MumbleUser? sender;

  ChatMessage({
    required this.senderName,
    required this.content,
    required this.timestamp,
    required this.isSelf,
    this.isSystem = false,
    this.isPrivate = false,
    this.recipientSession,
    this.senderSession,
    this.sender,
  });

  /// The session ID of the other person in a PM, regardless of who sent it.
  int? get partnerSession => isPrivate ? (isSelf ? recipientSession : senderSession) : null;
}
