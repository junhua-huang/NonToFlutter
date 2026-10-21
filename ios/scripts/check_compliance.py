#!/usr/bin/env python3
"""Check bundled disclosures; --release also enforces operator-supplied readiness evidence."""
import argparse
import json
import plistlib
import re
from pathlib import Path
from urllib.parse import urlparse

RESOURCES = Path(__file__).resolve().parents[1] / 'Nonto' / 'Resources'
REQUIRED_FIELDS = (
    'operatorName', 'contactEmail', 'privacyPolicyURL', 'termsURL', 'communityRulesURL', 'appFilingNumber',
    'storageSummary', 'retentionSummary', 'processorSummary', 'minorProtectionSummary',
    'realNameVerificationSummary', 'rightsResponseSummary',
)
EVIDENCE = (
    'accountDeletionVerified', 'moderationOperational', 'rightsRequestsOperational',
    'realNameVerificationVerified', 'minorProtectionReviewed',
    'storageAndProcessorsReviewed', 'appStorePrivacyLabelsReviewed',
)
PLACEHOLDER = re.compile(r'facebook[-_]?clone|example\.(com|org|net)|\.example\b|待补|待确认|未配置|TODO', re.I)
DOCUMENTS = ('privacy', 'terms', 'community')
APP_FILING = re.compile(r'[京津沪渝冀豫云辽黑湘皖鲁新苏浙赣鄂桂甘晋蒙陕吉闽贵粤青藏川宁琼]ICP备[0-9]{6,}号-[0-9]+A')
REQUIRED_TYPES = {
    'NSPrivacyCollectedDataTypeEmailAddress', 'NSPrivacyCollectedDataTypeName',
    'NSPrivacyCollectedDataTypeUserID', 'NSPrivacyCollectedDataTypePhotosorVideos',
    'NSPrivacyCollectedDataTypeOtherUserContent', 'NSPrivacyCollectedDataTypeSearchHistory',
    'NSPrivacyCollectedDataTypeProductInteraction', 'NSPrivacyCollectedDataTypeEmailsOrTextMessages',
    'NSPrivacyCollectedDataTypeDeviceID', 'NSPrivacyCollectedDataTypeCustomerSupport',
    'NSPrivacyCollectedDataTypePhoneNumber',
}

def inspect(resources=RESOURCES):
    errors, blockers = [], []
    config = json.loads((resources / 'Compliance.json').read_text())
    manifest = plistlib.loads((resources / 'PrivacyInfo.xcprivacy').read_bytes())
    if not config.get('policyVersion'):
        errors.append('policyVersion is missing')
    for name in DOCUMENTS:
        text = (resources / (name + '.txt')).read_text()
        if PLACEHOLDER.search(text):
            errors.append(name + ' contains a stale sample contact or placeholder promise')
        if '{{contactEmail}}' not in text:
            errors.append(name + ' must include the contact email')
        if '{{policyVersion}}' not in text:
            errors.append(name + ' must include the policy version')
        # Filling internal metadata alone must never bypass public disclosure.
        if '{{operatorName}}' not in text:
            blockers.append('Public operator identity disclosure is missing: ' + name)
        for key in re.findall(r'\{\{(\w+)\}\}', text):
            if key not in config:
                errors.append(name + ' has an unknown template key: ' + key)
    types = {row['NSPrivacyCollectedDataType'] for row in manifest['NSPrivacyCollectedDataTypes']}
    errors += ['Missing privacy data type: ' + name for name in sorted(REQUIRED_TYPES - types)]
    if manifest.get('NSPrivacyTracking') is not False or manifest.get('NSPrivacyTrackingDomains'):
        errors.append('Tracking declarations differ from the reviewed no-ad-tracking implementation')
    reasons = {row['NSPrivacyAccessedAPIType']: row['NSPrivacyAccessedAPITypeReasons'] for row in manifest['NSPrivacyAccessedAPITypes']}
    if 'CA92.1' not in reasons.get('NSPrivacyAccessedAPICategoryUserDefaults', []):
        errors.append('App-local UserDefaults reason CA92.1 is missing')
    for key in REQUIRED_FIELDS:
        value = config.get(key, '')
        if not isinstance(value, str) or not value.strip() or PLACEHOLDER.search(value):
            blockers.append('Complete and verify ' + key)
    email = config.get('contactEmail', '')
    if not re.fullmatch(r'[^\s@?]+@[^\s@?]+\.[^\s@?]+', email):
        blockers.append('A working contact email is required')
    if not APP_FILING.fullmatch(config.get('appFilingNumber', '').strip()):
        blockers.append('A verified APP filing number ending in -<number>A is required; a website ICP number is not an APP filing')
    for key in ('privacyPolicyURL', 'termsURL', 'communityRulesURL'):
        url = urlparse(config.get(key, ''))
        if url.scheme != 'https' or not url.hostname or url.username or url.password:
            blockers.append('A public HTTPS URL is required: ' + key)
    if config.get('releaseReviewed') is not True:
        blockers.append('Operator has not reviewed the completed policies')
    for key in EVIDENCE:
        if config.get('verification', {}).get(key) is not True:
            blockers.append('Missing operational verification: ' + key)
    return errors, blockers

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', action='store_true')
    args = parser.parse_args()
    errors, blockers = inspect()
    for message in errors:
        print('ERROR:', message)
    for message in blockers:
        print('RELEASE BLOCKER:', message)
    print(f'{len(errors)} structural errors; {len(blockers)} release blockers. This check is not legal certification.')
    return 1 if errors or (args.release and blockers) else 0

if __name__ == '__main__':
    raise SystemExit(main())
