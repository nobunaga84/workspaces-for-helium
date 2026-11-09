import json, sys
# prefs.py <Preferences> a.b ... (prints each value as JSON) | a.b=<json> ... (writes them; the browser closed)
path = sys.argv[1]
data = json.load(open(path, encoding='utf-8'))
writes = False
for arg in sys.argv[2:]:
    key, eq, value = arg.partition('=')
    keys = key.split('.')
    node = data
    for k in keys[:-1]:
        node = node.setdefault(k, {}) if eq else (node.get(k) or {})
    if eq:
        node[keys[-1]] = json.loads(value)
        writes = True
    else:
        print(json.dumps(node.get(keys[-1])))
if writes:
    json.dump(data, open(path, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
