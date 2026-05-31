// ───────────────────────────────────────────────────────────────────────
// KMS frontend — talks to the Go API (proxied at /api) for full CRUD.
// ───────────────────────────────────────────────────────────────────────

// State
let tree = [];                 // [{ id, name, slug, documents: [...] }]
let flatDocs = [];             // flattened document metas for prev/next
let currentDoc = null;         // full document currently open in reader
let editingId = null;          // doc id being edited (null = creating new)
let currentFontSize = 1.2;
let isWideMode = false;

const contentCache = new Map(); // id -> rendered HTML

// DOM
const el = {
  logoBtn: document.getElementById('logo-btn'),
  fileTree: document.getElementById('file-tree'),
  markdown: document.getElementById('markdown-container'),
  welcome: document.getElementById('welcome-screen'),
  editor: document.getElementById('editor'),
  editorTitle: document.getElementById('editor-title'),
  editorCategory: document.getElementById('editor-category'),
  editorContent: document.getElementById('editor-content'),
  editorPreview: document.getElementById('editor-preview'),
  editorSave: document.getElementById('editor-save'),
  editorCancel: document.getElementById('editor-cancel'),
  searchInput: document.getElementById('search-input'),
  searchClear: document.getElementById('search-clear'),
  breadcrumbs: document.getElementById('breadcrumbs'),
  themeToggle: document.getElementById('theme-toggle'),
  editBtn: document.getElementById('edit-btn'),
  deleteBtn: document.getElementById('delete-btn'),
  newCategoryBtn: document.getElementById('new-category-btn'),
  newDocumentBtn: document.getElementById('new-document-btn'),
  sidebar: document.querySelector('.sidebar'),
  sidebarToggle: document.getElementById('sidebar-toggle'),
  menuToggle: document.getElementById('menu-toggle'),
  progressBar: document.getElementById('progress-bar'),
  contentBody: document.querySelector('.content-body'),
  floatingToolbar: document.getElementById('floating-toolbar'),
  fontDecrease: document.getElementById('font-decrease'),
  fontIncrease: document.getElementById('font-increase'),
  widthToggle: document.getElementById('width-toggle'),
  backToTop: document.getElementById('back-to-top'),
  // modal
  modalOverlay: document.getElementById('modal-overlay'),
  modalTitle: document.getElementById('modal-title'),
  modalDesc: document.getElementById('modal-desc'),
  modalInput: document.getElementById('modal-input'),
  modalConfirm: document.getElementById('modal-confirm'),
  modalCancel: document.getElementById('modal-cancel'),
  toastContainer: document.getElementById('toast-container'),
  // auth
  authBtn: document.getElementById('auth-btn'),
  authLabel: document.getElementById('auth-label'),
  loginOverlay: document.getElementById('login-overlay'),
  loginUsername: document.getElementById('login-username'),
  loginPassword: document.getElementById('login-password'),
  loginSubmit: document.getElementById('login-submit'),
  loginCancel: document.getElementById('login-cancel'),
};

// Auth state (token persisted in localStorage)
let authToken = localStorage.getItem('kms_token') || null;
let authUser = localStorage.getItem('kms_user') || null;
const isAuthed = () => !!authToken;

marked.setOptions({ gfm: true, breaks: true });

document.addEventListener('DOMContentLoaded', () => {
  loadTree();
  setupEventListeners();
  setupHashRouting();
  initAuth();
});

// ─── API client ──────────────────────────────────────────────────────────
async function api(method, path, body) {
  const opts = { method, headers: {} };
  if (authToken) opts.headers['Authorization'] = `Bearer ${authToken}`;
  if (body !== undefined) {
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(body);
  }
  const res = await fetch(`/api${path}`, opts);
  if (res.status === 401) {
    // Token missing/expired: drop it and prompt the user to sign in again.
    clearAuth();
    throw new Error('Please sign in to do that');
  }
  if (res.status === 204) return null;
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(data.error || `Request failed (${res.status})`);
  }
  return data;
}

