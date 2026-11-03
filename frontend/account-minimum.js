(() => {
  try {
    const content = document.querySelector('#content');
    const dialog = document.querySelector('#record-dialog');
    const form = document.querySelector('#record-form');
    const fields = document.querySelector('#record-fields');
    const saveButton = document.querySelector('#save-record');

    content.addEventListener('click', (event) => {
      const button = event.target.closest('[data-action="manager-min-balance"]');
      if (!button || state.profile?.role !== 'MANAGER') return;

      try {
        const account = state.accounts.find((item) => item.id === button.dataset.id);
        if (!account) throw new Error('Akun kas tidak ditemukan. Muat ulang halaman dan coba kembali.');

        document.querySelector('#dialog-kicker').textContent = 'BATAS SALDO MINIMUM';
        document.querySelector('#dialog-title').textContent = `Ubah batas · ${account.name}`;
        fields.innerHTML = `<label for="field-manager-min-balance">Batas saldo minimum (Rp)</label><input id="field-manager-min-balance" name="min_balance" type="number" min="0" step="1" value="${Number(account.min_balance) || 0}" required><p class="cell-sub">Peringatan muncul saat saldo akun berada di bawah batas ini.</p>`;
        form.dataset.entity = 'manager-min-balance';
        form.dataset.managerAccountId = account.id;
        dialog.showModal();
      } catch (error) {
        notify(errorMessage(error), 'error');
      }
    });

    form.addEventListener('submit', async (event) => {
      if (form.dataset.entity !== 'manager-min-balance') return;
      event.preventDefault();
      event.stopImmediatePropagation();

      const input = fields.querySelector('#field-manager-min-balance');
      const minimum = Number(input.value);
      if (!Number.isFinite(minimum) || minimum < 0) {
        input.reportValidity();
        return;
      }

      saveButton.disabled = true;
      saveButton.textContent = 'Menyimpan...';
      try {
        const { error } = await supabaseClient
          .from('petty_cash_accounts')
          .update({ min_balance: minimum })
          .eq('id', form.dataset.managerAccountId);
        if (error) throw error;

        dialog.close();
        notify('Batas saldo minimum berhasil diperbarui.');
        await refreshData();
      } catch (error) {
        notify(errorMessage(error), 'error');
      } finally {
        saveButton.disabled = false;
        saveButton.textContent = 'Simpan';
      }
    }, true);
  } catch (error) {
    console.error('Fitur batas saldo minimum gagal dimulai:', error);
  }
})();
