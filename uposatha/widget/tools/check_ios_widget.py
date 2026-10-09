#!/usr/bin/env python3
"""Static sanity check of the Uposatha iOS widget (there is no Xcode on Linux; CI compiles it for real).

  python3 uposatha/widget/tools/check_ios_widget.py

Checks: the pbxproj object graph (every id defined once, every reference defined, no orphans, the widget target's phases, embed,
dependency, configurations), every file of the target exists on disk and is in a build phase, plists/entitlements are well formed
and agree (App Group, bundle ids, versions, deployment target), every .swift file has balanced braces/parentheses/brackets
(strings and comments skipped), every text key the Swift code asks for exists in WidgetStrings.swift in both languages.
Exit code 1 on any ERROR (warnings do not fail)."""
import os, re, sys, json, plistlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))              # uposatha/
IOS = os.path.join(ROOT, 'ios', 'App')
PBX = os.path.join(IOS, 'App.xcodeproj', 'project.pbxproj')
WDIR = os.path.join(IOS, 'UposathaWidget')

errors, warns = [], []
def err(m): errors.append(m)
def warn(m): warns.append(m)

# ---------------------------------------------------------------- old-style plist tokenizer / parser
TOKEN = re.compile(r'''\s+|/\*.*?\*/|//[^\n]*|(?P<str>"(?:\\.|[^"\\])*")|(?P<word>[A-Za-z0-9_./$\-+*@<>]+)|(?P<p>[{}()=;,])''', re.S)

def tokenize(text):
    pos, out = 0, []
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m:
            raise ValueError('bad character %r at offset %d' % (text[pos], pos))
        pos = m.end()
        if m.group('str') is not None:
            out.append(('s', bytes(m.group('str')[1:-1], 'utf-8').decode('unicode_escape') if '\\' in m.group('str') else m.group('str')[1:-1]))
        elif m.group('word') is not None:
            out.append(('s', m.group('word')))
        elif m.group('p') is not None:
            out.append(('p', m.group('p')))
    return out

class Parser:
    def __init__(self, toks): self.t, self.i, self.dups = toks, 0, []
    def peek(self): return self.t[self.i] if self.i < len(self.t) else (None, None)
    def eat(self, v=None):
        k, x = self.peek()
        if k is None: raise ValueError('unexpected end')
        if v is not None and x != v: raise ValueError('expected %r, got %r (token %d)' % (v, x, self.i))
        self.i += 1
        return k, x
    def value(self):
        k, x = self.peek()
        if k == 'p' and x == '{':
            self.eat('{'); d = {}
            while self.peek() != ('p', '}'):
                _, key = self.eat()
                self.eat('=')
                v = self.value()
                self.eat(';')
                if key in d: self.dups.append(key)
                d[key] = v
            self.eat('}')
            return d
        if k == 'p' and x == '(':
            self.eat('('); lst = []
            while self.peek() != ('p', ')'):
                lst.append(self.value())
                if self.peek() == ('p', ','): self.eat(',')
            self.eat(')')
            return lst
        if k == 's':
            self.eat()
            return x
        raise ValueError('unexpected token %r at %d' % (x, self.i))

ID = re.compile(r'^[0-9A-F]{24}$')

