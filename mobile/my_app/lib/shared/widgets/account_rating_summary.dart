import 'package:flutter/material.dart';
import '../models/account_review.dart';
import '../repositories/account_review_repository.dart';

class AccountReviewsBuilder extends StatefulWidget {
  const AccountReviewsBuilder({
    super.key,
    required this.userId,
    required this.builder,
    this.source,
  });
  final String userId;
  final AccountReviewSource? source;
  final AsyncWidgetBuilder<List<AccountReview>> builder;
  @override
  State<AccountReviewsBuilder> createState() => _AccountReviewsBuilderState();
}

class _AccountReviewsBuilderState extends State<AccountReviewsBuilder> {
  late Stream<List<AccountReview>> _reviews;
  void _subscribe() => _reviews = (widget.source ?? AccountReviewRepository())
      .watch(widget.userId);
  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(AccountReviewsBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userId != oldWidget.userId ||
        widget.source != oldWidget.source) {
      _subscribe();
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<AccountReview>>(
    key: ValueKey(widget.userId),
    stream: _reviews,
    builder: widget.builder,
  );
}

class AccountRatingBuilder extends StatelessWidget {
  const AccountRatingBuilder({
    super.key,
    required this.userId,
    required this.builder,
    this.source,
  });
  final String userId;
  final AccountReviewSource? source;
  final Widget Function(BuildContext, AccountRatingSummary) builder;
  @override
  Widget build(BuildContext context) => AccountReviewsBuilder(
    userId: userId,
    source: source,
    builder: (context, snapshot) => builder(
      context,
      AccountRatingSummary(
        snapshot.data ?? const [],
        loading: !snapshot.hasData && !snapshot.hasError,
        unavailable: snapshot.hasError,
      ),
    ),
  );
}
