import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oneday_app/core/models.dart';

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
    'ProfileView': ['displayName', 'homeRegion', 'verificationStatus'],
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
}