// ─── Tree loading & rendering ──────────────────────────────────────────────
async function loadTree() {
  try {
    tree = await api('GET', '/tree');
    flatDocs = [];
    tree.forEach((cat) => (cat.documents || []).forEach((d) => flatDocs.push(d)));
    renderTree(tree);
  } catch (err) {
    el.fileTree.innerHTML = `<div class="error-text"><i class="fa-solid fa-circle-exclamation"></i> ${escapeHtml(err.message)}</div>`;
  }
}

function renderTree(data) {
  el.fileTree.innerHTML = '';
  if (!data.length) {
    el.fileTree.innerHTML = `<div class="loading-spinner" style="opacity:.7">No content yet — create a category to begin.</div>`;
    return;
  }
  const ul = document.createElement('ul');
  ul.style.listStyle = 'none';
  data.forEach((cat) => ul.appendChild(createCategoryNode(cat)));
  el.fileTree.appendChild(ul);
}

function createCategoryNode(cat) {
  const li = document.createElement('li');
  li.className = 'tree-node';

  const label = document.createElement('div');
  label.className = 'tree-label tree-category';
  label.style.paddingLeft = '14px';

  const caret = document.createElement('i');
  caret.className = 'fa-solid fa-caret-right caret-icon rotated';
  const icon = document.createElement('i');
  icon.className = 'fa-solid fa-layer-group folder-icon';
  const name = document.createElement('span');
  name.textContent = cat.name;

  // add-document shortcut
  const add = document.createElement('i');
  add.className = 'fa-solid fa-plus cat-add';
  add.title = `Add document to "${cat.name}"`;
  add.addEventListener('click', (e) => {
    e.stopPropagation();
    enterEditMode(null, cat.id);
  });

  label.append(caret, icon, name, add);
  li.appendChild(label);

  const childUl = document.createElement('ul');
  childUl.className = 'tree-children';
  childUl.style.listStyle = 'none';
  (cat.documents || []).forEach((doc) => childUl.appendChild(createDocNode(doc)));
  li.appendChild(childUl);

  label.addEventListener('click', () => {
    childUl.classList.toggle('collapsed');
    caret.classList.toggle('rotated');
  });

  // double-click category name to rename, right area handled via delete in modal flow
  label.addEventListener('contextmenu', (e) => {
    e.preventDefault();
    categoryContextActions(cat);
  });

  return li;
}

function createDocNode(doc) {
  const li = document.createElement('li');
  li.className = 'tree-node';

  const label = document.createElement('div');
  label.className = 'tree-label';
  label.dataset.docId = doc.id;
  label.style.paddingLeft = '40px';
  if (currentDoc && currentDoc.id === doc.id) label.classList.add('active');

  const icon = document.createElement('i');
  icon.className = 'fa-regular fa-file-lines file-icon';
  const name = document.createElement('span');
  name.textContent = doc.title;

  label.append(icon, name);
  li.appendChild(label);

  label.addEventListener('click', () => {
    openDocument(doc.id);
    if (window.innerWidth <= 768) el.sidebar.classList.remove('open');
  });
  return li;
}

// ─── Reader ────────────────────────────────────────────────────────────────
async function openDocument(id, skipHash = false) {
  showView('reader');
  try {
    let doc;
    if (contentCache.has(id)) {
      doc = contentCache.get(id);
    } else {
      el.markdown.innerHTML = `<div class="loading-spinner"><i class="fa-solid fa-circle-notch fa-spin"></i> Loading...</div>`;
      doc = await api('GET', `/documents/${id}`);
      contentCache.set(id, doc);
    }
    currentDoc = doc;
    if (!skipHash) history.replaceState(null, '', `#doc/${id}`);

    renderDocument(doc);
    updateActiveState();
    el.editBtn.classList.toggle('hidden', !isAuthed());
    el.deleteBtn.classList.toggle('hidden', !isAuthed());
    el.contentBody.scrollTop = 0;
    el.progressBar.style.width = '0%';
  } catch (err) {
    el.markdown.innerHTML = `<div class="error-text"><i class="fa-solid fa-triangle-exclamation"></i> ${escapeHtml(err.message)}</div>`;
    toast(err.message, 'error');
  }
}

