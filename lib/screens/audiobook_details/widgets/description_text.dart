import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DescriptionText extends StatefulWidget {
  final String description;
  final int? maxLength;
  final bool expandable;

  const DescriptionText({
    super.key,
    required this.description,
    this.maxLength = 100,
    this.expandable = true,
  });

  @override
  State<DescriptionText> createState() => _DescriptionTextState();
}

class _DescriptionTextState extends State<DescriptionText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final hasLimit = widget.maxLength != null;
    final shouldTruncate =
        hasLimit && widget.description.length > widget.maxLength! && !_isExpanded;
    final showButton = widget.expandable &&
        hasLimit &&
        widget.description.length > widget.maxLength!;

    return InkWell(
      onTap: showButton
          ? () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            }
          : null,
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: shouldTruncate
                  ? widget.description.substring(0, widget.maxLength!)
                  : widget.description,
              style: GoogleFonts.ubuntu(
                fontSize: 13,
              ),
            ),
            if (showButton)
              TextSpan(
                text: _isExpanded ? '  Show less' : '  ... Show more',
                style: GoogleFonts.ubuntu(
                  fontSize: 13,
                  color: const Color.fromRGBO(204, 119, 34, 1),
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
