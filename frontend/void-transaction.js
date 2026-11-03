(() => {
  try {
    const content = document.querySelector('#content');
    const dialog = document.querySelector('#void-dialog');
    const form = document.querySelector('#void-form');
    const reasonField = document.querySelector('#void-reason');
    const summary = document.querySelector('#void-transaction-summary');
    const submitButton = document.querySelector('#void-submit');
    let transactionId = null;

    content.addEventListener('click', (event) => {
      const button = event.target.closest('[data-action="void"]');
      if (!button) return;
      if (state.profile?.role !== 'ADMIN') return;

      event.preventDefault();
      event.stopImmediatePropagation();
      try {
        const transaction = state.transactions.find((item) => item.id === button.dataset.id);
        if (!transaction || transaction.status !== 'posted') {
          notify('Transaksi tidak ditemukan atau sudah dibatalkan.', 'error');
          return;
        }

        transactionId = transaction.id;
        reasonField.value = '';
        summary.textContent = `${transaction.description || 'Transaksi'} · ${dateLabel(transaction.transaction_date)} · ${money(transaction.amount)}`;
        dialog.showModal();
        reasonField.focus();
      } catch (error) {
        notify(errorMessage(error), 'error');
      }
    }, true);

    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      event.stopImmediatePropagation();
      const reason = reasonField.value.trim();
      if (!transactionId || reason.length < 5) {
        reasonField.setCustomValidity(reason.length < 5 ? 'Alasan pembatalan minimal 5 karakter.' : 'Pilih transaksi yang akan dibatalkan.');
        reasonField.reportValidity();
        reasonField.setCustomValidity('');
        return;
      }

      submitButton.disabled = true;
      submitButton.textContent = 'Memproses...';
      try {
        const { error } = await supabaseClient.rpc('void_petty_cash_transaction', {
          p_transaction_id: transactionId,
          p_reason: reason
        });
        if (error) throw error;

        dialog.close();
        notify('Transaksi berhasil dibatalkan.');
        transactionId = null;
        await refreshData();
      } catch (error) {
        notify(errorMessage(error), 'error');
      } finally {
        submitButton.disabled = false;
        submitButton.textContent = 'Batalkan transaksi';
      }
    }, true);

    dialog.addEventListener('click', (event) => {
      if (event.target === dialog || event.target.closest('[data-void-close]')) dialog.close();
    });
    dialog.addEventListener('close', () => {
      transactionId = null;
      reasonField.value = '';
    });
  } catch (error) {
    console.error('Fitur dialog pembatalan transaksi gagal dimulai:', error);
  }
})();
