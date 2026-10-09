// Isi URL dan anon key dari Project Settings > API di Supabase.
const SUPABASE_URL = 'https://vxhuxhefncanqjqkbzul.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_MTf4CL4pbO7Iu2icpfB5mA_gt6LZ_Bu';

const { createClient } = window.supabase;
const supabaseClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
const state = {
  session: null,
  profile: null,
  view: 'dashboard',
  accounts: [],
  categories: [],
  requests: [],
  transactions: [],
  cashCounts: [],
  monthlyClosings: [],
  users: [],
  editing: null,
  search: '',
  filter: 'all',
  showVoided: false,
  reportMonth: new Date().toISOString().slice(0, 7),
  closingMonth: new Date().toISOString().slice(0, 7)
};

const $ = (selector, parent = document) => parent.querySelector(selector);
const money = (value) => new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 }).format(Number(value || 0));
const dateLabel = (value) => value ? new Intl.DateTimeFormat('id-ID', { day: '2-digit', month: 'short', year: 'numeric' }).format(new Date(`${value.slice(0, 10)}T00:00:00`)) : '-';
const escapeHtml = (value = '') => String(value).replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
const isAdmin = () => state.profile?.role === 'ADMIN';
const userName = (id) => state.users.find((user) => user.id === id)?.full_name || 'Pengguna';
const accountName = (id) => state.accounts.find((account) => account.id === id)?.name || 'Akun dihapus';
const categoryName = (id) => state.categories.find((category) => category.id === id)?.name || 'Tanpa kategori';
const roleLabel = () => isAdmin() ? 'ADMIN' : 'MANAGER';

const navItems = [
  { id: 'dashboard', label: 'Ringkasan', icon: '⌂', roles: ['ADMIN', 'MANAGER'] },
  { id: 'requests', label: 'Pengajuan', icon: '▤', roles: ['ADMIN', 'MANAGER'] },
  { id: 'transactions', label: 'Transaksi', icon: '↕', roles: ['ADMIN', 'MANAGER'] },
  { id: 'accounts', label: 'Akun kas', icon: '▣', roles: ['ADMIN', 'MANAGER'] },
  { id: 'reports', label: 'Laporan', icon: '▥', roles: ['ADMIN', 'MANAGER'] },
  { id: 'cash-counts', label: 'Kas opname', icon: '▧', roles: ['ADMIN', 'MANAGER'] },
  { id: 'closing', label: 'Tutup buku', icon: '■', roles: ['ADMIN', 'MANAGER'] }
];

function showLoading(show, compact = false) {
  const loading = $('#loading');
  loading.classList.toggle('compact', compact);
  loading.hidden = !show;
}

function notify(message, type = 'success') {
  const toast = $('#toast');
  const toastIcon = $('.toast-icon', toast);
  const toastMessage = $('.toast-message', toast);
  toastMessage.textContent = message;
  toast.classList.toggle('error', type === 'error');
  toast.classList.toggle('warning', type === 'warning');
  toastIcon.textContent = type === 'warning' ? '!' : type === 'error' ? '!' : '✓';
  toast.classList.add('show');
  window.clearTimeout(notify.timer);
  notify.timer = window.setTimeout(() => toast.classList.remove('show'), 5600);
}

function showFieldError(fieldName, message) {
  const field = $(`#field-${fieldName}`);
  const error = $(`#field-${fieldName}-error`);
  if (!field || !error) return;
  field.classList.add('field-invalid');
  error.textContent = message;
  field.scrollIntoView({ behavior: 'smooth', block: 'center' });
  field.focus({ preventScroll: true });
}

function clearFieldError(fieldName) {
  const field = $(`#field-${fieldName}`);
  const error = $(`#field-${fieldName}-error`);
  if (!field || !error) return;
  field.classList.remove('field-invalid');
  error.textContent = '';
}

function errorMessage(error) {
  const message = error?.message || 'Terjadi kesalahan. Silakan coba kembali.';
  if (/saldo akun tidak mencukupi/i.test(message)) return message;
  if (/row-level security|permission denied/i.test(message)) return 'Akses ditolak. Periksa role pengguna dan kebijakan RLS.';
  if (/fetch|network/i.test(message)) return 'Tidak dapat terhubung ke Supabase. Periksa koneksi dan konfigurasi.';
  return message;
}

function balanceErrorMessage(message) {
  const match = message.match(/Saldo akun tidak mencukupi\. Saldo saat ini Rp\s*([\d,]+(?:\.\d+)?)/i);
  if (!match) return message;
  const amount = Number(match[1].replace(/,/g, ''));
  const formattedBalance = money(amount).replace(/\u00a0/g, ' ');
  return `Saldo akun tidak mencukupi. Saldo saat ini ${formattedBalance}.`;
}

function renderNavigation() {
  $('#main-nav').innerHTML = navItems
    .filter((item) => item.roles.includes(state.profile.role))
    .map((item) => `<button class="nav-link ${state.view === item.id ? 'active' : ''}" type="button" data-view="${item.id}"><span class="nav-icon" aria-hidden="true">${item.icon}</span><span>${item.label}</span></button>`)
    .join('');
}

function showLogin(message = '') {
  $('#workspace').hidden = true;
  $('#login-screen').hidden = false;
  $('#login-error').textContent = message;
  showLoading(false);
}

async function loadProfile(session) {
  const { data, error } = await supabaseClient.from('users').select('id, full_name, role').eq('id', session.user.id).maybeSingle();
  if (error) throw error;
  if (!data || !['ADMIN', 'MANAGER'].includes(data.role)) {
    await supabaseClient.auth.signOut();
    throw new Error('Profil belum terdaftar. Hubungi administrator untuk mengaktifkan akun Anda.');
  }
  state.session = session;
  state.profile = data;
  state.view = 'dashboard';
  $('#login-screen').hidden = true;
  $('#workspace').hidden = false;
  $('#user-name').textContent = data.full_name;
  $('#user-role').textContent = data.role === 'ADMIN' ? 'Administrator' : 'Manager';
  $('#user-initials').textContent = data.full_name.trim().split(/\s+/).slice(0, 2).map((part) => part[0]).join('').toUpperCase();
  $('#today-label').textContent = new Intl.DateTimeFormat('id-ID', { weekday: 'short', day: 'numeric', month: 'short' }).format(new Date());
  renderNavigation();
  await refreshData();
}

