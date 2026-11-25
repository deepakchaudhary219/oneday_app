import 'network/api_client.dart';

/// What is being blocked or reported: exactly one id, the one the person saw on screen. Nobody ever handles a
/// user id; the server works out who is behind the moment, signal, connection and so on.
class SafetyTarget {
  const SafetyTarget.moment(this.id) : field = 'momentId';

  const SafetyTarget.signal(this.id) : field = 'signalId';

  const SafetyTarget.connection(this.id) : field = 'connectionId';

  const SafetyTarget.plan(this.id) : field = 'planId';

  const SafetyTarget.date(this.id) : field = 'dateId';

  const SafetyTarget.pulseStatus(this.id) : field = 'pulseStatusId';

  const SafetyTarget.call(this.id) : field = 'callId';

  /// The request field the id travels in.
  final String field;
  final String id;
}

/// What happened, in the backend's categories, ordered and worded for a person choosing under stress.
enum ReportCategory {
  harassment('HARASSMENT', 'Harassment or bullying'),
  explicit('UNSOLICITED_EXPLICIT_CONTENT', 'Unwanted sexual content'),
  persistent(
    'PERSISTENT_CONTACT_AFTER_DECLINE',
    'Keeps contacting me after I said no',
  ),
  threat('THREAT_OR_VIOLENCE', 'Threats or violence'),
  underage('UNDERAGE_SUSPECTED', 'Seems to be under 18'),
  intimateImagery(
    'NON_CONSENSUAL_INTIMATE_IMAGERY',
    'Intimate images shared without consent',
  ),
  impersonation('IMPERSONATION', 'Pretending to be someone else'),
  scam('SCAM_OR_FRAUD', 'Scam or fraud'),
  hate('HATE', 'Hate speech'),
  spam('SPAM', 'Spam'),
  other('OTHER', 'Something else');

  const ReportCategory(this.api, this.label);

  final String api;
  final String label;
}

/// Block, report and leave: available wherever another person appears.
abstract interface class SafetyRepository {
  /// Silent for the other person; they simply stop seeing you, and you them.
  Future<void> block(SafetyTarget target);

  /// Returns the server's receipt line ("Thanks. We review reports like this within ...").
  Future<String> report(
    SafetyTarget target,
    ReportCategory category, {
    String? details,
    bool alsoBlock = false,
  });

  /// Soft exit from a Connection: the chat closes and the other person is not told.
  Future<void> leaveQuietly(String connectionId);
}

class ApiSafety implements SafetyRepository {
  ApiSafety(this.api);

  final ApiClient api;

  static const maxDetails = 1000;

  @override
  Future<void> block(SafetyTarget target) =>
      api.post('/safety/blocks', body: {target.field: target.id});

  @override
  Future<String> report(
    SafetyTarget target,
    ReportCategory category, {
    String? details,
    bool alsoBlock = false,
  }) async {
    final text = details?.trim() ?? '';
    final receipt = await api.post(
      '/safety/reports',
      body: {
        target.field: target.id,
        'category': category.api,
        if (text.isNotEmpty) 'details': text,
        if (alsoBlock) 'alsoBlock': true,
      },
    );
    return (receipt is Map ? receipt['message'] as String? : null) ??
        'Thanks. Our team will review this.';
  }

  @override
  Future<void> leaveQuietly(String connectionId) =>
      api.post('/connections/$connectionId/exit');
}

/// Demo mode: remembers what was asked, so screens and tests can see it.
class FakeSafety implements SafetyRepository {
  final blocked = <SafetyTarget>[];
  final reported = <(SafetyTarget, ReportCategory, String?, bool)>[];
  final left = <String>[];

  @override
  Future<void> block(SafetyTarget target) async => blocked.add(target);

  @override
  Future<String> report(
    SafetyTarget target,
    ReportCategory category, {
    String? details,
    bool alsoBlock = false,
  }) async {
    reported.add((target, category, details, alsoBlock));
    if (alsoBlock) blocked.add(target);
    return 'Thanks. Our team will review this within a day.';
  }

  @override
  Future<void> leaveQuietly(String connectionId) async => left.add(connectionId);
}
