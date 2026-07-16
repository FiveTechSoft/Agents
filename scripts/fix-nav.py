with open('/tmp/fwh_docs_tmp/js/nav.js', 'r', encoding='utf-8') as f:
    content = f.read()

# The sidebar header HTML builds with:
# var html = '<div id="sidebar-header">...<span class="version">'+L.version+'</span></div>' + ...
# We need to add language switch links AFTER the version span, inside the header div

old_header = """<span class=\\"version\\">'+L.version+'</span></div>' +"""

new_header = """<span class=\\"version\\">'+L.version+'</span>\
    <div class=\\"nav-lang-switch\\" style=\\"margin-top:6px;font-size:11px\\">\
    <a href=\\"../../en/"""+cur.replace(/^(en|es|pt)\\/, '')+"""\\" style=\\"color:var(--link);text-decoration:none\\">EN</a> \
    &middot; <a href=\\"../../es/"""+cur.replace(/^(en|es|pt)\\/, '')+"""\\" style=\\"color:var(--link);text-decoration:none\\">ES</a> \
    &middot; <a href=\\"../../pt/"""+cur.replace(/^(en|es|pt)\\/, '')+"""\\" style=\\"color:var(--link);text-decoration:none\\">PT</a></div></div>' +"""

if old_header in content:
    content = content.replace(old_header, new_header)
    print('Language switch added to sidebar')
else:
    print('Pattern not found - checking...')
    if "sidebar-header" in content:
        print("sidebar-header found but pattern mismatch")

with open('/tmp/fwh_docs_tmp/js/nav.js', 'w', encoding='utf-8') as f:
    f.write(content)

# Also update the source in c:\fwteam
with open('c:/fwteam/docs/js/nav.js', 'r', encoding='utf-8') as f:
    content2 = f.read()
if old_header in content2:
    content2 = content2.replace(old_header, new_header)
    with open('c:/fwteam/docs/js/nav.js', 'w', encoding='utf-8') as f:
        f.write(content2)
    print('Source nav.js also updated')