async function refreshData() {
  showLoading(true, true);
  const [accounts, categories, requests, transactions, users, cashCounts, monthlyClosings] = await Promise.all([
    supabaseClient.from('petty_cash_accounts').select('*').order('name'),
    supabaseClient.from('expense_categories').select('*').order('name'),
    supabaseClient.from('petty_cash_requests').select('*').order('created_at', { ascending: false }),
    supabaseClient.from('petty_cash_transactions').select('*').order('transaction_date', { ascending: false }),
    supabaseClient.from('users').select('id, full_name, role'),
    supabaseClient.from('cash_counts').select('*').order('counted_at', { ascending: false }),
    supabaseClient.from('monthly_closings').select('*').order('closing_month', { ascending: false })
  ]);
  const failed = [accounts, requests, transactions, users].find((result) => result.error);
  showLoading(false);
  if (failed) {
    notify(errorMessage(failed.error), 'error');
    return;
  }
  state.accounts = accounts.data || [];
  state.categories = categories.error ? [] : categories.data || [];
  state.requests = requests.data || [];
  state.transactions = transactions.data || [];
  state.users = users.data || [];
  state.cashCounts = cashCounts.error ? [] : cashCounts.data || [];
  state.monthlyClosings = monthlyClosings.error ? [] : monthlyClosings.data || [];
  renderView();
}

function setView(view) {
  state.view = view;
  state.search = '';
  state.filter = 'all';
  state.showVoided = false;
  if (view === 'reports' || view === 'closing') state.reportMonth = new Date().toISOString().slice(0, 7);
  renderNavigation();
  renderView();
}

function renderView() {
  const labels = { dashboard: 'Ringkasan', requests: 'Pengajuan petty cash', transactions: 'Riwayat transaksi', accounts: 'Akun kas kecil', reports: 'Laporan', 'cash-counts': 'Kas opname', closing: 'Tutup buku' };
  $('#page-title').textContent = labels[state.view] || 'Ringkasan';
  $('#page-kicker').textContent = isAdmin() ? 'ADMINISTRASI KAS KECIL' : 'PEMANTAUAN & PERSETUJUAN';
  const content = $('#content');
  if (state.view === 'dashboard') content.innerHTML = dashboardMarkup();
  if (state.view === 'requests') content.innerHTML = requestsMarkup();
  if (state.view === 'transactions') content.innerHTML = transactionsMarkup();
  if (state.view === 'accounts') content.innerHTML = accountsMarkup();
  if (state.view === 'reports') content.innerHTML = reportsMarkup();
  if (state.view === 'cash-counts') content.innerHTML = cashCountsMarkup();
  if (state.view === 'closing') content.innerHTML = monthlyClosingMarkup();
}

function accountBalance(accountId) {
  const account = state.accounts.find((item) => item.id === accountId);
  const approvedInflow = state.requests
    .filter((request) => request.account_id === accountId && request.status === 'approved')
    .reduce((total, request) => total + Number(request.requested_amount), 0);
  const cashOut = state.transactions
    .filter((item) => item.account_id === accountId && item.transaction_type === 'OUT' && item.status !== 'void')
    .reduce((total, item) => total + Number(item.amount), 0);
  return Number(account?.initial_balance || 0) + approvedInflow - cashOut;
}

function getLastDayOfMonth(monthStr) {
  const [year, month] = monthStr.split('-').map(Number);
  return new Date(year, month, 0).getDate();
}

function getPreviousMonth(monthStr) {
  const [year, month] = monthStr.split('-').map(Number);
  const prevMonth = month === 1 ? 12 : month - 1;
  const prevYear = month === 1 ? year - 1 : year;
  return `${String(prevYear).padStart(4, '0')}-${String(prevMonth).padStart(2, '0')}`;
}

function accountBalanceAsOf(accountId, dateStr) {
  const account = state.accounts.find((item) => item.id === accountId);
  const approvedInflow = state.requests
    .filter((request) => request.account_id === accountId && request.status === 'approved' && (request.reviewed_at || '').slice(0, 10) <= dateStr)
    .reduce((total, request) => total + Number(request.requested_amount), 0);
  const cashOut = state.transactions
    .filter((item) => item.account_id === accountId && item.transaction_type === 'OUT' && item.status !== 'void' && item.transaction_date.slice(0, 10) <= dateStr)
    .reduce((total, item) => total + Number(item.amount), 0);
  return Number(account?.initial_balance || 0) + approvedInflow - cashOut;
}

function monthlySummary(accountId, monthStr) {
  const existing = state.monthlyClosings.find((item) => item.account_id === accountId && item.closing_month.slice(0, 7) === monthStr);
  if (existing) {
    return {
      startingBalance: Number(existing.starting_balance),
      inflows: Number(existing.total_inflows),
      outflows: Number(existing.total_outflows),
      adjustment: Number(existing.adjustment || 0),
      endingBalance: Number(existing.ending_balance),
      closed: true,
      closedAt: existing.closed_at
    };
  }
  const prevMonth = getPreviousMonth(monthStr);
  const prevLastDay = `${prevMonth}-${String(getLastDayOfMonth(prevMonth)).padStart(2, '0')}`;
  const startingBalance = accountBalanceAsOf(accountId, prevLastDay);
  const inflows = state.requests
    .filter((r) => r.account_id === accountId && r.status === 'approved' && r.reviewed_at?.slice(0, 7) === monthStr)
    .reduce((total, r) => total + Number(r.requested_amount), 0);
  const outflows = state.transactions
    .filter((t) => t.account_id === accountId && t.transaction_type === 'OUT' && t.status !== 'void' && t.transaction_date.slice(0, 7) === monthStr)
    .reduce((total, t) => total + Number(t.amount), 0);
  const endingBalance = startingBalance + inflows - outflows;
  return { startingBalance, inflows, outflows, adjustment: 0, endingBalance, closed: false };
}

function totals(transactions = state.transactions) {
  return {
    IN: state.requests
      .filter((request) => request.status === 'approved' && request.account_id)
      .reduce((sum, request) => sum + Number(request.requested_amount), 0),
    OUT: transactions
      .filter((item) => item.transaction_type === 'OUT' && item.status !== 'void')
      .reduce((sum, item) => sum + Number(item.amount), 0)
  };
}

function statusBadge(status) {
  const labels = { pending: 'Menunggu', approved: 'Disetujui', rejected: 'Ditolak' };
  return `<span class="badge badge-${status}">${labels[status] || escapeHtml(status)}</span>`;
}

function tableEmpty(columns, title, description) {
  return `<tr><td colspan="${columns}" class="empty-state"><strong>${title}</strong>${description}</td></tr>`;
}

