// Agents Documentation - Shared JavaScript

// Search index
var searchIndex = [
  { k: "web agents browser online html5 javascript tool calling web agent", t: "Web Agents", u: "../../en/agents/web-agents.html", s: "Agents" },
  { k: "agents exe executable windows desktop harbour fivewin standalone", t: "Agents EXE", u: "../../en/agents/agents-exe.html", s: "Agents" },
  { k: "agents apk android mobile phone tablet harbour apk", t: "Agents APK", u: "../../en/agents/agents-apk.html", s: "Agents" },
  { k: "class agent tools skills planning multi agent dispatch oop harbour", t: "Class Agent", u: "../../en/agents/agents-exe.html#class-agent", s: "Agents" },
  { k: "sse streaming http curl deepseek openai api chat completion tool call", t: "API & Streaming", u: "../../en/agents/agents-exe.html#api", s: "Agents" },
  { k: "build compile hbmk2 msvc harbour exe windows", t: "Building Agents EXE", u: "../../en/agents/agents-exe.html#building", s: "Agents" },
  { k: "read write edit glob grep shell web_search web_fetch tools", t: "Built-in Tools", u: "../../en/agents/agents-exe.html#tools", s: "Agents" },
];

// Navigation table — single source of truth for sidebar
var NAV = [
  { t: { en: "Agents Documentation", es: "Documentacion Agents", pt: "Documentacao Agents" }, items: [
    { u: "agents/web-agents.html",  l: { en: "Web Agents", es: "Agentes Web", pt: "Agentes Web" } },
    { u: "agents/agents-exe.html",   l: { en: "Agents EXE", es: "Agents EXE", pt: "Agents EXE" } },
    { u: "agents/agents-apk.html",   l: { en: "Agents APK", es: "Agents APK", pt: "Agents APK" } },
  ]},
  { t: { en: "Class Reference", es: "Referencia de Clase", pt: "Referencia da Classe" }, items: [
    { u: "agents/agents-exe.html#class-agent",    l: { en: "Class Agent", es: "Clase Agent", pt: "Classe Agent" } },
    { u: "agents/agents-exe.html#initialization", l: { en: "Initialization", es: "Inicializacion", pt: "Inicializacao" } },
    { u: "agents/agents-exe.html#main-loop",      l: { en: "Main Loop", es: "Bucle Principal", pt: "Loop Principal" } },
    { u: "agents/agents-exe.html#tools",          l: { en: "Built-in Tools", es: "Herramientas", pt: "Ferramentas" } },
    { u: "agents/agents-exe.html#skills",         l: { en: "Skills", es: "Habilidades", pt: "Habilidades" } },
    { u: "agents/agents-exe.html#multi-agent",    l: { en: "Multi-Agent", es: "Multi-Agente", pt: "Multi-Agente" } },
  ]},
  { t: { en: "Resources", es: "Recursos", pt: "Recursos" }, items: [
    { u: "https://github.com/FiveTechSoft/Agents", l: { en: "GitHub Repository &#8599;", es: "Repositorio GitHub &#8599;", pt: "Repositorio GitHub &#8599;" } },
    { u: "https://forums.fivetechsupport.com/",    l: { en: "Tech Support &#8599;", es: "Soporte Tecnico &#8599;", pt: "Suporte Tecnico &#8599;" } },
  ]},
];

function navLabel(v, lang) { return (typeof v === 'string') ? v : (v[lang] || v.en); }

function buildNav(lang, lp, path) {
  var html = '';
  NAV.forEach(function(sec) {
    html += '<div class="nav-section"><div class="nav-section-title">' + navLabel(sec.t, lang) + '</div>';
    sec.items.forEach(function(it) {
      var ext = it.u.indexOf('http') === 0;
      var href = ext ? it.u : (lp + '/' + it.u);
      var active = (!ext && path.indexOf('/' + it.u.split('#')[0]) !== -1) ? ' active' : '';
      var tgt = ext ? ' target="_blank"' : '';
      html += '<a class="nav-item' + active + '" href="' + href + '"' + tgt + '>' + navLabel(it.l, lang) + '</a>';
    });
    html += '</div>';
  });
  return html;
}

