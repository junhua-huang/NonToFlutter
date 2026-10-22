#!/usr/bin/env python3
"""Inspect or update NonTo's App Store draft; never submit or publish it."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import time
from urllib.parse import urlsplit
from urllib.request import Request, build_opener
from urllib.error import HTTPError, URLError

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'ios' / 'scripts'))
from testflight import Apple, BUNDLE, NoRedirect, require

APP_ID = '6824266681'
EDITABLE = {'PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'METADATA_REJECTED', 'REJECTED'}


def rows(api, resource, query=None, *, first_page=False):
    result = api.request('GET', resource, query=query)
    require(first_page or not result.get('links', {}).get('next'), 'Paginated resource needs explicit handling: ' + resource)
    return result.get('data', [])


def safe_get(api, resource):
    try:
        return api.request('GET', resource).get('data')
    except ValueError as error:
        return {'unavailable': str(error)}


def audit(api):
    app = api.request('GET', 'apps/' + APP_ID)['data']
    require(app['attributes']['bundleId'] == BUNDLE, 'App identity mismatch.')
    report = {'app': {key: app['attributes'].get(key) for key in ('name', 'bundleId', 'primaryLocale', 'contentRightsDeclaration')},
              'appInfos': [], 'versions': [], 'builds': [], 'betaAppLocalizations': [], 'internalGroups': []}
    for info in rows(api, f'apps/{APP_ID}/appInfos', {'limit': 200}):
        localizations = rows(api, f'appInfos/{info["id"]}/appInfoLocalizations', {'limit': 200})
        report['appInfos'].append({'id': info['id'], 'attributes': info['attributes'],
                                   'localizations': [{'id': row['id'], **row['attributes']} for row in localizations]})
    for version in rows(api, f'apps/{APP_ID}/appStoreVersions', {'limit': 200}):
        item = {'id': version['id'], 'attributes': version['attributes'], 'localizations': []}
        for loc in rows(api, f'appStoreVersions/{version["id"]}/appStoreVersionLocalizations', {'limit': 200}):
            sets = rows(api, f'appStoreVersionLocalizations/{loc["id"]}/appScreenshotSets', {'limit': 200})
            screenshots = []
            for screenshot_set in sets:
                images = rows(api, f'appScreenshotSets/{screenshot_set["id"]}/appScreenshots', {'limit': 200})
                screenshots.append({'id': screenshot_set['id'], 'displayType': screenshot_set['attributes'].get('screenshotDisplayType'),
                                    'count': len(images), 'states': [image['attributes'].get('assetDeliveryState') for image in images]})
            item['localizations'].append({'id': loc['id'], **loc['attributes'], 'screenshots': screenshots})
        review = safe_get(api, f'appStoreVersions/{version["id"]}/appStoreReviewDetail')
        if review and 'attributes' in review:
            attrs = review['attributes']
            item['reviewDetail'] = {'id': review['id'], 'demoAccountRequired': attrs.get('demoAccountRequired'),
                                    'provided': {key: bool(attrs.get(key)) for key in ('contactFirstName', 'contactLastName', 'contactPhone', 'contactEmail', 'demoAccountName', 'demoAccountPassword', 'notes')}}
        else:
            item['reviewDetail'] = review
        build = safe_get(api, f'appStoreVersions/{version["id"]}/build')
        item['selectedBuild'] = {'id': build['id'], **build['attributes']} if build and 'id' in build else build
        report['versions'].append(item)
    for build in rows(api, 'builds', {'filter[app]': APP_ID, 'sort': '-uploadedDate', 'limit': 10}, first_page=True):
        report['builds'].append({'id': build['id'], **build['attributes'], 'localizations':
                               [{'id': row['id'], **row['attributes']} for row in rows(api, f'builds/{build["id"]}/betaBuildLocalizations', {'limit': 200})]})
    report['betaAppLocalizations'] = [{'id': row['id'], **row['attributes']} for row in rows(api, f'apps/{APP_ID}/betaAppLocalizations', {'limit': 200})]
    for group in rows(api, f'apps/{APP_ID}/betaGroups', {'limit': 200}):
        if not group['attributes'].get('isInternalGroup'):
            continue
        builds = rows(api, f'betaGroups/{group["id"]}/builds', {'limit': 200})
        report['internalGroups'].append({'id': group['id'], 'hasAccessToAllBuilds': group['attributes'].get('hasAccessToAllBuilds'),
                                         'buildVersions': [build['attributes'].get('version') for build in builds]})
    return report


def patch(api, kind, identifier, attributes):
    return api.request('PATCH', f'{kind}/{identifier}', data={'data': {'type': kind, 'id': identifier, 'attributes': attributes}})['data']


def upsert_localization(api, kind, existing, locale, attributes, relation_type, relation_id):
    matches = [row for row in existing if row.get('locale', row.get('attributes', {}).get('locale')) == locale]
    require(len(matches) <= 1, 'Ambiguous localization: ' + kind)
    if matches:
        return patch(api, kind, matches[0]['id'], attributes)
    return api.request('POST', kind, data={'data': {'type': kind, 'attributes': {'locale': locale, **attributes},
                       'relationships': {relation_type: {'data': {'type': {'app': 'apps', 'build': 'builds'}[relation_type], 'id': relation_id}}}}})['data']


def validate_config(config):
    require(config['appID'] == APP_ID and config['bundleID'] == BUNDLE, 'Metadata target mismatch.')
    require(config['locale'] == 'zh-Hans', 'Only the approved Chinese localization is supported.')
    for key, limit in [('name', 30), ('subtitle', 30), ('description', 4000), ('promotionalText', 170)]:
        require(0 < len(config[key]) <= limit, 'Invalid length: ' + key)
    require(len(config['keywords'].encode()) <= 100, 'Keywords exceed 100 UTF-8 bytes.')
    require(1 <= len(config['screenshots']) <= 10, 'Expected one to ten screenshots.')
    for screenshot in config['screenshots']:
        path = (ROOT / screenshot['file']).resolve()
        require(path.is_relative_to(ROOT / '.github' / 'appstore' / 'screenshots'), 'Unexpected screenshot path.')
        require(hashlib.sha256(path.read_bytes()).hexdigest() == screenshot['sha256'], 'Screenshot bytes changed.')
        content = path.read_bytes()
        require(content[:8] == b'\x89PNG\r\n\x1a\n' and int.from_bytes(content[16:20], 'big') == 1320 and
                int.from_bytes(content[20:24], 'big') == 2868, 'Unexpected screenshot format or dimensions.')
    return config


def upload_screenshot(api, set_id, screenshot):
    path = ROOT / screenshot['file']
    content = path.read_bytes()
    checksum = hashlib.md5(content).hexdigest()
    existing = rows(api, f'appScreenshotSets/{set_id}/appScreenshots', {'limit': 200})
    matches = [row for row in existing if row['attributes'].get('fileName') == path.name]
    require(len(matches) <= 1, 'Ambiguous screenshot filename.')
    if matches:
        row = matches[0]
        require(row['attributes'].get('sourceFileChecksum') == checksum, 'Existing screenshot differs; refusing to replace it automatically.')
    else:
        row = api.request('POST', 'appScreenshots', data={'data': {'type': 'appScreenshots',
                          'attributes': {'fileName': path.name, 'fileSize': len(content)},
                          'relationships': {'appScreenshotSet': {'data': {'type': 'appScreenshotSets', 'id': set_id}}}}})['data']
        opener = build_opener(NoRedirect())
        for operation in row['attributes']['uploadOperations']:
            url = urlsplit(operation['url'])
            require(url.scheme == 'https' and url.hostname and url.hostname.endswith('.apple.com') and not url.username and not url.password,
                    'Unexpected asset upload host.')
            offset, length = operation['offset'], operation['length']
            require(0 <= offset < len(content) and 0 < length <= len(content) - offset, 'Invalid upload range.')
            headers = {header['name']: header['value'] for header in operation['requestHeaders']}
            require(not any(name.casefold() == 'authorization' for name in headers), 'Unexpected upload authorization header.')
            request = Request(operation['url'], data=content[offset:offset + length], headers=headers, method=operation['method'])
            try:
                with opener.open(request, timeout=60) as response:
                    require(200 <= response.status < 300, 'Asset transfer failed.')
            except (HTTPError, URLError, TimeoutError, OSError):
                raise ValueError('Asset transfer failed; no temporary upload URL was logged.') from None
        patch(api, 'appScreenshots', row['id'], {'uploaded': True, 'sourceFileChecksum': checksum})
    for _ in range(12):
        result = api.request('GET', 'appScreenshots/' + row['id'])['data']
        state = result['attributes'].get('assetDeliveryState', {}).get('state')
        print('Screenshot:', path.name, state, flush=True)
        if state == 'COMPLETE':
            return
        require(state != 'FAILED', 'Screenshot processing failed: ' + path.name)
        time.sleep(10)
    raise ValueError('Screenshot processing is still pending: ' + path.name)


def apply(api, before, config):
    validate_config(config)
    versions = [row for row in before['versions'] if row['attributes']['platform'] == 'IOS' and row['attributes']['appStoreState'] in EDITABLE]
    infos = [row for row in before['appInfos'] if row['attributes']['appStoreState'] in EDITABLE]
    require(len(versions) == len(infos) == 1, 'Expected one editable iOS draft and app info.')
    version, info = versions[0], infos[0]
    require(version['attributes']['versionString'] in {'1.0', config['version']}, 'Unexpected version; refusing to overwrite another release.')
    locale = config['locale']
    app_loc = [row for row in info['localizations'] if row['locale'] == locale]
    version_loc = [row for row in version['localizations'] if row['locale'] == locale]
    require(len(app_loc) == len(version_loc) == 1, 'Expected existing Chinese App Store localizations.')
    patch(api, 'appInfoLocalizations', app_loc[0]['id'], {key: config[key] for key in ('name', 'subtitle')})
    patch(api, 'appStoreVersions', version['id'], {'versionString': config['version'], 'copyright': config['copyright']})
    patch(api, 'appStoreVersionLocalizations', version_loc[0]['id'], {key: config[key] for key in
          ('description', 'keywords', 'promotionalText', 'marketingUrl', 'supportUrl')})
    upsert_localization(api, 'betaAppLocalizations', before['betaAppLocalizations'], locale,
                        {'description': config['description'], 'feedbackEmail': config['betaFeedbackEmail'], 'marketingUrl': config['marketingUrl']}, 'app', APP_ID)
    builds = [build for build in before['builds'] if build['version'] == config['betaBuildVersion'] and build['processingState'] == 'VALID']
    require(len(builds) == 1, 'Expected the processed test build.')
    upsert_localization(api, 'betaBuildLocalizations', builds[0]['localizations'], locale,
                        {'whatsNew': config['betaWhatsNew']}, 'build', builds[0]['id'])
    sets = rows(api, f'appStoreVersionLocalizations/{version_loc[0]["id"]}/appScreenshotSets', {'limit': 200})
    for screenshot in config['screenshots']:
        matches = [row for row in sets if row['attributes']['screenshotDisplayType'] == screenshot['displayType']]
        require(len(matches) <= 1, 'Ambiguous screenshot set.')
        if matches:
            screenshot_set = matches[0]
        else:
            screenshot_set = api.request('POST', 'appScreenshotSets', data={'data': {'type': 'appScreenshotSets',
                             'attributes': {'screenshotDisplayType': screenshot['displayType']}, 'relationships':
                             {'appStoreVersionLocalization': {'data': {'type': 'appStoreVersionLocalizations', 'id': version_loc[0]['id']}}}}})['data']
            sets.append(screenshot_set)
        upload_screenshot(api, screenshot_set['id'], screenshot)


def verify_applied(report, config):
    version = next(row for row in report['versions'] if row['attributes']['versionString'] == config['version'])
    require(version['attributes']['copyright'] == config['copyright'], 'Copyright readback mismatch.')
    loc = next(row for row in version['localizations'] if row['locale'] == config['locale'])
    for key in ('description', 'keywords', 'promotionalText', 'marketingUrl', 'supportUrl'):
        require(loc[key] == config[key], 'Metadata readback mismatch: ' + key)
    info_loc = next(loc for info in report['appInfos'] if info['attributes']['appStoreState'] in EDITABLE
                    for loc in info['localizations'] if loc['locale'] == config['locale'])
    require(all(info_loc[key] == config[key] for key in ('name', 'subtitle')), 'App info readback mismatch.')
    require(any(group['displayType'] == 'APP_IPHONE_67' and group['count'] == len(config['screenshots']) and
                all(state.get('state') == 'COMPLETE' for state in group['states']) for group in loc['screenshots']), 'Screenshot readback mismatch.')
    beta = next(row for row in report['betaAppLocalizations'] if row['locale'] == config['locale'])
    require(beta['description'] == config['description'] and beta['feedbackEmail'] == config['betaFeedbackEmail'], 'TestFlight description readback mismatch.')
    build = next(row for row in report['builds'] if row['version'] == config['betaBuildVersion'])
    require(any(row['locale'] == config['locale'] and row['whatsNew'] == config['betaWhatsNew'] for row in build['localizations']), 'TestFlight notes readback mismatch.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('appstore-audit.json'))
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--config', type=Path, default=ROOT / '.github' / 'appstore' / 'zh-Hans.json')
    args = parser.parse_args()
    api = Apple()
    report = audit(api)
    if args.apply:
        config = json.loads(args.config.read_text())
        apply(api, report, config)
        report = audit(api)
        verify_applied(report, config)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