def check_pbx():
    text = open(PBX, encoding='utf-8').read()
    first = text.split('\n', 1)[0]
    if not first.startswith('// !$*UTF8*$!'): err('pbxproj: header line missing')
    try:
        p = Parser(tokenize(text))
        root = p.value()
    except Exception as e:
        err('pbxproj does not parse: %s' % e)
        return None
    if p.dups: err('pbxproj: duplicate keys in a dictionary: %s' % sorted(set(p.dups)))
    if p.i != len(p.t): err('pbxproj: trailing tokens after the root dictionary')
    objs = root.get('objects', {})
    # duplicates among the object ids were reported by the parser (dict keys); also catch the id appearing as a key twice in text
    keys = re.findall(r'^\t\t([0-9A-F]{24}) (?:/\*.*?\*/ )?= \{', text, re.M)
    dup = sorted({k for k in keys if keys.count(k) > 1})
    if dup: err('pbxproj: object ids defined twice: %s' % dup)
    for k in objs:
        if not ID.match(k): err('pbxproj: id %r is not 24 hex digits' % k)
    # every id-looking value refers to a defined object
    refs = {}
    def walk(v, owner):
        if isinstance(v, dict):
            for kk, vv in v.items(): walk(vv, owner)
        elif isinstance(v, list):
            for vv in v: walk(vv, owner)
        elif isinstance(v, str) and ID.match(v):
            refs.setdefault(v, set()).add(owner)
    for oid, o in objs.items():
        for kk, vv in o.items(): walk(vv, oid)
    walk({'r': root.get('rootObject')}, 'root')
    for rid, owners in refs.items():
        if rid not in objs: err('pbxproj: %s is referenced (by %s) but not defined' % (rid, sorted(owners)))
    for oid, o in objs.items():
        if oid not in refs and oid != root.get('rootObject'):
            warn('pbxproj: %s (%s %s) is not referenced by anything' % (oid, o.get('isa'), o.get('name') or o.get('path') or ''))
    return root, objs

def group_paths(objs, main):
    """id -> absolute path for every file reference / group reachable from the main group"""
    out = {}
    def rec(gid, base):
        g = objs[gid]
        p = g.get('path')
        here = os.path.normpath(os.path.join(base, p)) if p else base
        out[gid] = here
        for c in g.get('children', []):
            co = objs.get(c)
            if co is None: continue
            if co['isa'] in ('PBXGroup', 'PBXVariantGroup'):
                rec(c, here)
            else:
                cp = co.get('path', '')
                st = co.get('sourceTree')
                if st == '<group>': out[c] = os.path.normpath(os.path.join(here, cp))
                elif st == 'SOURCE_ROOT': out[c] = os.path.normpath(os.path.join(IOS, cp))
                else: out[c] = None
    rec(main, IOS)
    return out