function renderDocument(doc) {
  const cat = tree.find((c) => c.id === doc.category_id);
  const updated = new Date(doc.updated_at).toLocaleString();
  const meta = `<div class="doc-meta"><i class="fa-solid fa-folder"></i> ${escapeHtml(cat ? cat.name : '—')}
    <span>·</span> <i class="fa-solid fa-clock"></i> Updated ${escapeHtml(updated)}</div>`;

  el.markdown.innerHTML = meta + marked.parse(doc.content || '');
  el.breadcrumbs.innerHTML = `<span>${escapeHtml(cat ? cat.name : 'Document')}</span>
    <span class="separator"><i class="fa-solid fa-chevron-right"></i></span><span>${escapeHtml(doc.title)}</span>`;

  el.markdown.querySelectorAll('h1,h2,h3,h4,h5,h6').forEach((h) => {
    if (!h.id) h.id = slugify(h.textContent);
  });
  processCodeBlocks();
  Prism.highlightAllUnder(el.markdown);
}

// ─── Editor (create / update) ───────────────────────────────────────────────
function enterEditMode(doc, presetCategoryId) {
  if (!tree.length) {
    toast('Create a category first', 'error');
    return;
  }
  editingId = doc ? doc.id : null;

  // populate category dropdown
  el.editorCategory.innerHTML = '';
  tree.forEach((c) => {
    const opt = document.createElement('option');
    opt.value = c.id;
    opt.textContent = c.name;
    el.editorCategory.appendChild(opt);
  });

  el.editorTitle.value = doc ? doc.title : '';
  el.editorContent.value = doc ? doc.content : '';
  el.editorCategory.value = doc ? doc.category_id : (presetCategoryId || tree[0].id);

  el.breadcrumbs.innerHTML = `<span>${doc ? 'Edit' : 'New'} document</span>`;
  showView('editor');
  updateEditorPreview();
  el.editorTitle.focus();
}

function updateEditorPreview() {
  el.editorPreview.innerHTML = marked.parse(el.editorContent.value || '');
  Prism.highlightAllUnder(el.editorPreview);
}

async function saveDocument() {
  const payload = {
    category_id: Number(el.editorCategory.value),
    title: el.editorTitle.value.trim(),
    content: el.editorContent.value,
  };
  if (!payload.title) {
    toast('Title is required', 'error');
    el.editorTitle.focus();
    return;
  }
  try {
    el.editorSave.disabled = true;
    let saved;
    if (editingId) {
      saved = await api('PUT', `/documents/${editingId}`, payload);
      contentCache.set(saved.id, saved);
    } else {
      saved = await api('POST', '/documents', payload);
    }
    await loadTree();
    await openDocument(saved.id);
    toast(editingId ? 'Document updated' : 'Document created', 'success');
  } catch (err) {
    toast(err.message, 'error');
  } finally {
    el.editorSave.disabled = false;
  }
}

async function deleteDocument() {
  if (!currentDoc) return;
  const ok = await confirmModal('Delete document', `Permanently delete "${currentDoc.title}"? This cannot be undone.`);
  if (!ok) return;
  try {
    await api('DELETE', `/documents/${currentDoc.id}`);
    contentCache.delete(currentDoc.id);
    currentDoc = null;
    await loadTree();
    showWelcome();
    toast('Document deleted', 'success');
  } catch (err) {
    toast(err.message, 'error');
  }
}

// ─── Categories ──────────────────────────────────────────────────────────
async function createCategory() {
  const name = await promptModal('New category', 'Name for the new category', '');
  if (!name) return;
  try {
    await api('POST', '/categories', { name });
    await loadTree();
    toast('Category created', 'success');
  } catch (err) {
    toast(err.message, 'error');
  }
}

async function categoryContextActions(cat) {
  const choice = await promptModal('Rename category', `Rename "${cat.name}" (leave blank & confirm to DELETE it and all its documents)`, cat.name);
  if (choice === null) return; // cancelled
  try {
    if (choice.trim() === '') {
      const ok = await confirmModal('Delete category', `Delete "${cat.name}" and ALL its documents?`);
      if (!ok) return;
      await api('DELETE', `/categories/${cat.id}`);
      toast('Category deleted', 'success');
    } else {
      await api('PUT', `/categories/${cat.id}`, { name: choice.trim() });
      toast('Category renamed', 'success');
    }
    await loadTree();
    showWelcome();
  } catch (err) {
    toast(err.message, 'error');
  }
}

