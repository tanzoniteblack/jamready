import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jam_ready/models/ruleset.dart';
import 'package:jam_ready/services/ruleset_repository.dart';

/// Creates a minimal valid custom ruleset for testing.
Ruleset _makeCustomRuleset({
  String id = 'custom_test',
  String name = 'Custom Test',
  int periodCount = 2,
}) {
  return Ruleset.custom(
    id: id,
    name: name,
    periodCount: periodCount,
    periodDurationMs: 10 * 60 * 1000,
    jamDurationMs: 60 * 1000,
    jamsResetPerPeriod: false,
    lineupDurationMs: 30 * 1000,
    lineupOvertimeDurationMs: 60 * 1000,
    timeoutsPerPeriod: 3,
    reviewsPerPeriod: 1,
    intermissionDurationsMs: [5 * 60 * 1000],
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RulesetRepository – built-in rulesets', () {
    test('returns exactly WFTDA and RDCL as built-in rulesets', () {
      final repo = RulesetRepository();
      final builtIn = repo.getBuiltInRulesets();

      expect(builtIn.length, 2);
      expect(builtIn.map((r) => r.id), containsAll(['wftda', 'rdcl']));
      expect(builtIn.every((r) => r.isBuiltIn), true);
    });

    test('getAllRulesets includes built-in rulesets when no custom ones exist', () async {
      final repo = RulesetRepository();
      final all = await repo.getAllRulesets();

      expect(all.length, 2);
      expect(all.map((r) => r.id), containsAll(['wftda', 'rdcl']));
    });
  });

  group('RulesetRepository – custom rulesets', () {
    test('returns empty list when no custom rulesets have been saved', () async {
      final repo = RulesetRepository();
      final customs = await repo.getCustomRulesets();
      expect(customs, isEmpty);
    });

    test('saves a custom ruleset and retrieves it', () async {
      final repo = RulesetRepository();
      final ruleset = _makeCustomRuleset(id: 'my_rules', name: 'My Rules', periodCount: 3);

      await repo.saveCustomRuleset(ruleset);

      final retrieved = await repo.getCustomRulesets();
      expect(retrieved.length, 1);
      expect(retrieved.first.id, 'my_rules');
      expect(retrieved.first.name, 'My Rules');
      expect(retrieved.first.periodCount, 3);
    });

    test('updating a ruleset with the same ID replaces it (no duplicates)', () async {
      final repo = RulesetRepository();
      final original = _makeCustomRuleset(id: 'editable', name: 'Original', periodCount: 2);
      final updated = original.copyWith(name: 'Updated', periodCount: 4);

      await repo.saveCustomRuleset(original);
      await repo.saveCustomRuleset(updated);

      final customs = await repo.getCustomRulesets();
      expect(customs.length, 1);
      expect(customs.first.name, 'Updated');
      expect(customs.first.periodCount, 4);
    });

    test('can save multiple distinct custom rulesets', () async {
      final repo = RulesetRepository();
      await repo.saveCustomRuleset(_makeCustomRuleset(id: 'rules_a', name: 'A'));
      await repo.saveCustomRuleset(_makeCustomRuleset(id: 'rules_b', name: 'B'));

      final customs = await repo.getCustomRulesets();
      expect(customs.length, 2);
      expect(customs.map((r) => r.id), containsAll(['rules_a', 'rules_b']));
    });

    test('getAllRulesets includes both built-in and custom rulesets', () async {
      final repo = RulesetRepository();
      await repo.saveCustomRuleset(_makeCustomRuleset(id: 'my_custom'));

      final all = await repo.getAllRulesets();
      expect(all.length, 3);
      expect(all.map((r) => r.id), containsAll(['wftda', 'rdcl', 'my_custom']));
    });

    test('deletes a custom ruleset by ID', () async {
      final repo = RulesetRepository();
      await repo.saveCustomRuleset(_makeCustomRuleset(id: 'to_delete'));
      expect((await repo.getCustomRulesets()).length, 1);

      await repo.deleteCustomRuleset('to_delete');
      expect((await repo.getCustomRulesets()).length, 0);
    });

    test('deleting a non-existent ID does not throw', () async {
      final repo = RulesetRepository();
      await expectLater(
        repo.deleteCustomRuleset('does_not_exist'),
        completes,
      );
    });

    test('throws ArgumentError when trying to save a built-in ruleset', () async {
      final repo = RulesetRepository();
      await expectLater(
        () => repo.saveCustomRuleset(Ruleset.wftda()),
        throwsArgumentError,
      );
    });
  });

  group('RulesetRepository – getRulesetById', () {
    test('finds a built-in ruleset by ID', () async {
      final repo = RulesetRepository();
      final ruleset = await repo.getRulesetById('wftda');

      expect(ruleset, isNotNull);
      expect(ruleset!.name, 'WFTDA');
    });

    test('finds an RDCL ruleset by ID', () async {
      final repo = RulesetRepository();
      final ruleset = await repo.getRulesetById('rdcl');

      expect(ruleset, isNotNull);
      expect(ruleset!.name, 'RDCL');
    });

    test('finds a custom ruleset by ID', () async {
      final repo = RulesetRepository();
      await repo.saveCustomRuleset(_makeCustomRuleset(id: 'find_me', name: 'Find Me'));

      final found = await repo.getRulesetById('find_me');
      expect(found, isNotNull);
      expect(found!.name, 'Find Me');
    });

    test('returns null for an unknown ID', () async {
      final repo = RulesetRepository();
      final result = await repo.getRulesetById('nonexistent_id');
      expect(result, isNull);
    });
  });

  group('RulesetRepository – error handling', () {
    test('returns empty list when stored JSON is corrupt', () async {
      SharedPreferences.setMockInitialValues({
        'custom_rulesets': 'not valid json {[<>',
      });
      final repo = RulesetRepository();
      final customs = await repo.getCustomRulesets();
      expect(customs, isEmpty);
    });
  });
}