def check_graph(root, objs):
    proj = objs[root['rootObject']]
    targets = {objs[t]['name']: t for t in proj['targets']}
    if 'UposathaWidget' not in targets or 'App' not in targets:
        err('pbxproj: targets App / UposathaWidget missing (have %s)' % list(targets)); return
    app, wid = objs[targets['App']], objs[targets['UposathaWidget']]
    paths = group_paths(objs, proj['mainGroup'])

    if wid['productType'] != 'com.apple.product-type.app-extension': err('widget: productType is %s' % wid['productType'])
    prod = objs[wid['productReference']]
    if prod.get('path') != 'UposathaWidget.appex': err('widget: product is %s' % prod.get('path'))
    # phases of the widget
    kinds = [objs[b]['isa'] for b in wid['buildPhases']]
    for need in ('PBXSourcesBuildPhase', 'PBXFrameworksBuildPhase', 'PBXResourcesBuildPhase'):
        if need not in kinds: err('widget: no %s' % need)
    in_sources, in_resources = set(), set()
    for b in wid['buildPhases']:
        ph = objs[b]
        for f in ph.get('files', []):
            fr = objs[objs[f]['fileRef']]
            (in_sources if ph['isa'] == 'PBXSourcesBuildPhase' else in_resources).add(fr['path'])
    # the files of the widget group: exist on disk, are in the right phase
    wgroup = next((g for g in objs.values() if g['isa'] == 'PBXGroup' and g.get('path') == 'UposathaWidget'), None)
    if wgroup is None: err('widget: no group UposathaWidget'); return
    listed = set()
    for c in wgroup['children']:
        co = objs[c]; full = paths.get(c)
        listed.add(co['path'])
        if not full or not os.path.exists(full): err('widget: file %s is in the project but not on disk (%s)' % (co['path'], full))
        ext = os.path.splitext(co['path'])[1]
        if ext == '.swift' and co['path'] not in in_sources: err('widget: %s is not in the Sources phase' % co['path'])
        if ext in ('.xcassets', '.json') and co['path'] not in in_resources: err('widget: %s is not in the Resources phase' % co['path'])
    for f in sorted(os.listdir(WDIR)):
        if f.startswith('.'): continue
        if f not in listed: err('widget: %s is on disk but not in the project group' % f)
    # nothing but the target's own files in its phases
    for s in in_sources:
        if s not in listed: err('widget: %s is built but is not in the widget group' % s)
    # no Capacitor in the extension
    if wid.get('packageProductDependencies'): err('widget: must not link Swift packages (Capacitor)')
    for b in wid['buildPhases']:
        if objs[b]['isa'] == 'PBXFrameworksBuildPhase' and objs[b].get('files'): warn('widget: frameworks phase is not empty: check it is not Capacitor')
    # embed + dependency in the app
    embed = [objs[b] for b in app['buildPhases'] if objs[b]['isa'] == 'PBXCopyFilesBuildPhase']
    if not embed: err('app: no Embed Foundation Extensions phase')
    else:
        e = embed[0]
        if e.get('dstSubfolderSpec') != '13': err('app: embed phase dstSubfolderSpec is %s, PlugIns is 13' % e.get('dstSubfolderSpec'))
        if not any(objs[objs[f]['fileRef']].get('path') == 'UposathaWidget.appex' for f in e['files']): err('app: the appex is not in the embed phase')
    if not any(objs[d]['target'] == targets['UposathaWidget'] for d in app['dependencies']): err('app: no target dependency on the widget')
    for d in app['dependencies']:
        pr = objs[objs[d]['targetProxy']]
        if pr['remoteGlobalIDString'] not in objs: err('app: dependency proxy points nowhere')
    # build settings
    def settings(t, name):
        lst = objs[objs[t]['buildConfigurationList']]
        return next(objs[c]['buildSettings'] for c in lst['buildConfigurations'] if objs[c]['name'] == name)
    for cfgname in ('Debug', 'Release'):
        a, w = settings(targets['App'], cfgname), settings(targets['UposathaWidget'], cfgname)
        for k in ('MARKETING_VERSION', 'CURRENT_PROJECT_VERSION', 'IPHONEOS_DEPLOYMENT_TARGET', 'SWIFT_VERSION', 'TARGETED_DEVICE_FAMILY', 'CODE_SIGN_STYLE'):
            if a.get(k) != w.get(k): err('%s: %s differs (app %r, widget %r)' % (cfgname, k, a.get(k), w.get(k)))
        if w.get('PRODUCT_BUNDLE_IDENTIFIER') != 'gift.dhamma.uposatha.widget': err('%s: widget bundle id %r' % (cfgname, w.get('PRODUCT_BUNDLE_IDENTIFIER')))
        if a.get('PRODUCT_BUNDLE_IDENTIFIER') != 'gift.dhamma.uposatha': err('%s: app bundle id %r' % (cfgname, a.get('PRODUCT_BUNDLE_IDENTIFIER')))
        if w.get('SKIP_INSTALL') != 'YES': err('%s: widget SKIP_INSTALL is not YES' % cfgname)
        for k in ('INFOPLIST_FILE', 'CODE_SIGN_ENTITLEMENTS'):
            if not os.path.exists(os.path.join(IOS, w.get(k, '/nonexistent'))): err('%s: widget %s %r does not exist' % (cfgname, k, w.get(k)))
        if 'DEVELOPMENT_TEAM' in a or 'DEVELOPMENT_TEAM' in w:
            if a.get('DEVELOPMENT_TEAM') != w.get('DEVELOPMENT_TEAM'): err('%s: DEVELOPMENT_TEAM differs' % cfgname)
    # other files of the project: missing ones are only warnings (public/, config.xml, capacitor.config.json are made by `cap sync`)
    for oid, o in objs.items():
        if o['isa'] == 'PBXFileReference' and oid not in [c for c in wgroup['children']]:
            full = paths.get(oid)
            if full and not os.path.exists(full): warn('project file not on disk (made by cap sync?): %s' % os.path.relpath(full, IOS))

# ---------------------------------------------------------------- plists
def load_plist(path):
    try:
        with open(path, 'rb') as f: return plistlib.load(f)
    except Exception as e:
        err('%s is not a well-formed plist: %s' % (os.path.relpath(path, ROOT), e)); return None

