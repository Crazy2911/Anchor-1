import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'repository.dart';

class QuoteDialog extends StatefulWidget {
  final String initialText;
  final Future<String> Function(String text, String tone) generate;

  const QuoteDialog({
    super.key,
    required this.initialText,
    required this.generate,
  });

  @override
  State<QuoteDialog> createState() => _QuoteDialogState();
}

class _QuoteDialogState extends State<QuoteDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController situationController;
  final quoteController = TextEditingController();

  String tone = 'gentle';
  String? error;
  String? copyMessage;
  bool consent = false;
  bool generating = false;
  bool hasQuote = false;

  @override
  void initState() {
    super.initState();
    situationController = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    situationController.dispose();
    quoteController.dispose();
    super.dispose();
  }

  Future<void> generateQuote() async {
    if (generating || !consent) return;
    if (!formKey.currentState!.validate()) return;

    final text = situationController.text.trim();
    final requestedTone = tone;

    setState(() {
      generating = true;
      error = null;
      copyMessage = null;
    });

    try {
      final quote = await widget.generate(text, requestedTone);

      if (!mounted) return;

      setState(() {
        quoteController.text = quote;
        hasQuote = true;
      });
    } on RepositoryException catch (exception) {
      if (!mounted) return;

      setState(() => error = exception.message);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        error = 'Could not generate encouragement. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => generating = false);
      }
    }
  }

  String? reviewedQuote() {
    final quote = quoteController.text.trim();

    if (quote.length < 10 || quote.length > 240) {
      setState(() {
        error = 'Keep your quote between 10 and 240 characters.';
      });
      return null;
    }

    return quote;
  }

  Future<void> copyQuote() async {
    final quote = reviewedQuote();
    if (quote == null) return;

    try {
      await Clipboard.setData(
        ClipboardData(text: '$quote\n— AI-generated encouragement'),
      );

      if (!mounted) return;
      setState(() => copyMessage = 'Copied.');
    } catch (_) {
      if (!mounted) return;
      setState(() => copyMessage = 'Could not access the clipboard.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Encouragement for you'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Form(
                key: formKey,
                child: TextFormField(
                  controller: situationController,
                  enabled: !generating,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Information for your encouragement',
                    helperText:
                        'Review, edit, or remove anything before generating.',
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();

                    if (text.length < 10 || text.length > 2000) {
                      return 'Use 10–2,000 characters.';
                    }

                    return null;
                  },
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: tone,
                decoration: const InputDecoration(labelText: 'Tone'),
                items: const [
                  DropdownMenuItem(value: 'gentle', child: Text('Gentle')),
                  DropdownMenuItem(
                    value: 'practical',
                    child: Text('Practical'),
                  ),
                  DropdownMenuItem(
                    value: 'uplifting',
                    child: Text('Uplifting'),
                  ),
                ],
                onChanged: generating
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => tone = value);
                        }
                      },
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: consent,
                title: const Text('Allow AI processing'),
                subtitle: const Text(
                  'Send the situation above and selected tone to Groq. '
                  'If Groq reaches its usage limit, send them to Google '
                  'Gemini instead. Images and other private entries '
                  'are not included.',
                ),
                onChanged: generating
                    ? null
                    : (value) {
                        setState(() => consent = value ?? false);
                      },
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: generating || !consent ? null : generateQuote,
                icon: generating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_outlined),
                label: Text(
                  generating
                      ? 'Generating…'
                      : hasQuote
                      ? 'Try another'
                      : 'Generate encouragement',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (hasQuote) ...[
                const SizedBox(height: 24),
                const Text(
                  'AI-generated encouragement',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Take what feels useful. This message is not posted or '
                  'saved to your account. Copy it if you want to keep it.',
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: quoteController,
                  enabled: !generating,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 240,
                  decoration: const InputDecoration(labelText: 'Your quote'),
                  onChanged: (_) {
                    if (copyMessage != null) {
                      setState(() => copyMessage = null);
                    }
                  },
                ),
                TextButton.icon(
                  onPressed: generating ? null : copyQuote,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy'),
                ),
                if (copyMessage != null) Text(copyMessage!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
