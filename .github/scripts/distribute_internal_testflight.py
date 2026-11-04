"""Assign an already processed build to existing internal groups and verify it."""
import sys
from appstore_metadata import Apple, APP_ID, BUNDLE, rows, require


def distribute(api, number):
    app = api.request('GET', 'apps/' + APP_ID)['data']
    require(app['attributes']['bundleId'] == BUNDLE, 'App identity mismatch.')
    builds = rows(api, 'builds', {'filter[app]': APP_ID, 'filter[version]': number, 'limit': 10})
    require(len(builds) == 1 and builds[0]['attributes']['processingState'] == 'VALID'
            and not builds[0]['attributes'].get('expired'), 'Expected one processed, unexpired build. Do not upload again.')
    build_id = builds[0]['id']
    groups = [group for group in rows(api, f'apps/{APP_ID}/betaGroups', {'limit': 200})
              if group['attributes'].get('isInternalGroup')]
    require(groups, 'No existing internal group; no tester invitation or group was created.')
    for group in groups:
        resource = f'betaGroups/{group["id"]}/builds'
        if not group['attributes'].get('hasAccessToAllBuilds'):
            assigned = rows(api, resource, {'limit': 200})
            if not any(build['id'] == build_id for build in assigned):
                api.request('POST', f'betaGroups/{group["id"]}/relationships/builds',
                            data={'data': [{'type': 'builds', 'id': build_id}]})
            current = rows(api, resource, {'limit': 200})
            require(any(build['id'] == build_id for build in current), 'TestFlight group readback mismatch; do not upload again.')
    print('TestFlight build', number, 'is available to', len(groups), 'existing internal group(s).')
    return len(groups)


if __name__ == '__main__':
    require(len(sys.argv) == 2, 'Supply the processed build number.')
    distribute(Apple(), sys.argv[1])