def check_plists():
    app_ent = load_plist(os.path.join(IOS, 'App', 'App.entitlements'))
    wid_ent = load_plist(os.path.join(WDIR, 'UposathaWidget.entitlements'))
    info_app = load_plist(os.path.join(IOS, 'App', 'Info.plist'))
    info_w = load_plist(os.path.join(WDIR, 'Info.plist'))
    for name, ent in (('App.entitlements', app_ent), ('UposathaWidget.entitlements', wid_ent)):
        if ent is not None and 'group.gift.dhamma.uposatha' not in ent.get('com.apple.security.application-groups', []):
            err('%s: App Group group.gift.dhamma.uposatha missing' % name)
    if info_w is not None:
        ext = info_w.get('NSExtension', {})
        if ext.get('NSExtensionPointIdentifier') != 'com.apple.widgetkit-extension': err('widget Info.plist: NSExtensionPointIdentifier is %r' % ext.get('NSExtensionPointIdentifier'))
        if 'NSExtensionPrincipalClass' in ext: err('widget Info.plist: a widget has no principal class (@main is enough)')
        if info_w.get('CFBundlePackageType') not in ('$(PRODUCT_BUNDLE_PACKAGE_TYPE)', 'XPC!'): err('widget Info.plist: CFBundlePackageType %r' % info_w.get('CFBundlePackageType'))
        for k in ('CFBundleShortVersionString', 'CFBundleVersion', 'CFBundleExecutable', 'CFBundleIdentifier'):
            if k not in info_w: err('widget Info.plist: %s missing' % k)
    if info_app is not None:
        schemes = [s for t in info_app.get('CFBundleURLTypes', []) for s in t.get('CFBundleURLSchemes', [])]
        if 'gift.dhamma.uposatha' not in schemes: err('app Info.plist: URL scheme gift.dhamma.uposatha missing')
    for root_, _, files in os.walk(WDIR):
        for f in files:
            if f == 'Contents.json' or f.endswith('.json'):
                try: json.load(open(os.path.join(root_, f), encoding='utf-8'))
                except Exception as e: err('%s is not valid JSON: %s' % (os.path.relpath(os.path.join(root_, f), ROOT), e))
    moon = os.path.join(WDIR, 'Assets.xcassets', 'moon.imageset', 'moon.png')
    if not os.path.exists(moon): err('the moon photo is missing: %s' % moon)

# ---------------------------------------------------------------- swift
def strip_swift(src):
    """drop comments and string literals (including interpolation) so only code brackets are left"""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith('//', i):
            while i < n and src[i] != '\n': i += 1
        elif src.startswith('/*', i):
            depth = 1; i += 2
            while i < n and depth:
                if src.startswith('/*', i): depth += 1; i += 2
                elif src.startswith('*/', i): depth -= 1; i += 2
                else: i += 1
        elif src.startswith('"""', i):
            j = src.find('"""', i + 3)
            if j < 0: out.append('\0UNTERMINATED'); break
            i = j + 3
        elif c == '"':
            i += 1
            while i < n and src[i] != '"':
                if src[i] == '\\':
                    if i + 1 < n and src[i + 1] == '(':
                        # interpolation: skip to the matching paren
                        depth = 1; i += 2
                        while i < n and depth:
                            if src[i] == '(': depth += 1
                            elif src[i] == ')': depth -= 1
                            i += 1
                        continue
                    i += 2; continue
                if src[i] == '\n': out.append('\0NEWLINE-IN-STRING'); break
                i += 1
            i += 1
        else:
            out.append(c); i += 1
    return ''.join(out)

