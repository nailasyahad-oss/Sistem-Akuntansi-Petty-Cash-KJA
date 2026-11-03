(() => {
  try {
    const content = document.querySelector('#content');
    const dialog = document.querySelector('#record-dialog');
    const form = document.querySelector('#record-form');
    const fields = document.querySelector('#record-fields');
    const saveButton = document.querySelector('#save-record');
    let editor = null;
    let coaLoadStarted = false;
    let coaLoadFailed = false;

    const activeCoa = () => state.chartOfAccounts.filter((item) => item.is_active);
    const accountForCategory = (category) => state.chartOfAccounts.find((item) => item.id === category.coa_id);
    async function refreshCoaData() {
      const { data, error } = await supabaseClient.from('chart_of_accounts').select('*').order('code');
      if (error) throw error;
      state.chartOfAccounts = data || [];
    }

    function renderManagementPanel() {
      const existingPanel = document.querySelector('#coa-journal-panel');
      if (state.view !== 'transactions' || !isAdmin()) {
        existingPanel?.remove();
        return;
      }
      if (!coaLoadStarted) {
        coaLoadStarted = true;
        refreshCoaData()
          .then(() => {
            renderManagementPanel();
          })
          .catch((error) => {
            coaLoadFailed = true;
            notify(`CoA belum dapat dimuat: ${errorMessage(error)}`, 'warning');
            renderManagementPanel();
          });
        return;
      }
      if (existingPanel) return;

      const panel = document.createElement('section');
      panel.id = 'coa-journal-panel';
      panel.className = 'panel category-panel';
      const coaRows = state.chartOfAccounts.map((item) => `<span class="category-pill ${item.is_active ? '' : 'inactive'}">${escapeHtml(item.code)} · ${escapeHtml(item.name)}<button type="button" data-coa-action="edit-coa" data-id="${item.id}">Ubah</button><button type="button" data-coa-action="toggle-coa" data-id="${item.id}" data-active="${item.is_active}">${item.is_active ? 'Nonaktifkan' : 'Aktifkan'}</button></span>`).join('');
      const categoryRows = state.categories.map((item) => {
        const coa = accountForCategory(item);
        const label = coa ? `${coa.code} · ${coa.name}` : (item.coa_code || 'Belum dipetakan');
        return `<span class="category-pill ${item.is_active ? '' : 'inactive'}">${escapeHtml(item.name)} → ${escapeHtml(label)}<button type="button" data-coa-action="edit-category" data-id="${item.id}">Atur CoA</button></span>`;
      }).join('');
      panel.innerHTML = `<div class="panel-heading"><div><h3>Chart of Accounts &amp; Kategori</h3><p>CoA pengeluaran dipakai otomatis saat transaksi dicatat.</p></div><div class="row-actions"><button class="small-action" type="button" data-coa-action="new-coa">＋ CoA</button><button class="small-action" type="button" data-coa-action="new-category">＋ Kategori</button></div></div><div class="category-list">${coaRows || '<span class="cell-sub">CoA belum tersedia. Jalankan blok Tahap 1 pada schema.sql.</span>'}</div><div class="category-list">${categoryRows || '<span class="cell-sub">Kategori belum tersedia.</span>'}</div>`;
      const existingCategoryPanel = content.querySelector('.category-panel');
      if (existingCategoryPanel) existingCategoryPanel.after(panel);
      else content.append(panel);
    }

    function openEditor(type, item = null) {
      if (!isAdmin()) return;
      if (type === 'category' && !activeCoa().length) {
        notify('Tambahkan akun CoA aktif sebelum mengatur kategori.', 'error');
        return;
      }

      editor = { type, id: item?.id || null };
      document.querySelector('#dialog-kicker').textContent = type === 'coa' ? 'CHART OF ACCOUNTS' : 'KATEGORI PENGELUARAN';
      document.querySelector('#dialog-title').textContent = type === 'coa'
        ? `${item ? 'Ubah' : 'Tambah'} akun CoA`
        : `${item ? 'Atur' : 'Tambah'} kategori`;

      if (type === 'coa') {
        fields.innerHTML = `<label for="field-coa-code">Kode akun</label><input id="field-coa-code" name="code" type="text" maxlength="24" value="${escapeHtml(item?.code || '')}" required><label for="field-coa-name">Nama akun</label><input id="field-coa-name" name="name" type="text" maxlength="100" value="${escapeHtml(item?.name || '')}" required><label for="field-coa-type">Jenis akun</label><select id="field-coa-type" name="type" required>${[['ASSET', 'Aset'], ['LIABILITY', 'Liabilitas'], ['EQUITY', 'Ekuitas'], ['REVENUE', 'Pendapatan'], ['EXPENSE', 'Beban']].map(([value, label]) => `<option value="${value}" ${item?.type === value ? 'selected' : ''}>${label}</option>`).join('')}</select>`;
          fields.innerHTML = `<label for="field-coa-code">Kode akun</label><input id="field-coa-code" name="code" type="text" maxlength="24" value="${escapeHtml(item?.code || '')}" required><label for="field-coa-name">Nama akun</label><input id="field-coa-name" name="name" type="text" maxlength="100" value="${escapeHtml(item?.name || '')}" required><label for="field-coa-type">Jenis akun</label><select id="field-coa-type" name="type" required>${[['ASSET', 'Aset'], ['LIABILITY', 'Liabilitas'], ['EQUITY', 'Ekuitas'], ['REVENUE', 'Pendapatan'], ['EXPENSE', 'Beban']].map(([value, label]) => `<option value="${value}" ${(item?.type || 'EXPENSE') === value ? 'selected' : ''}>${label}</option>`).join('')}</select>`;
      } else {
        const options = activeCoa().map((coa) => `<option value="${coa.id}" ${item?.coa_id === coa.id ? 'selected' : ''}>${escapeHtml(coa.code)} · ${escapeHtml(coa.name)}</option>`).join('');
        fields.innerHTML = `<label for="field-category-name">Nama kategori</label><input id="field-category-name" name="name" type="text" maxlength="80" value="${escapeHtml(item?.name || '')}" required><label for="field-category-coa">Akun beban (CoA)</label><select id="field-category-coa" name="coa_id" required><option value="">Pilih akun CoA</option>${options}</select>`;
      }

      form.dataset.entity = `coa-journal-${type}`;
      dialog.showModal();
    }

    async function saveEditor(event) {
      if (!editor) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      saveButton.disabled = true;
      saveButton.textContent = 'Menyimpan...';

      try {
        const values = Object.fromEntries(new FormData(form).entries());
        let result;
        if (editor.type === 'coa') {
          const payload = { code: values.code.trim(), name: values.name.trim(), type: values.type };
          result = editor.id
            ? await supabaseClient.from('chart_of_accounts').update(payload).eq('id', editor.id)
            : await supabaseClient.from('chart_of_accounts').insert(payload);
        } else {
          const coa = activeCoa().find((item) => item.id === values.coa_id);
          if (!coa) throw new Error('Pilih akun CoA yang masih aktif.');
          const payload = { name: values.name.trim(), coa_id: coa.id, coa_code: coa.code };
          result = editor.id
            ? await supabaseClient.from('expense_categories').update(payload).eq('id', editor.id)
            : await supabaseClient.from('expense_categories').insert({ ...payload, is_active: true });
        }
        if (result.error) throw result.error;
        if (editor.type === 'coa') await refreshCoaData();

        dialog.close();
        editor = null;
        notify('Data CoA dan kategori berhasil disimpan.');
        await refreshData();
      } catch (error) {
        notify(errorMessage(error), 'error');
      } finally {
        saveButton.disabled = false;
        saveButton.textContent = 'Simpan';
      }
    }

    content.addEventListener('click', (event) => {
      const button = event.target.closest('[data-coa-action]');
      if (!button) return;
      event.preventDefault();
      const item = [...state.chartOfAccounts, ...state.categories].find((record) => record.id === button.dataset.id);
      const action = button.dataset.coaAction;
      if (action === 'new-coa') return openEditor('coa');
      if (action === 'new-category') return openEditor('category');
      if (action === 'edit-coa') return openEditor('coa', item);
      if (action === 'edit-category') return openEditor('category', item);
      if (action === 'toggle-coa') {
        const deactivating = button.dataset.active === 'true';
        if (deactivating && state.categories.some((category) => category.is_active && category.coa_id === button.dataset.id)) {
          notify('Ubah pemetaan kategori aktif sebelum menonaktifkan CoA ini.', 'error');
          return;
        }
        try {
          supabaseClient.from('chart_of_accounts')
            .update({ is_active: !deactivating })
            .eq('id', button.dataset.id)
              .then(async ({ error }) => {
              if (error) throw error;
                await refreshCoaData();
              notify('Status akun CoA diperbarui.');
              return refreshData();
            })
            .catch((error) => notify(errorMessage(error), 'error'));
        } catch (error) {
          notify(errorMessage(error), 'error');
        }
      }
    });

    content.addEventListener('click', (event) => {
      const button = event.target.closest('[data-action="add-category"]');
      if (!button || !isAdmin() || !coaLoadStarted || coaLoadFailed) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      if (!activeCoa().length) {
        notify('Tambahkan akun CoA aktif sebelum membuat kategori.', 'error');
        return;
      }
      openEditor('category');
    }, true);

    form.addEventListener('submit', saveEditor, true);
    dialog.addEventListener('close', () => { editor = null; });

    function updateCategoryCoaHint() {
      const select = fields.querySelector('[name="category_id"]');
      let hint = fields.querySelector('[data-coa-journal-hint]');
      if (!select) {
        hint?.remove();
        return;
      }
      if (!hint) {
        hint = document.createElement('p');
        hint.className = 'cell-sub';
        hint.dataset.coaJournalHint = '';
        select.after(hint);
      }
      const category = state.categories.find((item) => item.id === select.value);
      const coa = category && accountForCategory(category);
      hint.textContent = coa
        ? `Akun beban otomatis: ${coa.code} · ${coa.name}`
        : 'Akun beban otomatis mengikuti kategori yang dipilih.';
    }

    fields.addEventListener('change', updateCategoryCoaHint);
    new MutationObserver(updateCategoryCoaHint).observe(fields, { childList: true });

    new MutationObserver(renderManagementPanel).observe(content, { childList: true });
    renderManagementPanel();
  } catch (error) {
    console.error('Fitur CoA dan auto-journaling gagal dimulai:', error);
  }
})();
