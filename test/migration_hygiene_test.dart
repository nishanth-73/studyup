import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static guards for the Supabase migrations. These run without a
/// database and catch the exact failure classes seen in production:
/// forward references, missing EXECUTE lockdown, and digest()
/// invisibility under a locked search_path.
void main() {
  late String f1;
  late String f2;
  late String f3;

  setUpAll(() {
    f1 = File('supabase/migrations/20261015_community.sql').readAsStringSync();
    f2 = File('supabase/migrations/20261102_social_backend.sql')
        .readAsStringSync();
    f3 = File('supabase/migrations/20261104_hardening_fix.sql')
        .readAsStringSync();
  });

  group('migration ordering (file 1 must be self-contained in order)', () {
    test('friendships table is created before community_are_friends', () {
      final tableAt = f1.indexOf(
        'create table if not exists public.friendships',
      );
      final funcAt = f1.indexOf(
        'create or replace function public.community_are_friends',
      );
      expect(tableAt, greaterThanOrEqualTo(0));
      expect(funcAt, greaterThanOrEqualTo(0));
      expect(
        tableAt,
        lessThan(funcAt),
        reason: 'LANGUAGE SQL bodies validate at CREATE time',
      );
    });

    test('every policy trigger target table is created earlier in file 1', () {
      final created = <String, int>{};
      final lines = f1.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final m = RegExp(r'^\s*create table if not exists public\.([a-z_]+)')
            .firstMatch(lines[i]);
        if (m != null) created.putIfAbsent(m.group(1)!, () => i);
      }
      final refs = RegExp(
        r'create (?:policy|trigger)\s+(?:"[^"]+"\s+on|[\w]+\s+[^;]*?\son)\s+public\.([a-z_]+)',
        multiLine: true,
      ).allMatches(f1);
      expect(refs, isNotEmpty);
      for (final r in refs) {
        final table = r.group(1)!;
        final lineNo = f1.substring(0, r.start).split('\n').length;
        expect(
          created[table],
          isNotNull,
          reason: 'policy/trigger references unknown table $table',
        );
        expect(
          created[table],
          lessThan(lineNo),
          reason: 'policy/trigger on $table precedes its creation',
        );
      }
    });
  });

  group('digest() visibility (42883 regression)', () {
    test('digest callers lock search_path including extensions', () {
      const digestUsers = ['invitation_preview', 'accept_invitation'];
      for (final fn in digestUsers) {
        // The effective setting is the LAST one applied: hardening fix wins.
        final matches = RegExp(
          'alter function public\\.$fn\\([^)]*\\)\\s+set search_path\\s*=\\s*([^;]+);',
        ).allMatches(f3);
        expect(
          matches,
          isNotEmpty,
          reason: '$fn must have an explicit search_path fix',
        );
        final last = matches.last.group(1)!;
        expect(last, contains('extensions'));
        expect(last, contains('public'));
      }
      expect(f3, contains('create extension if not exists pgcrypto'));
    });
  });

  group('least-privilege EXECUTE', () {
    const rpcs = [
      'public.create_invitation(text, timestamptz)',
      'public.accept_invitation(text)',
      'public.my_friends()',
      'public.search_users(text)',
      'public.leaderboard_scope(text, timestamptz, timestamptz)',
      'public.daily_rows(uuid, date, date)',
    ];

    test('every sensitive RPC is revoked from public and anon', () {
      for (final rpc in rpcs) {
        final name = RegExp(r'public\.(\w+)').firstMatch(rpc)!.group(1)!;
        final pattern = RegExp(
          'revoke all on function ${RegExp.escape(rpc)} from public, anon;',
        );
        final inF2 = pattern.hasMatch(f2);
        final inF3 = pattern.hasMatch(f3);
        expect(
          inF2 || inF3,
          isTrue,
          reason: '$name lacks an explicit revoke from public, anon',
        );
      }
    });

    test('invitation preview stays callable without login', () {
      expect(
        f3,
        contains(
          'grant execute on function public.invitation_preview(text) to anon, authenticated;',
        ),
      );
    });

    test('no service-role key or secret in migrations or config', () {
      for (final content in [f1, f2, f3]) {
        // Role grants / key material, never prose mentions.
        expect(content, isNot(contains('service_role')));
        expect(
          RegExp(r'eyJ[A-Za-z0-9_-]{20,}').hasMatch(content),
          isFalse,
          reason: 'JWT-like material must never live in migrations',
        );
      }
    });
  });

  group('defense in depth', () {
    test('community_are_friends rejects anonymous callers', () {
      final idx = f3.indexOf(
        'create or replace function public.community_are_friends',
      );
      expect(idx, greaterThanOrEqualTo(0));
      final body = f3.substring(idx, idx + 600);
      expect(body, contains('auth.uid() is not null'));
    });

    test('hardening file touches no tables or policies', () {
      expect(f3.toLowerCase(), isNot(contains('create table')));
      expect(f3.toLowerCase(), isNot(contains('create policy')));
      expect(f3.toLowerCase(), isNot(contains('drop table')));
      expect(f3.toLowerCase(), isNot(contains('delete from')));
    });
  });
}