function requestRows(list, compact = false) {
  if (!list.length) return tableEmpty(compact ? 3 : 5, 'Belum ada pengajuan', 'Pengajuan petty cash akan tampil di sini.');
  return list.map((item) => {
    const ownPending = isAdmin() && item.requester_id === state.profile.id && item.status === 'pending';
    const actions = isAdmin()
      ? (ownPending ? `<button class="small-action" data-action="edit" data-entity="request" data-id="${item.id}">Ubah</button><button class="small-action danger" data-action="delete" data-entity="request" data-id="${item.id}">Hapus</button>` : '—')
      : (item.status === 'pending' ? `<button class="small-action" data-action="approve" data-id="${item.id}">Setujui</button><button class="small-action danger" data-action="reject" data-id="${item.id}">Tolak</button>` : '—');
    const requestAccount = item.account_id ? accountName(item.account_id) : 'Akun belum dipilih';
    return `<tr><td><strong>${escapeHtml(item.purpose)}</strong><span class="cell-sub">${escapeHtml(requestAccount)} · ${dateLabel(item.created_at.slice(0, 10))}</span></td>${compact ? '' : `<td>${escapeHtml(userName(item.requester_id))}</td>`}<td class="amount">${money(item.requested_amount)}</td><td>${statusBadge(item.status)}${item.status === 'rejected' && item.rejection_reason ? `<span class="cell-sub">${escapeHtml(item.rejection_reason)}</span>` : ''}</td>${compact ? '' : `<td><div class="row-actions">${actions}</div></td>`}</tr>`;
  }).join('');
}

function transactionRows(list, compact = false) {
  if (!list.length) return tableEmpty(compact ? 3 : 5, 'Belum ada transaksi', 'Transaksi kas kecil akan tampil di sini.');
  return list.map((item) => {
    const isVoided = item.status === 'void';
    const voidBadge = isVoided ? '<span class="badge badge-void">Dibatalkan</span>' : '';
    const rowClass = isVoided ? 'voided' : '';
    const actions = isAdmin()
      ? isVoided
        ? `<button class="small-action" data-action="edit" data-entity="transaction" data-id="${item.id}">Ubah</button>`
        : `<button class="small-action" data-action="edit" data-entity="transaction" data-id="${item.id}">Ubah</button><button class="small-action danger" data-action="void" data-entity="transaction" data-id="${item.id}">Batalkan</button>`
      : '—';
    return `<tr class="${rowClass}"><td><strong>${escapeHtml(item.description)}</strong><span class="cell-sub">${dateLabel(item.transaction_date)}</span></td>${compact ? '' : `<td>${escapeHtml(accountName(item.account_id))}</td>`}<td><span class="badge badge-pending">Kas keluar</span>${voidBadge}</td>${compact ? '' : `<td><span class="cell-sub">${escapeHtml(categoryName(item.category_id))}</span></td>`}<td class="amount">${money(item.amount)}</td>${compact ? '' : `<td><div class="row-actions">${actions}</div></td>`}</tr>`;
  }).join('');
}

function dashboardMarkup() {
  const sums = totals();
  const pendingCount = state.requests.filter((item) => item.status === 'pending').length;
  const balance = state.accounts.reduce((sum, account) => sum + accountBalance(account.id), 0);
  const lowBalanceAccounts = state.accounts.filter((account) => {
    const minimum = Number(account.min_balance || 0);
    return minimum > 0 && accountBalance(account.id) < minimum;
  });
  const balanceWarnings = lowBalanceAccounts.length
    ? `<section class="balance-alerts" aria-label="Peringatan batas saldo">${lowBalanceAccounts.map((account) => `<div class="balance-alert"><strong>${escapeHtml(account.name)}</strong><span>Saldo ${money(accountBalance(account.id))} · Batas minimum ${money(account.min_balance)}</span><span>Segera ajukan pengisian</span></div>`).join('')}</section>`
    : '';
  const metrics = [
    ['Saldo kas kecil', money(balance), `${state.accounts.length} akun terdaftar`],
    ['Pengajuan menunggu', pendingCount, isAdmin() ? 'Menunggu keputusan manager' : 'Perlu ditinjau'],
    ['Total kas masuk', money(sums.IN), 'Akumulasi seluruh akun'],
    ['Total kas keluar', money(sums.OUT), 'Akumulasi seluruh akun']
  ];
  const recentRequests = state.requests.slice(0, 5);
  const recentTransactions = state.transactions.filter((item) => item.transaction_type === 'OUT').slice(0, 5);
  return `<div class="welcome-line"><div><h2>${isAdmin() ? 'Ringkasan operasional' : 'Pemantauan kas kecil'}</h2><p>Halo, ${escapeHtml(state.profile.full_name)}. Berikut kondisi kas terkini.</p></div>${isAdmin() ? '<button class="button button-primary" data-action="new" data-entity="request">＋ Buat pengajuan</button>' : ''}</div>
    ${balanceWarnings}
    <div class="metric-grid">${metrics.map(([label, value, note]) => `<article class="metric"><div class="metric-label">${label}</div><div class="metric-value">${value}</div><div class="metric-note">${note}</div></article>`).join('')}</div>
    <div class="dashboard-lower"><section class="panel"><div class="panel-heading"><div><h3>Pengajuan terbaru</h3><p>Pengajuan petty cash terkini</p></div><button class="small-action" data-view="requests">Lihat semua →</button></div><div class="table-wrap"><table><thead><tr><th>Keperluan</th><th>Nominal</th><th>Status</th></tr></thead><tbody>${requestRows(recentRequests, true)}</tbody></table></div></section>
    <section class="panel"><div class="panel-heading"><div><h3>Transaksi terakhir</h3><p>Pergerakan kas terbaru</p></div><button class="small-action" data-view="transactions">Riwayat →</button></div><div class="table-wrap"><table><thead><tr><th>Transaksi</th><th>Jenis</th><th>Nominal</th></tr></thead><tbody>${transactionRows(recentTransactions, true)}</tbody></table></div></section></div>`;
}

function filteredRequests() {
  return state.requests.filter((item) => {
    const text = `${item.purpose} ${userName(item.requester_id)}`.toLowerCase();
    return text.includes(state.search.toLowerCase()) && (state.filter === 'all' || item.status === state.filter);
  });
}

function requestsMarkup() {
  const addButton = isAdmin() ? '<button class="button button-primary" data-action="new" data-entity="request">＋ Buat pengajuan</button>' : '';
  return `<div class="toolbar"><h2>Daftar pengajuan <span class="cell-sub">${filteredRequests().length} data</span></h2><div class="toolbar-controls"><input class="search-field" data-search placeholder="Cari keperluan atau nama..." value="${escapeHtml(state.search)}" aria-label="Cari pengajuan"><select data-filter aria-label="Filter status"><option value="all">Semua status</option><option value="pending" ${state.filter === 'pending' ? 'selected' : ''}>Menunggu</option><option value="approved" ${state.filter === 'approved' ? 'selected' : ''}>Disetujui</option><option value="rejected" ${state.filter === 'rejected' ? 'selected' : ''}>Ditolak</option></select>${addButton}</div></div>
    <section class="panel"><div class="table-wrap"><table><thead><tr><th>Keperluan</th><th>Pengaju</th><th>Nominal</th><th>Status</th><th>Tindakan</th></tr></thead><tbody>${requestRows(filteredRequests())}</tbody></table></div></section>`;
}

