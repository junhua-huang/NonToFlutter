#!/usr/bin/env python3
"""Inspect or update NonTo's App Store draft; never submit or publish it."""
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'ios' / 'scripts'))
from testflight import Apple, BUNDLE, require

APP_ID = '6824266681'


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
        report['builds'].append({'id': build['id'], **build['attributes']})
    report['betaAppLocalizations'] = [{'id': row['id'], **row['attributes']} for row in rows(api, f'apps/{APP_ID}/betaAppLocalizations', {'limit': 200})]
    for group in rows(api, f'apps/{APP_ID}/betaGroups', {'limit': 200}):
        if not group['attributes'].get('isInternalGroup'):
            continue
        builds = rows(api, f'betaGroups/{group["id"]}/builds', {'limit': 200})
        report['internalGroups'].append({'id': group['id'], 'hasAccessToAllBuilds': group['attributes'].get('hasAccessToAllBuilds'),
                                         'buildVersions': [build['attributes'].get('version') for build in builds]})
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('appstore-audit.json'))
    args = parser.parse_args()
    report = audit(Apple())
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
