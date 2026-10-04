import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/launchers.dart';
import '../../data/models/delivery.dart';
import '../../providers/auth_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';

final _messagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, String>((ref, id) => ref.watch(communicationRepositoryProvider).watchMessages(id));

/// Messagerie client ↔ livreur liée à une livraison.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.deliveryId});
  final String deliveryId;
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  bool _sending = false;

  static const _quick = ['J\'arrive', 'Je suis devant', 'Appelez-moi svp', 'D\'accord, merci'];

  Future<void> _send([String? text]) async {
    final body = (text ?? _input.text).trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(communicationRepositoryProvider).sendMessage(widget.deliveryId, body);
      _input.clear();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final delivery = ref.watch(deliveryStreamProvider(widget.deliveryId)).value;
    final messages = ref.watch(_messagesProvider(widget.deliveryId));
    ref.listen(_messagesProvider(widget.deliveryId), (_, next) {
      if (next.hasValue) ref.read(communicationRepositoryProvider).markMessagesRead(widget.deliveryId).ignore();
    });

    final isDriver = delivery != null && delivery.driverId == me?.id;
    final otherPhone = delivery == null ? null : (isDriver ? delivery.customerPhone : null);

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isDriver ? delivery.customerName : 'Votre livreur'),
          if (delivery != null) Text(delivery.code, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ]),
        actions: [
          if (otherPhone != null) IconButton(onPressed: () => callPhone(otherPhone), icon: const Icon(Icons.call)),
        ],
      ),
      body: Constrained(
        maxWidth: 720,
        child: Column(children: [
          Expanded(
            child: AsyncBody<List<ChatMessage>>(
              value: messages,
              builder: (list) => list.isEmpty
                  ? const EmptyState(icon: Icons.chat_bubble_outline, message: 'Aucun message. Écrivez au correspondant.')
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(12),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final m = list[list.length - 1 - i];
                        final mine = m.senderId == me?.id;
                        return Align(
                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
                            decoration: BoxDecoration(
                              color: mine ? AppColors.primary : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: mine ? null : Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(m.body, style: TextStyle(color: mine ? Colors.white : null, fontSize: 15)),
                              Text(
                                '${formatTime(m.createdAt)}${mine && m.readAt != null ? ' · lu' : ''}',
                                style: TextStyle(fontSize: 11, color: mine ? Colors.white70 : AppColors.textMuted),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
          ),
          if (delivery != null && delivery.status.isActive) ...[
            SizedBox(
              height: 44,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                for (final q in _quick)
                  Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(label: Text(q), onPressed: () => _send(q))),
              ]),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(hintText: 'Votre message…'),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                    style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
                  ),
                ]),
              ),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('La conversation est fermée.', style: TextStyle(color: AppColors.textMuted)),
            ),
        ]),
      ),
    );
  }
}