// ─── View switching ────────────────────────────────────────────────────────
function showView(view) {
  el.welcome.classList.toggle('hidden', view !== 'welcome');
  el.markdown.classList.toggle('hidden', view !== 'reader');
  el.editor.classList.toggle('hidden', view !== 'editor');
  el.floatingToolbar.style.display = view === 'reader' ? '' : 'none';
  // Edit/Delete only make sense in the reader AND when signed in.
  const showDocActions = view === 'reader' && isAuthed();
  el.editBtn.classList.toggle('hidden', !showDocActions);
  el.deleteBtn.classList.toggle('hidden', !showDocActions);
}

function showWelcome() {
  showView('welcome');
  currentDoc = null;
  updateActiveState();
  el.breadcrumbs.innerHTML = '<span>Dashboard</span>';
  history.replaceState(null, '', window.location.pathname);
}

function updateActiveState() {
  document.querySelectorAll('.tree-label').forEach((l) => l.classList.remove('active'));
  if (!currentDoc) return;
  const active = document.querySelector(`.tree-label[data-doc-id="${currentDoc.id}"]`);
  if (active) {
    active.classList.add('active');
    const childUl = active.closest('.tree-children');
    if (childUl) {
      childUl.classList.remove('collapsed');
      const caret = childUl.previousElementSibling?.querySelector('.caret-icon');
      if (caret) caret.classList.add('rotated');
    }
  }
}

// ─── Code blocks (copy buttons + collapse) ──────────────────────────────────
const COLLAPSE_THRESHOLD = 20;
function processCodeBlocks() {
  el.markdown.querySelectorAll('pre').forEach((pre) => {
    const code = pre.querySelector('code');
    if (!code) return;
    let lang = 'text';
    code.classList.forEach((c) => { if (c.startsWith('language-')) lang = c.replace('language-', ''); });

    const lineCount = code.textContent.split('\n').length;
    const isLong = lineCount > COLLAPSE_THRESHOLD;

    const container = document.createElement('div');
    container.className = 'code-container' + (isLong ? ' collapsible collapsed' : '');
    const header = document.createElement('div');
    header.className = 'code-header';
    header.innerHTML = `<span><i class="fa-solid fa-code"></i> ${lang.toUpperCase()}</span>
      <button class="copy-btn"><i class="fa-regular fa-copy"></i> Copy</button>`;

    const parent = pre.parentNode;
    const next = pre.nextSibling;
    const body = document.createElement('div');
    body.className = 'code-body';
    if (next) parent.insertBefore(container, next); else parent.appendChild(container);
    container.appendChild(header);
    body.appendChild(pre);
    container.appendChild(body);

    if (isLong) {
      const toggle = document.createElement('button');
      toggle.className = 'code-toggle-btn';
      toggle.innerHTML = `<i class="fa-solid fa-chevron-down"></i> <span>Show ${lineCount} lines</span>`;
      container.appendChild(toggle);
      toggle.addEventListener('click', () => {
        const collapsed = container.classList.toggle('collapsed');
        toggle.querySelector('span').textContent = collapsed ? `Show ${lineCount} lines` : 'Collapse';
      });
    }

    header.querySelector('.copy-btn').addEventListener('click', (e) => {
      navigator.clipboard.writeText(code.textContent).then(() => {
        const btn = e.currentTarget;
        btn.innerHTML = `<i class="fa-solid fa-check"></i> Copied!`;
        setTimeout(() => { btn.innerHTML = `<i class="fa-regular fa-copy"></i> Copy`; }, 2000);
      });
    });
  });
}

