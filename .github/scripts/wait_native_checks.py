#!/usr/bin/env python3
"""Wait for all iPhone and iPad regressions on this exact commit before Store upload."""
import json
import os
import re
import time
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, Request, build_opener

REQUIRED = ('Native iOS', 'Native iOS 27 Regression', 'Native iPad')


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def check_states(runs, commit):
    states = {name: 'missing' for name in REQUIRED}
    for run in runs:
        name = run.get('name')
        if name not in states or states[name] != 'missing':
            continue
        if run.get('head_sha') != commit or run.get('head_branch') != 'ios' or run.get('event') != 'push':
            continue
        if run.get('status') == 'completed':
            if run.get('conclusion') != 'success':
                raise ValueError(name + ' did not pass; no Store upload will run.')
            states[name] = 'success'
        else:
            states[name] = run.get('status', 'pending')
    return states


def main():
    repository = os.environ['GITHUB_REPOSITORY']
    commit = os.environ['GITHUB_SHA']
    if repository != 'junhua-huang/NonToFlutter' or not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Unexpected regression target.')
    request = Request('https://api.github.com/repos/' + repository + '/actions/runs?head_sha=' + commit + '&per_page=100',
                      headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'Accept': 'application/vnd.github+json'})
    opener = build_opener(NoRedirect())
    deadline, previous = time.monotonic() + 1200, None
    while time.monotonic() < deadline:
        try:
            with opener.open(request, timeout=20) as response:
                states = check_states(json.load(response)['workflow_runs'], commit)
        except HTTPError as error:
            if error.code not in (408, 429, 500, 502, 503, 504):
                raise ValueError('Cannot read native checks; workflow needs actions:read.') from None
            time.sleep(20); continue
        except (URLError, TimeoutError):
            time.sleep(20); continue
        if states != previous:
            print(json.dumps(states), flush=True); previous = states
        if all(value == 'success' for value in states.values()):
            print('All iPhone and iPad regressions passed for the exact Store upload commit.', flush=True)
            return
        time.sleep(20)
    raise ValueError('Native regression checks are still pending; no Store upload was attempted.')


if __name__ == '__main__':
    main()
