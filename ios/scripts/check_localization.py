#!/usr/bin/env python3
"""Validate shipped catalogs, format arguments, legal resources and system prompts."""
from collections import Counter
import json
from pathlib import Path
import plistlib
import re

RESOURCES = Path(__file__).resolve().parents[1] / 'Nonto/Resources'
LANGUAGES = {'zh-Hans', 'zh-Hant', 'en'}
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
                values = list(units(node))
                if not values or any(not text for text in values):
                    errors.append(f'{name}/{language}: empty translation for {key!r}')
                for text in values:
                    if expected is not None and arguments(text) != expected:
                        errors.append(f'{name}/{language}: mismatched format arguments for {key!r}')
                    if language == 'en' and name in {'Localizable', 'ServerErrors', 'InfoPlist'} and re.search('[\u3400-\u9fff]', text):
                        errors.append(f'{name}/en: untranslated Chinese in {key!r}')
    info = plistlib.loads((resources / 'Info.plist').read_bytes())
    if set(info['CFBundleLocalizations']) != LANGUAGES:
        errors.append('Info.plist: missing supported languages')
    prompts = json.loads((resources / 'InfoPlist.xcstrings').read_text())['strings']
    for key in info:
        if key.startswith('NS') and key.endswith('UsageDescription') and key not in prompts:
            errors.append(f'Untranslated system permission: {key}')
    for name, minimum in [('privacy', 11), ('terms', 10), ('community', 8)]:
        canonical = (resources / (name + '.txt')).read_text()
        placeholders = Counter(re.findall(r'{{(\w+)}}', canonical))
        for language in ['en', 'zh-Hant']:
            text = (resources / (language + '.lproj') / (name + '.txt')).read_text()
            if Counter(re.findall(r'{{(\w+)}}', text)) != placeholders:
                errors.append(f'{name}/{language}: legal disclosure placeholders differ')
            headings = re.findall(r'^(?:[一二三四五六七八九十百]+、|[0-9]+\. )[^\n]+$', text, re.M)
            if len(headings) != minimum:
                errors.append(f'{name}/{language}: section count differs')
    names = json.loads((resources / 'EmojiNames.json').read_text())
    if any(set(item) != {'en', 'zh-Hant'} or not all(item.values()) for item in names.values()):
        errors.append('Missing localized emoji labels')
    return errors


if __name__ == '__main__':
    failures = inspect()
    if failures:
        raise SystemExit('\n'.join(failures))
    print('Localization catalogs, placeholders, permissions and offline policy translations verified.')