def check_swift(path):
    src = open(path, encoding='utf-8').read()
    code = strip_swift(src)
    rel = os.path.relpath(path, ROOT)
    if '\0' in code: err('%s: %s' % (rel, code[code.index('\0') + 1:].split('\0')[0][:30])); return
    pairs = {')': '(', ']': '[', '}': '{'}
    stack, line = [], 1
    for ch in code:
        if ch == '\n': line += 1
        elif ch in '([{': stack.append((ch, line))
        elif ch in pairs:
            if not stack or stack[-1][0] != pairs[ch]:
                err('%s:%d: unbalanced %r' % (rel, line, ch)); return
            stack.pop()
    if stack: err('%s: %r opened at line %d is never closed' % (rel, stack[-1][0], stack[-1][1]))
    if re.search(r'\bimport\s+Capacitor\b', src) and path.startswith(WDIR): err('%s: the widget must not import Capacitor' % rel)
    return src

STRING_KEY = re.compile(r'"([A-Za-z][A-Za-z0-9._]*)"')

def check_strings(sources):
    ws = open(os.path.join(WDIR, 'WidgetStrings.swift'), encoding='utf-8').read()
    langs = {}
    for lang in ('ru', 'en'):
        m = re.search(r'"%s": \[\n(.*?)\n        \],' % lang, ws, re.S)
        langs[lang] = set(re.findall(r'^\s+"([^"]+)": "', m.group(1), re.M)) if m else set()
        if not langs[lang]: err('WidgetStrings.swift: no %s block' % lang)
    if langs['ru'] and langs['en'] and langs['ru'] != langs['en']:
        err('WidgetStrings.swift: ru/en keys differ: %s' % sorted(langs['ru'] ^ langs['en']))
    # keys of strings.json are all there
    sj = json.load(open(os.path.join(ROOT, 'widget', 'design', 'strings.json'), encoding='utf-8'))
    for lang in ('ru', 'en'):
        for k, v in sj[lang].items():
            if isinstance(v, str) and k not in langs[lang]: err('WidgetStrings.swift is behind strings.json: %s.%s (run gen_ios_strings.py)' % (lang, k))
    # keys the code asks for: .s("key" ...) / .s(cond ? "a" : "b" ...) / .s("prefix." + x)
    for path, src in sources.items():
        if src is None or path.endswith('WidgetStrings.swift'): continue
        for m in re.finditer(r'\.s\(((?:[^()"]|"[^"]*"|\([^()]*\))*)', src):
            arg = m.group(1)
            first = re.split(r',\s*\[', arg)[0]     # up to the vars dictionary
            for lit in re.findall(r'"([^"]*)"', first):
                if lit.endswith('.'):
                    if not any(k.startswith(lit) for k in langs['en']): err('%s: no text keys with prefix %r' % (os.path.basename(path), lit))
                elif lit not in langs['en']:
                    err('%s: text key %r is not in WidgetStrings' % (os.path.basename(path), lit))

def main():
    r = check_pbx()
    if r:
        try:
            check_graph(*r)
        except (KeyError, TypeError, IndexError) as e:
            err('pbxproj graph check stopped on a broken reference: %r' % (e,))
    check_plists()
    sources = {}
    for f in sorted(os.listdir(WDIR)):
        if f.endswith('.swift'): sources[os.path.join(WDIR, f)] = check_swift(os.path.join(WDIR, f))
    for f in ('DgApp.swift', 'SceneDelegate.swift'):
        check_swift(os.path.join(IOS, 'App', f))
    check_strings(sources)
    # the plugin and the URL hand-over exist in the app
    dg = open(os.path.join(IOS, 'App', 'DgApp.swift'), encoding='utf-8').read()
    for needle in ('class DgWidgetPlugin', 'registerPluginInstance(DgWidgetPlugin())', 'group.gift.dhamma.uposatha', 'static func deliver(url: URL)', 'reloadAllTimelines()'):
        if needle not in dg: err('DgApp.swift: %r missing' % needle)
    sd = open(os.path.join(IOS, 'App', 'SceneDelegate.swift'), encoding='utf-8').read()
    if sd.count('deliver(url:') < 2: err('SceneDelegate.swift: the URL hand-over is missing (cold start and running app)')
    for w in warns: print('WARN ', w)
    for e in errors: print('ERROR', e)
    print('%d error(s), %d warning(s)' % (len(errors), len(warns)))
    return 1 if errors else 0

if __name__ == '__main__':
    sys.exit(main())