function filteredTransactions() {
  return state.transactions.filter((item) => item.transaction_type === 'OUT').filter((item) => {
    const text = `${item.description} ${accountName(item.account_id)} ${userName(item.created_by)}`.toLowerCase();
    return text.includes(state.search.toLowerCase()) && (state.filter === 'all' || item.transaction_type === state.filter) && (state.showVoided || item.status !== 'void');
  });
}

function transactionsMarkup() {
  const addButton = isAdmin() ? '<button class="button button-primary" data-action="new" data-entity="transaction">＋ Catat transaksi</button>' : '';
  const categoryManager = isAdmin() ? `<section class="panel category-panel"><div class="panel-heading"><div><h3>Kategori pengeluaran</h3><p>${state.categories.filter((category) => category.is_active).length} kategori aktif</p></div><button class="small-action" data-action="add-category">+ Tambah kategori</button></div><div class="category-list">${state.categories.map((category) => `<span class="category-pill ${category.is_active ? '' : 'inactive'}">${escapeHtml(category.name)}<button type="button" data-action="toggle-category" data-id="${category.id}" data-active="${category.is_active}">${category.is_active ? 'Nonaktifkan' : 'Aktifkan'}</button></span>`).join('')}</div></section>` : '';
  return `<div class="toolbar"><h2>Riwayat transaksi <span class="cell-sub">${filteredTransactions().length} data</span></h2><div class="toolbar-controls"><input class="search-field" data-search placeholder="Cari pengeluaran atau akun..." value="${escapeHtml(state.search)}" aria-label="Cari transaksi"><label class="void-filter"><input type="checkbox" data-show-void ${state.showVoided ? 'checked' : ''}> Tampilkan yang dibatalkan</label>${addButton}</div></div>${categoryManager}
    <section class="panel"><div class="table-wrap"><table><thead><tr><th>Uraian</th><th>Akun kas</th><th>Jenis</th><th>Kategori</th><th>Nominal</th><th>Tindakan</th></tr></thead><tbody>${transactionRows(filteredTransactions())}</tbody></table></div></section>`;
}

function accountsMarkup() {
  const balance = (account) => money(accountBalance(account.id));
  const rows = state.accounts.length ? state.accounts.map((account) => `<tr><td><strong>${escapeHtml(account.name)}</strong><span class="cell-sub">${escapeHtml(account.account_code)}</span></td><td>${money(account.initial_balance)}</td><td class="amount">${balance(account)}</td><td><span class="badge ${account.is_active ? 'badge-active' : 'badge-inactive'}">${account.is_active ? 'Aktif' : 'Nonaktif'}</span></td><td>${isAdmin() ? `<div class="row-actions"><button class="small-action" data-action="edit" data-entity="account" data-id="${account.id}">Ubah</button><button class="small-action danger" data-action="delete" data-entity="account" data-id="${account.id}">Hapus</button></div>` : '—'}</td></tr>`).join('') : tableEmpty(5, 'Belum ada akun kas kecil', 'Tambahkan akun untuk mulai mencatat saldo kas.');
  return `<div class="toolbar"><h2>Daftar akun <span class="cell-sub">${state.accounts.length} akun</span></h2>${isAdmin() ? '<button class="button button-primary" data-action="new" data-entity="account">＋ Tambah akun</button>' : ''}</div><section class="panel"><div class="table-wrap"><table><thead><tr><th>Akun</th><th>Saldo awal</th><th>Saldo saat ini</th><th>Status</th><th>Tindakan</th></tr></thead><tbody>${rows}</tbody></table></div></section>`;
}

function cashCountsMarkup() {
  const counts = state.cashCounts.slice().sort((a, b) => new Date(b.counted_at) - new Date(a.counted_at));
  return `<div class="toolbar"><h2>Kas opname <span class="cell-sub">${counts.length} pencatatan</span></h2>${isAdmin() ? '<button class="button button-primary" data-action="new" data-entity="cash-count">＋ Catat kas opname</button>' : ''}</div><section class="panel"><div class="table-wrap"><table><thead><tr><th>Akun kas</th><th>Saldo sistem</th><th>Uang fisik</th><th>Selisih</th><th>Dicatat oleh</th><th>Tanggal</th><th>Keterangan</th></tr></thead><tbody>${counts.length ? counts.map((item) => `<tr><td><strong>${escapeHtml(accountName(item.account_id))}</strong></td><td class="amount">${money(item.system_balance)}</td><td class="amount">${money(item.physical_amount)}</td><td class="amount ${Number(item.difference) === 0 ? 'diff-zero' : 'diff-nonzero'}">${money(item.difference)}</td><td><span class="cell-sub">${escapeHtml(userName(item.created_by))}</span></td><td><span class="cell-sub">${dateLabel(item.counted_at)}</span></td><td>${escapeHtml(item.notes || '')}</td></tr>`).join('') : tableEmpty(7, 'Belum ada pencatatan kas opname', 'Catat hasil pemeriksaan kas fisik.')}</tbody></table></div></section>`;
}