// Build TOC from h2/h3 headings
document.addEventListener('DOMContentLoaded', function() {
  var tocLinks = document.getElementById('toc-links');
  if (!tocLinks) return;
  var headings = document.querySelectorAll('#content h2[id], #content h3[id]');
  headings.forEach(function(h) {
    var a = document.createElement('a');
    a.className = 'toc-item' + (h.tagName === 'H3' ? ' toc-h3' : '');
    a.textContent = h.textContent;
    a.href = '#' + h.id;
    tocLinks.appendChild(a);
  });

  // Render sidebar nav
  var path = window.location.pathname;
  var navLangMatch = path.match(/\/(en|es|pt)\//);
  if (navLangMatch) {
    var navLang = navLangMatch[1];
    var navSidebar = document.getElementById('sidebar');
    if (navSidebar) {
      navSidebar.querySelectorAll('.nav-section').forEach(function(s) { s.remove(); });
      var navWrap = document.createElement('div');
      navWrap.id = 'main-nav';
      navWrap.innerHTML = buildNav(navLang, '../../' + navLang, path);
      navSidebar.appendChild(navWrap);
    }
  }

  // Highlight current page
  document.querySelectorAll('.nav-item').forEach(function(item) {
    if (item.getAttribute('href') && path.indexOf(item.getAttribute('href').split('#')[0]) !== -1) {
      item.classList.add('active');
    }
  });

  // Inject language switcher
  var sidebarHeader = document.getElementById('sidebar-header');
  if (sidebarHeader && !document.getElementById('lang-switcher')) {
    var langDiv = document.createElement('div');
    langDiv.id = 'lang-switcher';
    langDiv.style.cssText = 'padding:8px 16px 4px;display:flex;gap:6px;';
    var langs = [{code:'en',label:'EN'},{code:'es',label:'ES'},{code:'pt',label:'PT'}];
    langs.forEach(function(lang) {
      var btn = document.createElement('a');
      btn.textContent = lang.label;
      btn.style.cssText = 'padding:4px 12px;border-radius:4px;font-size:13px;font-weight:600;cursor:pointer;text-decoration:none;border:1px solid #30363d;';
      if (path.indexOf('/' + lang.code + '/') !== -1) {
        btn.style.background = '#1f6feb'; btn.style.color = '#fff'; btn.style.borderColor = '#1f6feb';
      } else {
        btn.style.background = '#161b22'; btn.style.color = '#8b949e';
      }
      btn.href = path.replace(/\/(en|es|pt)\//, '/' + lang.code + '/');
      langDiv.appendChild(btn);
    });
    sidebarHeader.appendChild(langDiv);
  }

  // Search box
  var sidebarHeader2 = document.getElementById('sidebar-header');
  if (sidebarHeader2 && !document.getElementById('search-input')) {
    var searchDiv = document.createElement('div');
    searchDiv.id = 'search-box';
    searchDiv.innerHTML = '<input type="text" id="search-input" placeholder="Search docs... (Ctrl+K)"><div id="search-results"></div>';
    sidebarHeader2.parentNode.insertBefore(searchDiv, sidebarHeader2.nextSibling);
  }

  // Setup search
  var searchInput = document.getElementById('search-input');
  var searchResults = document.getElementById('search-results');
  if (searchInput && searchResults) {
    searchInput.addEventListener('input', function() {
      var q = this.value.toLowerCase().trim();
      if (q.length < 2) { searchResults.classList.remove('active'); searchResults.innerHTML = ''; return; }
      var results = searchIndex.filter(function(item) {
        return item.k.indexOf(q) !== -1 || item.t.toLowerCase().indexOf(q) !== -1;
      });
      searchResults.innerHTML = '';
      if (results.length > 0) {
        searchResults.classList.add('active');
        var curLang = (window.location.pathname.match(/\/(en|es|pt)\//) || [])[1] || 'en';
        results.slice(0, 12).forEach(function(r) {
          var a = document.createElement('a');
          a.className = 'search-result';
          a.href = curLang !== 'en' ? r.u.replace('/en/', '/' + curLang + '/') : r.u;
          a.innerHTML = '<div class="sr-title">' + r.t + '</div><div class="sr-section">' + r.s + '</div>';
          searchResults.appendChild(a);
        });
      } else {
        searchResults.classList.add('active');
        searchResults.innerHTML = '<div style="padding:8px 12px;color:#8b949e;font-size:13px;">No results found</div>';
      }
    });
    document.addEventListener('keydown', function(e) {
      if ((e.ctrlKey || e.metaKey) && e.key === 'k') { e.preventDefault(); searchInput.focus(); searchInput.select(); }
    });
  }

  // Syntax highlight
  document.querySelectorAll('pre code').forEach(function(block) {
    block.innerHTML = highlightHarbour(block.textContent);
  });
});

// Harbour/xBase syntax highlighter
function highlightHarbour(code) {
  code = code.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  var tokens = [];
  function saveToken(m, cls) {
    tokens.push('<span class="' + cls + '">' + m + '</span>');
    return '\x00' + (tokens.length - 1) + '\x00';
  }
  code = code.replace(/(\/\/.*$)/gm, function(m) { return saveToken(m, 'cm'); });
  code = code.replace(/(\/\*[\s\S]*?\*\/)/g, function(m) { return saveToken(m, 'cm'); });
  code = code.replace(/^(\s*#\w+.*$)/gm, function(m) { return saveToken(m, 'pp'); });
  code = code.replace(/("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/g, function(m) { return saveToken(m, 'st'); });
  code = code.replace(/\b(\d+\.?\d*)\b/g, function(m) { return saveToken(m, 'nb'); });
  var kws = 'function|procedure|return|local|static|private|public|if|else|elseif|endif|do|while|enddo|for|next|to|step|exit|loop|class|endclass|method|data|from|inherit|nil|self|super|and|or|not|in|begin|end|sequence|recover|with|switch|case|otherwise|endswitch|try|catch|finally';
  var kwRe = new RegExp('\\b(' + kws + ')\\b', 'gi');
  code = code.replace(kwRe, function(m) { return '<span class="kw">' + m + '</span>'; });
  code = code.replace(/(\.(T|F|t|f)\.)/g, function(m) { return saveToken(m, 'nb'); });
  code = code.replace(/\x00(\d+)\x00/g, function(m, i) { return tokens[parseInt(i)]; });
  return code;
}

// Mobile menu
(function() {
  var btn = document.createElement('button');
  btn.id = 'menu-toggle';
  btn.innerHTML = '☰';
  btn.title = 'Menu';
  btn.onclick = function() {
    var sidebar = document.getElementById('sidebar');
    sidebar.classList.toggle('open');
    document.body.classList.toggle('sidebar-open');
    btn.innerHTML = sidebar.classList.contains('open') ? '✕' : '☰';
  };
  document.body.appendChild(btn);
  var sidebar = document.getElementById('sidebar');
  if (sidebar) {
    sidebar.addEventListener('click', function(e) {
      if (e.target.classList.contains('nav-item') && window.innerWidth <= 1024) {
        sidebar.classList.remove('open');
        document.body.classList.remove('sidebar-open');
        btn.innerHTML = '☰';
      }
    });
  }
})();
