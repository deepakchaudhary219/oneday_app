import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oneday_app/core/calls.dart';
import 'package:oneday_app/core/dates.dart';
import 'package:oneday_app/core/figures.dart';
import 'package:oneday_app/core/models.dart';
import 'package:oneday_app/core/pulse_status.dart';

/// Guards the app against backend drift: every endpoint the app calls, every request field it sends and every
/// response field the models read must exist in the backend's published contract (contract/openapi.json,
/// copied from the backend's docs/api/openapi.json). When the backend changes, refresh the copy and this test
/// says exactly what broke.
void main() {
  final spec = jsonDecode(
    File('contract/openapi.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final paths = spec['paths'] as Map<String, dynamic>;
  final schemas =
      (spec['components'] as Map<String, dynamic>)['schemas']
          as Map<String, dynamic>;

  Map<String, dynamic> resolve(Map<String, dynamic> schema) {
    final ref = schema[r'$ref'] as String?;
    return ref == null
        ? schema
        : schemas[ref.split('/').last] as Map<String, dynamic>;
  }

  Set<String> props(String name) =>
      ((schemas[name] as Map<String, dynamic>?)?['properties']
                  as Map<String, dynamic>? ??
              {})
          .keys
          .toSet();

  // (method, path, request fields sent, query parameters used)
  const calls = <(String, String, List<String>, List<String>)>[
    ('post', '/auth/otp/request', ['phone'], []),
    (
      'post',
      '/auth/otp/verify',
      [
        'challengeId',
        'phone',
        'code',
        'displayName',
        'dateOfBirth',
        'consentVersion',
      ],
      [],
    ),
    ('post', '/auth/login', ['email', 'password'], []),
    (
      'post',
      '/auth/register',
      ['email', 'password', 'displayName', 'dateOfBirth', 'consentVersion'],
      [],
    ),
    ('post', '/auth/refresh', ['refreshToken'], []),
    ('post', '/auth/logout', [], []),
    ('post', '/verification/liveness', ['sessionToken'], []),
    ('put', '/location', ['lat', 'lon'], []),
    ('get', '/profile/me', [], []),
    ('get', '/discover/constellation', [], ['scope', 'activity']),
    ('get', '/signals/budget', [], []),
    ('post', '/signals', ['momentId', 'reaction'], []),
    ('get', '/signals/digest', [], []),
    ('post', '/signals/{signalId}/reveal', [], []),
    ('post', '/signals/{signalId}/pass', [], []),
    ('get', '/connections', [], []),
    ('get', '/conversations/{conversationId}/messages', [], ['limit']),
    (
      'post',
      '/conversations/{conversationId}/messages',
      ['body', 'sendAnyway'],
      [],
    ),
    ('get', '/moments/friends', [], []),
    ('post', '/safety/blocks', [], []),
    ('post', '/safety/reports', [], []),
    ('post', '/connections/{connectionId}/exit', [], []),
    ('get', '/conversations/{conversationId}/balance', [], []),
    ('get', '/map/stories', [], ['scope', 'todaysPrompt']),
    (
      'patch',
      '/profile/me',
      ['discoveryRadiusKm', 'datingLens', 'discretionMode', 'accountPrivacy'],
      [],
    ),
    ('post', '/location/pause', [], []),
    ('get', '/consents', [], []),
    ('post', '/consents/{purpose}', [], []),
    ('delete', '/consents/{purpose}', [], []),
    ('get', '/auth/sessions', [], []),
    ('delete', '/auth/sessions/{sessionId}', [], []),
    ('get', '/privacy/export', [], []),
    ('delete', '/privacy/account', [], ['confirm']),
    ('get', '/grievances/officer', [], []),
    ('get', '/prompts/today', [], []),
    ('get', '/pulse-status/mine', [], []),
    ('put', '/pulse-status', ['mood', 'emoji', 'note'], []),
    ('delete', '/pulse-status', [], []),
    ('get', '/pulse-status/friends', [], []),
    ('get', '/plans', [], []),
    (
      'post',
      '/plans',
      [
        'meetingPointId',
        'activity',
        'title',
        'capacity',
        'startsAt',
        'endsAt',
      ],
      [],
    ),
    ('get', '/plans/mine', [], []),
    ('get', '/plans/{planId}', [], []),
    ('post', '/plans/{planId}/join', [], []),
    ('post', '/plans/{planId}/leave', [], []),
    ('get', '/plans/{planId}/requests', [], []),
    ('post', '/plans/{planId}/requests/{handle}/approve', [], []),
    ('post', '/plans/{planId}/requests/{handle}/decline', [], []),
    ('get', '/plans/{planId}/room', [], ['limit']),
    ('post', '/plans/{planId}/room', ['body', 'sendAnyway'], []),
    ('get', '/meeting-points', [], []),
    ('get', '/dates', [], []),
    (
      'post',
      '/dates',
      ['connectionId', 'placeName', 'startsAt', 'endsAt'],
      [],
    ),
    ('post', '/dates/{dateId}/accept', [], []),
    ('post', '/dates/{dateId}/decline', [], []),
    ('post', '/dates/{dateId}/cancel', [], []),
    ('put', '/dates/{dateId}/sharing', ['enabled'], []),
    ('put', '/dates/{dateId}/trusted-contact', ['phone', 'name'], []),
    ('post', '/dates/{dateId}/check-in', ['needHelp'], []),
    ('post', '/dates/{dateId}/sos', [], []),
    ('post', '/dates/{dateId}/end', [], []),
    ('post', '/dates/{dateId}/debrief', ['answers'], []),
    ('get', '/right-now', [], []),
    ('get', '/right-now/mine', [], []),
    ('post', '/right-now', ['activity', 'minutes'], []),
    ('delete', '/right-now', [], []),
    ('post', '/right-now/{sessionId}/join', [], []),
    ('get', '/right-now/requests', [], []),
    ('post', '/right-now/requests/{requestId}/accept', [], []),
    ('post', '/right-now/requests/{requestId}/decline', [], []),
    ('get', '/capsules/incoming', [], []),
    ('get', '/capsules/sent', [], []),
    ('get', '/capsules/{capsuleId}', [], []),
    ('delete', '/capsules/{capsuleId}', [], []),
    ('post', '/capsules', ['message', 'opensAt', 'connectionId'], []),
    ('get', '/threads', [], []),
    ('post', '/threads', ['title', 'days', 'inviteConnectionIds'], []),
    ('get', '/threads/{threadId}', [], []),
    ('post', '/threads/{threadId}/invite', ['connectionIds'], []),
    ('post', '/threads/{threadId}/accept', [], []),
    ('post', '/threads/{threadId}/decline', [], []),
    ('post', '/threads/{threadId}/leave', [], []),
    ('get', '/threads/{threadId}/posts', [], ['limit']),
    (
      'post',
      '/threads/{threadId}/posts',
      ['kind', 'caption', 'sendAnyway'],
      [],
    ),
    ('delete', '/threads/{threadId}/posts/{postId}', [], []),
    ('get', '/plus', [], []),
    ('post', '/plus/subscribe', [], []),
    ('post', '/plus/cancel', [], []),
    ('get', '/ledger', [], ['month']),
    ('get', '/ledger/week', [], []),
    ('get', '/moments/{momentId}/relay', [], []),
    (
      'post',
      '/moments',
      ['kind', 'caption', 'shareScope', 'replyToMomentId', 'promptKey'],
      [],
    ),
    ('post', '/moments/{momentId}/spotlights', ['answerMomentId'], []),
    ('get', '/spotlights/requests', [], []),
    ('post', '/spotlights/{spotlightId}/accept', [], []),
    ('post', '/spotlights/{spotlightId}/decline', [], []),
    ('get', '/figures/following', [], []),
    ('get', '/figures/feed', [], ['limit']),
    ('get', '/figures/{handle}', [], []),
    ('post', '/figures/{handle}/follow', [], []),
    ('delete', '/figures/{handle}/follow', [], []),
    ('get', '/figures/me', [], []),
    (
      'post',
      '/figures/apply',
      ['handle', 'publicName', 'category', 'evidence', 'bio'],
      [],
    ),
    ('get', '/amas', [], []),
    ('get', '/amas/{amaId}', [], []),
    (
      'post',
      '/amas',
      ['title', 'startsAt', 'minutes', 'corridorRegion'],
      [],
    ),
    ('delete', '/amas/{amaId}', [], []),
    (
      'post',
      '/amas/{amaId}/questions',
      ['question', 'anonymous', 'sendAnyway'],
      [],
    ),
    ('post', '/amas/{amaId}/questions/{questionId}/vote', [], []),
    ('delete', '/amas/{amaId}/questions/{questionId}/vote', [], []),
    ('post', '/amas/{amaId}/questions/{questionId}/answer', ['answer'], []),
    ('post', '/amas/{amaId}/questions/{questionId}/hide', [], []),
    ('get', '/e2ee/devices', [], []),
    (
      'post',
      '/e2ee/devices',
      ['identityKey', 'registrationId', 'signedPreKey', 'oneTimePreKeys'],
      [],
    ),
    ('delete', '/e2ee/devices/{deviceId}', [], []),
    ('post', '/e2ee/devices/{deviceId}/prekeys', ['oneTimePreKeys'], []),
    ('get', '/e2ee/connections/{connectionId}/bundles', [], []),
    ('get', '/e2ee/devices/{deviceId}/bundles', [], []),
    ('get', '/e2ee/devices/{deviceId}/inbox', [], ['limit']),
    ('post', '/e2ee/devices/{deviceId}/inbox/ack', ['envelopeIds'], []),
    (
      'post',
      '/conversations/{conversationId}/encrypted',
      ['senderDevice', 'commitment', 'envelopes'],
      [],
    ),
    (
      'post',
      '/conversations/{conversationId}/messages/{messageId}/report',
      ['plaintext', 'frankingKey', 'category', 'details', 'alsoBlock'],
      [],
    ),
    ('post', '/connections/{connectionId}/calls', [], []),
    ('get', '/calls/{callId}', [], []),
    ('post', '/calls/{callId}/accept', [], []),
    ('post', '/calls/{callId}/decline', [], []),
    ('post', '/calls/{callId}/end', [], []),
    ('put', '/calls/{callId}/layer', ['wants'], []),
    ('post', '/calls/{callId}/signal', ['kind', 'payload'], []),
    ('get', '/calls/ice-servers', [], []),
    ('get', '/live', [], []),
    ('post', '/live', ['title', 'threadId'], []),
    ('get', '/live/{liveId}/host', [], []),
    ('post', '/live/{liveId}/join', [], []),
    ('post', '/live/{liveId}/end', [], []),
    ('put', '/dates/{dateId}/location', ['lat', 'lon'], []),
    ('post', '/devices', ['pushToken', 'platform'], []),
    ('post', '/devices/unregister', ['pushToken'], []),
    ('post', '/media/uploads', ['kind', 'contentType', 'sizeBytes'], []),
    ('post', '/media/uploads/complete', ['mediaRef'], []),
    ('get', '/media/uploads/status', [], ['mediaRef']),
    (
      'post',
      '/moments',
      [
        'kind',
        'shareScope',
        'mediaRef',
        'capturedLive',
        'caption',
        'activityTag',
      ],
      [],
    ),
  ];

  for (final (method, path, fields, query) in calls) {
    test(
      '${method.toUpperCase()} $path exists with the fields the app sends',
      () {
        final op =
            (paths[path] as Map<String, dynamic>?)?[method]
                as Map<String, dynamic>?;
        expect(op, isNotNull, reason: '$method $path is not in the contract');
        final params = [
          for (final p in (op!['parameters'] as List? ?? []))
            (p as Map)['name'],
        ];
        for (final q in query) {
          expect(
            params,
            contains(q),
            reason: '$path has no query parameter $q',
          );
        }
        if (fields.isEmpty) return;
        final content =
            (op['requestBody'] as Map<String, dynamic>)['content']
                as Map<String, dynamic>;
        final body = resolve(
          (content.values.first as Map<String, dynamic>)['schema']
              as Map<String, dynamic>,
        );
        final known = (body['properties'] as Map<String, dynamic>).keys;
        for (final f in fields) {
          expect(known, contains(f), reason: '$path request has no field $f');
        }
      },
    );
  }

  // Response schemas → fields read by lib/core/models.dart and the token store.
  const reads = <String, List<String>>{
    'IssuedToken': ['token', 'refreshToken', 'expiresInSeconds', 'verified'],
    'PhoneAuthResult': ['token'],
    'ChallengeView': ['challengeId'],
    'VerificationResponse': ['status', 'message', 'token'],
    'ConstellationNode': [
      'nodeId',
      'firstName',
      'activity',
      'distance',
      'liveCaptured',
      'previewUrl',
      'whyYouSeeThis',
    ],
    'BudgetView': ['remaining', 'dailyBudget', 'nextFreesAt'],
    'DigestView': ['signals'],
    'DigestItem': [
      'signalId',
      'firstName',
      'reaction',
      'activityRef',
      'aboutActivity',
      'sharedContext',
      'receivedAt',
    ],
    'RevealView': ['conversationId'],
    'ConnectionView': [
      'id',
      'conversationId',
      'displayName',
      'warmth',
      'lastMessage',
      'lastMessageAt',
      'lastFromMe',
    ],
    'Warmth': ['level', 'line', 'starter'],
    'MessageView': [
      'id',
      'body',
      'mine',
      'sentAt',
      'encrypted',
      'pacingHint',
      'concern',
    ],
    'FriendStories': ['mine', 'firstName', 'moments'],
    'MomentView': ['id', 'mediaUrl', 'caption', 'activityTag', 'postedAt'],
    'ProfileView': [
      'displayName',
      'homeRegion',
      'bio',
      'verificationStatus',
      'discoveryRadiusKm',
      'datingLens',
      'discretionMode',
      'accountPrivacy',
      'safeZoneSet',
      'emergencyNumber',
    ],
    'ReportReceipt': ['message'],
    'E2eeDeviceView': ['deviceId', 'oneTimePreKeysLeft'],
    'Bundle': [
      'deviceId',
      'registrationId',
      'identityKey',
      'signedPreKey',
      'oneTimePreKey',
    ],
    'SignedPreKey': ['keyId', 'publicKey', 'signature'],
    'PreKey': ['keyId', 'publicKey'],
    'Outgoing': ['deviceId', 'toSelf', 'type', 'ciphertext'],
    'InboxItem': [
      'envelopeId',
      'conversationId',
      'messageId',
      'mine',
      'senderDevice',
      'sentAt',
      'type',
      'ciphertext',
    ],
    'CallView': [
      'id',
      'connectionId',
      'firstName',
      'direction',
      'status',
      'layer',
      'youWant',
      'theyAreReadyForMore',
      'endReason',
    ],
    'IceServers': ['iceServers'],
    'IceServer': ['urls', 'username', 'credential'],
    'LiveView': [
      'id',
      'hostFirstName',
      'state',
      'title',
      'audience',
      'threadId',
      'endsBy',
    ],
    'HostView': ['live', 'access', 'viewers'],
    'ViewerAccess': ['live', 'access'],
    'Access': ['serverUrl', 'token', 'expiresAt'],
    'LivePosition': ['lat', 'lon', 'at'],
    'RelayView': ['links', 'open', 'activity'],
    'RelayLink': [
      'momentId',
      'firstName',
      'position',
      'activity',
      'previewUrl',
      'mine',
      'spotlit',
    ],
    'SpotlightView': [
      'id',
      'withFirstName',
      'storyMomentId',
      'answerMomentId',
    ],
    'FigureView': [
      'handle',
      'publicName',
      'category',
      'bio',
      'verified',
      'following',
    ],
    'MyFigureView': ['handle', 'publicName', 'status', 'followers'],
    'FeedItem': ['handle', 'moment'],
    'AmaView': [
      'id',
      'title',
      'hostName',
      'hostHandle',
      'startsAt',
      'endsAt',
      'state',
      'corridorRegion',
      'canAsk',
      'youHost',
    ],
    'AmaDetail': ['ama', 'questions'],
    'QuestionView': [
      'id',
      'question',
      'askedBy',
      'answer',
      'mine',
      'youVoted',
      'votes',
      'hidden',
      'concern',
    ],
    'NearbyView': [
      'id',
      'firstName',
      'activity',
      'distance',
      'timeLeft',
      'whyYouSeeThis',
      'youAsked',
    ],
    'MySessionView': ['activity', 'timeLeft', 'requests'],
    'RequestView': ['requestId', 'firstName', 'sharedContext'],
    'AcceptView': ['conversationId'],
    'JoinView': ['message'],
    'CapsuleView': [
      'id',
      'direction',
      'state',
      'opensAt',
      'withFirstName',
      'message',
      'mediaUrl',
    ],
    'ThreadView': [
      'id',
      'title',
      'myStatus',
      'open',
      'endsAt',
      'youStartedIt',
      'members',
    ],
    'MemberView': ['handle', 'firstName', 'startedIt', 'you'],
    'PostView': [
      'id',
      'firstName',
      'mine',
      'postedAt',
      'caption',
      'mediaUrl',
      'concern',
    ],
    'PlusView': [
      'plus',
      'available',
      'price',
      'status',
      'renewsOrEndsAt',
      'cancelAtPeriodEnd',
      'benefits',
      'neverSold',
    ],
    'CheckoutView': ['subscriptionId', 'checkoutUrl', 'checkoutKey', 'price'],
    'LedgerView': [
      'month',
      'lines',
      'newConnections',
      'meaningfulConversations',
      'datesCompleted',
    ],
    'RecapView': ['ready', 'highlight', 'lines', 'ending'],
    'TodayView': [
      'promptKey',
      'text',
      'answeredByYou',
      'unlocked',
      'answeredNearby',
      'message',
      'festival',
      'answers',
    ],
    'Answer': ['momentId', 'firstName', 'activity', 'previewUrl'],
    'MyStatusView': ['mood'],
    'FriendStatusView': [
      'connectionId',
      'statusId',
      'firstName',
      'mood',
      'moodLabel',
      'emoji',
      'note',
      'checkIn',
    ],
    'PlanCard': [
      'id',
      'title',
      'activity',
      'hostFirstName',
      'place',
      'startsAt',
      'spotsLeft',
      'whyYouSeeThis',
      'you',
    ],
    'PlanView': [
      'id',
      'title',
      'activity',
      'hostFirstName',
      'place',
      'address',
      'startsAt',
      'endsAt',
      'spotsLeft',
      'status',
      'yourStatus',
      'going',
    ],
    'JoinRequest': ['handle', 'firstName', 'sharedContext'],
    'RoomMessage': ['id', 'firstName', 'body', 'mine', 'sentAt'],
    'MeetingPointView': ['id', 'name', 'address', 'distanceKm'],
    'DateView': [
      'partnerLocation',
      'id',
      'connectionId',
      'partnerFirstName',
      'placeName',
      'meetingPoint',
      'startsAt',
      'endsAt',
      'status',
      'youProposed',
      'emergencyNumber',
      'locationWindowOpen',
      'partnerSharing',
      'you',
    ],
    'YourSide': [
      'sharingLocation',
      'trustedContact',
      'homeSafe',
      'debriefSubmitted',
    ],
    'CheckInView': ['message', 'emergencyNumber', 'trustedContactAlerted'],
    'TrustedContactView': ['texted'],
    'DebriefView': ['message'],
    'BalanceView': ['state', 'message'],
    'StoryMap': ['clusters', 'message'],
    'Cluster': [
      'id',
      'vibe',
      'season',
      'people',
      'activities',
      'centerLat',
      'centerLon',
      'liveNow',
      'more',
      'stories',
    ],
    'StoryCard': [
      'momentId',
      'firstName',
      'activity',
      'previewUrl',
      'whyYouSeeThis',
    ],
    'PurposeView': ['purpose', 'processes', 'onWithdrawal', 'state'],
    'SessionView': ['id', 'device', 'current', 'lastUsedAt'],
    'OfficerContact': ['name', 'email', 'address'],
    'UploadTicket': ['mediaRef', 'uploadUrl', 'method', 'headers'],
    'UploadStatus': ['status', 'rejectReason'],
  };

  reads.forEach((schema, fields) {
    test('$schema has the fields the app reads', () {
      expect(schemas, contains(schema));
      for (final f in fields) {
        expect(props(schema), contains(f), reason: '$schema has no field $f');
      }
    });
  });

  test('the reactions the app offers are exactly the backend set', () {
    final reaction =
        (schemas['SendSignal']
                as Map<String, dynamic>)['properties']['reaction']
            as Map;
    expect((reaction['enum'] as List).toSet(), {
      for (final r in SignalReaction.values) r.api,
    });
  });

  test('the share scopes and story kinds the app sends are the backend\'s', () {
    final moment =
        (schemas['CreateMomentRequest'] as Map<String, dynamic>)['properties']
            as Map<String, dynamic>;
    expect(((moment['shareScope'] as Map)['enum'] as List).toSet(), {
      for (final s in ShareScope.values) s.api,
    });
    expect(
      (moment['kind'] as Map)['enum'] as List,
      containsAll(['PHOTO', 'VIDEO', 'TEXT']),
    );
    final upload =
        (schemas['UploadRequest'] as Map<String, dynamic>)['properties']
            as Map<String, dynamic>;
    expect(
      (upload['kind'] as Map)['enum'] as List,
      containsAll(['PHOTO', 'VIDEO']),
    );
    final status =
        (schemas['UploadStatus'] as Map<String, dynamic>)['properties']
            as Map<String, dynamic>;
    expect(
      (status['status'] as Map)['enum'] as List,
      containsAll(['READY', 'REJECTED']),
    );
  });

  test('the map lenses and privacy values the app sends are the backend\'s', () {
    final op =
        (paths['/map/stories'] as Map<String, dynamic>)['get']
            as Map<String, dynamic>;
    final scope = (op['parameters'] as List).cast<Map<String, dynamic>>()
        .firstWhere((p) => p['name'] == 'scope');
    final scopes = resolve(scope['schema'] as Map<String, dynamic>)['enum'] as List;
    expect(scopes, containsAll(['RADIUS', 'CITY', 'ROOTS', 'LANGUAGE']));
    final profile =
        (schemas['UpdateProfileRequest'] as Map<String, dynamic>)['properties']
            as Map<String, dynamic>;
    expect(
      (profile['accountPrivacy'] as Map)['enum'] as List,
      containsAll(['PUBLIC', 'PRIVATE']),
    );
    final balance =
        (schemas['BalanceView'] as Map<String, dynamic>)['properties']
            as Map<String, dynamic>;
    expect((balance['state'] as Map)['enum'] as List, contains('NUDGE'));
  });

  test('the moods and debrief answers the app offers are exactly the backend\'s', () {
    final mood =
        (schemas['SetStatus'] as Map<String, dynamic>)['properties']['mood']
            as Map;
    expect((mood['enum'] as List).toSet(), {for (final m in Mood.values) m.api});
    final answers =
        (schemas['DebriefRequest'] as Map<String, dynamic>)['properties']['answers']
            as Map;
    expect(((answers['items'] as Map)['enum'] as List).toSet(), {
      for (final a in DebriefAnswer.values) a.api,
    });
  });

  test('the figure categories the app offers are exactly the backend\'s', () {
    final category =
        (schemas['Application'] as Map<String, dynamic>)['properties']['category']
            as Map;
    expect((category['enum'] as List).toSet(), {
      for (final c in FigureCategory.values) c.api,
    });
  });

  test('call layers and envelope types are exactly the backend\'s', () {
    final wants =
        (schemas['LayerRequest'] as Map<String, dynamic>)['properties']['wants']
            as Map;
    expect((wants['enum'] as List).toSet(), {
      for (final l in CallLayer.values) l.api,
    });
    final type =
        (schemas['Outgoing'] as Map<String, dynamic>)['properties']['type']
            as Map;
    expect((type['enum'] as List).toSet(), {'PREKEY', 'MESSAGE'});
    final kind =
        (schemas['SignalRequest'] as Map<String, dynamic>)['properties']['kind']
            as Map;
    expect((kind['enum'] as List).toSet(), {'OFFER', 'ANSWER', 'ICE'});
  });
}
