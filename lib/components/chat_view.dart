import 'package:flutter/material.dart';
import 'package:rumble/utils/layout_constants.dart';
import 'package:provider/provider.dart';
import 'package:rumble/services/mumble_service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:rumble/utils/html_utils.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:intl/intl.dart';
import 'package:rumble/components/image_gallery.dart';
import 'package:rumble/components/ptt_button.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rumble/components/rumble_tooltip.dart';

class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _shouldAutoScroll = true;
  bool _isAutoScrolling = false;
  int _lastMessageCount = 0;
  String _selectedTab = 'channel';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    // Listen for new messages to auto-scroll
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mumbleService = context.read<MumbleService>();
      _lastMessageCount = mumbleService.messages.length;
      mumbleService.clearUnreadCount();
      mumbleService.addListener(_onMessagesUpdated);
      mumbleService.addListener(_onServiceChanged);
      _focusNode.onKeyEvent = _onKeyEvent;

      if (mumbleService.selectedPmSession != null) {
        setState(() {
          _selectedTab = 'pm_${mumbleService.selectedPmSession}';
        });
      }
    });
  }

  @override
  void dispose() {
    // Safely remove listener
    try {
      final mumbleService = context.read<MumbleService>();
      mumbleService.removeListener(_onMessagesUpdated);
      mumbleService.removeListener(_onServiceChanged);
    } catch (_) {}
    _controller.dispose();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (!_scrollController.hasClients || _isAutoScrolling) return;

    final pos = _scrollController.position;
    // Use a tighter threshold (20px) to prevent accidental reactivation while scrolling away
    final atBottom = pos.pixels >= pos.maxScrollExtent - 20;

    if (atBottom != _shouldAutoScroll) {
      setState(() {
        _shouldAutoScroll = atBottom;
      });
    }
  }

  void _onServiceChanged() {
    if (!mounted) return;
    final mumbleService = context.read<MumbleService>();
    final session = mumbleService.selectedPmSession;
    if (session != null) {
      final newTab = 'pm_$session';
      if (_selectedTab != newTab) {
        setState(() {
          _selectedTab = newTab;
        });
      }
    } else if (_selectedTab.startsWith('pm_')) {
      // If we were on a PM tab but no PM session is selected globally, we might stay there
      // unless the session was actually closed.
      if (!mumbleService.activePmSessions.contains(int.tryParse(_selectedTab.substring(3)))) {
        setState(() {
          _selectedTab = 'channel';
        });
      }
    }
  }

  void _onMessagesUpdated() {
    if (!mounted) return;
    final mumbleService = context.read<MumbleService>();
    final newCount = mumbleService.messages.length;

    // Only act if messages were actually added
    if (newCount > _lastMessageCount) {
      final lastMessage = mumbleService.messages.last;

      _lastMessageCount = newCount;
      if (lastMessage.isPrivate &&
          !lastMessage.isSelf &&
          _selectedTab != 'pm_${lastMessage.partnerSession}' &&
          !(widget.poppedOutSessions?.contains(lastMessage.partnerSession) ??
              false)) {
        // PM received but not in focus, and not popped out
      } else {
        mumbleService.clearUnreadCount();
      }
      if (_shouldAutoScroll) {
        _scrollToBottom();
      }
    }
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      final recipientSession =
          _selectedTab.startsWith('pm_')
              ? int.tryParse(_selectedTab.substring(3))
              : null;
      context.read<MumbleService>().sendMessage(
        text,
        recipientSession: recipientSession,
      );
      _controller.clear();
      _scrollToBottom();
    }
    _focusNode.requestFocus();
  }

  void _scrollToBottom() {
    if (!mounted || !_scrollController.hasClients) return;

    void executeScroll(int durationMs) {
      if (!mounted || !_scrollController.hasClients) return;
      _isAutoScrolling = true;
      _scrollController
          .animateTo(
            _scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: durationMs),
            curve: Curves.easeOut,
          )
          .then((_) {
            if (mounted) _isAutoScrolling = false;
          });
    }

    // First scroll attempt
    WidgetsBinding.instance.addPostFrameCallback((_) => executeScroll(300));

    // Follow-up scrolls after short delays to catch any "late" height changes from image rendering
    for (final ms in [100, 300, 800]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (mounted && _shouldAutoScroll && !_isAutoScrolling) {
          executeScroll(150);
        }
      });
    }
  }

  void _copyMessage(String content) {
    final markdown = HtmlUtils.htmlToMarkdown(content);
    Clipboard.setData(ClipboardData(text: markdown));

    if (mounted) {
      ShadToaster.of(context).show(
        ShadToast(
          title: const Text('Copied'),
          description: const Text('Message copied with formatting intact'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handlePaste() async {
    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null) {
        final html = HtmlUtils.imageToHtml(imageBytes);
        if (mounted) {
          context.read<MumbleService>().sendMessage(html);
          _scrollToBottom();
        }
      }
    } catch (e) {
      debugPrint('Error pasting image: $e');
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      // Check for Cmd+V or Ctrl+V
      final bool isV = event.logicalKey == LogicalKeyboardKey.keyV;
      final bool modifierPressed =
          HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed;

      if (isV && modifierPressed) {
        _handlePaste();
        return KeyEventResult.ignored;
      }

      // Handle Enter to send, Shift+Enter for new line
      final bool isEnter =
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter;
      final bool isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

      if (isEnter && !isShiftPressed) {
        _sendMessage();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final mumbleService = context.watch<MumbleService>();
    final isSlim = LayoutConstants.isSlim(context);

    final List<ChatMessage> filteredMessages;
    if (_selectedTab == 'channel') {
      filteredMessages =
          mumbleService.messages.where((m) => !m.isPrivate).toList();
    } else if (_selectedTab.startsWith('pm_')) {
      final session = int.tryParse(_selectedTab.substring(3));
      filteredMessages =
          mumbleService.messages
              .where((m) => m.isPrivate && m.partnerSession == session)
              .toList();
    } else {
      filteredMessages = [];
    }

    return Stack(
      children: [
        Column(
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.border.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    _buildTab(
                      id: 'channel',
                      label: mumbleService.currentChannelName,
                      icon: LucideIcons.hash,
                      theme: theme,
                    ),
                    ...mumbleService.activePmSessions.map((session) {
                      if (widget.poppedOutSessions?.contains(session) ?? false) {
                        return const SizedBox.shrink();
                      }
                      final user = mumbleService.users.cast<MumbleUser?>().firstWhere(
                        (u) => u?.session == session,
                        orElse: () => null,
                      );
                      return _buildTab(
                        id: 'pm_$session',
                        label: user?.name ?? 'Unknown',
                        icon: LucideIcons.user,
                        theme: theme,
                        onClose: () => mumbleService.closePmSession(session),
                        onPopOut: () => widget.onPopOut?.call(session),
                      );
                    }),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SelectionArea(
                      child: ListView.builder(
                        controller: _scrollController,
                        cacheExtent: 5000, // Force eager layout of images
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredMessages.length,
                        itemBuilder: (context, index) {
                          final msg = filteredMessages[index];
                          if (msg.isSystem) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: Column(
                                  children: [
                                    Text(
                                      '[${DateFormat('HH:mm:ss').format(msg.timestamp)}] ${msg.senderName}:',
                                      style: theme.textTheme.muted.copyWith(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    HtmlWidget(
                                      msg.content,
                                      enableCaching: true,
                                      textStyle: theme.textTheme.muted.copyWith(
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                      ),
                                      onTapImage: (imageData) {
                                        final allImages = filteredMessages
                                            .expand(
                                              (m) =>
                                                  HtmlUtils.extractImageSources(
                                                    m.content,
                                                  ),
                                            )
                                            .toList();
                                        final index = allImages.indexOf(
                                          imageData.sources.first.url,
                                        );
                                        ImageGalleryDialog.show(
                                          context,
                                          allImages,
                                          index >= 0 ? index : 0,
                                        );
                                      },
                                      onTapUrl: (url) async {
                                        final uri = Uri.parse(url);
                                        if (await canLaunchUrl(uri)) {
                                          await launchUrl(uri);
                                        }
                                        return true;
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: msg.isSelf
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!msg.isSelf)
                                      Text(
                                        msg.senderName,
                                        style: theme.textTheme.small.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    const SizedBox(width: 8),
                                    Text(
                                      DateFormat('HH:mm').format(msg.timestamp),
                                      style: theme.textTheme.muted.copyWith(
                                        fontSize: 10,
                                      ),
                                    ),
                                    if (msg.isSelf)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: Text(
                                          msg.senderName,
                                          style: theme.textTheme.small.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: theme
                                                .colorScheme
                                                .mutedForeground,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: msg.isSelf
                                        ? theme.colorScheme.primary.withValues(
                                            alpha: 0.1,
                                          )
                                        : theme.colorScheme.muted.withValues(
                                            alpha: 0.2,
                                          ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: msg.isSelf
                                          ? theme.colorScheme.primary
                                                .withValues(alpha: 0.2)
                                          : theme.colorScheme.border.withValues(
                                              alpha: 0.5,
                                            ),
                                    ),
                                  ),
                                  child: Stack(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 24,
                                        ),
                                        child: HtmlWidget(
                                          msg.content,
                                          enableCaching: true,
                                          textStyle: theme.textTheme.p.copyWith(
                                            fontSize: 14,
                                            height: 1.4,
                                          ),
                                          onTapImage: (imageData) {
                                            // Extract LATEST unique images from filtered messages
                                            final allImages = filteredMessages
                                                .expand(
                                                  (m) =>
                                                      HtmlUtils.extractImageSources(
                                                        m.content,
                                                      ),
                                                )
                                                .toList();
                                            // Handle duplicates by getting unique list while preserving order
                                            final uniqueImages = <String>[];
                                            for (final img in allImages) {
                                              if (!uniqueImages.contains(img)) {
                                                uniqueImages.add(img);
                                              }
                                            }

                                            final currentUrl =
                                                imageData.sources.first.url;
                                            final index = uniqueImages.indexOf(
                                              currentUrl,
                                            );

                                            ImageGalleryDialog.show(
                                              context,
                                              uniqueImages,
                                              index >= 0 ? index : 0,
                                            );
                                          },
                                          onTapUrl: (url) async {
                                            final uri = Uri.parse(url);
                                            if (await canLaunchUrl(uri)) {
                                              await launchUrl(uri);
                                            }
                                            return true;
                                          },
                                          customStylesBuilder: (element) {
                                            if (element.localName == 'img') {
                                              return {
                                                'width': 'auto',
                                                'max-width': '100%',
                                                'height': 'auto',
                                                'cursor': 'pointer',
                                                'border-radius': '8px',
                                              };
                                            }
                                            if (element.localName == 'ul' ||
                                                element.localName == 'ol') {
                                              return {
                                                'padding-left': '12px',
                                                'margin-top': '4px',
                                                'margin-bottom': '4px',
                                                'list-style-type':
                                                    element.localName == 'ul'
                                                    ? 'disc'
                                                    : 'decimal',
                                              };
                                            }
                                            if (element.localName == 'li') {
                                              return {
                                                'margin-bottom': '4px',
                                                'display': 'list-item',
                                              };
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                      Positioned(
                                        right: -8,
                                        top: -8,
                                        child: RumbleTooltip(
                                          message: 'Copy message',
                                          child: ShadIconButton.ghost(
                                            icon: Icon(
                                              LucideIcons.copy,
                                              size: 14,
                                              color: theme
                                                  .colorScheme
                                                  .mutedForeground
                                                  .withValues(alpha: 0.5),
                                            ),
                                            width: 32,
                                            height: 32,
                                            padding: EdgeInsets.zero,
                                            onPressed: () =>
                                                _copyMessage(msg.content),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (!_shouldAutoScroll)
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: RumbleTooltip(
                        message: 'Scroll to latest',
                        child: ShadIconButton.secondary(
                          icon: const Icon(LucideIcons.chevronDown, size: 16),
                          onPressed: () {
                            _scrollToBottom();
                            setState(() {
                              _shouldAutoScroll = true;
                            });
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.border.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ShadInput(
                      controller: _controller,
                      focusNode: _focusNode,
                      autofocus: true,
                      minLines: 1,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      placeholder: const Text('Type a message...'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  RumbleTooltip(
                    message: 'Send message',
                    child: ShadIconButton(
                      icon: const Icon(LucideIcons.send, size: 18),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (isSlim && mumbleService.isConnected)
          Positioned(
            left: 0,
            right: 0,
            bottom: 84, // Anchored closer to the input area
            child: Center(
              child: PushToTalkButton(
                service: mumbleService,
                width: 180,
                height: 48,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTab({
    required String id,
    required String label,
    required IconData icon,
    required ShadThemeData theme,
    VoidCallback? onClose,
    VoidCallback? onPopOut,
  }) {
    final isSelected = _selectedTab == id;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedTab = id);
        if (id.startsWith('pm_')) {
          context.read<MumbleService>().selectPmSession(int.tryParse(id.substring(3)));
        } else {
          context.read<MumbleService>().selectPmSession(null);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? theme.colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.05)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.mutedForeground,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.small.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? theme.colorScheme.foreground
                    : theme.colorScheme.mutedForeground,
              ),
            ),
            if (onPopOut != null) ...[
              const SizedBox(width: 8),
              RumbleTooltip(
                message: 'Pop out',
                child: GestureDetector(
                  onTap: () {
                    onPopOut();
                    if (_selectedTab == id) {
                      setState(() => _selectedTab = 'channel');
                    }
                  },
                  child: Icon(
                    LucideIcons.externalLink,
                    size: 12,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              ),
            ],
            if (onClose != null) ...[
              const SizedBox(width: 8),
              RumbleTooltip(
                message: 'Close tab',
                child: GestureDetector(
                  onTap: () {
                    onClose();
                    if (_selectedTab == id) {
                      setState(() => _selectedTab = 'channel');
                    }
                  },
                  child: Icon(
                    LucideIcons.x,
                    size: 12,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
