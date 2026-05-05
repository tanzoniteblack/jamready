import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ruleset.dart';

/// Repository for loading and saving rulesets.
///
/// Built-in rulesets (WFTDA, RDCL) are always available.
/// Custom rulesets are persisted to SharedPreferences.
class RulesetRepository {
  static const _customRulesetsKey = 'custom_rulesets';

  /// Get all available rulesets (built-in + custom)
  Future<List<Ruleset>> getAllRulesets() async {
    final builtIn = getBuiltInRulesets();
    final custom = await getCustomRulesets();
    return [...builtIn, ...custom];
  }

  /// Get built-in rulesets
  List<Ruleset> getBuiltInRulesets() {
    return [Ruleset.wftda(), Ruleset.rdcl()];
  }

  /// Get custom rulesets from storage
  Future<List<Ruleset>> getCustomRulesets() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_customRulesetsKey);
    if (json == null) return [];

    try {
      final list = jsonDecode(json) as List;
      return list
          .map((e) => Ruleset.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Save a custom ruleset
  Future<void> saveCustomRuleset(Ruleset ruleset) async {
    if (ruleset.isBuiltIn) {
      throw ArgumentError('Cannot save a built-in ruleset');
    }

    final customs = await getCustomRulesets();
    final index = customs.indexWhere((r) => r.id == ruleset.id);

    if (index >= 0) {
      customs[index] = ruleset;
    } else {
      customs.add(ruleset);
    }

    await _saveCustomRulesets(customs);
  }

  /// Delete a custom ruleset
  Future<void> deleteCustomRuleset(String id) async {
    final customs = await getCustomRulesets();
    customs.removeWhere((r) => r.id == id);
    await _saveCustomRulesets(customs);
  }

  Future<void> _saveCustomRulesets(List<Ruleset> rulesets) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(rulesets.map((r) => r.toJson()).toList());
    await prefs.setString(_customRulesetsKey, json);
  }

  /// Get a ruleset by ID
  Future<Ruleset?> getRulesetById(String id) async {
    // Check built-in first
    for (final ruleset in getBuiltInRulesets()) {
      if (ruleset.id == id) return ruleset;
    }

    // Then check custom
    final customs = await getCustomRulesets();
    for (final ruleset in customs) {
      if (ruleset.id == id) return ruleset;
    }

    return null;
  }
}