function reportsMarkup() {
  const monthlyOutflows = state.transactions.filter((item) => item.transaction_type === 'OUT' && item.status !== 'void' && item.transaction_date.slice(0, 7) === state.reportMonth);
  const monthlyInflows = state.requests.filter((request) => request.status === 'approved' && request.account_id && request.reviewed_at?.slice(0, 7) === state.reportMonth);
  const sum = {
    IN: monthlyInflows.reduce((total, request) => total + Number(request.requested_amount), 0),
    OUT: monthlyOutflows.reduce((total, item) => total + Number(item.amount), 0)
  };
  const balance = state.accounts.reduce((total, account) => total + accountBalance(account.id), 0);
  const entries = [
    ...monthlyInflows.map((request) => ({ date: request.reviewed_at.slice(0, 10), description: `Pengisian kas: ${request.purpose}`, account_id: request.account_id, type: 'IN', amount: request.requested_amount })),
    ...monthlyOutflows.map((item) => ({ date: item.transaction_date, description: item.description, account_id: item.account_id, type: 'OUT', amount: item.amount }))
  ].sort((left, right) => right.date.localeCompare(left.date));
  const rows = entries.length ? entries.map((item) => `<tr><td>${dateLabel(item.date)}</td><td><strong>${escapeHtml(item.description)}</strong></td><td>${escapeHtml(accountName(item.account_id))}</td><td><span class="badge ${item.type === 'IN' ? 'badge-approved' : 'badge-pending'}">${item.type === 'IN' ? 'Kas masuk' : 'Kas keluar'}</span></td><td class="amount">${money(item.amount)}</td></tr>`).join('') : tableEmpty(5, 'Tidak ada aktivitas pada periode ini', 'Pilih bulan lain untuk melihat laporan.');
  return `<div class="toolbar"><div><h2>Laporan kas kecil</h2><span class="cell-sub">Ringkasan transaksi berdasarkan bulan</span></div><div class="report-filter"><label for="report-month">Periode</label><input id="report-month" type="month" value="${state.reportMonth}"></div></div><div class="report-grid"><div class="report-total"><span>Kas masuk bulan ini</span><strong>${money(sum.IN)}</strong></div><div class="report-total"><span>Kas keluar bulan ini</span><strong>${money(sum.OUT)}</strong></div><div class="report-total"><span>Saldo seluruh akun</span><strong>${money(balance)}</strong></div></div><section class="panel"><div class="panel-heading"><div><h3>Rincian aktivitas kas</h3><p>${entries.length} aktivitas pada ${escapeHtml(state.reportMonth)}</p></div></div><div class="table-wrap"><table><thead><tr><th>Tanggal</th><th>Uraian</th><th>Akun</th><th>Jenis</th><th>Nominal</th></tr></thead><tbody>${rows}</tbody></table></div></section>`;
}

function field(label, name, value = '', type = 'text', required = true, extra = '') {
  const safeValue = escapeHtml(value ?? '');
  return `<label for="field-${name}">${label}</label><input id="field-${name}" name="${name}" type="${type}" value="${safeValue}" ${required ? 'required' : ''} ${extra}>`;
}

function requestForm(item = {}) {
  const activeAccounts = state.accounts.filter((account) => account.is_active);
  const accountOptions = activeAccounts.map((account) => `<option value="${account.id}" ${item.account_id === account.id ? 'selected' : ''}>${escapeHtml(account.name)}</option>`).join('');
  return `<label for="field-account_id">Akun kas kecil</label><select id="field-account_id" name="account_id" required><option value="">Pilih akun tujuan</option>${accountOptions}</select>${field('Keperluan pengisian', 'purpose', item.purpose, 'text', true, 'maxlength="180" placeholder="Contoh: pengisian awal atau replenishment"')}<label for="field-requested_amount">Nominal pengisian (Rp)</label><input id="field-requested_amount" name="requested_amount" type="number" min="1" step="1" value="${escapeHtml(item.requested_amount ?? '')}" required><p class="cell-sub">Saldo bertambah hanya setelah manager menyetujui pengajuan.</p>`;
}

function transactionForm(item = {}) {
  const activeAccounts = state.accounts.filter((account) => account.is_active);
  const accountOptions = activeAccounts.map((account) => `<option value="${account.id}" ${item.account_id === account.id ? 'selected' : ''}>${escapeHtml(account.name)} (${money(accountBalance(account.id))})</option>`).join('');
  const activeCategories = state.categories.filter((category) => category.is_active);
  const categoryOptions = activeCategories.map((category) => `<option value="${category.id}" ${item.category_id === category.id ? 'selected' : ''}>${escapeHtml(category.name)}</option>`).join('');
  const categoryField = state.categories.length
    ? `<label for="field-category_id">Kategori pengeluaran</label><select id="field-category_id" name="category_id" ${!item.id ? 'required' : ''}><option value="">${item.id ? 'Tanpa kategori' : 'Pilih kategori'}</option>${categoryOptions}</select>`
    : '<p class="cell-sub">Kategori belum tersedia. Jalankan blok kategori pada schema SQL terlebih dahulu.</p>';
  return `<label for="field-account_id">Akun kas kecil</label><select id="field-account_id" name="account_id" required><option value="">Pilih akun</option>${accountOptions}</select>${field('Tanggal transaksi', 'transaction_date', item.transaction_date || new Date().toISOString().slice(0, 10), 'date')}${categoryField}<label for="field-description">Uraian pengeluaran</label><textarea id="field-description" name="description" maxlength="240" required placeholder="Contoh: pembelian ATK">${escapeHtml(item.description || '')}</textarea><label for="field-amount">Nominal pengeluaran (Rp)</label><input id="field-amount" name="amount" type="number" min="1" step="1" value="${escapeHtml(item.amount ?? '')}" required><p id="field-amount-error" class="inline-field-error" aria-live="polite"></p><p class="cell-sub">Pengisian saldo dilakukan melalui pengajuan dan persetujuan manager.</p>`;
}

function accountForm(item = {}) {
  return `${field('Kode akun', 'account_code', item.account_code, 'text', true, 'maxlength="24" placeholder="Contoh: PK-001"')}<label for="field-name">Nama akun</label><input id="field-name" name="name" type="text" value="${escapeHtml(item.name || '')}" maxlength="80" required placeholder="Contoh: Kas kecil kantor">${field('Batas saldo minimum (Rp)', 'min_balance', item.min_balance ?? 0, 'number', true, 'min="0" step="1"')}${item.id ? `<p class="cell-sub">Saldo awal: ${money(item.initial_balance)} (tetap)</p><label class="check-field"><input name="is_active" type="checkbox" ${item.is_active ? 'checked' : ''}> Akun aktif</label>` : '<p class="cell-sub">Saldo awal akun baru Rp0. Pengisian dana diajukan melalui menu pengajuan.</p>'}`;
}

function cashCountForm() {
  const activeAccounts = state.accounts.filter((account) => account.is_active);
  const accountOptions = activeAccounts.map((account) =>
    `<option value="${account.id}">${escapeHtml(account.name)} (${money(accountBalance(account.id))})</option>`
  ).join('');
  return `<label for="field-account_id">Akun kas</label><select id="field-account_id" name="account_id" required><option value="">Pilih akun kas</option>${accountOptions}</select><label for="field-system-balance">Saldo sistem (otomatis)</label><div id="field-system-balance" class="amount" aria-live="polite">${money(0)}</div><label for="field-physical-amount">Uang fisik (Rp)</label><input id="field-physical-amount" name="physical_amount" type="number" min="0" step="1" value="0" required><label for="field-difference">Selisih</label><div id="field-difference" class="amount diff-zero" aria-live="polite">${money(0)}</div><label for="field-notes">Keterangan</label><textarea id="field-notes" name="notes" maxlength="240" placeholder="Wajib diisi jika selisih tidak nol"></textarea><p id="field-notes-error" class="inline-field-error" aria-live="polite"></p><p class="cell-sub">Kas opname hanya mencatat perbedaan fisik vs sistem; tidak mengubah saldo.</p>`;
}

