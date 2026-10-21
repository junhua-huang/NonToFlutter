"""Read recent technical NonTo crash evidence without tester identities."""
import importlib.util
import json
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('testflight', Path(__file__).resolve().parents[2] / 'ios/scripts/testflight.py')
tf = importlib.util.module_from_spec(spec); spec.loader.exec_module(tf)


def technical_summary(text):
    # Apple may return a JSON .ips report with a one-line JSON header before it.
    decoder = json.JSONDecoder()
    documents = []
    rest = text.lstrip()
    while rest.startswith('{'):
        try:
            value, end = decoder.raw_decode(rest)
            documents.append(value); rest = rest[end:].lstrip()
        except ValueError:
            break
    if documents:
        report = documents[-1]
        result = {key: report[key] for key in ('exception', 'termination', 'faultingThread') if key in report}
        threads = report.get('threads', [])
        triggered = [thread for thread in threads if thread.get('triggered')]
        if not triggered and isinstance(report.get('faultingThread'), int):
            index = report['faultingThread']
            if 0 <= index < len(threads): triggered = [threads[index]]
        result['frames'] = [{key: frame[key] for key in ('symbol', 'symbolLocation', 'imageIndex', 'imageOffset') if key in frame}
                            for thread in triggered for frame in thread.get('frames', [])[:40]]
        result['images'] = [{key: image[key] for key in ('name', 'uuid', 'base', 'arch') if key in image}
                            for image in report.get('usedImages', [])]
        return result
    # Legacy text reports: only exception headings and stack frames, never the
    # tester comment, device identifiers, binary paths, or arbitrary app logs.
    lines = [line for line in text.splitlines() if re.match(r'^(Exception Type:|Exception Codes:|Termination Reason:|Triggered by Thread:|Crashed Thread:|\d+\s+\S+\s+0x)', line)]
    return {'technicalLines': lines[:70]}


def main():
    apple = tf.Apple()
    apps = apple.request('GET', 'apps', query={'filter[bundleId]': tf.BUNDLE})['data']
    tf.require(len(apps) == 1, 'NonTo app was not uniquely identified.')
    builds = apple.request('GET', 'builds', query={'filter[app]': apps[0]['id'], 'sort': '-uploadedDate', 'limit': '1'})['data']
    tf.require(len(builds) == 1, 'Latest NonTo build was not uniquely identified.')
    version = builds[0]['attributes']['version']
    reports = apple.request('GET', f'apps/{apps[0]["id"]}/betaFeedbackCrashSubmissions', query={
        'filter[build]': builds[0]['id'], 'limit': '20', 'sort': '-createdDate',
        'fields[betaFeedbackCrashSubmissions]': 'createdDate,deviceModel,osVersion,appUptimeInMilliseconds,buildBundleId'})['data']
    print('NonTo build', version, 'crash submissions:', len(reports), flush=True)
    if not reports:
        reports = apple.request('GET', f'apps/{apps[0]["id"]}/betaFeedbackCrashSubmissions', query={
            'limit': '20', 'sort': '-createdDate',
            'fields[betaFeedbackCrashSubmissions]': 'createdDate,deviceModel,osVersion,appUptimeInMilliseconds,buildBundleId'})['data']
        print('Recent NonTo crash submissions across all builds:', len(reports), flush=True)
    for report in reports[:5]:
        print(json.dumps({key: report['attributes'].get(key) for key in
                          ('createdDate', 'deviceModel', 'osVersion', 'appUptimeInMilliseconds', 'buildBundleId')}), flush=True)
        log = apple.request('GET', f'betaFeedbackCrashSubmissions/{report["id"]}/crashLog')['data']['attributes'].get('logText', '')
        print(json.dumps(technical_summary(log), ensure_ascii=True), flush=True)
    print('Read-only technical crash lookup completed. No Apple resources changed.')


if __name__ == '__main__':
    try: main()
    except (ValueError, KeyError, OSError) as error:
        print('Crash lookup unavailable:', str(error) if isinstance(error, ValueError) else type(error).__name__)
        raise SystemExit(1)
