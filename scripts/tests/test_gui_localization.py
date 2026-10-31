"""Check literal GUI templates without launching macOS or translating raw logs."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def string_end(source, start):
    i = start + 1
    while i < len(source):
        if source[i:i + 2] == '\\(':
            i = expression_end(source, i + 1) + 1
        elif source[i] == '\\':
            i += 2
        elif source[i] == '"':
            return i + 1
        else:
            i += 1
    raise ValueError('unterminated Swift string')


def expression_end(source, start):
    depth, i = 1, start + 1
    while depth:
        if source[i] == '"':
            i = string_end(source, i)
            continue
        if source[i] == '(':
            depth += 1
        elif source[i] == ')':
            depth -= 1
        i += 1
    return i - 1


def template(literal):
    result, i = '', 1
    while i < len(literal) - 1:
        if literal[i:i + 2] == '\\(':
            result += '%@'
            i = expression_end(literal, i + 1) + 1
        else:
            result += literal[i]
            i += 1
    return result


def templates():
    """-> (the central English-to-Chinese templates, how many were parsed)."""
    source = (ROOT / 'gui/Sources/PackagingModel/Localization.swift').read_text()
    body = source.split('public static let catalog: [String: String] = [', 1)[1].split('\n    ]', 1)[0]
    pairs = re.findall(r'^\s*("(?:[^"\\]|\\.)*"):\s*("(?:[^"\\]|\\.)*"),?$', body, re.M)
    return {json.loads(k): json.loads(v) for k, v in pairs}, len(pairs)


class LocalizationCoverage(unittest.TestCase):
    def test_game_language_choices_have_interface_translations(self):
        import ast
        catalog, _ = templates()
        tree = ast.parse((ROOT / 'dm/tools/nacp.py').read_text())
        node = next(n for n in tree.body if isinstance(n, ast.Assign)
                    and any(isinstance(t, ast.Name) and t.id == 'LANGUAGES' for t in n.targets))
        for _, name in ast.literal_eval(node.value):
            self.assertIn(name, catalog)

    def test_launcher_labels_and_notes_use_the_shared_catalog(self):
        catalog, _ = templates()
        for name in ['dm/apple/LauncherSettings.swift', 'dm/apple/AboutTouchline.swift',
                     'dm/ios/Sources/Launcher.swift', 'dm/macos/Launcher.swift']:
            source = (ROOT / name).read_text()
            for match in re.finditer(r'(?:\bl\(|\blabel:\s*|\bnote:\s*)(?=")', source):
                begin = match.end(); end = string_end(source, begin)
                # Dynamic file names and version concatenations use the shared presenter.
                if source[end+1:].lstrip().startswith('+'):
                    continue
                text = template(source[begin:end])
                if text:
                    self.assertIn(text, catalog, f'{name}: missing translation for {text!r}')

    def test_visible_literal_templates_have_central_chinese_translations(self):
        catalog, pairs = templates()
        self.assertEqual(len(catalog), pairs, 'duplicate English catalog keys')
        self.assertGreater(len(catalog), 150)
        count = 0
        for name in ('NXPackagingGUI/App.swift', 'NXPackagingGUI/TaskController.swift',
                     'NXPackagingGUI/SupportedGamesView.swift', 'NXPackagingGUI/PackagingConfirmationView.swift',
                     'PackagingModel/ApprovalSheet.swift'):
            source = (ROOT / 'gui/Sources' / name).read_text()
            for match in re.finditer(r'(?:\bl\(|\bpathRow\(|\bprompt:\s*|\bmessage\s*=\s*)(?=")', source):
                begin = match.end()
                text = template(source[begin:string_end(source, begin)])
                self.assertIn(text, catalog, f'{name}: missing translation for {text!r}')
                self.assertTrue(catalog.get(text), text)
                count += 1
        self.assertGreater(count, 65)

    def test_about_sheet_links_to_this_repository_and_names_this_project(self):
        catalog, _ = templates()
        source = (ROOT / 'dm/apple/AboutTouchline.swift').read_text()
        for url in ('https://github.com/ohxiaoguang/touchline23',
                    'https://github.com/ohxiaoguang/touchline23/issues'):
            self.assertIn(f'"{url}"', source)
        self.assertNotIn('touchline27', source.lower(), 'the About sheet must not link the other project')
        notes = [
            'Touchline 23 is an independent community project and is not affiliated with or endorsed by EA SPORTS, Nintendo, or their affiliates.',
            'The open-source license applies only to the project code explicitly covered by the license. It does not grant rights to game content, firmware, keys, or other third-party assets.',
            'Please use the official GitHub repository for project information. Beware of unauthorized paid IPA resales or unofficial repackaged builds.',
        ]
        for key in ['About Touchline 23', 'Project home', 'Report an issue'] + notes:
            self.assertTrue(catalog.get(key), key)
        for name in ('dm/ios/Sources/Launcher.swift', 'dm/macos/Launcher.swift'):
            launcher = (ROOT / name).read_text()
            self.assertIn('l("About Touchline 23")', launcher, name)
            self.assertIn('AboutTouchlineView().environmentObject(language)', launcher, name)

    def test_user_directory_and_sheet_do_not_render_maintenance_history(self):
        source = (ROOT / 'gui/Sources/NXPackagingGUI/SupportedGamesView.swift').read_text()
        for old in ('.evidence', 'GameConcept', 'buildVerified', 'runtimeVerified',
                    'targetSummary', 'Evidence source', 'What the columns mean'):
            self.assertNotIn(old, source)
        self.assertIn('model.catalog?.supportedGames', source)
        self.assertIn('ForEach(GameSort.allCases', source)
        app = (ROOT / 'gui/Sources/NXPackagingGUI/App.swift').read_text()
        self.assertIn('.sheet(isPresented: $model.showConfirmation)', app)
        self.assertIn('model.startApprovedBuild()', app)
        sheet = (ROOT / 'gui/Sources/NXPackagingGUI/PackagingConfirmationView.swift').read_text()
        self.assertIn('@State private var showDetails = false', sheet)
        self.assertIn('.frame(height: 210)', sheet)
        self.assertIn('.lineLimit(2).truncationMode(.middle)', sheet)
        catalog, _ = templates()
        for key in ('Confirm Packaging', 'Start Packaging', 'Technical Details',
                    'Search by name, Title ID or version', 'Supported games: %@'):
            self.assertTrue(catalog.get(key), key)

    def test_language_preference_is_not_part_of_configuration_or_bridge_arguments(self):
        configuration = (ROOT / 'gui/Sources/PackagingModel/Configuration.swift').read_text()
        self.assertNotIn('interface-language', configuration)
        app = (ROOT / 'gui/Sources/NXPackagingGUI/App.swift').read_text()
        self.assertNotIn('.id(language', app, 'changing view identity would reset StateObject')
        self.assertIn('@EnvironmentObject private var language', app)
        self.assertIn('RawLogView(text: model.output)', app, 'raw tool logs must bypass translation')
        log_view = (ROOT / 'gui/Sources/NXPackagingGUI/RawLogView.swift').read_text()
        self.assertIn('view.string = text', log_view)
        self.assertNotIn('GUIText', log_view)
        self.assertIn('view.isEditable = false', log_view)
        self.assertIn('view.isSelectable = true', log_view)


if __name__ == '__main__':
    unittest.main()