// ─── Search ────────────────────────────────────────────────────────────────
let searchTimer;
function handleSearch(e) {
  const q = e.target.value.trim();
  el.searchClear.classList.toggle('hidden', q.length === 0);
  clearTimeout(searchTimer);
  searchTimer = setTimeout(async () => {
    if (!q) { renderTree(tree); return; }
    try {
      const results = await api('GET', `/documents?q=${encodeURIComponent(q)}`);
      renderSearchResults(results, q);
    } catch (err) {
      toast(err.message, 'error');
    }
  }, 250);
}

function renderSearchResults(results, q) {
  el.fileTree.innerHTML = '';
  if (!results.length) {
    el.fileTree.innerHTML = `<div class="loading-spinner" style="opacity:.7">No matches for "${escapeHtml(q)}"</div>`;
    return;
  }
  const ul = document.createElement('ul');
  ul.style.listStyle = 'none';
  results.forEach((doc) => {
    const li = createDocNode(doc);
    li.querySelector('.tree-label').style.paddingLeft = '14px';
    ul.appendChild(li);
  });
  el.fileTree.appendChild(ul);
}

// ─── Modal helpers (promise-based) ───────────────────────────────────────────
let modalResolver = null;
let modalMode = 'prompt';
function promptModal(title, desc, value = '') {
  modalMode = 'prompt';
  el.modalTitle.textContent = title;
  el.modalDesc.textContent = desc;
  el.modalInput.style.display = '';
  el.modalInput.value = value;
  el.modalOverlay.classList.remove('hidden');
  setTimeout(() => el.modalInput.focus(), 50);
  return new Promise((resolve) => (modalResolver = resolve));
}
function confirmModal(title, desc) {
  modalMode = 'confirm';
  el.modalTitle.textContent = title;
  el.modalDesc.textContent = desc;
  el.modalInput.style.display = 'none';
  el.modalOverlay.classList.remove('hidden');
  return new Promise((resolve) => (modalResolver = resolve));
}
function closeModal(result) {
  el.modalOverlay.classList.add('hidden');
  el.modalInput.style.display = '';
  if (modalResolver) { modalResolver(result); modalResolver = null; }
}

// ─── Toasts ──────────────────────────────────────────────────────────────
function toast(message, type = '') {
  const t = document.createElement('div');
  t.className = `toast ${type}`;
  const icon = type === 'success' ? 'fa-circle-check' : type === 'error' ? 'fa-circle-exclamation' : 'fa-circle-info';
  t.innerHTML = `<i class="fa-solid ${icon}"></i> ${escapeHtml(message)}`;
  el.toastContainer.appendChild(t);
  setTimeout(() => { t.style.opacity = '0'; setTimeout(() => t.remove(), 250); }, 2800);
}

// ─── Auth ──────────────────────────────────────────────────────────────────
async function initAuth() {
  updateAuthUI();
  // Confirm a stored token is still valid; quietly drop it if not.
  if (authToken) {
    try {
      await api('GET', '/auth/me');
    } catch {
      clearAuth();
    }
  }
}

function updateAuthUI() {
  document.body.classList.toggle('authed', isAuthed());
  if (isAuthed()) {
    el.authLabel.textContent = authUser || 'Logout';
    el.authBtn.title = 'Sign out';
    el.authBtn.classList.add('authed-user');
    el.authBtn.querySelector('i').className = 'fa-solid fa-right-from-bracket';
  } else {
    el.authLabel.textContent = 'Login';
    el.authBtn.title = 'Sign in';
    el.authBtn.classList.remove('authed-user');
    el.authBtn.querySelector('i').className = 'fa-solid fa-right-to-bracket';
  }
  // Re-evaluate edit/delete visibility for the current view.
  if (currentDoc && !el.markdown.classList.contains('hidden')) {
    const show = isAuthed();
    el.editBtn.classList.toggle('hidden', !show);
    el.deleteBtn.classList.toggle('hidden', !show);
  }
}

function openLogin() {
  el.loginUsername.value = '';
  el.loginPassword.value = '';
  el.loginOverlay.classList.remove('hidden');
  setTimeout(() => el.loginUsername.focus(), 50);
}

function closeLogin() {
  el.loginOverlay.classList.add('hidden');
}

