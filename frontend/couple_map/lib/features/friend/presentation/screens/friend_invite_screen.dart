import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../domain/providers/friend_provider.dart';

class FriendInviteSheet extends ConsumerStatefulWidget {
  final VoidCallback? onAdded;

  const FriendInviteSheet({super.key, this.onAdded});

  @override
  ConsumerState<FriendInviteSheet> createState() => _FriendInviteSheetState();
}

class _FriendInviteSheetState extends ConsumerState<FriendInviteSheet> {
  final TextEditingController _codeController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  static final _friendCodeRegex = RegExp(r'^[A-Z0-9]{5}$');

  Future<void> _sendRequest() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    if (!_friendCodeRegex.hasMatch(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('친구 코드는 영문 대문자와 숫자 5자리입니다')),
      );
      return;
    }
    final auth = ref.read(authProvider);
    if (auth is! AuthSuccess) return;
    setState(() => _isSending = true);
    try {
      await ref.read(friendRepositoryProvider).sendFriendRequest(code);
      if (mounted) {
        Navigator.pop(context);
        widget.onAdded?.call();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('친구 요청을 보냈어요!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('오류: ${e.toString()}')));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '친구 초대',
            style: TextStyle(
              fontFamily: 'NotoSerifKR',
              color: Color(0xFF191919),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '친구의 코드를 입력해주세요.',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            maxLength: 5,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Color(0xFF191919),
            ),
            decoration: InputDecoration(
              hintText: '예: AB3C5',
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
              filled: true,
              fillColor: const Color(0xFFF2F0EC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isSending ? null : _sendRequest,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF7A7A),
                disabledBackgroundColor: const Color(0xFFFFB5B5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _isSending
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      '추가하기',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFE0E0E0)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                '닫기',
                style: TextStyle(
                  color: Color(0xFF191919),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
