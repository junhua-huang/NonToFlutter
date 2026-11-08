#!/usr/bin/env python3
"""Validate shipped catalogs, format arguments, legal resources and system prompts."""
from collections import Counter
import json
from pathlib import Path
import plistlib
import re

RESOURCES = Path(__file__).resolve().parents[1] / 'Nonto/Resources'
LANGUAGES = {'zh-Hans', 'zh-Hant', 'en', 'fr', 'ru', 'es', 'ja'}
PLURAL_FORMS = {'en': {'one', 'other'}, 'fr': {'one', 'many', 'other'},
                'es': {'one', 'many', 'other'}, 'ru': {'one', 'few', 'many', 'other'}, 'ja': {'other'}}
FORMAT = re.compile(r'%(?:(\d+)\$)?(@|lld|ld|d|f|lf|%)')


def arguments(value):
    result = []
    position = 0
    for match in FORMAT.finditer(value):
        index, kind = match.groups()
        if kind == '%':
            continue
        position += 1
        result.append((int(index or position), kind))
    return Counter(result)


def units(node):
    if 'stringUnit' in node:
        yield node['stringUnit']['value']
    for value in node.values():
        if isinstance(value, dict):
            yield from units(value)


def inspect(resources=RESOURCES):
    errors = []
    for name in ['Localizable', 'InfoPlist', 'PolicyDetails', 'ServerErrors']:
        catalog = json.loads((resources / (name + '.xcstrings')).read_text())
        if catalog['sourceLanguage'] != 'zh-Hans':
            errors.append(f'{name}: source language changed')
        for key, entry in catalog['strings'].items():
            locales = entry.get('localizations', {})
            if set(locales) != LANGUAGES:
                errors.append(f'{name}: incomplete locales for {key!r}')
            # InfoPlist and error table keys are identifiers, not display formats.
            expected = arguments(key) if name == 'Localizable' else None
            for language, node in locales.items():
                plural = node.get('variations', {}).get('plural')
                if plural is not None and language in PLURAL_FORMS and set(plural) != PLURAL_FORMS[language]:
                    errors.append(f'{name}/{language}: incomplete plural forms for {key!r}')
                values = list(units(node))
                if not values or any(not text for text in values):
                    errors.append(f'{name}/{language}: empty translation for {key!r}')
                for text in values:
                    if expected is not None and arguments(text) != expected:
                        errors.append(f'{name}/{language}: mismatched format arguments for {key!r}')
                    if language in {'en', 'fr', 'ru', 'es'} and name in {'Localizable', 'ServerErrors', 'InfoPlist'} and re.search('[\u3400-\u9fff]', text):
                        errors.append(f'{name}/{language}: untranslated Chinese in {key!r}')
                    if re.search(r'QZX\d+XZQ', text):
                        errors.append(f'{name}/{language}: unresolved translation token in {key!r}')
    info = plistlib.loads((resources / 'Info.plist').read_bytes())
    if set(info['CFBundleLocalizations']) != LANGUAGES:
        errors.append('Info.plist: missing supported languages')
    prompts = json.loads((resources / 'InfoPlist.xcstrings').read_text())['strings']
    for key in info:
        if key.startswith('NS') and key.endswith('UsageDescription') and key not in prompts:
            errors.append(f'Untranslated system permission: {key}')
    ui = json.loads((resources / 'Localizable.xcstrings').read_text())['strings']
    for language in sorted(LANGUAGES):
        keyword = ui['注销']['localizations'].get(language, {}).get('stringUnit', {}).get('value')
        prompt = ui['请输入“注销”确认']['localizations'].get(language, {}).get('stringUnit', {}).get('value', '')
        if keyword and keyword not in prompt:
            errors.append(f'{language}: deletion confirmation keyword differs from prompt')
    for name, minimum in [('privacy', 11), ('terms', 10), ('community', 8)]:
        canonical = (resources / (name + '.txt')).read_text()
        if (resources / 'zh-Hans.lproj' / (name + '.txt')).read_text() != canonical:
            errors.append(f'{name}/zh-Hans: generated canonical copy differs')
        placeholders = Counter(re.findall(r'{{(\w+)}}', canonical))
        for language in sorted(LANGUAGES - {'zh-Hans'}):
            path = resources / (language + '.lproj') / (name + '.txt')
            if not path.exists():
                errors.append(f'{name}/{language}: missing legal translation')
                continue
            text = path.read_text()
            if Counter(re.findall(r'{{(\w+)}}', text)) != placeholders:
                errors.append(f'{name}/{language}: legal disclosure placeholders differ')
            headings = re.findall(r'^(?:[一二三四五六七八九十百]+、|[0-9]+\. )[^\n]+$', text, re.M)
            if len(headings) != minimum:
                errors.append(f'{name}/{language}: section count differs')
    names = json.loads((resources / 'EmojiNames.json').read_text())
    if any(set(item) != LANGUAGES - {'zh-Hans'} or not all(item.values()) for item in names.values()):
        errors.append('Missing localized emoji labels')
    return errors


if __name__ == '__main__':
    failures = inspect()
    if failures:
        raise SystemExit('\n'.join(failures))
    print('Localization catalogs, placeholders, permissions and offline policy translations verified.')