async function doLogin() {
  const username = el.loginUsername.value.trim();
  const password = el.loginPassword.value;
  if (!username || !password) {
    toast('Enter username and password', 'error');
    return;
  }
  try {
    el.loginSubmit.disabled = true;
    const res = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.error || 'Login failed');
    authToken = data.token;
    authUser = data.username;
    localStorage.setItem('kms_token', authToken);
    localStorage.setItem('kms_user', authUser);
    closeLogin();
    updateAuthUI();
    toast(`Signed in as ${authUser}`, 'success');
  } catch (err) {
    toast(err.message, 'error');
  } finally {
    el.loginSubmit.disabled = false;
  }
}

function clearAuth() {
  authToken = null;
  authUser = null;
  localStorage.removeItem('kms_token');
  localStorage.removeItem('kms_user');
  updateAuthUI();
  // If the editor is open, bail back to a safe view.
  if (!el.editor.classList.contains('hidden')) {
    if (currentDoc) openDocument(currentDoc.id); else showWelcome();
  }
}

function logout() {
  clearAuth();
  toast('Signed out', 'success');
}

// ─── Utils ─────────────────────────────────────────────────────────────────
function slugify(s) {
  return s.trim().toLowerCase().replace(/[^\w\s-]/g, '').replace(/[\s_-]+/g, '-').replace(/^-+|-+$/g, '');
}
function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
function applyWidthMode(force) {
  document.documentElement.style.setProperty('--reading-max-width', force || isWideMode ? '1200px' : '740px');
}

// ─── Hash routing ────────────────────────────────────────────────────────
function setupHashRouting() {
  const load = () => {
    const hash = window.location.hash.slice(1);
    if (hash.startsWith('doc/')) {
      const id = Number(hash.slice(4));
      if (id) openDocument(id, true);
    }
  };
  window.addEventListener('hashchange', load);
  setTimeout(load, 200);
}