function updateCashCountDifference() {
  const form = $('#record-form');
  if (form.dataset.entity !== 'cash-count') return;
  const accountId = $('#field-account_id').value;
  const physical = Number($('#field-physical-amount').value) || 0;
  const systemBal = accountBalance(accountId || null);
  const diff = physical - systemBal;
  const sysEl = $('#field-system-balance');
  const diffEl = $('#field-difference');
  if (sysEl) sysEl.textContent = money(systemBal);
  if (diffEl) {
    diffEl.textContent = money(diff);
    diffEl.className = 'amount ' + (diff === 0 ? 'diff-zero' : 'diff-nonzero');
  }
}

function updateMonthlyClosingSummary() {
  const form = $('#record-form');
  if (form.dataset.entity !== 'closing') return;
  const accountId = $('#field-account_id').value;
  const monthStr = $('#field-closing_month').value;
  if (!accountId || !monthStr) return;
  const summary = monthlySummary(accountId, monthStr);
  $('#field-summary-starting').textContent = money(summary.startingBalance);
  $('#field-summary-inflows').textContent = money(summary.inflows);
  $('#field-summary-outflows').textContent = money(summary.outflows);
  if (summary.closed) {
    $('#field-summary-ending').textContent = money(summary.endingBalance);
    $('#field-summary-ending').className = 'amount';
  } else {
    const adj = Number($('#field-adjustment').value) || 0;
    $('#field-summary-ending').textContent = money(summary.startingBalance + summary.inflows - summary.outflows + adj);
    const diff = summary.startingBalance + summary.inflows - summary.outflows + adj;
    $('#field-summary-ending').className = 'amount ' + (diff === 0 ? 'diff-zero' : 'diff-nonzero');
  }
}

function monthlyClosingMarkup() {
  const closings = state.monthlyClosings.slice().sort((a, b) => new Date(b.closing_month) - new Date(a.closing_month));
  const closedMonths = new Set(closings.map((item) => `${item.account_id}|${item.closing_month.slice(0, 7)}`));
  const rows = state.accounts
    .filter((account) => account.is_active)
    .map((account) => {
      const summary = monthlySummary(account.id, state.closingMonth);
      const isClosed = closedMonths.has(`${account.id}|${state.closingMonth}`);
      return `<tr><td><strong>${escapeHtml(account.name)}</strong><span class="cell-sub">${escapeHtml(account.account_code || '')}</span></td><td class="amount">${money(summary.startingBalance)}</td><td class="amount">${money(summary.inflows)}</td><td class="amount">${money(summary.outflows)}</td><td class="amount ${Number(summary.endingBalance) === 0 ? 'diff-zero' : 'diff-nonzero'}"><strong>${money(summary.endingBalance)}</strong></td><td>${isClosed ? '<span class="badge badge-closed">Tertutup</span>' : '<span class="badge badge-open">Terbuka</span>'}</td></tr>`;
    });
  return `<div class="toolbar"><h2>Tutup buku <span class="cell-sub">${state.closingMonth}</span></h2>${isAdmin() ? '<button class="button button-primary" data-action="new" data-entity="closing">＋ Tutup buku bulan ini</button>' : ''}</div><div class="toolbar-controls"><label for="closing-month-nav">Periode</label><input id="closing-month-nav" type="month" value="${state.closingMonth}"></div><section class="panel"><div class="panel-heading"><div><h3>Ringkasan akun — ${escapeHtml(state.closingMonth)}</h3><p>${rows.length} akun kas aktif</p></div></div><div class="table-wrap"><table><thead><tr><th>Akun kas</th><th>Saldo awal</th><th>Total masuk</th><th>Total keluar</th><th>Saldo akhir</th><th>Status</th></tr></thead><tbody>${rows.length ? rows.join('') : tableEmpty(6, 'Tidak ada akun kas aktif', 'Aktifkan akun kas untuk melihat ringkasan bulanan.')}</tbody></table></div></section><section class="panel"><h3>Riwayat tutup buku</h3><div class="table-wrap"><table><thead><tr><th>Akun</th><th>Bulan</th><th>Saldo akhir</th><th>Diclose oleh</th><th>Tanggal</th></tr></thead><tbody>${closings.length ? closings.map((item) => `<tr><td>${escapeHtml(accountName(item.account_id))}</td><td><span class="cell-sub">${item.closing_month}</span></td><td class="amount">${money(item.ending_balance)}</td><td>${escapeHtml(userName(item.closed_by))}</td><td><span class="cell-sub">${dateLabel(item.closed_at)}</span></td></tr>`).join('') : tableEmpty(5, 'Belum ada rekaman tutup buku', 'Tutup buku untuk mencatat rekaman bulanan.')}</tbody></table></div></section>`;
}

function monthlyClosingForm(item = {}) {
  const activeAccounts = state.accounts.filter((account) => account.is_active);
  const accountOptions = activeAccounts.map((account) => `<option value="${account.id}">${escapeHtml(account.name)}</option>`).join('');
  const monthValue = item.closing_month?.slice(0, 7) || state.closingMonth;
  const existing = item.id ? state.monthlyClosings.find((c) => c.id === item.id) : null;
  const summary = existing ? { endingBalance: Number(existing.ending_balance) } : { endingBalance: 0 };
  return `<label for="field-account_id">Akun kas</label><select id="field-account_id" name="account_id" required><option value="">Pilih akun kas</option>${accountOptions}</select><label for="field-closing_month">Bulan tutup buku</label><input id="field-closing_month" name="closing_month" type="month" value="${monthValue}" required><fieldset class="summary-grid"><legend>Ringkasan otomatis</legend><div class="summary-item"><span class="summary-label">Saldo awal</span><span id="field-summary-starting" class="amount">${money(0)}</span></div><div class="summary-item"><span class="summary-label">Total masuk</span><span id="field-summary-inflows" class="amount">${money(0)}</span></div><div class="summary-item"><span class="summary-label">Total keluar</span><span id="field-summary-outflows" class="amount">${money(0)}</span></div><div class="summary-item"><span class="summary-label">Penyesuaian</span><input id="field-adjustment" name="adjustment" type="number" step="100" value="0" min="0"></div><div class="summary-item summary-end"><span class="summary-label">Saldo akhir</span><span id="field-summary-ending" class="amount diff-zero">${money(0)}</span></div></fieldset><label for="field-notes">Keterangan</label><textarea id="field-notes" name="notes" maxlength="240" placeholder="Opsional: catatan penutupan buku bulan ini">${escapeHtml(item.notes || '')}</textarea>`;
}

