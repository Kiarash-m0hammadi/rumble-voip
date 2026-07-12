import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:provider/provider.dart';
import 'package:rumble/services/mumble_service.dart';
import 'package:rumble/models/chat_message.dart';
import 'package:rumble/utils/html_utils.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rumble/components/rumble_tooltip.dart';
import 'package:rumble/src/rust/api/client.dart';

class FloatingChatPanel extends StatefulWidget {
  final int partnerSession;
  final VoidCallback onClose;

  const FloatingChatPanel({
    super.key,
    required this.partnerSession,
    required this.onClose,
  });

  @override
  State<FloatingChatPanel> createState() => _FloatingChatPanelState();
}

class _FloatingChatPanelState extends State<FloatingChatPanel> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Offset _position = const Offset(100, 100);
  bool _minimized = false;

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      context.read<MumbleService>().sendPrivateMessage(widget.partnerSession, text);
      _controller.clear();
      _scrollToBottom();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MumbleService>().addListener(_onMessagesUpdated);
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    try {
      context.read<MumbleService>().removeListener(_onMessagesUpdated);
    } catch (_) {}
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onMessagesUpdated() {
    if (!mounted) return;
    final mumbleService = context.read<MumbleService>();
    final lastMessage = mumbleService.messages.lastOrNull;
    if (lastMessage != null &&
        lastMessage.isPrivate &&
        lastMessage.partnerSession == widget.partnerSession) {
      _scrollToBottom();
      mumbleService.clearUnreadCount();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final mumbleService = context.watch<MumbleService>();
    final partner = mumbleService.users.cast<MumbleUser?>().firstWhere(
          (u) => u?.session == widget.partnerSession,
          orElse: () => null,
        );
    final messages = mumbleService.messages
        .where((m) => m.isPrivate && m.partnerSession == widget.partnerSession)
        .toList();

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position += details.delta;
          });
        },
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          color: theme.colorScheme.background,
          child: Container(
            width: 350,
            height: _minimized ? 50 : 450,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.border),
            ),
            child: Column(
              children: [
                _buildHeader(partner, theme),
                if (!_minimized) ...[
                  Expanded(child: _buildMessageList(messages, theme)),
                  _buildInput(theme),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(MumbleUser? partner, ShadThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted.withValues(alpha: 0.5),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.user, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              partner?.name ?? 'Unknown',
              style: theme.textTheme.small.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          RumbleTooltip(
            message: _minimized ? 'Restore' : 'Minimize',
            child: ShadIconButton.ghost(
              width: 24,
              height: 24,
              padding: EdgeInsets.zero,
              icon: Icon(_minimized ? LucideIcons.maximize2 : LucideIcons.minimize2, size: 14),
              onPressed: () => setState(() => _minimized = !_minimized),
            ),
          ),
          RumbleTooltip(
            message: 'Close',
            child: ShadIconButton.ghost(
              width: 24,
              height: 24,
              padding: EdgeInsets.zero,
              icon: const Icon(LucideIcons.x, size: 14),
              onPressed: widget.onClose,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(List<ChatMessage> messages, ShadThemeData theme) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: msg.isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                '${msg.isSelf ? "Me" : msg.senderName} • ${DateFormat('HH:mm').format(msg.timestamp)}',
                style: theme.textTheme.muted.copyWith(fontSize: 10),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: msg.isSelf
                      ? theme.colorScheme.primary.withValues(alpha: 0.1)
                      : theme.colorScheme.muted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: HtmlWidget(
                  msg.content,
                  textStyle: theme.textTheme.p.copyWith(fontSize: 13),
                  onTapUrl: (url) async {
                    final uri = Uri.parse(url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                    return true;
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInput(ShadThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colorScheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ShadInput(
              controller: _controller,
              placeholder: const Text('Message...'),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          ShadIconButton(
            width: 32,
            height: 32,
            padding: EdgeInsets.zero,
            icon: const Icon(LucideIcons.send, size: 16),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }
}