// ─── Event wiring ──────────────────────────────────────────────────────────
function setupEventListeners() {
  el.logoBtn.addEventListener('click', () => {
    showWelcome();
    if (window.innerWidth <= 768) el.sidebar.classList.remove('open');
  });

  el.themeToggle.addEventListener('click', () => {
    document.body.classList.toggle('dark-mode');
    el.themeToggle.querySelector('i').className =
      document.body.classList.contains('dark-mode') ? 'fa-solid fa-sun' : 'fa-solid fa-moon';
  });

  // Auth controls
  el.authBtn.addEventListener('click', () => { if (isAuthed()) logout(); else openLogin(); });
  el.loginSubmit.addEventListener('click', doLogin);
  el.loginCancel.addEventListener('click', closeLogin);
  el.loginPassword.addEventListener('keydown', (e) => { if (e.key === 'Enter') doLogin(); });
  el.loginUsername.addEventListener('keydown', (e) => { if (e.key === 'Enter') el.loginPassword.focus(); });
  el.loginOverlay.addEventListener('click', (e) => { if (e.target === el.loginOverlay) closeLogin(); });

  el.editBtn.addEventListener('click', () => { if (currentDoc) enterEditMode(currentDoc); });
  el.deleteBtn.addEventListener('click', deleteDocument);
  el.newCategoryBtn.addEventListener('click', createCategory);
  el.newDocumentBtn.addEventListener('click', () => enterEditMode(null));

  el.editorSave.addEventListener('click', saveDocument);
  el.editorCancel.addEventListener('click', () => {
    if (currentDoc) openDocument(currentDoc.id); else showWelcome();
  });
  el.editorContent.addEventListener('input', () => {
    clearTimeout(el._previewTimer);
    el._previewTimer = setTimeout(updateEditorPreview, 150);
  });
  // Tab inserts two spaces in the editor.
  el.editorContent.addEventListener('keydown', (e) => {
    if (e.key === 'Tab') {
      e.preventDefault();
      const s = el.editorContent.selectionStart, en = el.editorContent.selectionEnd;
      el.editorContent.value = el.editorContent.value.slice(0, s) + '  ' + el.editorContent.value.slice(en);
      el.editorContent.selectionStart = el.editorContent.selectionEnd = s + 2;
    }
    // Ctrl/Cmd+S to save
    if ((e.ctrlKey || e.metaKey) && e.key === 's') { e.preventDefault(); saveDocument(); }
  });

  el.searchInput.addEventListener('input', handleSearch);
  el.searchClear.addEventListener('click', () => {
    el.searchInput.value = '';
    el.searchClear.classList.add('hidden');
    renderTree(tree);
  });

  // Modal buttons
  el.modalConfirm.addEventListener('click', () => closeModal(modalMode === 'prompt' ? el.modalInput.value : true));
  el.modalCancel.addEventListener('click', () => closeModal(modalMode === 'prompt' ? null : false));
  el.modalInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') closeModal(el.modalInput.value);
    if (e.key === 'Escape') closeModal(null);
  });
  el.modalOverlay.addEventListener('click', (e) => {
    if (e.target === el.modalOverlay) closeModal(modalMode === 'prompt' ? null : false);
  });

  // Sidebar toggle (desktop collapse / mobile slide)
  const toggleSidebar = () => {
    if (window.innerWidth <= 768) {
      el.sidebar.classList.toggle('open');
    } else {
      el.sidebar.classList.toggle('collapsed');
      el.sidebarToggle.querySelector('i').className =
        el.sidebar.classList.contains('collapsed') ? 'fa-solid fa-angles-right' : 'fa-solid fa-angles-left';
    }
  };
  el.sidebarToggle.addEventListener('click', toggleSidebar);
  el.menuToggle.addEventListener('click', toggleSidebar);
  document.addEventListener('click', (e) => {
    if (window.innerWidth <= 768 && !el.sidebar.contains(e.target) && !el.menuToggle.contains(e.target)) {
      el.sidebar.classList.remove('open');
    }
  });

  // Reading progress + back to top
  el.contentBody.addEventListener('scroll', () => {
    const top = el.contentBody.scrollTop;
    const h = el.contentBody.scrollHeight - el.contentBody.clientHeight;
    el.progressBar.style.width = `${h > 0 ? (top / h) * 100 : 0}%`;
    el.backToTop.classList.toggle('visible', top > 300);
  });
  el.backToTop.addEventListener('click', () => el.contentBody.scrollTo({ top: 0, behavior: 'smooth' }));

  // Floating toolbar
  el.fontDecrease.addEventListener('click', () => {
    currentFontSize = Math.max(0.8, currentFontSize - 0.1);
    document.documentElement.style.setProperty('--dynamic-font-size', `${currentFontSize}rem`);
  });
  el.fontIncrease.addEventListener('click', () => {
    currentFontSize = Math.min(2.5, currentFontSize + 0.1);
    document.documentElement.style.setProperty('--dynamic-font-size', `${currentFontSize}rem`);
  });
  el.widthToggle.addEventListener('click', () => { isWideMode = !isWideMode; applyWidthMode(); });

  // Sidebar resizing
  const resizer = document.getElementById('sidebar-resizer');
  let resizing = false;
  resizer.addEventListener('mousedown', (e) => {
    e.preventDefault(); resizing = true;
    document.body.classList.add('is-resizing'); resizer.classList.add('active');
    el.sidebar.style.transition = 'none';
  });
  document.addEventListener('mousemove', (e) => {
    if (!resizing || window.innerWidth <= 768) return;
    let w = Math.min(600, Math.max(200, e.clientX));
    el.sidebar.style.width = `${w}px`;
    el.sidebar.style.minWidth = `${w}px`;
    document.documentElement.style.setProperty('--sidebar-width', `${w}px`);
  });
  document.addEventListener('mouseup', () => {
    if (!resizing) return;
    resizing = false;
    document.body.classList.remove('is-resizing'); resizer.classList.remove('active');
    el.sidebar.style.transition = '';
    const w = parseInt(el.sidebar.style.width);
    if (w) localStorage.setItem('sidebar-width', `${w}px`);
  });
  const savedWidth = localStorage.getItem('sidebar-width');
  if (savedWidth && window.innerWidth > 768) {
    el.sidebar.style.width = savedWidth;
    el.sidebar.style.minWidth = savedWidth;
    document.documentElement.style.setProperty('--sidebar-width', savedWidth);
  }
}
