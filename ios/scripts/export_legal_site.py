#!/usr/bin/env python3
"""Export the exact bundled legal documents as a static, tracker-free website."""
import argparse
import hashlib
import html
import json
import re
from pathlib import Path
from urllib.parse import quote

import check_compliance

TITLES = {'privacy': '隐私政策', 'terms': '服务条款', 'community': '社区规范'}
DEFAULT_OUTPUT = Path(__file__).resolve().parents[1] / 'legal-public'
MISSING = '暂未提供。可通过“联系与投诉”了解相关信息。'
STYLE = '''
:root{color-scheme:light dark;--accent:#159fe5;--background:#f6f7f9;--card:#fff;--text:#17191c;--muted:#606770;--line:#dce1e6}
@media(prefers-color-scheme:dark){:root{--background:#090b0e;--card:#15191e;--text:#f1f4f6;--muted:#acb5bf;--line:#343b44}}
*{box-sizing:border-box}body{margin:0;background:var(--background);color:var(--text);font:17px/1.8 system-ui,-apple-system,sans-serif}
header,main,footer{max-width:800px;margin:auto;padding:24px}header{padding-bottom:0}nav{display:flex;flex-wrap:wrap;gap:12px 24px}
a{color:var(--accent);text-underline-offset:4px;overflow-wrap:anywhere}a:focus-visible{outline:3px solid var(--accent);outline-offset:4px}
article,.card{background:var(--card);border:1px solid var(--line);border-radius:20px;padding:24px;margin-top:20px}h1{font-size:1.8rem;line-height:1.4}
h2{font-size:1.2rem;margin-top:2em}p{white-space:pre-wrap;overflow-wrap:anywhere}.muted,footer{color:var(--muted)}
.notice{border-inline-start:4px solid var(--accent);padding:12px 16px;background:var(--card)}details{border-bottom:1px solid var(--line);padding:10px 0}
summary{cursor:pointer}li{margin-bottom:8px}@media(max-width:420px){header,main,footer{padding:18px}article,.card{padding:18px}}
'''

def render(template, config):
    return re.sub(r'\{\{(\w+)\}\}', lambda match: str(config.get(match[1], '')).strip() or
                  config.get('disclosureNotes', {}).get(match[1], '') or MISSING, template)

def document_body(text):
    # Headings use the same standalone Chinese-number convention as PolicySection.
    blocks = text.split('\n', 1)[1].split('\n\n')
    parts = []
    for block in blocks:
        value = block.strip()
        if not value:
            continue
        tag = 'h2' if re.fullmatch(r'[一二三四五六七八九十百]+、[^\n]+', value) else 'p'
        parts.append(f'<{tag}>{html.escape(value)}</{tag}>')
    return '\n'.join(parts)

def pages(resources=check_compliance.RESOURCES):
    errors, blockers = check_compliance.inspect(resources)
    if errors:
        raise ValueError('; '.join(errors))
    config = json.loads((resources / 'Compliance.json').read_text())
    revision = hashlib.sha256(b''.join((resources / name).read_bytes() for name in
        ['Compliance.json'] + [kind + '.txt' for kind in check_compliance.DOCUMENTS])).hexdigest()
    version = html.escape(config['policyVersion'])
    nav = '<a href="index.html">服务与隐私</a> ' + ' '.join(
        f'<a href="{kind}.html">{title}</a>' for kind, title in TITLES.items())
    email = config.get('contactEmail', '')
    contact = html.escape(email)
    if re.fullmatch(r'[^\s@?:/]+@[^\s@?:/]+\.[^\s@?:/]+', email):
        contact = f'<a href="mailto:{html.escape(quote(email, safe="@."), quote=True)}">{contact}</a>'
    def page(title, content):
        return f'''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<meta name="referrer" content="no-referrer"><title>南图 · {title}</title><style>{STYLE}</style></head>
<body><header><nav aria-label="服务文档">{nav}</nav></header><main><h1>南图 · {title}</h1>{content}</main>
<footer>版本：{version}<br>联系、投诉与权利申请：{contact}<br>请勿通过邮件发送密码、验证码或无关完整证件。</footer></body></html>
'''
    result = {}
    for kind, title in TITLES.items():
        text = render((resources / (kind + '.txt')).read_text(), config)
        result[kind + '.html'] = page(title, '<article>' + document_body(text) + '</article>')
    cards = ''.join(f'<section class="card"><h2><a href="{kind}.html">{title}</a></h2></section>' for kind, title in TITLES.items())
    filing = config.get('appFilingNumber', '')
    filing_text = ('APP 备案：' + html.escape(filing)) if filing else '备案信息可通过工信部备案管理系统查询。'
    result['index.html'] = page('服务与隐私', '<p>了解南图的信息处理、使用规则、举报和申诉方式。</p>' + cards +
        '<section class="card"><h2>联系与投诉</h2><p>请按使用反馈、举报投诉、个人信息权利申请或处置申诉说明来意，提供相关账号或内容编号及必要依据。请只提供与请求有关的信息。</p>' +
        '<p>' + filing_text +
        '</p><a href="https://beian.miit.gov.cn/">前往工信部备案查询系统</a></section>')
    result['manifest.json'] = json.dumps({'policyVersion': config['policyVersion'], 'revision': revision,
        'releaseReady': not blockers, 'documents': list(TITLES)}, ensure_ascii=False, indent=2) + '\n'
    return result, blockers

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument('--check', action='store_true', help='Fail if committed pages differ from the app documents')
    parser.add_argument('--release', action='store_true', help='Refuse to export unverified release policies')
    args = parser.parse_args()
    result, blockers = pages()
    if args.release and blockers:
        raise SystemExit('Release export blocked: ' + '; '.join(blockers))
    if args.check:
        stale = [name for name, text in result.items() if not (args.output / name).is_file() or (args.output / name).read_text() != text]
        if stale:
            raise SystemExit('Legal website is out of sync: ' + ', '.join(stale))
        print('Legal website matches bundled policies; releaseReady=' + str(not blockers))
        return
    args.output.mkdir(parents=True, exist_ok=True)
    for name, text in result.items():
        (args.output / name).write_text(text)
    print(f'Exported {len(result)} files; releaseReady={not blockers}. No files were deployed.')

if __name__ == '__main__':
    main()