function openEditor(entity, item = null) {
  if (!isAdmin()) return;
  if (entity === 'request' && !state.accounts.some((account) => account.is_active)) return notify('Tambahkan akun kas aktif sebelum membuat pengajuan.', 'error');
  if (entity === 'transaction' && !state.accounts.some((account) => account.is_active)) return notify('Tambahkan akun kas aktif sebelum mencatat transaksi.', 'error');
  if (entity === 'cash-count' && !state.accounts.some((account) => account.is_active)) return notify('Tambahkan akun kas aktif sebelum mencatat kas opname.', 'error');
  if (entity === 'closing' && !state.accounts.some((account) => account.is_active)) return notify('Tambahkan akun kas aktif sebelum menutup buku.', 'error');
  state.editing = { entity, id: item?.id || null };
  const names = { request: 'pengajuan', transaction: 'transaksi', account: 'akun kas', 'cash-count': 'kas opname', closing: 'tutup buku' };
  $('#dialog-kicker').textContent = item ? 'UBAH DATA' : 'DATA BARU';
  $('#dialog-title').textContent = `${item ? 'Ubah' : 'Tambah'} ${names[entity]}`;
  $('#record-fields').innerHTML = entity === 'request' ? requestForm(item || {}) : entity === 'transaction' ? transactionForm(item || {}) : entity === 'cash-count' ? cashCountForm() : entity === 'closing' ? monthlyClosingForm(item || {}) : accountForm(item || {});
  $('#record-form').dataset.entity = entity;
  $('#record-dialog').showModal();
  if (entity === 'cash-count') updateCashCountDifference();
  if (entity === 'closing') updateMonthlyClosingSummary();
}

async function saveRecord(event) {
  event.preventDefault();
  if (!state.editing) return;
  const { entity, id } = state.editing;
  const formData = new FormData(event.currentTarget);
  const values = Object.fromEntries(formData.entries());
  let table;
  let payload;

  if (entity === 'request') {
    table = 'petty_cash_requests';
    payload = { account_id: values.account_id, purpose: values.purpose.trim(), requested_amount: Number(values.requested_amount) };
    if (!id) Object.assign(payload, { requester_id: state.profile.id, status: 'pending' });
  } else if (entity === 'account') {
    table = 'petty_cash_accounts';
    payload = { account_code: values.account_code.trim().toUpperCase(), name: values.name.trim(), min_balance: Number(values.min_balance) };
    if (id) payload.is_active = formData.has('is_active');
    else Object.assign(payload, { initial_balance: 0, created_by: state.profile.id });
  } else if (entity === 'cash-count') {
    table = 'cash_counts';
    const systemBal = accountBalance(values.account_id);
    const physical = Number(values.physical_amount) || 0;
    const difference = physical - systemBal;
    if (difference !== 0 && !values.notes?.trim()) {
      showFieldError('notes', 'Keterangan wajib diisi ketika selisih tidak nol.');
      return;
    }
    payload = {
      account_id: values.account_id,
      system_balance: systemBal,
      physical_amount: physical,
      difference,
      notes: values.notes?.trim() || null,
      counted_at: new Date().toISOString()
    };
    if (!id) payload.created_by = state.profile.id;
  } else if (entity === 'closing') {
    const closed = state.monthlyClosings.find((c) => c.account_id === values.account_id && c.closing_month.slice(0, 7) === values.closing_month);
    if (closed && !id) {
      notify('Buku bulan ini sudah ditutup untuk akun tersebut.', 'error');
      return;
    }
    table = 'monthly_closings';
    const summary = monthlySummary(values.account_id, values.closing_month);
    const adjustment = Number(values.adjustment) || 0;
    const endingBalance = summary.startingBalance + summary.inflows - summary.outflows + adjustment;
    payload = {
      account_id: values.account_id,
      closing_month: values.closing_month + '-01',
      starting_balance: summary.startingBalance,
      total_inflows: summary.inflows,
      total_outflows: summary.outflows,
      adjustment,
      ending_balance: endingBalance,
      closed_by: state.profile.id,
      notes: values.notes?.trim() || null
    };
  } else {
    table = 'petty_cash_transactions';
    payload = {
      account_id: values.account_id,
      category_id: values.category_id || null,
      request_id: null,
      transaction_type: 'OUT',
      transaction_date: values.transaction_date,
      description: values.description.trim(),
      amount: Number(values.amount)
    };
    if (!id) payload.created_by = state.profile.id;
  }

  const button = $('#save-record');
  button.disabled = true;
  button.textContent = 'Menyimpan...';
  const result = id
    ? await supabaseClient.from(table).update(payload).eq('id', id)
    : await supabaseClient.from(table).insert(payload);
  button.disabled = false;
  button.textContent = 'Simpan';
  if (result.error) {
    const displayedError = errorMessage(result.error);
    const isInsufficientBalance = entity === 'transaction' && /saldo akun tidak mencukupi/i.test(displayedError);
    if (isInsufficientBalance) {
      $('#record-dialog').close();
      window.setTimeout(() => notify(balanceErrorMessage(displayedError), 'error'), 220);
      return;
    }
    if (entity === 'transaction') showFieldError('amount', displayedError);
    notify(displayedError, 'error');
    return;
  }
  $('#record-dialog').close();
  state.editing = null;
  notify(id ? 'Perubahan berhasil disimpan.' : 'Data berhasil ditambahkan.');
  await refreshData();
}

async function deleteRecord(entity, id) {
  const config = {
    request: { table: 'petty_cash_requests', label: 'pengajuan' },
    transaction: { table: 'petty_cash_transactions', label: 'transaksi' },
    account: { table: 'petty_cash_accounts', label: 'akun kas' }
  }[entity];
  if (!config || !window.confirm(`Hapus ${config.label} ini? Tindakan ini tidak dapat dibatalkan.`)) return;
  const { error } = await supabaseClient.from(config.table).delete().eq('id', id);
  if (error) return notify(errorMessage(error), 'error');
  notify(`${config.label[0].toUpperCase()}${config.label.slice(1)} berhasil dihapus.`);
  await refreshData();
}

