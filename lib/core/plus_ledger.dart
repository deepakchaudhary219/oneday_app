import 'network/api_client.dart';

/// OneDay Plus: a wider radius and more hosted plans. Safety is never paywalled, and the server lists what is
/// never sold so the app can say so.
class PlusStatus {
  const PlusStatus({
    required this.plus,
    required this.available,
    this.price,
    this.status,
    this.renewsOrEndsAt,
    this.cancelAtPeriodEnd = false,
    this.benefits = const [],
    this.neverSold = const [],
  });

  final bool plus;

  /// Whether Plus can be bought in this deployment.
  final bool available;
  final String? price;
  final String? status;
  final DateTime? renewsOrEndsAt;
  final bool cancelAtPeriodEnd;
  final List<String> benefits;
  final List<String> neverSold;

  /// From PlusView.
  factory PlusStatus.fromJson(Map<String, dynamic> j) => PlusStatus(
    plus: j['plus'] as bool? ?? false,
    available: j['available'] as bool? ?? false,
    price: j['price'] as String?,
    status: j['status'] as String?,
    renewsOrEndsAt: j['renewsOrEndsAt'] == null
        ? null
        : DateTime.parse(j['renewsOrEndsAt'] as String).toLocal(),
    cancelAtPeriodEnd: j['cancelAtPeriodEnd'] as bool? ?? false,
    benefits: (j['benefits'] as List? ?? const []).cast<String>(),
    neverSold: (j['neverSold'] as List? ?? const []).cast<String>(),
  );
}

/// Where to pay: Razorpay's hosted checkout (UPI Autopay) for the new subscription.
class Checkout {
  const Checkout({required this.subscriptionId, this.url, this.key, this.price});

  final String subscriptionId;
  final String? url;
  final String? key;
  final String? price;

  factory Checkout.fromJson(Map<String, dynamic> j) => Checkout(
    subscriptionId: j['subscriptionId'] as String? ?? '',
    url: j['checkoutUrl'] as String?,
    key: j['checkoutKey'] as String?,
    price: j['price'] as String?,
  );
}

/// The private Real Value Ledger: real outcomes, never screen time.
class LedgerMonth {
  const LedgerMonth({
    required this.month,
    this.lines = const [],
    this.newConnections = 0,
    this.meaningfulConversations = 0,
    this.datesCompleted = 0,
  });

  /// `2026-11`.
  final String month;

  /// The server's sentences, ready to show.
  final List<String> lines;
  final int newConnections;
  final int meaningfulConversations;
  final int datesCompleted;

  factory LedgerMonth.fromJson(Map<String, dynamic> j) => LedgerMonth(
    month: j['month'] as String? ?? '',
    lines: (j['lines'] as List? ?? const []).cast<String>(),
    newConnections: (j['newConnections'] as num?)?.toInt() ?? 0,
    meaningfulConversations:
        (j['meaningfulConversations'] as num?)?.toInt() ?? 0,
    datesCompleted: (j['datesCompleted'] as num?)?.toInt() ?? 0,
  );
}

/// Last week as one highlight, a few facts and a kind ending.
class WeeklyRecap {
  const WeeklyRecap({
    required this.ready,
    this.highlight,
    this.lines = const [],
    this.ending,
  });

  final bool ready;
  final String? highlight;
  final List<String> lines;
  final String? ending;

  factory WeeklyRecap.fromJson(Map<String, dynamic> j) => WeeklyRecap(
    ready: j['ready'] as bool? ?? false,
    highlight: j['highlight'] as String?,
    lines: (j['lines'] as List? ?? const []).cast<String>(),
    ending: j['ending'] as String?,
  );
}

abstract interface class PlusLedgerRepository {
  Future<PlusStatus> plus();

  Future<Checkout> subscribe();

  /// Ends at the period's end; nothing is taken away before then.
  Future<PlusStatus> cancel();

  /// [month] like `2026-10`; null for this month.
  Future<LedgerMonth> ledger({String? month});

  Future<WeeklyRecap> week();
}

class ApiPlusLedger implements PlusLedgerRepository {
  ApiPlusLedger(this.api);

  final ApiClient api;

  @override
  Future<PlusStatus> plus() async =>
      PlusStatus.fromJson(await api.get('/plus') as Map<String, dynamic>);

  @override
  Future<Checkout> subscribe() async => Checkout.fromJson(
    await api.post('/plus/subscribe') as Map<String, dynamic>,
  );

  @override
  Future<PlusStatus> cancel() async => PlusStatus.fromJson(
    await api.post('/plus/cancel') as Map<String, dynamic>,
  );

  @override
  Future<LedgerMonth> ledger({String? month}) async => LedgerMonth.fromJson(
    await api.get('/ledger', query: {'month': month}) as Map<String, dynamic>,
  );

  @override
  Future<WeeklyRecap> week() async => WeeklyRecap.fromJson(
    await api.get('/ledger/week') as Map<String, dynamic>,
  );
}

class FakePlusLedger implements PlusLedgerRepository {
  bool subscribed = false;
  bool cancelled = false;

  PlusStatus get _status => PlusStatus(
    plus: subscribed,
    available: true,
    price: '₹149 a month',
    status: subscribed ? 'ACTIVE' : null,
    cancelAtPeriodEnd: cancelled,
    renewsOrEndsAt: subscribed
        ? DateTime.now().add(const Duration(days: 30))
        : null,
    benefits: const [
      'See Nearby up to 25 km',
      'Host up to 4 plans at a time',
    ],
    neverSold: const [
      'Safety features',
      'Who saw your story',
      'More signals',
      'Being shown first',
    ],
  );

  @override
  Future<PlusStatus> plus() async => _status;

  @override
  Future<Checkout> subscribe() async {
    subscribed = true;
    return const Checkout(
      subscriptionId: 'sub_demo',
      url: 'https://checkout.example/sub_demo',
      price: '₹149 a month',
    );
  }

  @override
  Future<PlusStatus> cancel() async {
    cancelled = true;
    return _status;
  }

  @override
  Future<LedgerMonth> ledger({String? month}) async => const LedgerMonth(
    month: '2026-11',
    newConnections: 3,
    meaningfulConversations: 5,
    datesCompleted: 1,
    lines: [
      'You made 3 new connections, 1 of them from Kerala.',
      '5 conversations went past small talk.',
      'You went on 1 date and got home safe.',
    ],
  );

  @override
  Future<WeeklyRecap> week() async => const WeeklyRecap(
    ready: true,
    highlight: 'Sunday badminton with Kabir and Meera',
    lines: ['2 new connections', 'You answered 3 prompts'],
    ending: 'A good week. Rest well.',
  );
}