async function reviewRequest(id, decision) {
  const reason = decision === 'rejected' ? window.prompt('Masukkan alasan penolakan:') : null;
  if (decision === 'rejected' && !reason?.trim()) {
    if (reason !== null) notify('Alasan penolakan wajib diisi.', 'error');
    return;
  }
  const { error } = await supabaseClient.rpc('review_petty_cash_request', {
    p_request_id: id,
    p_decision: decision,
    p_rejection_reason: reason?.trim() || null
  });
  if (error) return notify(errorMessage(error), 'error');
  notify(decision === 'approved' ? 'Pengajuan disetujui.' : 'Pengajuan ditolak.');
  await refreshData();
}

$('#login-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const formData = new FormData(event.currentTarget);
  const button = $('.login-submit', event.currentTarget);
  button.disabled = true;
  $('#login-error').textContent = '';
  const { data, error } = await supabaseClient.auth.signInWithPassword({ email: formData.get('email'), password: formData.get('password') });
  button.disabled = false;
  if (error) return $('#login-error').textContent = errorMessage(error);
  showLoading(true);
  try {
    await loadProfile(data.session);
  } catch (profileError) {
    showLogin(errorMessage(profileError));
  }
});

$('#logout-button').addEventListener('click', async () => {
  const { error } = await supabaseClient.auth.signOut();
  if (error) return notify(errorMessage(error), 'error');
  state.session = null;
  state.profile = null;
  state.accounts = [];
  state.requests = [];
  state.transactions = [];
  state.users = [];
  showLogin();
});

$('#main-nav').addEventListener('click', (event) => {
  const button = event.target.closest('[data-view]');
  if (button) setView(button.dataset.view);
});

$('#content').addEventListener('click', async (event) => {
  const viewButton = event.target.closest('[data-view]');
  if (viewButton) return setView(viewButton.dataset.view);
  const button = event.target.closest('[data-action]');
  if (!button) return;
  const { action, entity, id } = button.dataset;
  if (action === 'new') return openEditor(entity);
  if (action === 'edit') {
    const source = { request: state.requests, transaction: state.transactions, account: state.accounts }[entity];
    return openEditor(entity, source.find((item) => item.id === id));
  }
  if (action === 'delete') return deleteRecord(entity, id);
  if (action === 'approve') return reviewRequest(id, 'approved');
  if (action === 'reject') return reviewRequest(id, 'rejected');
  if (action === 'add-category') return addCategory();
  if (action === 'toggle-category') return toggleCategory(id, button.dataset.active === 'true');
  if (action === 'void') return voidTransaction(id);
});

async function addCategory() {
  if (!isAdmin()) return;
  const name = window.prompt('Nama kategori pengeluaran:');
  if (!name?.trim()) return;
  try {
    const { error } = await supabaseClient.from('expense_categories').insert({
      name: name.trim(),
      coa_code: null,
      is_active: true
    });
    if (error) throw error;
    notify('Kategori pengeluaran berhasil ditambahkan.');
    await refreshData();
  } catch (categoryError) {
    notify(errorMessage(categoryError), 'error');
  }
}

async function toggleCategory(id, wasActive) {
  if (!isAdmin()) return;
  try {
    const { error } = await supabaseClient.from('expense_categories').update({ is_active: !wasActive }).eq('id', id);
    if (error) throw error;
    notify(wasActive ? 'Kategori dinonaktifkan.' : 'Kategori diaktifkan.');
    await refreshData();
  } catch (categoryError) {
    notify(errorMessage(categoryError), 'error');
  }
}

async function voidTransaction(id) {
  if (!isAdmin()) return;
  const reason = window.prompt('Masukkan alasan pembatalan (minimal 5 karakter):');
  if (reason !== null && (!reason.trim() || reason.trim().length < 5)) {
    notify('Alasan pembatalan wajib diisi minimal 5 karakter.', 'error');
    return;
  }
  if (!reason) return;
  try {
    const { error } = await supabaseClient.rpc('void_petty_cash_transaction', {
      p_transaction_id: id,
      p_reason: reason.trim()
    });
    if (error) throw error;
    notify('Transaksi berhasil dibatalkan.');
    await refreshData();
  } catch (voidError) {
    notify(errorMessage(voidError), 'error');
  }
}

document.addEventListener('input', (event) => {
  if (event.target.matches('[data-search]')) {
    state.search = event.target.value;
    const position = event.target.selectionStart;
    renderView();
    const search = $('[data-search]');
    search.focus();
    search.setSelectionRange(position, position);
  if (event.target.matches('#field-amount')) clearFieldError('amount');
  }
  if (event.target.matches('#report-month')) {
    state.reportMonth = event.target.value;
    renderView();
  }
  if (event.target.matches('#field-physical-amount') && $('#record-form').dataset.entity === 'cash-count') {
    updateCashCountDifference();
  }
  if (event.target.matches('#field-notes')) clearFieldError('notes');
  if ($('#record-form') && $('#record-form').dataset.entity === 'closing' && event.target.matches('#field-adjustment')) {
    updateMonthlyClosingSummary();
  }
});

document.addEventListener('change', (event) => {
  if (event.target.matches('[data-filter]')) {
    state.filter = event.target.value;
    renderView();
  }
  if (event.target.matches('[data-show-void]')) {
    state.showVoided = event.target.checked;
    renderView();
  }
  if (event.target.matches('#field-account_id') && $('#record-form').dataset.entity === 'cash-count') {
    updateCashCountDifference();
  }
  if (event.target.matches('#field-account_id') && $('#record-form').dataset.entity === 'closing') {
    updateMonthlyClosingSummary();
  }
  if (event.target.matches('#field-closing_month') && $('#record-form').dataset.entity === 'closing') {
    state.closingMonth = event.target.value;
    updateMonthlyClosingSummary();
  }
  if (event.target.matches('#closing-month-nav')) {
    state.closingMonth = event.target.value;
    renderView();
  }
});

$('#record-form').addEventListener('submit', saveRecord);
$('#record-dialog').addEventListener('click', (event) => {
  if (event.target.matches('[data-close-dialog]')) $('#record-dialog').close();
});
$('#toast').addEventListener('click', (event) => {
  if (event.target.closest('.toast-close')) $('#toast').classList.remove('show');
});
$('#record-dialog').addEventListener('close', () => { state.editing = null; });

async function initialize() {
  showLoading(true);
  const { data, error } = await supabaseClient.auth.getSession();
  if (error) {
    showLogin(errorMessage(error));
    return;
  }
  if (!data.session) {
    showLogin();
    return;
  }
  try {
    await loadProfile(data.session);
  } catch (profileError) {
    showLogin(errorMessage(profileError));
  }
}

supabaseClient.auth.onAuthStateChange((event, session) => {
  if (event === 'SIGNED_OUT' && !session) showLogin();
});

initialize();